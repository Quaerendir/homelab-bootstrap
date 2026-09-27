#!/bin/bash
# homelab-bootstrap MOTD -- Debian/Ubuntu
# Deployed to /etc/update-motd.d/01-homelab

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[2;37m'; N='\033[0m'

HOSTNAME=$(hostname -s | tr '[:lower:]' '[:upper:]')
DISTRO=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)
KERNEL=$(uname -r)
UPTIME=$(uptime -p | sed 's/up //')
LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
MEM_USED=$(free -h | awk '/^Mem/{print $3}')
MEM_TOTAL=$(free -h | awk '/^Mem/{print $2}')
MEM_PCT=$(free | awk '/^Mem/{printf "%.0f", $3/$2*100}')
DISK_USED=$(df -h / | awk 'NR==2{print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
DISK_PCT=$(df / | awk 'NR==2{print $5}' | tr -d '%')
IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
USERS=$(who | wc -l)
CPU_MODEL=""
CPU_CORES_DETAIL=""
# NVIDIA GB10 Grace Blackwell Superchip (DGX Spark-class: ASUS Ascent GX10, Dell Pro
# Max GB10, Gigabyte AI TOP ATOM, HP ZGX Nano, Lenovo...) ships under a different OEM
# marketing name per vendor for the same reference chip -- detect via the GPU name
# (stable across OEMs, unlike DMI product_name) and report the canonical spec name,
# with lscpu's per-core-type breakdown (10x Cortex-X925 + 10x Cortex-A725, per spec).
if command -v nvidia-smi &>/dev/null; then
  GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
  if [[ "$GPU_NAME" == *"GB10"* ]]; then
    CPU_MODEL="NVIDIA GB10 Grace Blackwell Superchip"
    CPU_CORES_DETAIL=$(lscpu 2>/dev/null | awk -F': *' '
      /Model name:/ { model=$2 }
      /Core\(s\) per socket:/ { if (model != "") { printf "%s%sx %s", (n++?" + ":""), $2, model; model="" } }
    ')
  fi
fi
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
# ARM boards (Raspberry Pi and most SBCs) have no "model name" in /proc/cpuinfo --
# /proc/device-tree/model has the friendly board name instead (Pi included).
[ -z "$CPU_MODEL" ] && [ -r /proc/device-tree/model ] && CPU_MODEL=$(tr -d '\0' < /proc/device-tree/model)
# Older/non-devicetree kernels: /proc/cpuinfo's trailing "Model" line (Raspberry Pi's own field)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(grep -m1 '^Model' /proc/cpuinfo | cut -d: -f2 | xargs)
# ACPI-based ARM64 boards (no device tree at all, e.g. non-NVIDIA server SoCs) --
# fall back to the board's DMI product name, then to lscpu's core name.
[ -z "$CPU_MODEL" ] && [ -r /sys/class/dmi/id/product_name ] && CPU_MODEL=$(cat /sys/class/dmi/id/product_name)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu 2>/dev/null | grep -m1 'Model name:' | cut -d: -f2 | xargs)
CPU_CORES=$(nproc)
DATE_NOW=$(date '+%A, %d %B %Y  %H:%M')

[ "$DISK_PCT" -ge 90 ] && DISK_COLOR=$R || { [ "$DISK_PCT" -ge 75 ] && DISK_COLOR=$Y || DISK_COLOR=$G; }
[ "$MEM_PCT"  -ge 90 ] && MEM_COLOR=$R  || { [ "$MEM_PCT"  -ge 75 ] && MEM_COLOR=$Y  || MEM_COLOR=$G; }

PAD=4; LEN=${#HOSTNAME}; INNER=$(( LEN + PAD * 2 ))
LINE=$(printf '=%.0s' $(seq 1 $INNER))
LPAD=$(printf '%*s' $PAD '')

printf "\n"
printf "${R}+${LINE}+${N}\n"
printf "${R}|${N}${LPAD}${W}${HOSTNAME}${N}${LPAD}${R}|${N}\n"
printf "${R}+${LINE}+${N}\n\n"
printf "  ${D}%-12s${N} %s\n"  "System"   "$DISTRO"
printf "  ${D}%-12s${N} %s\n"  "Kernel"   "$KERNEL"
printf "  ${D}%-12s${N} %s\n"  "CPU"      "$CPU_MODEL (${CPU_CORES_DETAIL:-$CPU_CORES cores})"
printf "  ${D}%-12s${N} %s\n"  "Date"     "$DATE_NOW"
printf "\n"
printf "  ${D}%-12s${N} %s\n"  "IP"       "$IP_ADDR"
printf "  ${D}%-12s${N} %s\n"  "Uptime"   "$UPTIME"
printf "  ${D}%-12s${N} %s\n"  "Load"     "$LOAD"
printf "  ${D}%-12s${N} ${MEM_COLOR}${MEM_USED} / ${MEM_TOTAL} (${MEM_PCT}%%)${N}\n" "Memory"
printf "  ${D}%-12s${N} ${DISK_COLOR}${DISK_USED} / ${DISK_TOTAL} (${DISK_PCT}%%)${N}\n" "Disk /"
printf "  ${D}%-12s${N} %s\n"  "Users"    "$USERS logged in"
printf "\n"
