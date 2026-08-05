#!/bin/bash

# ==============================================================================
# Script Name : server-health-monitor.sh
# Description : Monitors server load and automatically captures a complete
#               system health snapshot when the load average exceeds the
#               configured threshold. The report includes CPU, memory,
#               MySQL, network, processes, TCP connections, and OOM events
#               to assist in troubleshooting high-load incidents.
#
# Author      : way to host
# Company     : way to host
# Website     : way to host
# Version     : 1.0
# Created     : 2026-08-05
# Last Update : 2026-08-05
# License     : Internal Use Only
#
# Features:
#   ✓ Load threshold monitoring
#   ✓ Automatic diagnostic snapshot
#   ✓ CPU & Memory statistics
#   ✓ VMStat statistics
#   ✓ TCP connection state summary
#   ✓ Top 20 IPs / Process / Port
#   ✓ MySQL connection statistics
#   ✓ MySQL processlist & full processlist
#   ✓ MySQL server status
#   ✓ Top CPU-consuming processes
#   ✓ Top CPU-consuming threads
#   ✓ Top memory-consuming processes
#   ✓ Recent Linux OOM Killer events
#   ✓ SAR load history (if installed)
#   ✓ Automatic log rotation
#
# Log Directory:
#   /var/log/mysql-monitor/
#
# Requirements:
#   - Bash
#   - MySQL Client (mysql, mysqladmin)
#   - net-tools (netstat)
#   - iproute2 (ss)
#   - procps-ng (vmstat, ps, top)
#   - sysstat (sar) [Optional]
#
# Changelog:
# ------------------------------------------------------------------------------
# v1.0 - Initial Release
#   - Automatic server health snapshot on high load
#   - Added MySQL diagnostics
#   - Added network connection analysis
#   - Added process and thread statistics
#   - Added OOM detection
#   - Added automatic log cleanup
#
# ==============================================================================

THRESHOLD=10
DIR="/var/log/mysql-monitor"

mkdir -p "$DIR"

# Delete logs older than 30 days
find "$DIR" -type f -name "oom-*.log" -mtime +30 -delete

LOAD=$(awk '{print $1}' /proc/loadavg)

if awk "BEGIN {exit !($LOAD >= $THRESHOLD)}"; then

LOG="$DIR/oom-$(date +%F_%H-%M-%S).log"

{

echo "===== $(date) ====="
echo "Hostname : $(hostname)"
echo "Uptime   : $(uptime)"
echo "Load     : $(cat /proc/loadavg)"
echo
# ==============================================================================
echo "===== Memory ====="
free -h
echo
# ==============================================================================
echo "===== CPU ====="
top -bn1 | head -10
echo
# ==============================================================================
echo "===== VMStat ====="
vmstat 1 5
echo

if command -v sar >/dev/null 2>&1; then
    echo "===== Load Average History (sar) ====="
    sar -q 1 5
    echo
fi

# ==============================================================================

echo "===== TCP Connection States ====="
ss -ant | awk 'NR>1 {print $1}' | sort | uniq -c | sort -nr
echo
# ==============================================================================
echo "===== SYN-RECV Connections ====="
ss -antp state syn-recv
echo
# ==============================================================================
echo "===== CLOSE-WAIT Connections ====="
ss -antp state close-wait
echo
# ==============================================================================
echo "===== Top 20 IPs / Process / Port ====="
netstat -ntp 2>/dev/null | awk '
$6=="ESTABLISHED"{
    split($5,a,":")
    ip=a[1]
    if(ip=="127.0.0.1") next

    split($4,b,":")
    port=b[length(b)]

    split($7,c,"/")
    proc=c[2]

    key=ip "|" proc "|" port
    cnt[key]++
}
END{
    printf "%-20s %-5s %-20s %-5s\n","IP","Conn","Process","Port"
    for(i in cnt){
        split(i,a,"|")
        printf "%-20s %-5d %-20s %-5s\n",a[1],cnt[i],a[2],a[3]
    }
}' | sort -k2 -nr | head -20
echo

echo "===== MySQL Connection Statistics ====="

timeout 15 bash -c '
get_mysql() {
    mysql -Nse "$1" 2>/dev/null | awk "{print \$2}"
}

MAX_CONN=$(get_mysql "SHOW VARIABLES LIKE '\''max_connections'\'';")
MAX_USED=$(get_mysql "SHOW STATUS LIKE '\''Max_used_connections'\'';")
THREADS=$(get_mysql "SHOW STATUS LIKE '\''Threads_connected'\'';")
RUNNING=$(get_mysql "SHOW STATUS LIKE '\''Threads_running'\'';")
CONNECTIONS=$(get_mysql "SHOW STATUS LIKE '\''Connections'\'';")
ABORTED=$(get_mysql "SHOW STATUS LIKE '\''Aborted_connects'\'';")
SLOW=$(get_mysql "SHOW STATUS LIKE '\''Slow_queries'\'';")
WAIT=$(get_mysql "SHOW VARIABLES LIKE '\''wait_timeout'\'';")
INTERACTIVE=$(get_mysql "SHOW VARIABLES LIKE '\''interactive_timeout'\'';")

PEAK_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($MAX_USED/$MAX_CONN)*100}")
CURR_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($THREADS/$MAX_CONN)*100}")

