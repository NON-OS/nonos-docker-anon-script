# NONOS x EK — Anon Relay Farm & Server Hardening 🧱

A fully automated, scalable deployment framework for running up to **252 Dockerized Anon relays** with hardened security, `macvlan` IP isolation, and enterprise-grade Linux hardening — designed for **data center environments**.

---

## 🔧 Overview

This project provisions and launches a fleet of Anon protocol relays using Docker, while simultaneously securing the host system using best practices for server hardening. Each relay runs in an isolated container, with a unique IP address assigned via macvlan networking, and a dedicated configuration.

---

## 🔐 Security Features

- SSH hardened:  
  - ✅ Port `55089`  
  - ✅ Root login **enabled**
- System-level hardening:  
  - ✅ Kernel protections via `sysctl`  
  - ✅ UFW firewall configuration  
  - ✅ `fail2ban`, `auditd`, `logwatch`, `unattended-upgrades`
- Production-ready networking:  
  - ✅ Docker `macvlan` network with IP isolation  
  - ✅ 252 ORPorts exposed (`9001–9252`)  
- Fully automated:  
  - ✅ Docker image build for Anon  
  - ✅ Per-container volumes & relay identity  
  - ✅ Automatic YAML + `anonrc` generation

---

## 📦 Requirements

- Debian 12 (or equivalent) with root access  
- Subnet for macvlan (default: `192.168.100.0/24`)  
- Docker & Docker Compose (installed automatically)

---

## 🚀 Installation

```bash
git clone https://github.com/NON-OS/nonos-docker-anon-script
cd nonos-docker-anon-script
chmod +x nonos-docker-anon-script
sudo nonos-docker-anon-script
