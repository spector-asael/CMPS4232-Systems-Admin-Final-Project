#!/bin/bash
# Filename: log_analyzer.sh
# Purpose: Analyze authentication logs and create a security audit report.
# Phase 2 - Log Analytics, Regex & Job Automation

set -euo pipefail

# 1. Check root privileges
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Run this script with root privileges (use sudo)." >&2
    exit 1
fi

# 2. Detect authentication log location
if [[ -f "/var/log/auth.log" ]]; then
    AUTH_LOG="/var/log/auth.log"
elif [[ -f "/var/log/secure" ]]; then
    AUTH_LOG="/var/log/secure"
else
    echo "[ERROR] No valid auth log found (/var/log/auth.log or /var/log/secure)." >&2
    exit 1
fi

REPORT_FILE="/var/log/audit_report.txt"

# 3. Create temp environment with trap cleanup
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

FAILED_SSH="$TEMP_DIR/failed_ssh.txt"
DENIED_SUDO="$TEMP_DIR/denied_sudo.txt"
ROOT_ESCALATIONS="$TEMP_DIR/root_escalations.txt"
REPORT_TEMP="$TEMP_DIR/audit_report.txt"

# 4. Extract security events using regular expressions
grep -Ei 'sshd.*(Failed password|Failed publickey|Invalid user|authentication failure)' \
    "$AUTH_LOG" | sed -E 's/[[:cntrl:]]+$//' > "$FAILED_SSH" || true

grep -Ei 'sudo.*(not in sudoers|command not allowed|authentication failure|incorrect password|a password is required|conversation failed)' \
    "$AUTH_LOG" | sed -E 's/[[:cntrl:]]+$//' > "$DENIED_SUDO" || true

grep -Ei '(sudo.*(USER=root.*COMMAND=|session opened for user root)|su.*(Successful su for root|session opened for user root))' \
    "$AUTH_LOG" | sed -E 's/[[:cntrl:]]+$//' > "$ROOT_ESCALATIONS" || true

# 5. Calculate summary metrics
FAILED_SSH_COUNT=$(awk 'END { print NR+0 }' "$FAILED_SSH")
DENIED_SUDO_COUNT=$(awk 'END { print NR+0 }' "$DENIED_SUDO")
ROOT_ESCALATION_COUNT=$(awk 'END { print NR+0 }' "$ROOT_ESCALATIONS")
PROCESS_COUNT=$(ps -e --no-headers | wc -l)

print_events() {
    local EVENT_FILE="$1"
    if [[ -s "$EVENT_FILE" ]]; then
        awk '{ printf "  %3d. %s\n", NR, $0 }' "$EVENT_FILE"
    else
        echo "  None found in $AUTH_LOG."
    fi
}

# 6. Generate formatted audit report
{
    echo "============================================================"
    echo "                 SYSTEM SECURITY AUDIT REPORT               "
    echo "============================================================"
    printf "Report generated  : %s\n" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf "Hostname          : %s\n" "$(hostname)"
    printf "Authentication log: %s\n" "$AUTH_LOG"
    echo
    echo "SUMMARY"
    echo "------------------------------------------------------------"
    printf "Failed SSH login entries          : %s\n" "$FAILED_SSH_COUNT"
    printf "Denied/failed sudo entries        : %s\n" "$DENIED_SUDO_COUNT"
    printf "Successful root escalation entries: %s\n" "$ROOT_ESCALATION_COUNT"
    printf "Processes in process table        : %s\n" "$PROCESS_COUNT"
    echo
    echo "1. FAILED SSH LOGIN ATTEMPTS"
    echo "------------------------------------------------------------"
    print_events "$FAILED_SSH"
    echo
    echo "2. UNAUTHORIZED OR FAILED SUDO ATTEMPTS"
    echo "------------------------------------------------------------"
    print_events "$DENIED_SUDO"
    echo
    echo "3. SUCCESSFUL ROOT ESCALATION ENTRIES"
    echo "------------------------------------------------------------"
    print_events "$ROOT_ESCALATIONS"
    echo
    echo "4. TOP 10 MEMORY-CONSUMING PROCESSES"
    echo "------------------------------------------------------------"
    printf "%-7s %-7s %-12s %-7s %-7s %-10s %-7s %s\n" \
        "PID" "PPID" "USER" "%MEM" "%CPU" "RSS(KB)" "STAT" "COMMAND"
    ps -eo pid,ppid,user,%mem,%cpu,rss,stat,comm --sort=-%mem | head -n 11
    echo
    echo "NOTES"
    echo "------------------------------------------------------------"
    echo "Counts represent matching log entries, not necessarily unique sessions."
    echo "============================================================"
} > "$REPORT_TEMP"

# 7. Write report and set strict secure permissions
cp "$REPORT_TEMP" "$REPORT_FILE"
chmod 600 "$REPORT_FILE"
echo "[INFO] Audit summary successfully written to $REPORT_FILE"
