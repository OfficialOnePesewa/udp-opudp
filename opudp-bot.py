#!/usr/bin/env python3
# ============================================================
#  OPUDP Telegram Bot — Full Panel Mirror v2.0.0
#  Author  : OfficialOnePesewa
#  GitHub  : https://github.com/OfficialOnePesewa/udp-opudp
# ============================================================
#  ALL 25 panel functions available via Telegram
#  Setup:
#    1. @BotFather → /newbot → copy token
#    2. @userinfobot → copy your user ID
#    3. Edit BOT_TOKEN and ADMIN_IDS below
#    4. python3 opudp-bot.py
# ============================================================

import os, subprocess, datetime, re, logging, secrets
from functools import wraps
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, ParseMode
from telegram.ext import (
    Updater, CommandHandler, CallbackQueryHandler,
    MessageHandler, Filters, CallbackContext, ConversationHandler
)

# ── CONFIG ────────────────────────────────────────────────────
BOT_TOKEN = "YOUR_BOT_TOKEN_HERE"
ADMIN_IDS = [123456789]

# ── PATHS ─────────────────────────────────────────────────────
USERS_DB    = "/etc/zivpn/users.db"
CODES_DB    = "/etc/zivpn/codes.db"
HWID_LOG    = "/etc/zivpn/hwid.log"
PORT_FILE   = "/etc/zivpn/port_range"
CONFIG_FILE = "/etc/zivpn/config.json"
BACKUP_DIR  = "/etc/zivpn/backups"
LISTEN_PORT = "5667"

# ── STATES ────────────────────────────────────────────────────
(
    ADD_USERNAME, ADD_PASSWORD, ADD_EXPIRY, ADD_CONN,
    ADD_HWID_CHOICE, ADD_HWID_INPUT,
    RM_PICK,
    RV_PICK, RV_EXP,
    HA_USER, HA_COUNT, HA_INPUT,
    HR_USER, HR_PICK,
    HVU_PICK,
    HC_USER, HC_CONFIRM,
    SC_USER, SC_PICK,
    GC_COUNT, GC_LABEL,
    CP_START, CP_END,
    RB_PICK,
) = range(24)

logging.basicConfig(format="%(asctime)s %(levelname)s %(message)s", level=logging.INFO)

# ── AUTH ──────────────────────────────────────────────────────
def admin_only(fn):
    @wraps(fn)
    def wrapper(update, ctx, *a, **k):
        if update.effective_user.id not in ADMIN_IDS:
            update.effective_message.reply_text("⛔ Access denied.")
            return
        return fn(update, ctx, *a, **k)
    return wrapper

# ── UTILS ─────────────────────────────────────────────────────
def run(cmd, timeout=25):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return (r.stdout + r.stderr).strip()
    except subprocess.TimeoutExpired:
        return "(timed out)"
    except Exception as e:
        return str(e)

def svc(name):
    return subprocess.run(["systemctl","is-active",name], capture_output=True, text=True).stdout.strip()

def server_ip():
    o = run("curl -s4 --connect-timeout 5 ifconfig.me 2>/dev/null || curl -s4 icanhazip.com")
    return o.strip() or "unknown"

def get_port():
    try: return open(PORT_FILE).read().strip()
    except: return "6000:19999"

def expired(exp):
    if exp == "never": return False
    try: return datetime.datetime.strptime(exp,"%Y-%m-%d").date() < datetime.date.today()
    except: return False

def days_left(exp):
    if exp == "never": return "∞"
    try: return str((datetime.datetime.strptime(exp,"%Y-%m-%d").date()-datetime.date.today()).days)
    except: return "?"

def valid_hwid(h):
    return bool(re.match(r'^[0-9A-Fa-f]{32}$', re.sub(r'[\s\-]','',h)))

def clean(h):
    return re.sub(r'[\s\-]','',h).upper()

def fmt(h):
    h=h.upper(); return f"{h[:8]}-{h[8:16]}-{h[16:24]}-{h[24:32]}"

def cnt_hwids(f):
    if not f or f=="none": return 0
    return len([x for x in f.split(",") if x.strip()])

def back(label="◀️ Back", d="main"):
    return InlineKeyboardMarkup([[InlineKeyboardButton(label, callback_data=d)]])

def reply(update, text, kb=None, md=True):
    kw = {"parse_mode": ParseMode.MARKDOWN} if md else {}
    if kb: kw["reply_markup"] = kb
    if update.callback_query:
        try: update.callback_query.edit_message_text(text, **kw)
        except: update.callback_query.message.reply_text(text, **kw)
    else:
        update.message.reply_text(text, **kw)

# ── DB ────────────────────────────────────────────────────────
def read_users():
    if not os.path.exists(USERS_DB): return []
    out = []
    for line in open(USERS_DB):
        line = line.strip()
        if not line: continue
        p = line.split(":")
        while len(p)<7: p.append("")
        out.append({"username":p[0],"password":p[1],"expiry":p[2],"bw":p[3],
                    "max_conn":p[4] or "0","hwids":p[5] or "none","hl":p[6] or "0"})
    return out

def write_users(users):
    with open(USERS_DB,"w") as f:
        for u in users:
            f.write(f"{u['username']}:{u['password']}:{u['expiry']}:{u['bw']}:{u['max_conn']}:{u['hwids']}:{u['hl']}\n")

def find_user(name):
    for u in read_users():
        if u["username"]==name: return u
    return None

def rebuild():
    users = read_users()
    pwds  = [f'"{u["password"]}"' for u in users if not expired(u["expiry"])]
    cfg   = ('{\n  "listen": ":'+LISTEN_PORT+'",\n  "cert": "/etc/zivpn/zivpn.crt",\n'
             '  "key": "/etc/zivpn/zivpn.key",\n  "obfs": "zivpn",\n'
             '  "auth": {\n    "mode": "passwords",\n    "config": ['+",".join(pwds)+']\n  }\n}')
    open(CONFIG_FILE,"w").write(cfg)

