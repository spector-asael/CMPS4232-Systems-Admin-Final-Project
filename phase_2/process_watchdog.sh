#!/bin/bash
# Filename: process_watchdog.sh
# Purpose: Resource-efficient process monitoring, priority throttling, and threshold enforcement.
# Phase 2 - Log Analytics, Regex & Job Automation

set -euo pipefail

# ------------------------------------------------------------
# Configuration Parameters
# ------------------------------------------------------------
LOG_FILE="/var/log/process_watchdog.log"
CPU_WARN_THRESHOLD=75.0
CPU_CRIT_THRESHOLD=90.0
MEM_WARN_THRESHOLD=75.0
MEM_CRIT_THRESHOLD=90.0

# Critical System Process Whitelist (Never terminate or renice)
WHITELIST_PATTERNS="^(sshd|systemd|cron|dockerd|rsyslogd|dbus-daemon|init)$"

log_action() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# 1. Enforce Root Privileges
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Process watchdog requires root privileges (sudo)." >&2
    exit 1
fi

# 2. Setup Log Destination
touch "$LOG_FILE" 2>/dev/null || { echo "[ERROR] Cannot write to $LOG_FILE" >&2; exit 1; }
chmod 640 "$LOG_FILE"

log_action "[INFO] Watchdog inspection cycle started."

# 3. High-Efficiency Pre-filtered Process Scan
# Pre-filters processes in AWK to eliminate redundant subshell forks inside bash
ps -eo pid,ppid,%cpu,%mem,comm --no-headers | awk -v cw="$CPU_WARN_THRESHOLD" \
                                                 -v cc="$CPU_CRIT_THRESHOLD" \
                                                 -v mw="$MEM_WARN_THRESHOLD" \
                                                 -v mc="$MEM_CRIT_THRESHOLD" '
{
    pid = $1; ppid = $2; cpu = $3; mem = $4; comm = $5;
    if (cpu >= cw || mem >= mw) {
        status = "WARN";
        if (cpu >= cc || mem >= mc) { status = "CRIT"; }
        print pid, cpu, mem, status, comm;
    }
}' | while read -r pid cpu mem status comm; do

    # Safety Protection 1: Skip system PIDs (<= 1000), self ($$), and parent ($PPID)
    if [[ "$pid" -le 1000 || "$pid" -eq $$ || "$pid" -eq $PPID ]]; then
        continue
    fi

    # Safety Protection 2: Whitelist core infrastructure daemons
    if [[ "$comm" =~ $WHITELIST_PATTERNS ]]; then
        log_action "[SKIP] Whitelisted infrastructure process '$comm' (PID: $pid) exceeded limit (CPU: ${cpu}%, MEM: ${mem}%)."
        continue
    fi

    # --- CRITICAL ACTION: SIGTERM -> Non-blocking Verification -> SIGKILL ---
    if [[ "$status" == "CRIT" ]]; then
        log_action "[CRITICAL] Process '$comm' (PID: $pid) breached threshold (CPU: ${cpu}%, MEM: ${mem}%). Sending SIGTERM (15)."
        kill -15 "$pid" 2>/dev/null || true

        # Fast non-blocking check (poll up to 3 seconds)
        terminated=0
        for i in {1..6}; do
            sleep 0.5
            if ! kill -0 "$pid" 2>/dev/null; then
                terminated=1
                break
            fi
        done

        if [[ "$terminated" -eq 1 ]]; then
            log_action "[INFO] Process '$comm' (PID: $pid) terminated gracefully after SIGTERM."
        else
            log_action "[CRITICAL] Process '$comm' (PID: $pid) failed to exit. Escalating to SIGKILL (9)."
            kill -9 "$pid" 2>/dev/null || true
        fi

    # --- WARNING ACTION: Apply Priority Throttling (renice) ---
    elif [[ "$status" == "WARN" ]]; then
        current_nice=$(ps -o ni= -p "$pid" 2>/dev/null | xargs || echo "0")
        if [[ -n "$current_nice" && "$current_nice" -lt 10 ]]; then
            log_action "[WARNING] Throttling high-resource process '$comm' (PID: $pid, CPU: ${cpu}%, MEM: ${mem}%). Applying renice +10."
            renice +10 -p "$pid" &>/dev/null || true
        fi
    fi

done

log_action "[INFO] Watchdog inspection cycle completed successfully."
exit 0
