#!/bin/bash
# ============================================================
#  OPUDP Installer — ZIVPN UDP Management Panel
#  Author : OfficialOnePesewa
#  GitHub : https://github.com/OfficialOnePesewa/udp-opudp
#  Version: 4.0.0 (True HWID Enforcement Edition)
# ============================================================

[[ $EUID -ne 0 ]] && echo "Please run as root!" && exit 1

ZIVPN_BIN_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
GITHUB_RAW="https://raw.githubusercontent.com/OfficialOnePesewa/udp-opudp/main"
LISTEN_PORT="5667"
DEFAULT_PORTS="6000:19999"

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'
R='\033[0;31m'; M='\033[0;35m'; W='\033[1;37m'; NC='\033[0m'

echo -e "${C}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║       OPUDP — ZIVPN UDP Ultimate Installer          ║"
echo "║       True HWID Enforcement Edition v4.0.0          ║"
echo "║       github.com/OfficialOnePesewa/udp-opudp        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

TOTAL=9
step() { echo -e "${G}[${1}/${TOTAL}]${NC} $2"; }

step 1 "Updating system packages..."
apt-get update -y -q && apt-get upgrade -y -q
apt-get install -y -q curl wget openssl ufw bc python3 2>/dev/null
echo -e "  ${G}Done.${NC}"

step 2 "Downloading ZIVPN binary..."
wget -q --show-progress "$ZIVPN_BIN_URL" -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

step 3 "Setting up directories and data files..."
mkdir -p /etc/zivpn/backups /etc/zivpn/sessions
touch /etc/zivpn/users.db
touch /etc/zivpn/connections.log
touch /etc/zivpn/auth.log
echo "$DEFAULT_PORTS" > /etc/zivpn/port_range
echo -e "  ${G}Done.${NC}"

step 4 "Generating SSL certificate (10-year)..."
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/C=US/ST=California/L=Los Angeles/O=OfficialOnePesewa/OU=VPN/CN=opudp" \
    -keyout /etc/zivpn/zivpn.key \
    -out    /etc/zivpn/zivpn.crt 2>/dev/null
echo -e "  ${G}Certificate generated.${NC}"

step 5 "Writing base config (passwords mode — enable HWID via opudp option 21)..."
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
echo -e "  ${G}Config written.${NC}"

step 6 "Creating ZIVPN systemd service..."
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

step 7 "Creating OPUDP Auth Daemon systemd service..."
cat > /etc/systemd/system/opudp-auth.service << EOF
[Unit]
Description=OPUDP HWID Auth Daemon
After=network.target zivpn.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/opudp-authd
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zivpn.service
systemctl enable opudp-auth.service
systemctl start  zivpn.service
systemctl start  opudp-auth.service
echo -e "  ${G}Services started.${NC}"

step 8 "Configuring firewall and NAT rules..."
IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
PORT_START=$(echo "$DEFAULT_PORTS" | cut -d: -f1)
PORT_END=$(echo "$DEFAULT_PORTS"   | cut -d: -f2)

# Tune kernel UDP buffers
sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1
grep -q "rmem_max" /etc/sysctl.conf || echo "net.core.rmem_max=16777216" >> /etc/sysctl.conf
grep -q "wmem_max" /etc/sysctl.conf || echo "net.core.wmem_max=16777216" >> /etc/sysctl.conf

# NAT: forward UDP port range → ZIVPN listener
iptables -t nat -A PREROUTING -i "$IFACE" -p udp \
    --dport "${PORT_START}:${PORT_END}" \
    -j DNAT --to-destination ":${LISTEN_PORT}"

# Firewall rules
ufw allow "${PORT_START}:${PORT_END}/udp" >/dev/null 2>&1
ufw allow "${LISTEN_PORT}/udp"            >/dev/null 2>&1

# Persist iptables
if command -v iptables-save &>/dev/null; then
    apt-get install -y -q iptables-persistent 2>/dev/null
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
fi
echo -e "  ${G}Firewall configured.${NC}"

step 9 "Downloading OPUDP panel and auth daemon..."
wget -q --show-progress "${GITHUB_RAW}/opudp"       -O /usr/local/bin/opudp
wget -q --show-progress "${GITHUB_RAW}/opudp-authd" -O /usr/local/bin/opudp-authd
chmod +x /usr/local/bin/opudp
chmod +x /usr/local/bin/opudp-authd
echo -e "  ${G}Panel and auth daemon installed.${NC}"

# Cleanup installer
rm -f i.sh install.sh 2>/dev/null

SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo ""
echo -e "${C}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${C}║${G}         OPUDP v4.0.0 Installed Successfully!        ${C}║${NC}"
echo -e "${C}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  Run panel      :  ${Y}opudp${NC}"
echo -e "${C}║${NC}  Server IP      :  ${Y}${SERVER_IP}${NC}"
echo -e "${C}║${NC}  UDP Ports      :  ${Y}${DEFAULT_PORTS}${NC}"
echo -e "${C}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${M}  HWID Enforcement (disabled by default):${NC}"
echo -e "${C}║${NC}  → Run ${Y}opudp${NC} → option ${M}21${NC} → option ${M}a${NC} to enable"
echo -e "${C}║${NC}  → Add users via ${Y}opudp${NC} → option ${G}6${NC}"
echo -e "${C}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  Files installed:"
echo -e "${C}║${NC}    ${Y}/usr/local/bin/opudp${NC}       ← panel"
echo -e "${C}║${NC}    ${Y}/usr/local/bin/opudp-authd${NC} ← HWID daemon"
echo -e "${C}║${NC}    ${Y}/etc/zivpn/${NC}               ← all data"
echo -e "${C}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  Re-install command:"
echo -e "${C}║${NC}  ${Y}wget -O i.sh https://raw.githubusercontent.com/${NC}"
echo -e "${C}║${NC}  ${Y}OfficialOnePesewa/udp-opudp/main/install.sh${NC}"
echo -e "${C}║${NC}  ${Y}&& sudo chmod +x i.sh && sudo ./i.sh${NC}"
echo -e "${C}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
