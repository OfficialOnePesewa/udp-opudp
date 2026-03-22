#!/bin/bash
# ============================================================
#  OPUDP Telegram Bot Installer
#  Run on your VPS after installing OPUDP
# ============================================================
[[ $EUID -ne 0 ]] && echo "Run as root." && exit 1

export DEBIAN_FRONTEND=noninteractive

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'
R='\033[0;31m'; W='\033[1;37m'; NC='\033[0m'

echo -e "${C}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          OPUDP Telegram Bot Installer                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Install python deps
echo -e "${Y}Installing python3-pip and python-telegram-bot...${NC}"
apt-get install -y -q python3-pip 2>/dev/null
pip3 install python-telegram-bot==13.15 --break-system-packages -q 2>/dev/null \
    || pip3 install python-telegram-bot==13.15 -q 2>/dev/null

# Download bot script
echo -e "${Y}Downloading bot script...${NC}"
curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/udp-opudp/main/opudp-bot.py \
    -o /usr/local/bin/opudp-bot.py \
    || wget -q https://raw.githubusercontent.com/OfficialOnePesewa/udp-opudp/main/opudp-bot.py \
        -O /usr/local/bin/opudp-bot.py
chmod +x /usr/local/bin/opudp-bot.py

# Prompt for token and admin ID
echo ""
echo -e "${W}Step 1:${NC} Create a bot via ${Y}@BotFather${NC} on Telegram → copy the token"
echo -e "${W}Step 2:${NC} Get your Telegram user ID via ${Y}@userinfobot${NC}"
echo ""
read -rp "  Paste your Bot Token: " BOT_TOKEN
read -rp "  Paste your Telegram User ID: " ADMIN_ID

# Inject into script
sed -i "s|YOUR_BOT_TOKEN_HERE|${BOT_TOKEN}|g"   /usr/local/bin/opudp-bot.py
sed -i "s|ADMIN_IDS  = \[123456789\]|ADMIN_IDS  = [${ADMIN_ID}]|g" /usr/local/bin/opudp-bot.py

# Create systemd service
cat > /etc/systemd/system/opudp-bot.service << EOF
[Unit]
Description=OPUDP Telegram Bot
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/opudp-bot.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=opudp-bot

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable opudp-bot.service >/dev/null 2>&1
systemctl start  opudp-bot.service

sleep 2
if systemctl is-active --quiet opudp-bot.service; then
    echo -e "${G}✓ Bot is running!${NC}"
else
    echo -e "${R}✗ Bot failed to start. Check: journalctl -u opudp-bot -n 30${NC}"
fi

echo ""
echo -e "${C}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${C}║${G}           OPUDP Bot Installed!                         ${C}║${NC}"
echo -e "${C}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  Open Telegram → search your bot → send /start          ${NC}"
echo -e "${C}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  Bot commands:                                           ${NC}"
echo -e "${C}║${NC}  /start    — main menu with buttons                      ${NC}"
echo -e "${C}║${NC}  /users    — list all users                              ${NC}"
echo -e "${C}║${NC}  /adduser  — add a new user                              ${NC}"
echo -e "${C}║${NC}  /removeuser — remove a user                             ${NC}"
echo -e "${C}║${NC}  /renewuser  — renew a user                              ${NC}"
echo -e "${C}║${NC}  /hwidadd    — add HWID to user                          ${NC}"
echo -e "${C}║${NC}  /hwidremove — remove HWID from user                     ${NC}"
echo -e "${C}║${NC}  /setconn    — set connection limit                      ${NC}"
echo -e "${C}║${NC}  /gencode    — generate access codes                     ${NC}"
echo -e "${C}║${NC}  /stats    — server stats                                ${NC}"
echo -e "${C}║${NC}  /cancel   — cancel current action                       ${NC}"
echo -e "${C}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
