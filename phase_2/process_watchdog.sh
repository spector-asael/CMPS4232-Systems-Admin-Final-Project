#!/bin/bash
# NOTE: Asael will update this later so that the comments look less like AI
# Filename: process_watchdog.sh
# Purpose: Monitor active system processes against CPU/Memory thresholds,
#          dynamically apply renice for warnings, and issue SIGTERM/SIGKILL for critical limits.

# ------------------------------------------------------------
# Configuration & Constants
# ------------------------------------------------------------
LOG_FILE="/var/log/process_watchdog.log"
CPU_WARN_THRESHOLD=75.0
CPU_CRIT_THRESHOLD=90.0
MEM_WARN_THRESHOLD=75.0
MEM_CRIT_THRESHOLD=90.0
SAFETY_WINDOW=5 # Seconds to wait after SIGTERM before escalating to SIGKILL

# ------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------
log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ------------------------------------------------------------
# 1. Check for Root Privileges
# ------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "[-] Error: This script must be run with root privileges (sudo)." >&2
    exit 1
fi

# ------------------------------------------------------------
# 2. Initialize Logging
# ------------------------------------------------------------
touch "$LOG_FILE" 2>/dev/null
if [[ $? -ne 0 ]]; then
    echo "[-] Error: Could not create or write to $LOG_FILE." >&2
    exit 1
fi
chmod 640 "$LOG_FILE"

log_action "[INFO] Process watchdog cycle started."

# ------------------------------------------------------------
# 3. Threshold Evaluation & Process Control Loop
# ------------------------------------------------------------
# Scan all running processes for PID, %CPU, %MEM, and command name
ps -eo pid,%cpu,%mem,comm --no-headers | while read -r pid cpu mem comm; do

    # Skip self, parent shell, kernel threads, or low PIDs to protect system stability
    if [[ "$pid" -eq $$ || "$pid" -le 10 ]]; then
        continue
    fi

    # Use awk for reliable floating-point threshold comparisons
    is_crit=$(awk -v c="$cpu" -v m="$mem" -v cw="$CPU_CRIT_THRESHOLD" -v mw="$MEM_CRIT_THRESHOLD" 'BEGIN {print (c >= cw || m >= mw) ? 1 : 0}')
    is_warn=$(awk -v c="$cpu" -v m="$mem" -v cw="$CPU_WARN_THRESHOLD" -v mw="$MEM_WARN_THRESHOLD" 'BEGIN {print (c >= cw || m >= mw) ? 1 : 0}')

    # --- CRITICAL THRESHOLD ACTION (SIGTERM / SIGKILL) ---
    if [[ "$is_crit" -eq 1 ]]; then
        log_action "[CRITICAL] Process '$comm' (PID: $pid) breached limits (CPU: ${cpu}%, MEM: ${mem}%). Issuing SIGTERM (Signal 15)."
        kill -15 "$pid" 2>/dev/null

        # Wait for the designated safety window
        sleep "$SAFETY_WINDOW"

        # Check if process is still alive; escalate to SIGKILL if necessary
        if kill -0 "$pid" 2>/dev/null; then
            log_action "[CRITICAL] Process '$comm' (PID: $pid) failed to stop after SIGTERM. Escalating to SIGKILL (Signal 9)."
            kill -9 "$pid" 2>/dev/null
        else
            log_action "[INFO] Process '$comm' (PID: $pid) terminated gracefully."
        fi

    # --- WARNING THRESHOLD ACTION (renice) ---
    elif [[ "$is_warn" -eq 1 ]]; then
        # Check current nice value to avoid redundant renicing
        current_nice=$(ps -o ni= -p "$pid" 2>/dev/null | xargs)
        if [[ -n "$current_nice" && "$current_nice" -lt 10 ]]; then
            log_action "[WARNING] Process '$comm' (PID: $pid) exceeded warning thresholds (CPU: ${cpu}%, MEM: ${mem}%). Applying renice (+10)."
            renice +10 -p "$pid" &>/dev/null
        fi
    fi

done

log_action "[INFO] Process watchdog cycle completed successfully."
exit 0
