#!/bin/bash
set -euo pipefail

# ====================================================
#   NØNOS Relay Farm Installer (Final Edition)
# ====================================================
#  → Builds isolated Docker relays using Anon Protocol
#  → Includes hardened firewall, SSH, kernel configs
#  → Automatically provisions and deploys 252 relays
# ====================================================

echo "[0/12] 🚀 Starting NØNOS Full Relay Farm Setup..."

# ========= [1] Create Admin User =========
echo "[1/12] 👤 Creating non-root user: relayadmin"
adduser relayadmin
usermod -aG sudo relayadmin

# ========= [2] SSH Hardening =========
echo "[2/12] 🔐 Securing SSH..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sed -i 's/^#Port .*/Port 55089/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo "UseDNS no" >> /etc/ssh/sshd_config
systemctl restart ssh

# ========= [3] Install Dependencies =========
echo "[3/12] 📦 Installing core packages..."
apt update && apt upgrade -y
apt install -y \
  ca-certificates curl gnupg lsb-release net-tools \
  nano unattended-upgrades docker.io docker-compose \
  fail2ban logwatch auditd ufw

# ========= [4] UFW Firewall =========
echo "[4/12] 🧱 Configuring UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 55089/tcp
for port in $(seq 9001 9252); do ufw allow $port/tcp; done
ufw --force enable

# ========= [5] Fail2Ban Setup =========
echo "[5/12] 🛡️ Enabling Fail2Ban..."
cat <<EOF > /etc/fail2ban/jail.d/sshd.local
[sshd]
enabled = true
port = 55089
filter = sshd
logpath = /var/log/auth.log
maxretry = 4
EOF
systemctl enable fail2ban
systemctl restart fail2ban

# ========= [6] Kernel Hardening =========
echo "[6/12] 🧬 Applying sysctl hardening..."
cat <<EOF >> /etc/sysctl.conf

# NØNOS Hardened Kernel Config
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
EOF
sysctl -p

# ========= [7] Auto Updates =========
echo "[7/12] 🔁 Enabling unattended-upgrades..."
dpkg-reconfigure -plow unattended-upgrades

# ========= [8] Docker Macvlan =========
echo "[8/12] 🌐 Creating macvlan docker network..."
docker network create -d macvlan \
  --subnet=192.168.100.0/24 \
  --gateway=192.168.100.1 \
  -o parent=eth0 macvlan_net || true

# ========= [9] Build anon-exit-image =========
echo "[9/12] 🏗️ Building anon-exit-image..."
mkdir -p /opt/anon-farm/base-image
cd /opt/anon-farm/base-image

# -- Dockerfile --
cat <<EOF > Dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y \\
    nyx \\
    debconf \\
    net-tools \\
    nano \\
    unattended-upgrades \\
    curl \\
    wget
RUN echo "anon anon/terms boolean true" | debconf-set-selections
RUN wget -qO- https://deb.en.anyone.tech/anon.asc | tee /etc/apt/trusted.gpg.d/anon.asc && \\
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/anon.asc] https://deb.en.anyone.tech anon-live-jammy main" | tee /etc/apt/sources.list.d/anon.list
RUN apt-get update && apt-get install -y anon
COPY config/anon.config /etc/anon/anonrc
COPY start.sh /start.sh
RUN chmod +x /start.sh
CMD ["/start.sh"]
EOF

# -- Startup script --
cat <<EOF > start.sh
#!/bin/bash
echo "🔌 Launching Anon Relay..."
exec anon
EOF
chmod +x start.sh

# -- anonrc default placeholder --
mkdir -p config
echo "# default anonrc (replaced dynamically)" > config/anon.config

# Build Image
docker build -t anon-exit-image .

# ========= [10] Generate Relay Instances =========
echo "[10/12] 🧬 Generating 252 relays..."
cd /opt/anon-farm
mkdir -p volumes

for i in $(seq -w 1 252); do
  RELAY_NAME=anonrelay$i
  IP=192.168.100.$((i+1))
  PORT=$((9000 + i))
  mkdir -p volumes/$RELAY_NAME/etc/anon volumes/$RELAY_NAME/var/log/anon volumes/$RELAY_NAME/run/anon volumes/$RELAY_NAME/var/lib/anon

  # anonrc
  cat <<EOF > volumes/$RELAY_NAME/etc/anon/anonrc
Nickname $RELAY_NAME
ContactInfo relay@nonos.site
ORPort $PORT
ControlPort 9051
SocksPort 0
DirPort 80
DirPortFrontPage /etc/anon/anyone-exit-notice.html
Log notice file /var/log/anon/notices.log
ExitRelay 1
IPv6Exit 0
ReevaluateExitPolicy 1
AllowSingleHopExits 0
ExitPolicyRejectPrivate 1
LongLivedPorts 22,80,443,465,587,993,995
ExitPolicy reject *:25
ExitPolicy reject *:587
ExitPolicy reject *:465
ExitPolicy reject *:2525
ExitPolicy reject *:3389
ExitPolicy reject *:23
ExitPolicy reject *:3128
ExitPolicy reject *:5900
ExitPolicy reject *:9999
ExitPolicy accept *:*
AgreeToTerms 1
EOF

  # HTML notice page
  cat <<EOF > volumes/$RELAY_NAME/etc/anon/anyone-exit-notice.html
<!DOCTYPE html>
<html><body><h1>NØNOS Exit - $RELAY_NAME</h1><p>Powered by anyone.network</p></body></html>
EOF

done

# ========= [11] Docker Compose =========
echo "[11/12] 🧾 Writing Docker Compose file..."
cat <<EOF > /opt/anon-farm/docker-compose.yml
version: '3.8'
services:
EOF

for i in $(seq -w 1 252); do
  RELAY_NAME=anonrelay$i
  IP=192.168.100.$((i+1))
  PORT=$((9000 + i))

  cat <<EOF >> /opt/anon-farm/docker-compose.yml
  $RELAY_NAME:
    image: anon-exit-image
    container_name: $RELAY_NAME
    hostname: $RELAY_NAME
    restart: unless-stopped
    networks:
      macvlan_net:
        ipv4_address: $IP
    ports:
      - "$PORT:9001"
    volumes:
      - ./volumes/$RELAY_NAME/etc/anon:/etc/anon
      - ./volumes/$RELAY_NAME/var/log/anon:/var/log/anon
      - ./volumes/$RELAY_NAME/var/lib/anon:/var/lib/anon
      - ./volumes/$RELAY_NAME/run/anon:/run/anon
    logging:
      driver: "none"

EOF
done

# Docker Network section
cat <<EOF >> /opt/anon-farm/docker-compose.yml
networks:
  macvlan_net:
    external: true
EOF

# ========= [12] Start Deployment =========
echo "[12/12] 🚀 Launching NØNOS farm..."
cd /opt/anon-farm
docker compose up -d

echo ""
echo "[✅] NØNOS: All 252 relays deployed successfully!"
echo "[ℹ️] Use: docker ps | grep anonrelay"
