#!/bin/bash
# Filename: log_analyzer.sh
# Purpose: Single-pass authentication log analytics and security auditing.
# Phase 2 - Log Analytics, Regex & Job Automation

set -euo pipefail

# 1. Enforce Root Privileges
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run with root privileges (sudo)." >&2
    exit 1
fi

# 2. Identify System Auth Log Location
if [[ -f "/var/log/auth.log" ]]; then
    AUTH_LOG="/var/log/auth.log"
elif [[ -f "/var/log/secure" ]]; then
    AUTH_LOG="/var/log/secure"
else
    echo "[ERROR] No valid authentication log found (/var/log/auth.log or /var/log/secure)." >&2
    exit 1
fi

REPORT_FILE="/var/log/audit_report.txt"

# 3. Create Isolated Temp Environment
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

FAILED_SSH="$TEMP_DIR/failed_ssh.txt"
DENIED_SUDO="$TEMP_DIR/denied_sudo.txt"
ROOT_ESCALATIONS="$TEMP_DIR/root_escalations.txt"
REPORT_TEMP="$TEMP_DIR/audit_report.txt"

# 4. Single-Pass High-Efficiency Event Classification (AWK Engine)
awk -v ssh_out="$FAILED_SSH" \
    -v sudo_out="$DENIED_SUDO" \
    -v root_out="$ROOT_ESCALATIONS" '
BEGIN { IGNORECASE = 1 }
{
    # 4a. Match Failed SSH Attempts
    if ($0 ~ /sshd\[[0-9]+\]:.*(Failed password|Failed publickey|Invalid user|authentication failure|Connection closed by authenticating user)/) {
        print $0 > ssh_out
    }
    # 4b. Match Unauthorized or Failed Sudo Executions
    if ($0 ~ /sudo:.*(not in sudoers|command not allowed|authentication failure|incorrect password|a password is required|conversation failed)/) {
        print $0 > sudo_out
    }
    # 4c. Match Successful Root Escalations (Strict session opened check to prevent false positives)
    if ($0 ~ /(sudo:.*session opened for user root|su:.*session opened for user root|su:.*Successful su for root)/) {
        print $0 > root_out
    }
}' "$AUTH_LOG"

# Ensure temp files exist even if zero events matched
touch "$FAILED_SSH" "$DENIED_SUDO" "$ROOT_ESCALATIONS"

# 5. Calculate Metrics
FAILED_SSH_COUNT=$(wc -l < "$FAILED_SSH")
DENIED_SUDO_COUNT=$(wc -l < "$DENIED_SUDO")
ROOT_ESCALATION_COUNT=$(wc -l < "$ROOT_ESCALATIONS")
PROCESS_COUNT=$(ps -e --no-headers | wc -l)

print_events() {
    local EVENT_FILE="$1"
    if [[ -s "$EVENT_FILE" ]]; then
        awk '{ printf "  %3d. %s\n", NR, $0 }' "$EVENT_FILE"
    else
        echo "  None detected in log history."
    fi
}

# 6. Build Formatted Audit Report
{
    echo "============================================================"
    echo "                 SYSTEM SECURITY AUDIT REPORT               "
    echo "============================================================"
    printf "Report generated  : %s\n" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf "Hostname          : %s\n" "$(hostname)"
    printf "Authentication log: %s\n" "$AUTH_LOG"
    echo
    echo "SUMMARY METRICS"
    echo "------------------------------------------------------------"
    printf "Failed SSH login entries          : %s\n" "$FAILED_SSH_COUNT"
    printf "Denied/failed sudo entries        : %s\n" "$DENIED_SUDO_COUNT"
    printf "Successful root escalation entries: %s\n" "$ROOT_ESCALATION_COUNT"
    printf "Active system processes           : %s\n" "$PROCESS_COUNT"
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
    printf "%-8s %-8s %-14s %-6s %-6s %-10s %-6s %s\n" \
        "PID" "PPID" "USER" "%MEM" "%CPU" "RSS(KB)" "STAT" "COMMAND"
    ps -eo pid,ppid,user,%mem,%cpu,rss,stat,args --sort=-%mem --no-headers | head -n 10 | \
    awk '{ printf "%-8s %-8s %-14s %-6s %-6s %-10s %-6s ", $1, $2, $3, $4, $5, $6, $7; for(i=8;i<=NF;i++) printf "%s ", $i; print "" }'
    echo
    echo "NOTES"
    echo "------------------------------------------------------------"
    echo "Report generated via automated log analysis utility."
    echo "============================================================"
} > "$REPORT_TEMP"

# 7. Write Securely to Destination
cp "$REPORT_TEMP" "$REPORT_FILE"
chmod 600 "$REPORT_FILE"
echo "[INFO] Audit summary written successfully to $REPORT_FILE"

# 8. Output Preview if executed interactively
if [[ -t 1 ]]; then
    echo
    echo "--- [LIVE TERMINAL PREVIEW] ---"
    head -n 25 "$REPORT_FILE"
    echo "... [Full report available at $REPORT_FILE] ..."
fi
