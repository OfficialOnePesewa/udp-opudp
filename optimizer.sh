#!/bin/bash
# ============================================
# VPS Optimizer Script
# Compatible: Ubuntu 16/18/20/22/24 & Debian 9/10/11/12
# GitHub: https://github.com/OfficialOnePesewa/vpn-scripts
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${RED}Run as root!${NC}" && exit 1

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}       VPS Optimizer for VPN          ${NC}"
echo -e "${CYAN}======================================${NC}"

# ---- BBR CONGESTION CONTROL ----
echo -e "${YELLOW}Enabling BBR congestion control...${NC}"
modprobe tcp_bbr 2>/dev/null
echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

# ---- TCP/NETWORK SPEED ----
echo -e "${YELLOW}Optimizing TCP/Network settings...${NC}"
cat >> /etc/sysctl.conf << EOF

# --- VPS Optimizer TCP/Network ---
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_syn_retries=3
net.ipv4.tcp_synack_retries=3
net.ipv4.tcp_max_syn_backlog=4096
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_keepalive_intvl=15
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.core.rmem_default=65536
net.core.wmem_default=65536
net.core.netdev_max_backlog=65536
net.core.somaxconn=65536
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.ipv4.tcp_mem=786432 1048576 26777216
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_forward=1
EOF

sysctl -p > /dev/null 2>&1

# ---- SWAP MEMORY ----
echo -e "${YELLOW}Setting up Swap memory...${NC}"

# Remove existing swap if any
swapoff -a 2>/dev/null
sed -i '/swapfile/d' /etc/fstab
rm -f /swapfile

# Create 1GB swap
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Optimize swap usage
echo "vm.swappiness=10" >> /etc/sysctl.conf
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
sysctl -p > /dev/null 2>&1

# ---- VERIFY ----
echo -e "${CYAN}======================================${NC}"
echo -e "${GREEN} Optimization Complete!${NC}"
echo -e "${CYAN}======================================${NC}"

# BBR Check
BBR=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
if [[ "$BBR" == "bbr" ]]; then
  echo -e "${GREEN} BBR: ENABLED${NC}"
else
  echo -e "${RED} BBR: NOT ACTIVE (reboot required)${NC}"
fi

# Swap Check
SWAP=$(swapon --show | grep swapfile)
if [[ -n "$SWAP" ]]; then
  echo -e "${GREEN} Swap: ACTIVE (1GB)${NC}"
else
  echo -e "${RED} Swap: NOT ACTIVE${NC}"
fi

echo -e "${CYAN}======================================${NC}"
echo -e "${YELLOW} Rebooting in 5 seconds to apply all changes...${NC}"
echo -e "${YELLOW} Press CTRL+C to cancel reboot.${NC}"
sleep 5
reboot
