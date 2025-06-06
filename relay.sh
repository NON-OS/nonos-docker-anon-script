#!/bin/bash

# ===============
#     NONOS
# ===============

echo "[0/12] Starting NONOS Total Relay Farm Deployment..."

### [1] Create Non-Root Admin User
adduser relayadmin
usermod -aG sudo relayadmin

### [2] SSH Hardening - Port 55089 and Root Login Enabled
echo "[2/12] Configuring SSH..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sed -i 's/^#Port 22/Port 55089/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo "UseDNS no" >> /etc/ssh/sshd_config
systemctl restart ssh

### [3] Install Core Packages
echo "[3/12] Installing Docker and essentials..."
apt update && apt upgrade -y
apt install -y ca-certificates curl gnupg lsb-release net-tools nano unattended-upgrades docker.io docker-compose fail2ban logwatch auditd ufw

### [4] Firewall Setup
echo "[4/12] Setting up UFW firewall rules..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 55089/tcp
for port in $(seq 9001 9252); do ufw allow $port/tcp; done
ufw --force enable

### [5] Fail2Ban Config
echo "[5/12] Configuring Fail2Ban..."
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

### [6] Kernel Hardening
echo "[6/12] Applying sysctl kernel hardening..."
cat <<EOF >> /etc/sysctl.conf

# NONOS Hardened Relay Kernel Tweaks
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

### [7] Auto Security Updates
echo "[7/12] Enabling auto-updates..."
dpkg-reconfigure -plow unattended-upgrades

### [8] Create macvlan Network (Change IFACE/SUBNET as needed!)
echo "[8/12] Creating macvlan network..."
docker network create -d macvlan \\
  --subnet=192.168.100.0/24 \\
  --gateway=192.168.100.1 \\
  -o parent=eth0 macvlan_net

### [9] Build Docker Image
echo "[9/12] Building anon-exit-image..."
mkdir -p /opt/anon-farm/base-image
cd /opt/anon-farm/base-image

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

RUN apt-get update && \\
    apt-get install -y anon

COPY config/anon.config /etc/anon/anonrc
COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]
EOF

cat <<EOF > start.sh
#!/bin/bash
echo "Starting Anon Relay..."
exec anon
EOF
chmod +x start.sh

mkdir -p config
echo "# default anonrc (replaced per instance)" > config/anon.config

docker build -t anon-exit-image .

### [10] Generate Relays and Compose Files
echo "[10/12] Creating relay volumes and docker-compose files..."
cd /opt/anon-farm
mkdir -p volumes

for i in $(seq -w 1 252); do
  RELAY=anon-relay-$i
  IP=192.168.100.$((i+1))
  PORT=$((9000 + i))
  mkdir -p volumes/$RELAY/var/lib/anon volumes/$RELAY/etc/anon volumes/$RELAY/run/anon
  cat <<EOF > volumes/$RELAY/etc/anon/anonrc
Nickname $RELAY
ContactInfo anon@example.com
ORPort $PORT
SocksPort 0
ExitRelay 0
EOF

  cat <<EOF > $RELAY.yaml
version: '3.8'
services:
  relay:
    image: anon-exit-image
    container_name: $RELAY
    init: true
    restart: unless-stopped
    ports:
      - "$PORT:$PORT"
    networks:
      macvlan_net:
        ipv4_address: $IP
    volumes:
      - ./volumes/$RELAY/var/lib/anon:/var/lib/anon/
      - ./volumes/$RELAY/etc/anon:/etc/anon/
      - ./volumes/$RELAY/run/anon:/run/anon/
networks:
  macvlan_net:
    external: true
EOF
done

### [11] Start All Relays
echo "[11/12] Launching all 252 relays..."
for i in $(seq -w 1 252); do
  docker compose -f anon-relay-$i.yaml up -d
done

### [12] Done
echo "[✔] All Nonos Anon relays are deployed and running!"
echo "[✔] Access SSH via port 55089"