printf "+----------------------------+------------+------------------------------------------+\n"
printf "| %-26s | %-10s | %-40s |\n" "Metric" "Value" "Details"
printf "+----------------------------+------------+------------------------------------------+\n"

printf "| %-26s | %-10s | %-40s |\n" "Max Connections" "$MAX_CONN" "Configured connection limit"
printf "| %-26s | %-10s | %-40s |\n" "Peak Used" "$MAX_USED" "$MAX_USED/$MAX_CONN (${PEAK_PERCENT}%% used)"
printf "| %-26s | %-10s | %-40s |\n" "Current Connected" "$THREADS" "$THREADS/$MAX_CONN (${CURR_PERCENT}%% used)"
printf "| %-26s | %-10s | %-40s |\n" "Running Queries" "$RUNNING" "Queries executing now"
printf "| %-26s | %-10s | %-40s |\n" "Total Connections" "$CONNECTIONS" "Since MySQL startup"
printf "| %-26s | %-10s | %-40s |\n" "Aborted Connects" "$ABORTED" "Failed connection attempts"
printf "| %-26s | %-10s | %-40s |\n" "Slow Queries" "$SLOW" "Since MySQL startup"
printf "| %-26s | %-10s | %-40s |\n" "wait_timeout" "$WAIT" "Idle connection timeout (sec)"
printf "| %-26s | %-10s | %-40s |\n" "interactive_timeout" "$INTERACTIVE" "Interactive timeout (sec)"

printf "+----------------------------+------------+------------------------------------------+\n"
'
echo
# ==============================================================================
echo "===== MySQL Processlist ====="
timeout 15 mysqladmin processlist
echo
# ==============================================================================
echo "===== MySQL Status ====="
timeout 15 mysqladmin status
echo
# ==============================================================================
echo "===== Top Processes by CPU ====="
ps -eo pid,user,%cpu,%mem,rss,cmd --sort=-%cpu | head -30
echo
# ==============================================================================
echo "=====>>> Top CPU Threads <<<====="
ps -eLo pid,tid,pcpu,pmem,user,comm --sort=-pcpu | head -30
echo
# ==============================================================================
echo "===== Top Processes by Memory ====="
ps -eo pid,user,%cpu,%mem,rss,cmd --sort=-%mem | head -30
echo
# ==============================================================================
echo "===== Recent OOM Messages ====="
dmesg -T 2>/dev/null | grep -i -E "killed process|out of memory|oom" | tail -20
echo

} > "$LOG" 2>&1

fi
