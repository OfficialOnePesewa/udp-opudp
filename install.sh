#!/bin/bash
# ============================================================
#  OPUDP Installer — ZIVPN UDP Management Panel
#  Author  : OfficialOnePesewa
#  GitHub  : https://github.com/OfficialOnePesewa/udp-opudp
#  Version : 3.2.0
#  OS      : Debian 9/10/11/12 + Ubuntu 18/20/22/24 LTS
# ============================================================

# ── Root check ────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo bash i.sh"
    exit 1
fi

# ── Force non-interactive (prevents ALL apt prompts) ──────────
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# ── Colours ───────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; NC='\033[0m'

# ── Settings ──────────────────────────────────────────────────
ZIVPN_BIN_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
PANEL_URL="https://raw.githubusercontent.com/OfficialOnePesewa/udp-opudp/main/opudp"
LISTEN_PORT="5667"
DEFAULT_PORTS="6000:19999"
PORT_START="6000"
PORT_END="19999"
TOTAL=10

# ── Helper functions ──────────────────────────────────────────
step() {
    echo -e "\n${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${G}[${1}/${TOTAL}]${NC} ${W}${2}${NC}"
}
ok()   { echo -e "  ${G}✓${NC}  $1"; }
warn() { echo -e "  ${Y}⚠${NC}  $1"; }
fail() { echo -e "  ${R}✗${NC}  $1"; }

apt_install() {
    apt-get install -y -q \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        -o Dpkg::Options::="--force-confnew" \
        "$@" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
#  BANNER
# ══════════════════════════════════════════════════════════════
clear
echo -e "${C}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          OPUDP — ZIVPN UDP Ultimate Installer               ║"
echo "║          github.com/OfficialOnePesewa/udp-opudp             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ══════════════════════════════════════════════════════════════
#  STEP 1 — DETECT OS
# ══════════════════════════════════════════════════════════════
step 1 "Detecting operating system..."

if [[ ! -f /etc/os-release ]]; then
    fail "Cannot detect OS — /etc/os-release missing."
    exit 1
fi

source /etc/os-release
OS_ID="${ID,,}"
OS_VERSION_ID="${VERSION_ID}"
OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"

case "$OS_ID" in
    debian)
        OS_FAMILY="debian"
        ok "Debian ${OS_VERSION_ID} (${OS_CODENAME}) detected"
        ;;
    ubuntu)
        OS_FAMILY="ubuntu"
        ok "Ubuntu ${OS_VERSION_ID} (${OS_CODENAME}) detected"
        ;;
    *)
        fail "Unsupported OS: ${PRETTY_NAME}"
        echo -e "  ${Y}Supported: Debian 9/10/11/12, Ubuntu 18.04/20.04/22.04/24.04${NC}"
        exit 1
        ;;
esac

if ! command -v systemctl &>/dev/null; then
    fail "systemd is required but not found."
    exit 1
fi
ok "systemd: available"

ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
    fail "Unsupported architecture: ${ARCH}. Only x86_64 is supported."
    exit 1
fi
ok "Architecture: x86_64"

# ══════════════════════════════════════════════════════════════
#  STEP 2 — PACKAGES
# ══════════════════════════════════════════════════════════════
step 2 "Updating package lists and installing dependencies..."

# Pre-seed debconf to silence all interactive prompts
debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v4 boolean true" 2>/dev/null
debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v6 boolean false" 2>/dev/null
debconf-set-selections <<< "netfilter-persistent netfilter-persistent/autosave boolean true" 2>/dev/null

# Update package index only — no upgrade (upgrade can cause dialogs)
apt-get update -y -q 2>/dev/null
ok "Package lists updated"

# Packages needed on both distros
CORE_PKGS=(
    curl wget openssl bc
    iproute2 iptables ufw
    python3 ca-certificates
    gnupg lsb-release
    coreutils procps
)

