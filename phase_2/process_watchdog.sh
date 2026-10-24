#!/bin/bash
# Filename: process_watchdog.sh
# Purpose: Modular resource-efficient process monitoring, priority throttling, and threshold enforcement.
# Phase 2 - Log Analytics, Regex & Job Automation

set -euo pipefail

# ------------------------------------------------------------
# Global Configuration Parameters
# ------------------------------------------------------------
LOG_FILE="/var/log/process_watchdog.log"
CPU_WARN_THRESHOLD=75.0
CPU_CRIT_THRESHOLD=90.0
MEM_WARN_THRESHOLD=75.0
MEM_CRIT_THRESHOLD=90.0

# Critical System Process Whitelist Pattern
WHITELIST_PATTERNS="^(sshd|systemd|cron|dockerd|rsyslogd|dbus-daemon|init)$"

# ------------------------------------------------------------
# Modular Helper & Logging Functions
# ------------------------------------------------------------

log_action() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# 1. Modular Check: Root Privileges
check_prerequisites() {
    if [[ $EUID -ne 0 ]]; then
        echo "[ERROR] Process watchdog requires root privileges (sudo)." >&2
        exit 1
    fi
}

# 2. Modular Setup: Log File Initialization
init_logging() {
    touch "$LOG_FILE" 2>/dev/null || { echo "[ERROR] Cannot write to $LOG_FILE" >&2; exit 1; }
    chmod 640 "$LOG_FILE"
}

# 3. Modular Safety Check: Protect System & Whitelisted Processes
is_safe_process() {
    local pid="$1"
    local comm="$2"

    # Skip system PIDs (<= 1000), self ($$), and parent ($PPID)
    if [[ "$pid" -le 1000 || "$pid" -eq $$ || "$pid" -eq $PPID ]]; then
        return 1
    fi

    # Skip whitelisted infrastructure daemons
    if [[ "$comm" =~ $WHITELIST_PATTERNS ]]; then
        log_action "[SKIP] Whitelisted process '$comm' (PID: $pid) skipped."
        return 1
    fi

    return 0
}

# 4. Modular Handler: Critical Threshold (SIGTERM -> Escalation -> SIGKILL)
handle_critical_process() {
    local pid="$1"
    local cpu="$2"
    local mem="$3"
    local comm="$4"

    log_action "[CRITICAL] Process '$comm' (PID: $pid) breached limits (CPU: ${cpu}%, MEM: ${mem}%). Issuing SIGTERM (15)."
    kill -15 "$pid" 2>/dev/null || return 0

    # Fast non-blocking poll up to 3 seconds (6 x 0.5s)
    local terminated=0
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
}

# 5. Modular Handler: Warning Threshold (Throttling / Renice)
handle_warning_process() {
    local pid="$1"
    local cpu="$2"
    local mem="$3"
    local comm="$4"

    local raw_nice
    raw_nice=$(ps -o ni= -p "$pid" 2>/dev/null | tr -d ' ' || true)

    # Safe Integer Validation: Guard against race conditions if process dies mid-check
    if [[ -n "$raw_nice" && "$raw_nice" =~ ^-?[0-9]+$ ]]; then
        if [[ "$raw_nice" -lt 10 ]]; then
            log_action "[WARNING] Throttling process '$comm' (PID: $pid, CPU: ${cpu}%, MEM: ${mem}%). Applying renice +10."
            renice +10 -p "$pid" &>/dev/null || true
        fi
    fi
}

# 6. Modular Engine: Process Scanner & Enforcement Loop
scan_and_enforce() {
    # Process scan pre-filtered via AWK for performance
    while read -r pid cpu mem status comm; do
        [[ -z "$pid" ]] && continue

        if ! is_safe_process "$pid" "$comm"; then
            continue
        fi

        if [[ "$status" == "CRIT" ]]; then
            handle_critical_process "$pid" "$cpu" "$mem" "$comm"
        elif [[ "$status" == "WARN" ]]; then
            handle_warning_process "$pid" "$cpu" "$mem" "$comm"
        fi

    done < <(ps -eo pid,ppid,%cpu,%mem,comm --no-headers | awk -v cw="$CPU_WARN_THRESHOLD" \
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
    }')
}

# ------------------------------------------------------------
# Main Execution Entry Point
# ------------------------------------------------------------
main() {
    check_prerequisites
    init_logging

    log_action "[INFO] Watchdog inspection cycle started."
    scan_and_enforce
    log_action "[INFO] Watchdog inspection cycle completed successfully."
}

main "$@"