# ══════════════════════════════════════════════════════════════
#  MAIN MENU
# ══════════════════════════════════════════════════════════════
def menu_kb():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("▶️ Start",      callback_data="svc_start"),
         InlineKeyboardButton("⏹ Stop",        callback_data="svc_stop"),
         InlineKeyboardButton("🔁 Restart",    callback_data="svc_restart"),
         InlineKeyboardButton("ℹ️ Status",     callback_data="svc_status")],
        [InlineKeyboardButton("👥 List Users",  callback_data="list_users"),
         InlineKeyboardButton("➕ Add User",    callback_data="add_user"),
         InlineKeyboardButton("🗑 Remove",      callback_data="remove_user")],
        [InlineKeyboardButton("🔄 Renew",       callback_data="renew_user"),
         InlineKeyboardButton("🧹 Cleanup Exp", callback_data="cleanup"),
         InlineKeyboardButton("🔗 Conn Limit",  callback_data="set_conn")],
        [InlineKeyboardButton("📱 HWID All",    callback_data="hwid_all"),
         InlineKeyboardButton("📱 Add HWID",    callback_data="hwid_add"),
         InlineKeyboardButton("📱 Rm HWID",     callback_data="hwid_remove")],
        [InlineKeyboardButton("📱 View Dev",    callback_data="hwid_view_user"),
         InlineKeyboardButton("📱 Clear HWID",  callback_data="hwid_clear"),
         InlineKeyboardButton("📜 HWID Logs",   callback_data="hwid_logs")],
        [InlineKeyboardButton("📊 Conn Stats",  callback_data="conn_stats"),
         InlineKeyboardButton("📈 BW Report",   callback_data="bw_report"),
         InlineKeyboardButton("🔄 Reset BW",    callback_data="reset_bw")],
        [InlineKeyboardButton("⚡ Speed Test",  callback_data="speed_test"),
         InlineKeyboardButton("📋 Live Logs",   callback_data="live_logs"),
         InlineKeyboardButton("🔌 Chg Port",    callback_data="change_port")],
        [InlineKeyboardButton("💾 Backup",      callback_data="backup"),
         InlineKeyboardButton("📂 Restore",     callback_data="restore"),
         InlineKeyboardButton("⬆️ Update",      callback_data="auto_update")],
        [InlineKeyboardButton("🎫 Gen Codes",   callback_data="gen_code"),
         InlineKeyboardButton("📋 View Codes",  callback_data="view_codes"),
         InlineKeyboardButton("🔄 Refresh",     callback_data="main")],
    ])

def header():
    z=svc("zivpn"); m=svc("opudp-hwid-monitor")
    users=read_users()
    act=sum(1 for u in users if not expired(u["expiry"]))
    lkd=sum(1 for u in users if u["hl"]=="1" and u["hwids"]!="none")
    si="🟢" if z=="active" else "🔴"; mi="🟢" if m=="active" else "🔴"
    return (f"*🖥 OPUDP Control Panel*\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"{si} ZIVPN     : `{z}`\n"
            f"{mi} HWID Mon  : `{m}`\n"
            f"👥 Users     : `{act}` active\n"
            f"🔒 HWID Lock : `{lkd}` users\n"
            f"🌐 Server IP : `{server_ip()}`\n"
            f"🔌 UDP Ports : `{get_port()}`\n"
            f"━━━━━━━━━━━━━━━━━━━━━━")

@admin_only
def cmd_start(update, ctx):
    update.message.reply_text(header(), parse_mode=ParseMode.MARKDOWN, reply_markup=menu_kb())

@admin_only
def cmd_menu(update, ctx):
    cmd_start(update, ctx)