# Persistence package — pick the right one per OS
if [[ "$OS_FAMILY" == "debian" ]]; then
    CORE_PKGS+=(netfilter-persistent iptables-persistent)
else
    CORE_PKGS+=(iptables-persistent)
fi

echo -e "  Installing packages..."
for pkg in "${CORE_PKGS[@]}"; do
    if dpkg -s "$pkg" &>/dev/null 2>&1; then
        echo -e "    ${G}✓${NC} ${pkg} (already installed)"
    else
        if apt_install "$pkg"; then
            echo -e "    ${G}✓${NC} ${pkg}"
        else
            echo -e "    ${Y}⚠${NC}  ${pkg} (skipped — non-critical)"
        fi
    fi
done

# ══════════════════════════════════════════════════════════════
#  STEP 3 — KERNEL & NETWORK TUNING
# ══════════════════════════════════════════════════════════════
step 3 "Enabling IP forwarding and tuning kernel for UDP..."

SYSCTL_FILE="/etc/sysctl.d/99-opudp.conf"
cat > "$SYSCTL_FILE" << 'EOF'
# OPUDP — Kernel optimisations for ZIVPN UDP
net.ipv4.ip_forward = 1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.core.netdev_max_backlog = 5000
EOF

sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1
ok "IP forwarding enabled and persisted to /etc/sysctl.d/99-opudp.conf"

# ══════════════════════════════════════════════════════════════
#  STEP 4 — DOWNLOAD ZIVPN BINARY
# ══════════════════════════════════════════════════════════════
step 4 "Downloading ZIVPN binary..."

rm -f /usr/local/bin/zivpn 2>/dev/null

if wget --timeout=60 --tries=3 -q --show-progress \
        "$ZIVPN_BIN_URL" -O /usr/local/bin/zivpn; then
    chmod +x /usr/local/bin/zivpn
    ok "ZIVPN binary downloaded and made executable"
else
    fail "Failed to download ZIVPN binary."
    exit 1
fi

# ══════════════════════════════════════════════════════════════
#  STEP 5 — DIRECTORIES & DATA FILES
# ══════════════════════════════════════════════════════════════
step 5 "Creating directories and data files..."

mkdir -p /etc/zivpn/backups /etc/zivpn/sessions
[[ ! -f /etc/zivpn/users.db ]] && touch /etc/zivpn/users.db
[[ ! -f /etc/zivpn/codes.db ]] && touch /etc/zivpn/codes.db
echo "${DEFAULT_PORTS}" > /etc/zivpn/port_range

ok "Directory  : /etc/zivpn/ (with backups/ sessions/)"
ok "Data files : users.db  codes.db  port_range"

# ══════════════════════════════════════════════════════════════
#  STEP 6 — SSL CERTIFICATE
# ══════════════════════════════════════════════════════════════
step 6 "Generating SSL certificate (10-year)..."

openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/C=US/ST=California/L=Los Angeles/O=OfficialOnePesewa/OU=VPN/CN=opudp" \
    -keyout /etc/zivpn/zivpn.key \
    -out    /etc/zivpn/zivpn.crt \
    2>/dev/null

if [[ -f /etc/zivpn/zivpn.crt && -f /etc/zivpn/zivpn.key ]]; then
    chmod 600 /etc/zivpn/zivpn.key
    chmod 644 /etc/zivpn/zivpn.crt
    ok "SSL certificate generated (valid 10 years)"
else
    fail "SSL certificate generation failed."
    exit 1
fi

# ══════════════════════════════════════════════════════════════
#  STEP 7 — ZIVPN CONFIG
# ══════════════════════════════════════════════════════════════
step 7 "Writing ZIVPN configuration..."

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

ok "Config written: /etc/zivpn/config.json"

# ══════════════════════════════════════════════════════════════
#  STEP 8 — SYSTEMD SERVICE
# ══════════════════════════════════════════════════════════════
step 8 "Creating and starting ZIVPN systemd service..."

systemctl stop zivpn.service 2>/dev/null

