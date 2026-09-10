#!/bin/sh
# homelab-bootstrap MOTD -- Solaris 11.4
# Deployed to /etc/homelab-motd.sh
# Sourced from /etc/profile (sh/ksh/bash login) and /etc/zprofile (zsh login)
# POSIX sh -- no bashisms. kstat(1) field names verified on Solaris 11.4 x86;
# re-check cpu_info/system_pages/zfs kstats if this is illumos/OmniOS/etc.

# interactive shells only (skips scp/sftp/rsync)
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[2;37m'; N='\033[0m'

HOSTNAME=$(hostname | tr '[:lower:]' '[:upper:]')
DISTRO=$(head -n1 /etc/release 2>/dev/null | sed 's/^ *//; s/ *$//')
[ -z "$DISTRO" ] && DISTRO="Solaris $(uname -r)"
KERNEL="SunOS $(uname -r) ($(uname -v))"
CPU_MODEL=$(kstat -p cpu_info:0:cpu_info0:brand 2>/dev/null | awk -F'\t' '{print $2}')
CPU_CORES=$(psrinfo | wc -l | tr -d ' ')
DATE_NOW=$(date '+%A, %d %B %Y  %H:%M')

# uptime from kstat boot_time (no `uptime -p` on Solaris)
BOOT_SEC=$(kstat -p unix:0:system_misc:boot_time 2>/dev/null | awk -F'\t' '{print $2}')
NOW_SEC=$(date +%s)
UPTIME="n/a"
if [ -n "$BOOT_SEC" ]; then
  UP=$(( NOW_SEC - BOOT_SEC ))
  UP_D=$(( UP / 86400 )); UP_H=$(( UP % 86400 / 3600 )); UP_M=$(( UP % 3600 / 60 ))
  UPTIME=""
  [ "$UP_D" -gt 0 ] && UPTIME="${UP_D} days, "
  UPTIME="${UPTIME}${UP_H}h ${UP_M}m"
fi

LOAD=$(uptime | sed -n 's/.*load average: *//p')

# memory via kstat system_pages (no `free` on Solaris)
PAGESZ=$(pagesize)
TOTAL_PG=$(kstat -p unix:0:system_pages:physmem 2>/dev/null | awk -F'\t' '{print $2}')
FREE_PG=$(kstat -p unix:0:system_pages:freemem 2>/dev/null | awk -F'\t' '{print $2}')
MEM_TOTAL_B=0; MEM_USED_B=0; MEM_PCT=0
if [ -n "$TOTAL_PG" ] && [ -n "$FREE_PG" ]; then
  MEM_TOTAL_B=$(( TOTAL_PG * PAGESZ ))
  MEM_USED_B=$(( MEM_TOTAL_B - FREE_PG * PAGESZ ))
  [ "$MEM_USED_B" -lt 0 ] && MEM_USED_B=0
  [ "$MEM_TOTAL_B" -gt 0 ] && MEM_PCT=$(( MEM_USED_B * 100 / MEM_TOTAL_B ))
fi

human_bytes() {
  awk -v b="$1" 'BEGIN {
    split("B K M G T", u, " "); i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    if (b < 10 && i > 1) printf "%.1f%s", b, u[i]
    else                 printf "%.0f%s", b, u[i]
  }'
}
MEM_USED=$(human_bytes "$MEM_USED_B")
MEM_TOTAL=$(human_bytes "$MEM_TOTAL_B")

# ZFS ARC size (Solaris root pool is ZFS by default since 11.0)
ARC_B=$(kstat -p zfs:0:arcstats:size 2>/dev/null | awk -F'\t' '{print $2}')
ARC=""
[ -n "$ARC_B" ] && [ "$ARC_B" -gt 0 ] 2>/dev/null && ARC=$(human_bytes "$ARC_B")

DISK_USED=$(df -h / | awk 'NR==2{print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
DISK_PCT=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')

# default-route interface -> its inet addr
IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
IP_ADDR="n/a"
[ -n "$IFACE" ] && IP_ADDR=$(ifconfig "$IFACE" inet 2>/dev/null | awk '/inet /{print $2; exit}')

USERS=$(who | wc -l | tr -d ' ')

[ "${DISK_PCT:-0}" -ge 90 ] && DISK_COLOR=$R || { [ "${DISK_PCT:-0}" -ge 75 ] && DISK_COLOR=$Y || DISK_COLOR=$G; }
[ "${MEM_PCT:-0}"  -ge 90 ] && MEM_COLOR=$R  || { [ "${MEM_PCT:-0}"  -ge 75 ] && MEM_COLOR=$Y  || MEM_COLOR=$G; }

PAD=4; LEN=${#HOSTNAME}; INNER=$(( LEN + PAD * 2 ))
LINE=$(printf '=%.0s' $(seq 1 $INNER))
LPAD=$(printf '%*s' $PAD '')

printf "\n"
printf "${R}+${LINE}+${N}\n"
printf "${R}|${N}${LPAD}${W}${HOSTNAME}${N}${LPAD}${R}|${N}\n"
printf "${R}+${LINE}+${N}\n\n"
printf "  ${D}%-12s${N} %s\n"  "System"   "$DISTRO"
printf "  ${D}%-12s${N} %s\n"  "Kernel"   "$KERNEL"
printf "  ${D}%-12s${N} %s\n"  "CPU"      "$CPU_MODEL ($CPU_CORES vCPU)"
printf "  ${D}%-12s${N} %s\n"  "Date"     "$DATE_NOW"
printf "\n"
printf "  ${D}%-12s${N} %s\n"  "IP"       "$IP_ADDR"
printf "  ${D}%-12s${N} %s\n"  "Uptime"   "$UPTIME"
printf "  ${D}%-12s${N} %s\n"  "Load"     "$LOAD"
printf "  ${D}%-12s${N} ${MEM_COLOR}${MEM_USED} / ${MEM_TOTAL} (${MEM_PCT}%%)${N}\n" "Memory"
[ -n "$ARC" ] && printf "  ${D}%-12s${N} %s\n" "ZFS ARC" "$ARC"
printf "  ${D}%-12s${N} ${DISK_COLOR}${DISK_USED} / ${DISK_TOTAL} (${DISK_PCT}%%)${N}\n" "Disk /"
printf "  ${D}%-12s${N} %s\n"  "Users"    "$USERS logged in"
printf "\n"
