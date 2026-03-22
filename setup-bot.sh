#!/bin/bash
# ============================================================
#  OPUDP Telegram Bot Installer — Fixed Injection
#  Author : OfficialOnePesewa
#  GitHub : https://github.com/OfficialOnePesewa/udp-opudp
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

# ── Step 1: Install dependencies ──────────────────────────────
echo -e "${Y}Installing python3-pip...${NC}"
apt-get install -y -q python3-pip 2>/dev/null

echo -e "${Y}Installing python-telegram-bot 13.15...${NC}"
pip3 install "python-telegram-bot==13.15" --break-system-packages -q 2>/dev/null \
    || pip3 install "python-telegram-bot==13.15" -q 2>/dev/null

python3 -c "import telegram; print('  Library OK')" 2>/dev/null \
    || echo -e "${R}  Warning: library may not be installed correctly${NC}"

# ── Step 2: Download bot script ───────────────────────────────
echo -e "${Y}Downloading bot script...${NC}"
curl -fsSL "https://raw.githubusercontent.com/OfficialOnePesewa/udp-opudp/main/opudp-bot.py" \
    -o /usr/local/bin/opudp-bot.py 2>/dev/null \
    || wget -q "https://raw.githubusercontent.com/OfficialOnePesewa/udp-opudp/main/opudp-bot.py" \
        -O /usr/local/bin/opudp-bot.py
chmod +x /usr/local/bin/opudp-bot.py
echo -e "${G}  ✓ Bot script downloaded${NC}"

# ── Step 3: Collect credentials ───────────────────────────────
echo ""
echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${W}Step 1:${NC} Create bot via ${Y}@BotFather${NC} → /newbot → copy token"
echo -e "${W}Step 2:${NC} Get your Telegram ID via ${Y}@userinfobot${NC}"
echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Read Bot Token
while true; do
    read -rp "  Paste your Bot Token: " BOT_TOKEN
    BOT_TOKEN=$(echo "$BOT_TOKEN" | tr -d ' \n\r\t')
    if [[ -z "$BOT_TOKEN" ]]; then
        echo -e "${R}  Empty — try again.${NC}"
    elif [[ "$BOT_TOKEN" == *":"* ]]; then
        echo -e "${G}  ✓ Token accepted.${NC}"; break
    else
        echo -e "${R}  Invalid (should contain ':') — try again.${NC}"
    fi
done

# Read Admin ID
while true; do
    read -rp "  Paste your Telegram User ID: " ADMIN_ID
    ADMIN_ID=$(echo "$ADMIN_ID" | tr -d ' \n\r\t')
    if [[ -z "$ADMIN_ID" ]]; then
        echo -e "${R}  Empty — try again.${NC}"
    elif [[ "$ADMIN_ID" =~ ^[0-9]+$ ]]; then
        echo -e "${G}  ✓ User ID accepted.${NC}"; break
    else
        echo -e "${R}  Must be numbers only — try again.${NC}"
    fi
done

# ── Step 4: Inject credentials using Python ───────────────────
echo ""
echo -e "${Y}Injecting credentials...${NC}"

# Write a temporary Python injector script to avoid shell escaping issues
cat > /tmp/inject_bot.py << 'PYEOF'
import sys, re

bot_file = "/usr/local/bin/opudp-bot.py"
token    = sys.argv[1]
admin_id = sys.argv[2]

with open(bot_file, "r") as f:
    content = f.read()

# Replace line by line for reliability
new_lines = []
for line in content.splitlines(keepends=True):
    stripped = line.strip()
    if stripped.startswith("BOT_TOKEN"):
        new_lines.append(f'BOT_TOKEN = "{token}"\n')
    elif re.match(r"^ADMIN_IDS\s*=", stripped):
        new_lines.append(f'ADMIN_IDS = [{admin_id}]\n')
    else:
        new_lines.append(line)

with open(bot_file, "w") as f:
    f.writelines(new_lines)

# Verify
with open(bot_file, "r") as f:
    result = f.read()

if token in result and admin_id in result:
    print("INJECT_OK")
else:
    print("INJECT_FAIL")
PYEOF

# Run the injector with token and ID as arguments
INJECT_RESULT=$(python3 /tmp/inject_bot.py "$BOT_TOKEN" "$ADMIN_ID")
rm -f /tmp/inject_bot.py

if [[ "$INJECT_RESULT" == "INJECT_OK" ]]; then
    echo -e "${G}  ✓ Credentials injected successfully!${NC}"
else
    echo -e "${R}  ✗ Injection failed: ${INJECT_RESULT}${NC}"
    echo -e "${Y}  Trying fallback method...${NC}"
    # Last resort: direct line replacement
    python3 - "$BOT_TOKEN" "$ADMIN_ID" << 'FALLBACK'
import sys, re
token, aid = sys.argv[1], sys.argv[2]
f = "/usr/local/bin/opudp-bot.py"
lines = open(f).readlines()
out = []
for l in lines:
    if l.strip().startswith("BOT_TOKEN"):
        out.append(f'BOT_TOKEN = "{token}"\n')
    if re.match(r"^ADMIN_IDS\s*=", l.strip()):
        out.append(f'ADMIN_IDS = [{aid}]\n')
    else:
        out.append(l)
open(f,"w").writelines(out)
print("FALLBACK_OK")
FALLBACK
fi

# Confirm what was written
echo ""
echo -e "${W}  Verification:${NC}"
grep -E "^BOT_TOKEN|^ADMIN_IDS" /usr/local/bin/opudp-bot.py | head -2 | \
    while read line; do echo -e "  ${G}✓${NC} $line"; done

# ── Step 5: Create systemd service ────────────────────────────
echo ""
echo -e "${Y}Creating systemd service...${NC}"

cat > /etc/systemd/system/opudp-bot.service << EOF
[Unit]
Description=OPUDP Telegram Bot
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/opudp-bot.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=opudp-bot

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable opudp-bot.service >/dev/null 2>&1
systemctl stop   opudp-bot.service 2>/dev/null
sleep 1
systemctl start  opudp-bot.service

# ── Step 6: Final status ──────────────────────────────────────
sleep 3
STATUS=$(systemctl is-active opudp-bot.service)

# Check for token error in logs
LOG_CHECK=$(journalctl -u opudp-bot -n 5 --no-pager 2>/dev/null)

echo ""
echo -e "${C}╔══════════════════════════════════════════════════════════╗${NC}"
if [[ "$STATUS" == "active" ]] && ! echo "$LOG_CHECK" | grep -q "BOT_TOKEN"; then
    echo -e "${C}║${G}         OPUDP Telegram Bot is RUNNING! ✓              ${C}║${NC}"
    echo -e "${C}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${C}║${NC}  Status   : ${G}● active${NC}"
    echo -e "${C}║${NC}  Admin ID : ${G}${ADMIN_ID}${NC}"
    echo -e "${C}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${C}║${NC}  Open Telegram → your bot → send ${Y}/start${NC}"
else
    echo -e "${C}║${R}         Bot failed to start — see below              ${C}║${NC}"
    echo -e "${C}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${C}║${NC}  Recent logs:"
    journalctl -u opudp-bot -n 5 --no-pager 2>/dev/null | tail -5 | \
        while read line; do echo -e "  ${R}${line}${NC}"; done
fi
echo -e "${C}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${C}║${NC}  ${Y}systemctl status opudp-bot${NC}   — check status"
echo -e "${C}║${NC}  ${Y}systemctl restart opudp-bot${NC}  — restart"
echo -e "${C}║${NC}  ${Y}journalctl -u opudp-bot -f${NC}   — live logs"
echo -e "${C}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