cat > /etc/systemd/system/zivpn.service << EOF
[Unit]
Description=ZIVPN UDP VPN Server (OPUDP)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=zivpn
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
LimitNOFILE=65536
LimitNPROC=512

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zivpn.service >/dev/null 2>&1
systemctl start  zivpn.service

sleep 3
if systemctl is-active --quiet zivpn.service; then
    ok "ZIVPN service: running"
else
    warn "ZIVPN service not running yet — this is normal before the first user is added"
    warn "After adding a user: opudp → option 3 to restart"
fi

# ══════════════════════════════════════════════════════════════
#  STEP 9 — FIREWALL & NAT RULES
# ══════════════════════════════════════════════════════════════
step 9 "Configuring firewall and NAT rules..."

# ── Detect primary network interface ─────────────────────────
IFACE=""

# Method 1: ip route default (most reliable on both Debian & Ubuntu)
IFACE=$(ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}')

# Method 2: ip route any line with via
[[ -z "$IFACE" ]] && \
    IFACE=$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')

# Method 3: scan common interface names
if [[ -z "$IFACE" ]]; then
    for try_if in eth0 eth1 ens3 ens4 ens5 ens18 ens33 \
                  enp0s3 enp0s5 enp1s0 enp2s0 \
                  venet0 vnet0 bond0 br0; do
        if ip link show "$try_if" &>/dev/null 2>&1; then
            IFACE="$try_if"
            break
        fi
    done
fi

if [[ -n "$IFACE" ]]; then
    ok "Network interface: ${IFACE}"
else
    warn "Interface not detected — NAT PREROUTING skipped"
    warn "Fix manually: iptables -t nat -A PREROUTING -i <YOUR_IFACE> -p udp --dport ${PORT_START}:${PORT_END} -j DNAT --to :${LISTEN_PORT}"
fi

# ── Remove any old OPUDP NAT rules to avoid duplicates ────────
iptables -t nat -D PREROUTING -p udp \
    --dport "${PORT_START}:${PORT_END}" \
    -j DNAT --to-destination ":${LISTEN_PORT}" 2>/dev/null

if [[ -n "$IFACE" ]]; then
    iptables -t nat -A PREROUTING -i "$IFACE" -p udp \
        --dport "${PORT_START}:${PORT_END}" \
        -j DNAT --to-destination ":${LISTEN_PORT}" 2>/dev/null
    ok "NAT rule: UDP ${PORT_START}:${PORT_END} → :${LISTEN_PORT}"
fi

# ── INPUT chain rules ─────────────────────────────────────────
# Allow loopback
iptables -A INPUT -i lo -j ACCEPT 2>/dev/null
# Allow established/related (works on both Debian & Ubuntu kernels)
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
# Allow SSH — prevent lockout
iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null
# Allow ZIVPN listener
iptables -A INPUT -p udp --dport "${LISTEN_PORT}" -j ACCEPT 2>/dev/null
# Allow full UDP port range
iptables -A INPUT -p udp --dport "${PORT_START}:${PORT_END}" -j ACCEPT 2>/dev/null
ok "iptables INPUT rules applied"

# ── UFW (if active) ───────────────────────────────────────────
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | awk 'NR==1{print $2}')
    if [[ "$UFW_STATUS" == "active" ]]; then
        ufw allow 22/tcp                               >/dev/null 2>&1
        ufw allow "${LISTEN_PORT}/udp"                 >/dev/null 2>&1
        ufw allow "${PORT_START}:${PORT_END}/udp"      >/dev/null 2>&1
        ok "UFW rules added (UFW is active)"
    else
        ok "UFW present but not active — iptables rules applied"
    fi
fi

# ── Persist iptables across reboots ──────────────────────────
mkdir -p /etc/iptables
iptables-save  > /etc/iptables/rules.v4 2>/dev/null
ip6tables-save > /etc/iptables/rules.v6 2>/dev/null

