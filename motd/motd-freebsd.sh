#!/bin/sh
# homelab-bootstrap MOTD -- FreeBSD
# Deployed to /usr/local/etc/homelab-motd.sh
# Sourced from /etc/profile (sh/bash login) and /usr/local/etc/zprofile (zsh login)
# POSIX sh -- no bashisms, no /proc (not mounted by default on FreeBSD)

# interactive shells only (skips scp/sftp/rsync)
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[2;37m'; N='\033[0m'

HOSTNAME=$(hostname -s | tr '[:lower:]' '[:upper:]')
DISTRO="FreeBSD $(freebsd-version -u 2>/dev/null || uname -r)"
KERNEL=$(uname -r)
CPU_MODEL=$(sysctl -n hw.model | sed 's/  */ /g')
CPU_CORES=$(sysctl -n hw.ncpu)
DATE_NOW=$(date '+%A, %d %B %Y  %H:%M')

# uptime from kern.boottime (no `uptime -p` on FreeBSD)
BOOT_SEC=$(sysctl -n kern.boottime | sed -n 's/.*{ sec = \([0-9][0-9]*\).*/\1/p')
NOW_SEC=$(date +%s)
UP=$(( NOW_SEC - BOOT_SEC ))
UP_D=$(( UP / 86400 )); UP_H=$(( UP % 86400 / 3600 )); UP_M=$(( UP % 3600 / 60 ))
UPTIME=""
[ "$UP_D" -gt 0 ] && UPTIME="${UP_D} days, "
UPTIME="${UPTIME}${UP_H}h ${UP_M}m"

LOAD=$(sysctl -n vm.loadavg | tr -d '{}' | sed 's/^ *//; s/ *$//')

# memory via vm.stats (no `free` on FreeBSD); free+inactive counted as available
PAGESZ=$(sysctl -n hw.pagesize)
MEM_TOTAL_B=$(sysctl -n hw.physmem)
FREE_PG=$(sysctl -n vm.stats.vm.v_free_count)
INACT_PG=$(sysctl -n vm.stats.vm.v_inactive_count)
MEM_USED_B=$(( MEM_TOTAL_B - (FREE_PG + INACT_PG) * PAGESZ ))
[ "$MEM_USED_B" -lt 0 ] && MEM_USED_B=0
MEM_PCT=$(( MEM_USED_B * 100 / MEM_TOTAL_B ))

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

# ZFS ARC size (silently skipped on UFS-only systems)
ARC_B=$(sysctl -n kstat.zfs.misc.arcstats.size 2>/dev/null || echo 0)
ARC=""
[ "$ARC_B" -gt 0 ] && ARC=$(human_bytes "$ARC_B")

DISK_USED=$(df -h / | awk 'NR==2{print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
DISK_PCT=$(df / | awk 'NR==2{print $5}' | tr -d '%')

# default-route interface -> its inet addr (no `hostname -I` on FreeBSD)
IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
IP_ADDR="n/a"
[ -n "$IFACE" ] && IP_ADDR=$(ifconfig "$IFACE" inet 2>/dev/null | awk '/inet /{print $2; exit}')

USERS=$(who | wc -l | tr -d ' ')

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
printf "  ${D}%-12s${N} %s\n"  "CPU"      "$CPU_MODEL ($CPU_CORES cores)"
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
