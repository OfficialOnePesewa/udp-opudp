#!/bin/bash
# ============================================================
#  OPUDP Installer — ZIVPN UDP Management Panel
#  Author : OfficialOnePesewa
#  GitHub : https://github.com/OfficialOnePesewa/udp-opudp
# ============================================================

[[ $EUID -ne 0 ]] && echo "Please run as root!" && exit 1

ZIVPN_BIN_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
PANEL_URL="https://raw.githubusercontent.com/OfficialOnePesewa/udp-opudp/main/opudp"
LISTEN_PORT="5667"
DEFAULT_PORTS="6000:19999"

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; R='\033[0;31m'; NC='\033[0m'

echo -e "${C}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║         OPUDP — ZIVPN UDP Ultimate Installer        ║"
echo "║         github.com/OfficialOnePesewa/udp-opudp      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

step() { echo -e "${G}[${1}/${TOTAL}]${NC} $2"; }
TOTAL=8

step 1 "Updating system packages..."
apt-get update -y -q && apt-get upgrade -y -q
apt-get install -y -q curl wget openssl ufw bc 2>/dev/null

step 2 "Downloading ZIVPN binary..."
wget -q --show-progress "$ZIVPN_BIN_URL" -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

step 3 "Setting up directories and data files..."
mkdir -p /etc/zivpn/backups
touch /etc/zivpn/users.db
echo "$DEFAULT_PORTS" > /etc/zivpn/port_range

step 4 "Generating SSL certificate (10-year)..."
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/C=US/ST=California/L=Los Angeles/O=OfficialOnePesewa/OU=VPN/CN=opudp" \
    -keyout /etc/zivpn/zivpn.key \
    -out  /etc/zivpn/zivpn.crt 2>/dev/null
echo -e "  ${G}Certificate generated.${NC}"

step 5 "Writing base config (no passwords — add users via opudp)..."
cat > /etc/zivpn/config.json << EOF
{
  "listen": ":${LISTEN_PORT}",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": []
  }
}
EOF

step 6 "Creating systemd service..."
cat > /etc/systemd/system/zivpn.service << EOF
[Unit]
Description=ZIVPN UDP VPN Server — OPUDP
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zivpn.service
systemctl start zivpn.service

step 7 "Configuring firewall and NAT rules..."
IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
PORT_START=$(echo "$DEFAULT_PORTS" | cut -d: -f1)
PORT_END=$(echo "$DEFAULT_PORTS"   | cut -d: -f2)

# Tune kernel buffers for UDP performance
sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1

# Persist sysctl settings
grep -q "rmem_max" /etc/sysctl.conf || echo "net.core.rmem_max=16777216" >> /etc/sysctl.conf
grep -q "wmem_max" /etc/sysctl.conf || echo "net.core.wmem_max=16777216" >> /etc/sysctl.conf

# NAT: forward UDP port range to ZIVPN listener
iptables -t nat -A PREROUTING -i "$IFACE" -p udp \
    --dport "${PORT_START}:${PORT_END}" \
    -j DNAT --to-destination ":${LISTEN_PORT}"

# Firewall rules
ufw allow "${PORT_START}:${PORT_END}/udp" >/dev/null 2>&1
ufw allow "${LISTEN_PORT}/udp"            >/dev/null 2>&1

# Persist iptables rules across reboots
if command -v iptables-save &>/dev/null; then
    apt-get install -y -q iptables-persistent 2>/dev/null
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
fi

step 8 "Installing OPUDP management panel..."
wget -q --show-progress "$PANEL_URL" -O /usr/local/bin/opudp
chmod +x /usr/local/bin/opudp

# Cleanup installer files
rm -f i.sh install.sh 2>/dev/null

SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo ""
echo -e "${C}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${C}║${G}         OPUDP Installed Successfully!               ${C}║${NC}"
echo -e "${C}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  Run panel  :  ${Y}opudp${NC}"
echo -e "${C}║${NC}  Server IP  :  ${Y}${SERVER_IP}${NC}"
echo -e "${C}║${NC}  UDP Ports  :  ${Y}${DEFAULT_PORTS}${NC}"
echo -e "${C}║${NC}  Users      :  Add via ${Y}opudp → option 6${NC}"
echo -e "${C}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  ZIVPN App config after adding a user:${NC}"
echo -e "${C}║${NC}    UDP Server   → ${Y}${SERVER_IP}${NC}"
echo -e "${C}║${NC}    UDP Password → ${Y}<password you set in opudp>${NC}"
echo -e "${C}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  Share install command:${NC}"
echo -e "${C}║${NC}  ${Y}wget -O i.sh https://raw.githubusercontent.com/${NC}"
echo -e "${C}║${NC}  ${Y}OfficialOnePesewa/udp-opudp/main/install.sh${NC}"
echo -e "${C}║${NC}  ${Y}&& sudo chmod +x i.sh && sudo ./i.sh${NC}"
echo -e "${C}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