# Try the right persistence service for each distro
PERSIST_OK=false
for svc in netfilter-persistent iptables-persistent; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}"; then
        systemctl enable  "$svc" >/dev/null 2>&1
        systemctl restart "$svc" >/dev/null 2>&1
        ok "iptables rules persisted via ${svc}"
        PERSIST_OK=true
        break
    fi
done

if [[ "$PERSIST_OK" != true ]]; then
    # Universal fallback: if-pre-up.d script
    mkdir -p /etc/network/if-pre-up.d
    cat > /etc/network/if-pre-up.d/opudp-iptables << 'IPEOF'
#!/bin/sh
test -f /etc/iptables/rules.v4 && /sbin/iptables-restore < /etc/iptables/rules.v4
exit 0
IPEOF
    chmod +x /etc/network/if-pre-up.d/opudp-iptables
    ok "iptables rules persisted via if-pre-up.d (fallback)"
fi

# ══════════════════════════════════════════════════════════════
#  STEP 10 — INSTALL OPUDP PANEL
# ══════════════════════════════════════════════════════════════
step 10 "Installing OPUDP management panel..."

if wget --timeout=60 --tries=3 -q \
        "$PANEL_URL" -O /usr/local/bin/opudp; then
    chmod +x /usr/local/bin/opudp
    ok "OPUDP panel installed → run: opudp"
else
    fail "Could not download OPUDP panel from GitHub."
    exit 1
fi

# ── Cleanup ───────────────────────────────────────────────────
rm -f i.sh 2>/dev/null

# ── Get server public IP ──────────────────────────────────────
SERVER_IP=$(curl -s4 --connect-timeout 8 ifconfig.me   2>/dev/null || \
            curl -s4 --connect-timeout 8 api.ipify.org 2>/dev/null || \
            curl -s4 --connect-timeout 8 icanhazip.com 2>/dev/null || \
            hostname -I 2>/dev/null | awk '{print $1}')

# ══════════════════════════════════════════════════════════════
#  COMPLETE
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${C}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${C}║${G}              OPUDP Installed Successfully!                 ${C}║${NC}"
echo -e "${C}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  OS           :  ${Y}${PRETTY_NAME}${NC}"
echo -e "${C}║${NC}  Server IP    :  ${Y}${SERVER_IP}${NC}"
echo -e "${C}║${NC}  Interface    :  ${Y}${IFACE:-not detected}${NC}"
echo -e "${C}║${NC}  UDP Ports    :  ${Y}${DEFAULT_PORTS}${NC}"
echo -e "${C}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  Run panel    :  ${Y}opudp${NC}"
echo -e "${C}║${NC}  Add users    :  ${Y}opudp → option 6${NC}"
echo -e "${C}║${NC}  Restart VPN  :  ${Y}opudp → option 3${NC}"
echo -e "${C}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  ZIVPN App Configuration (after adding a user):${NC}"
echo -e "${C}║${NC}    UDP Server   →  ${Y}${SERVER_IP}${NC}"
echo -e "${C}║${NC}    UDP Password →  ${Y}(password you set in opudp)${NC}"
echo -e "${C}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  Share this install command:${NC}"
echo -e "${C}║${NC}  ${Y}wget -O i.sh https://raw.githubusercontent.com/         ${NC}"
echo -e "${C}║${NC}  ${Y}OfficialOnePesewa/udp-opudp/main/install.sh             ${NC}"
echo -e "${C}║${NC}  ${Y}&& sudo chmod +x i.sh && sudo ./i.sh                    ${NC}"
echo -e "${C}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${W}Service Status:${NC}"
if systemctl is-active --quiet zivpn.service; then
    echo -e "  ZIVPN   : ${G}● running${NC}"
else
    echo -e "  ZIVPN   : ${Y}● stopped${NC} (normal — will start after first user is added)"
fi
echo ""
echo -e "  ${Y}→ Run ${W}opudp${Y} to open the control panel now.${NC}"
echo ""
