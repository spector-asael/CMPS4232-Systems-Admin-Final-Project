#!/bin/bash
# Filename: log_analyzer.sh
# Purpose: Modular, single-pass authentication log analytics and security auditing.
# Phase 2 - Log Analytics, Regex & Job Automation

set -euo pipefail

# Global Configuration
REPORT_FILE="/var/log/audit_report.txt"
AUTH_LOG=""
TEMP_DIR=""

# ------------------------------------------------------------
# Modular Functions
# ------------------------------------------------------------

# 1. Modular Check: Privilege & Directory Verification
check_prerequisites() {
    if [[ $EUID -ne 0 ]]; then
        echo "[ERROR] Root privileges required. Re-run with sudo." >&2
        exit 1
    fi

    TEMP_DIR=$(mktemp -d) || { echo "[ERROR] Failed to create temporary directory." >&2; exit 1; }
    if [[ -z "$TEMP_DIR" || ! -d "$TEMP_DIR" ]]; then
        echo "[ERROR] Invalid temporary directory path." >&2
        exit 1
    fi
    trap 'rm -rf "$TEMP_DIR"' EXIT
}

# 2. Modular Check: Locate and Validate Log File
detect_auth_log() {
    if [[ -f "/var/log/auth.log" && -r "/var/log/auth.log" ]]; then
        AUTH_LOG="/var/log/auth.log"
    elif [[ -f "/var/log/secure" && -r "/var/log/secure" ]]; then
        AUTH_LOG="/var/log/secure"
    else
        echo "[ERROR] No readable auth log found (/var/log/auth.log or /var/log/secure)." >&2
        exit 1
    fi
}

# 3. Modular Helper: Event Formatting
print_events() {
    local event_file="$1"
    if [[ -s "$event_file" ]]; then
        awk '{ printf "  %3d. %s\n", NR, $0 }' "$event_file"
    else
        echo "  None detected in log history."
    fi
}

# 4. Modular Engine: Single-Pass Parsing
parse_security_events() {
    local failed_ssh="$1"
    local denied_sudo="$2"
    local root_escalations="$3"

    awk -v ssh_out="$failed_ssh" \
        -v sudo_out="$denied_sudo" \
        -v root_out="$root_escalations" '
    BEGIN { IGNORECASE = 1 }
    {
        # Failed SSH Attempts
        if ($0 ~ /sshd\[[0-9]+\]:.*(Failed password|Failed publickey|Invalid user|authentication failure|Connection closed by authenticating user)/) {
            print $0 > ssh_out
        }
        # Unauthorized / Failed Sudo Attempts
        if ($0 ~ /sudo:.*(not in sudoers|command not allowed|authentication failure|incorrect password|a password is required|conversation failed)/) {
            print $0 > sudo_out
        }
        # Successful Root Escalations
        if ($0 ~ /(sudo:.*session opened for user root|su:.*session opened for user root|su:.*Successful su for root)/) {
            print $0 > root_out
        }
    }' "$AUTH_LOG"

    touch "$failed_ssh" "$denied_sudo" "$root_escalations"
}

# 5. Modular Builder: Generate Report Content
generate_audit_report() {
    local failed_ssh="$1"
    local denied_sudo="$2"
    local root_escalations="$3"
    local report_temp="$4"

    local failed_ssh_count
    local denied_sudo_count
    local root_escalation_count
    local process_count

    failed_ssh_count=$(wc -l < "$failed_ssh")
    denied_sudo_count=$(wc -l < "$denied_sudo")
    root_escalation_count=$(wc -l < "$root_escalations")
    process_count=$(ps -e --no-headers | wc -l)

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
        printf "Failed SSH login entries          : %s\n" "$failed_ssh_count"
        printf "Denied/failed sudo entries        : %s\n" "$denied_sudo_count"
        printf "Successful root escalation entries: %s\n" "$root_escalation_count"
        printf "Active system processes           : %s\n" "$process_count"
        echo
        echo "1. FAILED SSH LOGIN ATTEMPTS"
        echo "------------------------------------------------------------"
        print_events "$failed_ssh"
        echo
        echo "2. UNAUTHORIZED OR FAILED SUDO ATTEMPTS"
        echo "------------------------------------------------------------"
        print_events "$denied_sudo"
        echo
        echo "3. SUCCESSFUL ROOT ESCALATION ENTRIES"
        echo "------------------------------------------------------------"
        print_events "$root_escalations"
        echo
        echo "4. TOP 10 MEMORY-CONSUMING PROCESSES"
        echo "------------------------------------------------------------"
        printf "%-8s %-8s %-14s %-6s %-6s %-10s %-6s %s\n" \
            "PID" "PPID" "USER" "%MEM" "%CPU" "RSS(KB)" "STAT" "COMMAND"
        # Avoid head to prevent SIGPIPE exit under set -o pipefail
        ps -eo pid,ppid,user,%mem,%cpu,rss,stat,args --sort=-%mem --no-headers | \
        awk 'NR <= 10 { printf "%-8s %-8s %-14s %-6s %-6s %-10s %-6s ", $1, $2, $3, $4, $5, $6, $7; for(i=8;i<=NF;i++) printf "%s ", $i; print "" }'
        echo
        echo "NOTES"
        echo "------------------------------------------------------------"
        echo "Report generated via automated log analysis utility."
        echo "============================================================"
    } > "$report_temp"
}

# 6. Modular Publisher: Write to Target File & Handle Terminal Preview
publish_report() {
    local report_temp="$1"

    if ! cp "$report_temp" "$REPORT_FILE" 2>/dev/null; then
        echo "[ERROR] Failed to write report to $REPORT_FILE." >&2
        exit 1
    fi

    chmod 600 "$REPORT_FILE" || echo "[WARN] Failed to set permissions on $REPORT_FILE." >&2
    echo "[INFO] Audit summary written successfully to $REPORT_FILE"

    if [[ -t 1 ]]; then
        echo
        echo "--- [LIVE TERMINAL PREVIEW] ---"
        awk 'NR <= 25' "$REPORT_FILE"
        echo "... [Full report available at $REPORT_FILE] ..."
    fi
}

# ------------------------------------------------------------
# Main Execution Entry Point
# ------------------------------------------------------------
main() {
    check_prerequisites
    detect_auth_log

    local failed_ssh="$TEMP_DIR/failed_ssh.txt"
    local denied_sudo="$TEMP_DIR/denied_sudo.txt"
    local root_escalations="$TEMP_DIR/root_escalations.txt"
    local report_temp="$TEMP_DIR/audit_report.txt"

    parse_security_events "$failed_ssh" "$denied_sudo" "$root_escalations"
    generate_audit_report "$failed_ssh" "$denied_sudo" "$root_escalations" "$report_temp"
    publish_report "$report_temp"
}

main "$@"