# ══════════════════════════════════════════════════════════════
#  BUTTON DISPATCHER (non-conversation buttons)
# ══════════════════════════════════════════════════════════════
@admin_only
def btn(update, ctx):
    q=update.callback_query; q.answer(); d=q.data
    import time

    if d=="main":
        q.edit_message_text(header(), parse_mode=ParseMode.MARKDOWN, reply_markup=menu_kb())

    elif d=="svc_start":
        run("systemctl start zivpn"); time.sleep(1)
        st=svc("zivpn")
        q.edit_message_text(f"{'✅ ZIVPN started!' if st=='active' else '❌ Failed.'}", reply_markup=back())

    elif d=="svc_stop":
        run("systemctl stop zivpn")
        q.edit_message_text("⏹ *ZIVPN stopped.*", parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="svc_restart":
        run("systemctl restart zivpn"); time.sleep(1)
        st=svc("zivpn")
        q.edit_message_text(f"{'✅ ZIVPN restarted!' if st=='active' else '❌ Failed.'}", reply_markup=back())

    elif d=="svc_status":
        out=run("systemctl status zivpn --no-pager -l 2>&1 | head -20")
        q.edit_message_text(f"*ℹ️ ZIVPN Status*\n```\n{out[:2000]}\n```", parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="list_users":
        users=read_users()
        if not users:
            q.edit_message_text("👥 No users.", reply_markup=back()); return
        lines=["*👥 User List*\n━━━━━━━━━━━━━━━━━━━━━━"]
        for u in users:
            dl=days_left(u["expiry"]); mc="∞" if u["max_conn"]=="0" else u["max_conn"]
            n=cnt_hwids(u["hwids"])
            st="🔴 EXPIRED" if expired(u["expiry"]) else ("🟡 EXPIRING" if dl!=("∞") and dl.lstrip("-").isdigit() and int(dl)<=3 else "🟢 ACTIVE")
            hs=f"🔒{n}dev" if u["hl"]=="1" and u["hwids"]!="none" else "🔓"
            lines.append(f"\n👤`{u['username']}` {st}\n🔑`{u['password']}`\n📅`{u['expiry']}`({dl}d) 🔗`{mc}` {hs}")
        txt="\n".join(lines)
        if len(txt)>4000: txt=txt[:4000]+"…"
        q.edit_message_text(txt, parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="cleanup":
        users=read_users(); before=len(users)
        kept=[u for u in users if not expired(u["expiry"])]
        write_users(kept); rebuild(); run("systemctl restart zivpn")
        q.edit_message_text(f"🧹 Removed *{before-len(kept)}* expired user(s). Remaining: *{len(kept)}*",
                             parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="conn_stats":
        lc=run(f"ss -u state established 2>/dev/null | grep ':{LISTEN_PORT}' | awk '{{print $5}}' | cut -d: -f1 | sort -u | wc -l")
        li=run(f"ss -u state established 2>/dev/null | grep ':{LISTEN_PORT}' | awk '{{print $5}}' | cut -d: -f1 | sort -u")
        lines=[f"*📊 Connection Stats*\n━━━━━━━━━━━━━━━━━━━━━━\n🔗 Live: `{lc}`"]
        if li.strip():
            for ip in li.strip().split("\n"): lines.append(f"  `→ {ip}`")
        users=read_users()
        lines.append("\n*Per User:*")
        for u in users:
            mc="∞" if u["max_conn"]=="0" else u["max_conn"]
            n=cnt_hwids(u["hwids"]); hs=f"🔒{n}" if u["hl"]=="1" else "🔓"
            ei="🔴" if expired(u["expiry"]) else "🟢"
            lines.append(f"  {ei}`{u['username']}` lim:`{mc}` {hs}")
        q.edit_message_text("\n".join(lines), parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="bw_report":
        try:
            iface=run("ip -4 route show default | awk 'NR==1{print $5}'").strip()
            rx=int(open(f"/sys/class/net/{iface}/statistics/rx_bytes").read())
            tx=int(open(f"/sys/class/net/{iface}/statistics/tx_bytes").read())
            bw=f"📥 RX:`{round(rx/1048576,2)} MB` 📤 TX:`{round(tx/1048576,2)} MB`"
        except: bw="Bandwidth unavailable"; iface="?"
        users=read_users()
        lines=[f"*📈 Bandwidth Report*\n━━━━━━━━━━━━━━━━━━━━━━\n🌐`{iface}`\n{bw}\n\n*Users:*"]
        for u in users:
            dl=days_left(u["expiry"]); est="🔴 EXPIRED" if expired(u["expiry"]) else f"🟢 {dl}d"
            lines.append(f"  👤`{u['username']}` {est} 🔗`{'∞' if u['max_conn']=='0' else u['max_conn']}`")
        q.edit_message_text("\n".join(lines), parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="reset_bw":
        run("iptables -Z 2>/dev/null")
        q.edit_message_text("✅ *Bandwidth counters reset.*", parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="speed_test":
        q.edit_message_text("⚡ *Running speed test... (up to 30s)*", parse_mode=ParseMode.MARKDOWN)
        r=run("speedtest-cli --simple 2>/dev/null || curl -o /dev/null -s -w 'DL: %{speed_download} B/s' http://speedtest.tele2.net/10MB.zip", timeout=40)
        q.edit_message_text(f"⚡ *Speed Test*\n```\n{r[:1000] or 'Unavailable'}\n```", parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="live_logs":
        logs=run("journalctl -u zivpn -n 30 --no-pager -o cat 2>/dev/null") or "No logs."
        q.edit_message_text(f"*📋 ZIVPN Logs (last 30)*\n```\n{logs[:3000]}\n```", parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="backup":
        os.makedirs(BACKUP_DIR, exist_ok=True)
        name=f"opudp_backup_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.tar.gz"
        path=os.path.join(BACKUP_DIR, name)
        run(f"tar -czf {path} /etc/zivpn/ 2>/dev/null")
        sz=run(f"du -sh {path} 2>/dev/null | cut -f1")
        q.edit_message_text(f"💾 *Backup saved!*\n`{path}`\nSize: `{sz}`", parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="auto_update":
        q.edit_message_text("⬆️ *Updating...*", parse_mode=ParseMode.MARKDOWN)
        run("systemctl stop zivpn")
        BU="https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
        r1=run(f"wget -q '{BU}' -O /usr/local/bin/zivpn.new && chmod +x /usr/local/bin/zivpn.new && mv /usr/local/bin/zivpn.new /usr/local/bin/zivpn && echo OK || echo FAIL")
        run("systemctl start zivpn")
        PU="https://raw.githubusercontent.com/OfficialOnePesewa/udp-opudp/main/opudp"
        r2=run(f"wget -q '{PU}' -O /usr/local/bin/opudp.new && chmod +x /usr/local/bin/opudp.new && mv /usr/local/bin/opudp.new /usr/local/bin/opudp && echo OK || echo FAIL")
        BotU="https://raw.githubusercontent.com/OfficialOnePesewa/udp-opudp/main/opudp-bot.py"
        r3=run(f"wget -q '{BotU}' -O /usr/local/bin/opudp-bot.py.new && mv /usr/local/bin/opudp-bot.py.new /usr/local/bin/opudp-bot.py && echo OK || echo FAIL")
        time.sleep(2)
        q.edit_message_text(
            f"⬆️ *Update Complete*\n"
            f"{'✅' if 'OK' in r1 else '❌'} ZIVPN binary\n"
            f"{'✅' if 'OK' in r2 else '❌'} Panel\n"
            f"{'✅' if 'OK' in r3 else '❌'} Telegram bot\n"
            f"ZIVPN: `{svc('zivpn')}`",
            parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="view_codes":
        try: lines=[l.strip() for l in open(CODES_DB) if l.strip()]
        except: lines=[]
        unused=[l for l in lines if ":unused:" in l]; used=[l for l in lines if ":used:" in l]
        txt=[f"*🎫 Access Codes*\n━━━━━━━━━━━━━━━━━━━━━━\n✅ Unused:`{len(unused)}` ❌ Used:`{len(used)}`\n"]
        if unused:
            txt.append("*Unused:*")
            for l in unused[:15]:
                p=l.split(":"); txt.append(f"  🟢`{p[0]}` _{p[3] if len(p)>3 else ''}_")
            if len(unused)>15: txt.append(f"  _...+{len(unused)-15} more_")
        q.edit_message_text("\n".join(txt), parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="hwid_all":
        users=read_users()
        if not users:
            q.edit_message_text("📱 No users.", reply_markup=back()); return
        lines=["*📱 HWID All Users*\n━━━━━━━━━━━━━━━━━━━━━━"]
        lk=0; ns=0
        for u in users:
            n=cnt_hwids(u["hwids"])
            if u["hl"]=="1" and u["hwids"]!="none":
                lk+=1; lines.append(f"\n🔒`{u['username']}` *{n} dev*")
                for i,h in enumerate(u["hwids"].split(","),1): lines.append(f"  `[{i}]` `{fmt(h)}`")
            else:
                ns+=1; lines.append(f"\n🔓`{u['username']}` _no HWID_")
        lines.append(f"\n━━━━━━━━━━━━━━━━━━━━━━\n🔒Locked:`{lk}` 🔓Not set:`{ns}`")
        txt="\n".join(lines)
        if len(txt)>4000: txt=txt[:4000]+"…"
        q.edit_message_text(txt, parse_mode=ParseMode.MARKDOWN, reply_markup=back())

    elif d=="hwid_logs":
        try:
            ls=open(HWID_LOG).readlines(); last="".join(ls[-30:])
        except: last="No HWID log found."
        q.edit_message_text(f"*📜 HWID Logs (last 30)*\n```\n{last[:3000]}\n```", parse_mode=ParseMode.MARKDOWN, reply_markup=back())

# ══════════════════════════════════════════════════════════════
#  CONVERSATIONS
# ══════════════════════════════════════════════════════════════

# ── ADD USER ──────────────────────────────────────────────────
@admin_only
def add_start(update, ctx):
    reply(update, "➕ *Add New User*\n\nEnter *username*:")
    return ADD_USERNAME

def add_uname(update, ctx):
    n=update.message.text.strip().replace(" ","")
    if find_user(n):
        update.message.reply_text(f"❌ `{n}` exists. Try another:", parse_mode=ParseMode.MARKDOWN)
        return ADD_USERNAME
    ctx.user_data["n"]=n
    update.message.reply_text("Enter *password*:", parse_mode=ParseMode.MARKDOWN)
    return ADD_PASSWORD

def add_pass(update, ctx):
    ctx.user_data["p"]=update.message.text.strip().replace(" ","")
    kb=InlineKeyboardMarkup([
        [InlineKeyboardButton("1 month",  callback_data="e1"),InlineKeyboardButton("3 months",callback_data="e3")],
        [InlineKeyboardButton("6 months", callback_data="e6"),InlineKeyboardButton("1 year",  callback_data="ey")],
        [InlineKeyboardButton("Never",    callback_data="en")],
    ])
    update.message.reply_text("📅 *Expiry:*", parse_mode=ParseMode.MARKDOWN, reply_markup=kb)
    return ADD_EXPIRY

def add_exp(update, ctx):
    q=update.callback_query; q.answer()
    t=datetime.date.today()
    m={"e1":(t+datetime.timedelta(30)).isoformat(),"e3":(t+datetime.timedelta(90)).isoformat(),
       "e6":(t+datetime.timedelta(180)).isoformat(),"ey":(t+datetime.timedelta(365)).isoformat(),"en":"never"}
    ctx.user_data["e"]=m.get(q.data,"never")
    kb=InlineKeyboardMarkup([
        [InlineKeyboardButton("1",callback_data="m1"),InlineKeyboardButton("2",callback_data="m2"),InlineKeyboardButton("3",callback_data="m3")],
        [InlineKeyboardButton("5",callback_data="m5"),InlineKeyboardButton("10",callback_data="m10"),InlineKeyboardButton("∞",callback_data="m0")],
    ])
    q.edit_message_text("🔗 *Connection limit:*", parse_mode=ParseMode.MARKDOWN, reply_markup=kb)
    return ADD_CONN

def add_conn(update, ctx):
    q=update.callback_query; q.answer()
    ctx.user_data["mc"]=q.data.replace("m","")
    ctx.user_data["hw"]=[]
    kb=InlineKeyboardMarkup([
        [InlineKeyboardButton("1 device", callback_data="nd1"),InlineKeyboardButton("2 devices",callback_data="nd2"),InlineKeyboardButton("3 devices",callback_data="nd3")],
        [InlineKeyboardButton("4 devices",callback_data="nd4"),InlineKeyboardButton("5 devices",callback_data="nd5")],
        [InlineKeyboardButton("⏭ Skip HWID",callback_data="nd0")],
    ])
    q.edit_message_text("📱 *HWID Device Lock*\n\nCustomer: *ZIVPN Pro → ☰ Menu → Tool → HWID → copy*\n\nHow many devices?",
                        parse_mode=ParseMode.MARKDOWN, reply_markup=kb)
    return ADD_HWID_CHOICE

def add_hwid_choice(update, ctx):
    q=update.callback_query; q.answer()
    num=int(q.data.replace("nd",""))
    ctx.user_data["hw_total"]=num; ctx.user_data["hw_idx"]=1; ctx.user_data["hw"]=[]
    if num==0: return _save_user(q, ctx)
    q.edit_message_text(f"📱 *Device 1 of {num}*\n\nPaste HWID (32 hex chars):", parse_mode=ParseMode.MARKDOWN)
    return ADD_HWID_INPUT

def add_hwid_input(update, ctx):
    raw=clean(update.message.text.strip())
    idx=ctx.user_data["hw_idx"]; total=ctx.user_data["hw_total"]
    if not valid_hwid(raw):
        update.message.reply_text(f"❌ Invalid HWID for device {idx}. 32 hex chars needed.\nPaste again:")
        return ADD_HWID_INPUT
    hw=ctx.user_data["hw"]
    if raw in hw:
        update.message.reply_text("⚠️ Duplicate — paste different HWID:"); return ADD_HWID_INPUT
    hw.append(raw); ctx.user_data["hw"]=hw
    update.message.reply_text(f"✅ Device {idx}: `{fmt(raw)}`", parse_mode=ParseMode.MARKDOWN)
    if idx<total:
        ctx.user_data["hw_idx"]=idx+1
        update.message.reply_text(f"📱 *Device {idx+1} of {total}*\n\nPaste HWID:", parse_mode=ParseMode.MARKDOWN)
        return ADD_HWID_INPUT
    return _save_user(update, ctx)

def _save_user(upd_or_q, ctx):
    d=ctx.user_data
    hwid_list=",".join(d.get("hw",[])) or "none"; hl="1" if hwid_list!="none" else "0"
    users=read_users()
    users.append({"username":d["n"],"password":d["p"],"expiry":d["e"],"bw":"0",
                  "max_conn":d["mc"],"hwids":hwid_list,"hl":hl})
    write_users(users); rebuild(); run("systemctl restart zivpn")
    ip=server_ip(); mc="Unlimited" if d["mc"]=="0" else f"{d['mc']} device(s)"
    n=cnt_hwids(hwid_list); ht=f"🔒 LOCKED — {n} device(s)" if hl=="1" else "🔓 Not set — use 📱 Add HWID"
    msg=(f"✅ *User `{d['n']}` created!*\n━━━━━━━━━━━━━━━━━━━━━━\n"
         f"🌐 Server : `{ip}`\n🔑 Password: `{d['p']}`\n"
         f"📅 Expiry  : `{d['e']}`\n🔗 Limit   : `{mc}`\n📱 HWID    : {ht}\n"
         f"━━━━━━━━━━━━━━━━━━━━━━\n_Enter password in ZIVPN app → UDP Tunnel_")
    try:
        if hasattr(upd_or_q,"edit_message_text"): upd_or_q.edit_message_text(msg,parse_mode=ParseMode.MARKDOWN,reply_markup=back())
        else: upd_or_q.message.reply_text(msg,parse_mode=ParseMode.MARKDOWN,reply_markup=back())
    except: pass
    ctx.user_data.clear(); return ConversationHandler.END

# ── REMOVE USER ───────────────────────────────────────────────
@admin_only
def rm_start(update, ctx):
    users=read_users()
    if not users:
        reply(update,"👥 No users."); return ConversationHandler.END
    kb=InlineKeyboardMarkup([[InlineKeyboardButton(u["username"],callback_data=f"rm_{u['username']}")] for u in users]+[[InlineKeyboardButton("❌ Cancel",callback_data="rm_x")]])
    reply(update,"🗑 *Remove User* — select:",kb)
    return RM_PICK

def rm_pick(update, ctx):
    q=update.callback_query; q.answer()
    if q.data=="rm_x": q.edit_message_text("Cancelled."); return ConversationHandler.END
    name=q.data[3:]; users=[u for u in read_users() if u["username"]!=name]
    write_users(users); rebuild(); run("systemctl restart zivpn")
    q.edit_message_text(f"✅ `{name}` removed.",parse_mode=ParseMode.MARKDOWN,reply_markup=back())
    return ConversationHandler.END

# ── RENEW USER ────────────────────────────────────────────────
@admin_only
def rv_start(update, ctx):
    users=read_users()
    if not users:
        reply(update,"👥 No users."); return ConversationHandler.END
    kb=InlineKeyboardMarkup([[InlineKeyboardButton(u["username"],callback_data=f"rv_{u['username']}")] for u in users]+[[InlineKeyboardButton("❌ Cancel",callback_data="rv_x")]])
    reply(update,"🔄 *Renew User* — select:",kb)
    return RV_PICK

def rv_pick(update, ctx):
    q=update.callback_query; q.answer()
    if q.data=="rv_x": q.edit_message_text("Cancelled."); return ConversationHandler.END
    ctx.user_data["rv"]=q.data[3:]
    kb=InlineKeyboardMarkup([
        [InlineKeyboardButton("1 month",callback_data="re1"),InlineKeyboardButton("3 months",callback_data="re3")],
        [InlineKeyboardButton("6 months",callback_data="re6"),InlineKeyboardButton("1 year",callback_data="rey")],
        [InlineKeyboardButton("Never",callback_data="ren")],
    ])
    q.edit_message_text(f"📅 New expiry for `{ctx.user_data['rv']}`:",parse_mode=ParseMode.MARKDOWN,reply_markup=kb)
    return RV_EXP

def rv_exp(update, ctx):
    q=update.callback_query; q.answer()
    t=datetime.date.today()
    m={"re1":(t+datetime.timedelta(30)).isoformat(),"re3":(t+datetime.timedelta(90)).isoformat(),
       "re6":(t+datetime.timedelta(180)).isoformat(),"rey":(t+datetime.timedelta(365)).isoformat(),"ren":"never"}
    ne=m.get(q.data,"never"); name=ctx.user_data["rv"]
    users=read_users()
    for u in users:
        if u["username"]==name: u["expiry"]=ne
    write_users(users); rebuild(); run("systemctl restart zivpn")
    q.edit_message_text(f"✅ `{name}` renewed → `{ne}`",parse_mode=ParseMode.MARKDOWN,reply_markup=back())
    ctx.user_data.clear(); return ConversationHandler.END

# ── SET CONN LIMIT ────────────────────────────────────────────
@admin_only
def sc_start(update, ctx):
    users=read_users()
    if not users:
        reply(update,"👥 No users."); return ConversationHandler.END
    kb=InlineKeyboardMarkup([[InlineKeyboardButton(u["username"],callback_data=f"sc_{u['username']}")] for u in users]+[[InlineKeyboardButton("❌ Cancel",callback_data="sc_x")]])
    reply(update,"🔗 *Set Conn Limit* — select user:",kb)
    return SC_USER

def sc_user(update, ctx):
    q=update.callback_query; q.answer()
    if q.data=="sc_x": q.edit_message_text("Cancelled."); return ConversationHandler.END
    ctx.user_data["sc"]=q.data[3:]
    kb=InlineKeyboardMarkup([
        [InlineKeyboardButton("1",callback_data="sl1"),InlineKeyboardButton("2",callback_data="sl2"),InlineKeyboardButton("3",callback_data="sl3")],
        [InlineKeyboardButton("5",callback_data="sl5"),InlineKeyboardButton("10",callback_data="sl10"),InlineKeyboardButton("∞",callback_data="sl0")],
    ])
    q.edit_message_text(f"🔗 Limit for `{ctx.user_data['sc']}`:",parse_mode=ParseMode.MARKDOWN,reply_markup=kb)
    return SC_PICK

def sc_pick(update, ctx):
    q=update.callback_query; q.answer()
    lim=q.data[2:]; name=ctx.user_data["sc"]
    users=read_users()
    for u in users:
        if u["username"]==name: u["max_conn"]=lim
    write_users(users)
    label="Unlimited" if lim=="0" else f"{lim} device(s)"
    q.edit_message_text(f"✅ `{name}` limit → *{label}*",parse_mode=ParseMode.MARKDOWN,reply_markup=back())
    ctx.user_data.clear(); return ConversationHandler.END

# ── HWID ADD ──────────────────────────────────────────────────
@admin_only
def ha_start(update, ctx):
    users=read_users()
    if not users:
        reply(update,"👥 No users."); return ConversationHandler.END
    kb=InlineKeyboardMarkup([[InlineKeyboardButton(u["username"],callback_data=f"ha_{u['username']}")] for u in users]+[[InlineKeyboardButton("❌ Cancel",callback_data="ha_x")]])
    reply(update,"📱 *Add HWID Device* — select user:",kb)
    return HA_USER

def ha_user(update, ctx):
    q=update.callback_query; q.answer()
    if q.data=="ha_x": q.edit_message_text("Cancelled."); return ConversationHandler.END
    ctx.user_data["ha_u"]=q.data[3:]; ctx.user_data["ha_c"]=[]
    n=cnt_hwids(find_user(ctx.user_data["ha_u"])["hwids"])
    kb=InlineKeyboardMarkup([
        [InlineKeyboardButton("1",callback_data="hac1"),InlineKeyboardButton("2",callback_data="hac2"),InlineKeyboardButton("3",callback_data="hac3")],
        [InlineKeyboardButton("4",callback_data="hac4"),InlineKeyboardButton("5",callback_data="hac5")],
    ])
    q.edit_message_text(f"📱 *Add to `{ctx.user_data['ha_u']}`*\nCurrent: *{n} dev*\n\nHow many new?",parse_mode=ParseMode.MARKDOWN,reply_markup=kb)
    return HA_COUNT

def ha_count(update, ctx):
    q=update.callback_query; q.answer()
    ctx.user_data["ha_t"]=int(q.data[3:]); ctx.user_data["ha_i"]=1
    q.edit_message_text(f"📱 *Device 1 of {ctx.user_data['ha_t']}*\n\nCustomer: *ZIVPN Pro → ☰ Menu → Tool → HWID → copy*\n\nPaste HWID:",parse_mode=ParseMode.MARKDOWN)
    return HA_INPUT

def ha_input(update, ctx):
    raw=clean(update.message.text.strip())
    idx=ctx.user_data["ha_i"]; total=ctx.user_data["ha_t"]
    name=ctx.user_data["ha_u"]; col=ctx.user_data["ha_c"]
    if not valid_hwid(raw):
        update.message.reply_text(f"❌ Invalid HWID for device {idx}. Try again:"); return HA_INPUT
    u=find_user(name); ex=u["hwids"].split(",") if u and u["hwids"]!="none" else []
    if raw in ex or raw in col:
        update.message.reply_text("⚠️ Already registered. Paste different HWID:"); return HA_INPUT
    col.append(raw); ctx.user_data["ha_c"]=col
    update.message.reply_text(f"✅ Device {idx}: `{fmt(raw)}`",parse_mode=ParseMode.MARKDOWN)
    if idx<total:
        ctx.user_data["ha_i"]=idx+1
        update.message.reply_text(f"📱 *Device {idx+1} of {total}*\n\nPaste HWID:",parse_mode=ParseMode.MARKDOWN)
        return HA_INPUT
    users=read_users(); added=0
    for u in users:
        if u["username"]==name:
            ex2=u["hwids"].split(",") if u["hwids"]!="none" else []
            for h in col:
                if h not in ex2: ex2.append(h); added+=1
            u["hwids"]=",".join(ex2) if ex2 else "none"; u["hl"]="1" if ex2 else "0"
    write_users(users)
    total_now=cnt_hwids(find_user(name)["hwids"])
    update.message.reply_text(f"✅ *Added {added} device(s) to `{name}`*\nTotal: *{total_now}*",
                               parse_mode=ParseMode.MARKDOWN,reply_markup=back())
    ctx.user_data.clear(); return ConversationHandler.END

# ── HWID REMOVE ───────────────────────────────────────────────
@admin_only
def hr_start(update, ctx):
    users=[u for u in read_users() if u["hl"]=="1" and u["hwids"]!="none"]
    if not users:
        reply(update,"📱 No users with HWID locks."); return ConversationHandler.END
    kb=InlineKeyboardMarkup([[InlineKeyboardButton(u["username"],callback_data=f"hr_{u['username']}")] for u in users]+[[InlineKeyboardButton("❌ Cancel",callback_data="hr_x")]])
    reply(update,"📱 *Remove HWID Device* — select user:",kb)
    return HR_USER

def hr_user(update, ctx):
    q=update.callback_query; q.answer()
    if q.data=="hr_x": q.edit_message_text("Cancelled."); return ConversationHandler.END
    name=q.data[3:]; ctx.user_data["hr_u"]=name
    u=find_user(name); hwids=u["hwids"].split(",") if u and u["hwids"]!="none" else []
    ctx.user_data["hr_hw"]=hwids
    btns=[[InlineKeyboardButton(f"[{i}] {fmt(h)}",callback_data=f"hrp{i-1}")] for i,h in enumerate(hwids,1)]
    btns+=[[InlineKeyboardButton("🗑 Remove ALL",callback_data="hrp_all")],[InlineKeyboardButton("❌ Cancel",callback_data="hrp_x")]]
    q.edit_message_text(f"📱 Select device to remove from `{name}`:",parse_mode=ParseMode.MARKDOWN,reply_markup=InlineKeyboardMarkup(btns))
    return HR_PICK

def hr_pick(update, ctx):
    q=update.callback_query; q.answer()
    name=ctx.user_data["hr_u"]; hwids=ctx.user_data["hr_hw"]; users=read_users()
    if q.data=="hrp_x":
        q.edit_message_text("Cancelled."); ctx.user_data.clear(); return ConversationHandler.END
    if q.data=="hrp_all":
        for u in users:
            if u["username"]==name: u["hwids"]="none"; u["hl"]="0"
        write_users(users)
        q.edit_message_text(f"✅ All HWIDs removed from `{name}`.",parse_mode=ParseMode.MARKDOWN,reply_markup=back())
    else:
        idx=int(q.data[3:]); removed=hwids[idx]; rest=[h for i,h in enumerate(hwids) if i!=idx]
        for u in users:
            if u["username"]==name: u["hwids"]=",".join(rest) if rest else "none"; u["hl"]="1" if rest else "0"
        write_users(users)
        q.edit_message_text(f"✅ Removed from `{name}`:\n`{fmt(removed)}`\nRemaining: *{len(rest)}*",
                             parse_mode=ParseMode.MARKDOWN,reply_markup=back())
    ctx.user_data.clear(); return ConversationHandler.END

# ── HWID VIEW USER ────────────────────────────────────────────
@admin_only
def hvu_start(update, ctx):
    users=read_users()
    if not users:
        reply(update,"👥 No users."); return ConversationHandler.END
    kb=InlineKeyboardMarkup([[InlineKeyboardButton(u["username"],callback_data=f"hvu_{u['username']}")] for u in users]+[[InlineKeyboardButton("❌ Cancel",callback_data="hvu_x")]])
    reply(update,"📱 *View User Devices* — select:",kb)
    return HVU_PICK

def hvu_pick(update, ctx):
    q=update.callback_query; q.answer()
    if q.data=="hvu_x": q.edit_message_text("Cancelled."); return ConversationHandler.END
    name=q.data[4:]; u=find_user(name); n=cnt_hwids(u["hwids"]) if u else 0
    lines=[f"*📱 Devices for `{name}`*\n━━━━━━━━━━━━━━━━━━━━━━"]
    if u and u["hl"]=="1" and u["hwids"]!="none":
        lines.append(f"Status: 🔒 *LOCKED — {n} device(s)*")
        for i,h in enumerate(u["hwids"].split(","),1):
            lines.append(f"\n*Device [{i}]*\n  `{h}`\n  `{fmt(h)}`")
        lines.append("\n_Only these devices can connect._")
    else:
        lines.append("Status: 🔓 *No HWID set*\n_Any device can connect._")
    q.edit_message_text("\n".join(lines),parse_mode=ParseMode.MARKDOWN,reply_markup=back())
    return ConversationHandler.END

# ── HWID CLEAR ALL ────────────────────────────────────────────
@admin_only
def hc_start(update, ctx):
    users=[u for u in read_users() if u["hl"]=="1" and u["hwids"]!="none"]
    if not users:
        reply(update,"📱 No users with HWID locks."); return ConversationHandler.END
    kb=InlineKeyboardMarkup([[InlineKeyboardButton(u["username"],callback_data=f"hc_{u['username']}")] for u in users]+[[InlineKeyboardButton("❌ Cancel",callback_data="hc_x")]])
    reply(update,"📱 *Clear All Devices* — select user:",kb)
    return HC_USER

def hc_user(update, ctx):
    q=update.callback_query; q.answer()
    if q.data=="hc_x": q.edit_message_text("Cancelled."); return ConversationHandler.END
    name=q.data[3:]; ctx.user_data["hc_u"]=name
    n=cnt_hwids(find_user(name)["hwids"])
    kb=InlineKeyboardMarkup([[InlineKeyboardButton("✅ Yes, clear all",callback_data="hcc_y")],[InlineKeyboardButton("❌ Cancel",callback_data="hcc_n")]])
    q.edit_message_text(f"⚠️ Clear ALL {n} HWID(s) from `{name}`?\nAny device will be able to connect after.",
                        parse_mode=ParseMode.MARKDOWN,reply_markup=kb)
    return HC_CONFIRM

def hc_confirm(update, ctx):
    q=update.callback_query; q.answer()
    if q.data=="hcc_n":
        q.edit_message_text("Cancelled."); ctx.user_data.clear(); return ConversationHandler.END
    name=ctx.user_data["hc_u"]; users=read_users()
    for u in users:
        if u["username"]==name: u["hwids"]="none"; u["hl"]="0"
    write_users(users)
    q.edit_message_text(f"✅ All HWID devices cleared for `{name}`.",parse_mode=ParseMode.MARKDOWN,reply_markup=back())
    ctx.user_data.clear(); return ConversationHandler.END

# ── CHANGE PORT ───────────────────────────────────────────────
@admin_only
def cp_start(update, ctx):
    cur=get_port(); ctx.user_data["cp_old"]=cur
    reply(update,f"🔌 *Change UDP Port Range*\nCurrent: `{cur}`\n\nEnter *new start port* (e.g. `6000`):")
    return CP_START

def cp_s(update, ctx):
    ps=update.message.text.strip()
    if not ps.isdigit():
        update.message.reply_text("❌ Numbers only. Enter start port:"); return CP_START
    ctx.user_data["cp_s"]=ps
    update.message.reply_text("Enter *end port* (e.g. `19999`):",parse_mode=ParseMode.MARKDOWN)
    return CP_END

def cp_e(update, ctx):
    pe=update.message.text.strip(); ps=ctx.user_data["cp_s"]
    if not pe.isdigit():
        update.message.reply_text("❌ Numbers only. Enter end port:"); return CP_END
    if int(ps)>=int(pe):
        update.message.reply_text("❌ Start must be less than end:"); return CP_END
    old=ctx.user_data["cp_old"]; os_p,oe_p=old.split(":") if ":" in old else ("6000","19999")
    iface=run("ip -4 route show default | awk 'NR==1{print $5}'").strip()
    run(f"iptables -t nat -D PREROUTING -i {iface} -p udp --dport {os_p}:{oe_p} -j DNAT --to-destination :{LISTEN_PORT} 2>/dev/null")
    run(f"iptables -t nat -A PREROUTING -i {iface} -p udp --dport {ps}:{pe} -j DNAT --to-destination :{LISTEN_PORT}")
    run("iptables-save > /etc/iptables/rules.v4 2>/dev/null")
    run(f"ufw delete allow {os_p}:{oe_p}/udp 2>/dev/null; ufw allow {ps}:{pe}/udp 2>/dev/null")
    open(PORT_FILE,"w").write(f"{ps}:{pe}")
    update.message.reply_text(f"✅ *Port range changed!*\nOld: `{old}` → New: `{ps}:{pe}`",
                               parse_mode=ParseMode.MARKDOWN,reply_markup=back())
    ctx.user_data.clear(); return ConversationHandler.END

# ── RESTORE BACKUP ────────────────────────────────────────────
@admin_only
def rb_start(update, ctx):
    if update.callback_query: update.callback_query.answer()
    try: files=sorted([f for f in os.listdir(BACKUP_DIR) if f.endswith(".tar.gz")],reverse=True)
    except: files=[]
    if not files:
        reply(update,"💾 No backups found."); return ConversationHandler.END
    btns=[[InlineKeyboardButton(f[:35],callback_data=f"rb_{f}")] for f in files[:10]]
    btns+=[[InlineKeyboardButton("❌ Cancel",callback_data="rb_x")]]
    reply(update,"📂 *Restore Backup* — select:",InlineKeyboardMarkup(btns))
    return RB_PICK

def rb_pick(update, ctx):
    q=update.callback_query; q.answer()
    if q.data=="rb_x": q.edit_message_text("Cancelled."); return ConversationHandler.END
    fname=q.data[3:]; fpath=os.path.join(BACKUP_DIR,fname)
    if not os.path.exists(fpath):
        q.edit_message_text("❌ File not found."); return ConversationHandler.END
    run(f"tar -xzf {fpath} -C / 2>/dev/null"); rebuild(); run("systemctl restart zivpn")
    q.edit_message_text(f"✅ *Restored from:*\n`{fname}`",parse_mode=ParseMode.MARKDOWN,reply_markup=back())
    return ConversationHandler.END

# ── GENERATE CODES ────────────────────────────────────────────
@admin_only
def gc_start(update, ctx):
    kb=InlineKeyboardMarkup([
        [InlineKeyboardButton("1",callback_data="gcc1"),InlineKeyboardButton("2",callback_data="gcc2"),InlineKeyboardButton("3",callback_data="gcc3")],
        [InlineKeyboardButton("5",callback_data="gcc5"),InlineKeyboardButton("10",callback_data="gcc10")],
    ])
    reply(update,"🎫 *Generate Access Codes*\n\nHow many codes?",kb)
    return GC_COUNT

def gc_count(update, ctx):
    q=update.callback_query; q.answer()
    ctx.user_data["gcc"]=int(q.data[3:])
    q.edit_message_text("Enter a *label*\n(e.g. `John - April payment`):",parse_mode=ParseMode.MARKDOWN)
    return GC_LABEL

def gc_label(update, ctx):
    label=update.message.text.strip().replace(":",""); count=ctx.user_data["gcc"]
    chars="ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    now_s=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    codes=[]; os.makedirs(os.path.dirname(CODES_DB),exist_ok=True)
    with open(CODES_DB,"a") as f:
        for _ in range(count):
            raw="".join(secrets.choice(chars) for _ in range(16))
            code=f"{raw[:4]}-{raw[4:8]}-{raw[8:12]}-{raw[12:16]}"
            f.write(f"{code}:unused:{now_s}:{label}\n"); codes.append(code)
    lines=[f"🎫 *{count} Code(s) Generated*\n_Label: {label}_\n━━━━━━━━━━━━━━━━━━━━━━"]
    for c in codes: lines.append(f"🟢 `{c}`")
    lines.append("\n_Each code valid for ONE installation only._")
    update.message.reply_text("\n".join(lines),parse_mode=ParseMode.MARKDOWN)
    ctx.user_data.clear(); return ConversationHandler.END

# ── CANCEL ────────────────────────────────────────────────────
def cancel(update, ctx):
    ctx.user_data.clear()
    if update.callback_query: update.callback_query.edit_message_text("❌ Cancelled.")
    else: update.message.reply_text("❌ Cancelled.")
    return ConversationHandler.END

# ══════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════
def main():
    if BOT_TOKEN=="YOUR_BOT_TOKEN_HERE":
        print("ERROR: Set BOT_TOKEN and ADMIN_IDS first!"); return

    up=Updater(BOT_TOKEN); dp=up.dispatcher

    def conv(entry_cmds, entry_cb, states, fb=None):
        entries=[CommandHandler(c,fn) for c,fn in entry_cmds]
        if entry_cb: entries.append(CallbackQueryHandler(entry_cb[0],pattern=f"^{entry_cb[1]}$"))
        return ConversationHandler(entry_points=entries,states=states,
                                   fallbacks=[CommandHandler("cancel",cancel)],allow_reentry=True)

    dp.add_handler(conv([("adduser",add_start)],   (add_start,"add_user"), {
        ADD_USERNAME:   [MessageHandler(Filters.text&~Filters.command,add_uname)],
        ADD_PASSWORD:   [MessageHandler(Filters.text&~Filters.command,add_pass)],
        ADD_EXPIRY:     [CallbackQueryHandler(add_exp,   pattern="^e[136yn]$")],
        ADD_CONN:       [CallbackQueryHandler(add_conn,  pattern="^m")],
        ADD_HWID_CHOICE:[CallbackQueryHandler(add_hwid_choice,pattern="^nd")],
        ADD_HWID_INPUT: [MessageHandler(Filters.text&~Filters.command,add_hwid_input)],
    }))
    dp.add_handler(conv([("removeuser",rm_start)],  (rm_start,"remove_user"),   {RM_PICK:[CallbackQueryHandler(rm_pick,pattern="^rm_")]}))
    dp.add_handler(conv([("renewuser",rv_start)],   (rv_start,"renew_user"),    {RV_PICK:[CallbackQueryHandler(rv_pick,pattern="^rv_")],RV_EXP:[CallbackQueryHandler(rv_exp,pattern="^re")]}))
    dp.add_handler(conv([("setconn",sc_start)],     (sc_start,"set_conn"),      {SC_USER:[CallbackQueryHandler(sc_user,pattern="^sc_")],SC_PICK:[CallbackQueryHandler(sc_pick,pattern="^sl")]}))
    dp.add_handler(conv([("hwidadd",ha_start)],     (ha_start,"hwid_add"),      {HA_USER:[CallbackQueryHandler(ha_user,pattern="^ha_")],HA_COUNT:[CallbackQueryHandler(ha_count,pattern="^hac")],HA_INPUT:[MessageHandler(Filters.text&~Filters.command,ha_input)]}))
    dp.add_handler(conv([("hwidremove",hr_start)],  (hr_start,"hwid_remove"),   {HR_USER:[CallbackQueryHandler(hr_user,pattern="^hr_")],HR_PICK:[CallbackQueryHandler(hr_pick,pattern="^hrp")]}))
    dp.add_handler(conv([("hwidview",hvu_start)],   (hvu_start,"hwid_view_user"),{HVU_PICK:[CallbackQueryHandler(hvu_pick,pattern="^hvu_")]}))
    dp.add_handler(conv([("hwidclear",hc_start)],   (hc_start,"hwid_clear"),    {HC_USER:[CallbackQueryHandler(hc_user,pattern="^hc_")],HC_CONFIRM:[CallbackQueryHandler(hc_confirm,pattern="^hcc_")]}))
    dp.add_handler(conv([("changeport",cp_start)],  (cp_start,"change_port"),   {CP_START:[MessageHandler(Filters.text&~Filters.command,cp_s)],CP_END:[MessageHandler(Filters.text&~Filters.command,cp_e)]}))
    dp.add_handler(conv([("restore",rb_start)],     (rb_start,"restore"),       {RB_PICK:[CallbackQueryHandler(rb_pick,pattern="^rb_")]}))
    dp.add_handler(conv([("gencode",gc_start)],     (gc_start,"gen_code"),      {GC_COUNT:[CallbackQueryHandler(gc_count,pattern="^gcc")],GC_LABEL:[MessageHandler(Filters.text&~Filters.command,gc_label)]}))

    dp.add_handler(CommandHandler("start",  cmd_start))
    dp.add_handler(CommandHandler("menu",   cmd_menu))
    dp.add_handler(CommandHandler("cancel", cancel))
    dp.add_handler(CallbackQueryHandler(btn))

    print(f"OPUDP Bot v2.0 started — Admin IDs: {ADMIN_IDS}")
    up.start_polling(); up.idle()

if __name__=="__main__":
    main()
