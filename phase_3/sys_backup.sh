#!/bin/bash
# Filename: sys_backup.sh
# Purpose: Modular, CPU-throttled automated disaster recovery and backup utility.
# Phase 3 - Containerization, Systems Administration & Disaster Recovery

set -euo pipefail

# ------------------------------------------------------------
# Global Configuration Parameters
# ------------------------------------------------------------
BACKUP_DIR="/var/backups/sysadmins"
LOG_FILE="/var/log/sys_backup.log"
RETENTION_DAYS=7
NICE_PRIORITY=10

# Primary host target directories for backup
TARGET_DIRS=(
    "/etc"
    "/var/log"
    "/srv/sysadmins/dashboard"
)

# Global array to hold verified target directories
VALID_TARGETS=()

# ------------------------------------------------------------
# Modular Helper & Logging Functions
# ------------------------------------------------------------

log_action() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# 1. Modular Check: Privilege & Dependency Verification
check_prerequisites() {
    if [[ $EUID -ne 0 ]]; then
        echo "[ERROR] Backup utility requires root privileges (sudo)." >&2
        exit 1
    fi

    local req_cmds=("tar" "nice" "find" "du" "gzip" "ps")
    for cmd in "${req_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "[ERROR] Required system binary '$cmd' not found in PATH." >&2
            exit 1
        fi
    done
}

# 2. Modular Setup: Environment & Logging Initialization
init_backup_environment() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        chmod 750 "$BACKUP_DIR"
        log_action "INFO" "Created target backup directory: $BACKUP_DIR"
    fi

    touch "$LOG_FILE" 2>/dev/null || { echo "[ERROR] Cannot write to log file $LOG_FILE." >&2; exit 1; }
    chmod 640 "$LOG_FILE"
}

# 3. Modular Check: Target Directory Validation
validate_targets() {
    VALID_TARGETS=()
    for dir in "${TARGET_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            VALID_TARGETS+=("$dir")
            log_action "INFO" "Target path validated: $dir"
        else
            log_action "WARN" "Target path missing or unreachable: $dir (skipping)."
        fi
    done

    if [[ ${#VALID_TARGETS[@]} -eq 0 ]]; then
        log_action "ERROR" "No valid target directories exist to perform backup."
        exit 1
    fi
}

# 4. Modular Engine: Throttled Archive Execution & Priority Audit
create_throttled_archive() {
    local archive_path="$1"
    log_action "INFO" "Initiating CPU-throttled tar compression (nice priority level: +$NICE_PRIORITY)..."

    # Spawn tar compression background job using only validated target paths
    nice -n "$NICE_PRIORITY" tar -czf "$archive_path" "${VALID_TARGETS[@]}" 2>/dev/null &
    local tar_pid=$!

    # Audit active background process niceness to verify CPU priority throttling
    sleep 0.1
    if kill -0 "$tar_pid" 2>/dev/null; then
        local current_nice
        current_nice=$(ps -o ni= -p "$tar_pid" 2>/dev/null | tr -d ' ' || true)
        if [[ -n "$current_nice" ]]; then
            log_action "INFO" "Verified active compression PID $tar_pid running at scheduling priority (nice: $current_nice)."
        fi
    fi

    # Capture wait exit status safely (tar status 1 = file changed during read warning, status 2+ = fatal)
    set +e
    wait "$tar_pid"
    local tar_status=$?
    set -e

    if [[ $tar_status -gt 1 ]]; then
        log_action "ERROR" "Compression process failed with fatal code $tar_status for archive: $archive_path"
        [[ -f "$archive_path" ]] && rm -f "$archive_path"
        exit 1
    elif [[ $tar_status -eq 1 ]]; then
        log_action "WARN" "Tar finished with minor warnings (some files changed during read)."
    fi
}

# 5. Modular Verification: Integrity Testing & File Hardening
verify_and_secure_archive() {
    local archive_path="$1"

    if [[ ! -s "$archive_path" ]]; then
        log_action "ERROR" "Generated archive file is missing or empty: $archive_path"
        exit 1
    fi

    # Conduct integrity testing using tar table inspection
    if tar -tzf "$archive_path" &>/dev/null; then
        log_action "INFO" "Archive integrity check passed (tar -tzf)."
    else
        log_action "ERROR" "Archive corruption detected during integrity verification! Removing file."
        rm -f "$archive_path"
        exit 1
    fi

    # Restrict permissions to read/write for root only (chmod 600)
    chmod 600 "$archive_path"
    
    local archive_size
    archive_size=$(du -h "$archive_path" | cut -f1)
    log_action "SUCCESS" "Backup archive successfully created: $archive_path (Size: $archive_size)"
}

# 6. Modular Cleanup: Retention Policy Management
enforce_retention_policy() {
    log_action "INFO" "Enforcing retention policy (purging archives older than $RETENTION_DAYS days)..."
    
    local purged_count=0
    while IFS= read -r old_file; do
        if [[ -n "$old_file" ]]; then
            rm -f "$old_file"
            log_action "INFO" "Purged expired backup archive: $old_file"
            ((purged_count++)) || true
        fi
    done < <(find "$BACKUP_DIR" -type f -name "sys_backup_*.tar.gz" -mtime +"$RETENTION_DAYS")

    log_action "INFO" "Retention enforcement completed. Total expired archives purged: $purged_count."
}

# ------------------------------------------------------------
# Main Execution Entry Point
# ------------------------------------------------------------
main() {
    check_prerequisites
    init_backup_environment

    log_action "INFO" "=================================================="
    log_action "INFO" "Starting System Backup & Disaster Recovery Cycle"
    log_action "INFO" "=================================================="

    validate_targets

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local archive_name="sys_backup_${timestamp}.tar.gz"
    local archive_path="${BACKUP_DIR}/${archive_name}"

    create_throttled_archive "$archive_path"
    verify_and_secure_archive "$archive_path"
    enforce_retention_policy

    log_action "INFO" "System backup cycle finalized successfully."
    log_action "INFO" "=================================================="
}

main "$@"
