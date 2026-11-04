#!/bin/bash
# Filename: net_check.sh
# Purpose: Comprehensive network connectivity and container health verification utility.
# Phase 3 - Containerization, Systems Administration & Disaster Recovery

set -euo pipefail

# ------------------------------------------------------------
# Global Configuration Parameters
# ------------------------------------------------------------
CONTAINER_NAME="health_dashboard"
HOST_PORT="8080"
TARGET_URL="http://localhost:${HOST_PORT}"
EXTERNAL_IP="8.8.8.8"
DOMAIN_TEST="google.com"
LOG_FILE="/var/log/net_check.log"

# Terminal Color Codes
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# ------------------------------------------------------------
# Modular Helper & Logging Functions
# ------------------------------------------------------------

log_action() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')

    case "$level" in
        "INFO")  echo -e "[$timestamp] [${GREEN}INFO${RESET}] $message" ;;
        "WARN")  echo -e "[$timestamp] [${YELLOW}WARN${RESET}] $message" ;;
        "ERROR") echo -e "[$timestamp] [${RED}ERROR${RESET}] $message" >&2 ;;
        *)       echo -e "[$timestamp] [$level] $message" ;;
    esac

    # Log to file if root/permitted
    if [[ -w "$LOG_FILE" ]] || [[ -w "$(dirname "$LOG_FILE")" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# 1. Modular Check: Binary Dependency Verification
check_prerequisites() {
    local req_cmds=("curl" "ping" "docker" "ss")
    for cmd in "${req_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_action "ERROR" "Required system utility '$cmd' is not installed or not in PATH."
            exit 1
        fi
    done
}

# 2. Modular Check: Host Network & WAN Reachability
check_network_connectivity() {
    log_action "INFO" "Verifying host network connectivity & DNS resolution..."

    if ping -c 2 -W 2 "$EXTERNAL_IP" &>/dev/null; then
        log_action "INFO" "WAN ICMP reachability test passed ($EXTERNAL_IP)."
    else
        log_action "WARN" "WAN ping to $EXTERNAL_IP failed (ICMP may be blocked by firewall)."
    fi

    if command -v getent &>/dev/null; then
        if getent hosts "$DOMAIN_TEST" &>/dev/null; then
            log_action "INFO" "DNS resolution test passed ($DOMAIN_TEST)."
        else
            log_action "ERROR" "DNS resolution check failed for $DOMAIN_TEST."
            return 1
        fi
    fi
}

# 3. Modular Check: Container Execution & Health State
check_container_status() {
    log_action "INFO" "Auditing Docker container '$CONTAINER_NAME'..."

    # Check active execution state
    if ! docker ps -q -f name="^/${CONTAINER_NAME}$" &>/dev/null; then
        if docker ps -a -q -f name="^/${CONTAINER_NAME}$" &>/dev/null; then
            log_action "ERROR" "Container '$CONTAINER_NAME' exists but is STOPPED."
        else
            log_action "ERROR" "Container '$CONTAINER_NAME' does not exist."
        fi
        return 1
    fi

    # Inspect internal HEALTHCHECK instruction state if configured
    local health_status
    health_status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")

    if [[ "$health_status" == "healthy" ]]; then
        log_action "INFO" "Container '$CONTAINER_NAME' is active and HEALTHY."
    elif [[ "$health_status" == "starting" ]]; then
        log_action "WARN" "Container '$CONTAINER_NAME' health status is still initializing..."
    elif [[ "$health_status" == "unhealthy" ]]; then
        log_action "ERROR" "Container '$CONTAINER_NAME' is UNHEALTHY according to internal daemon probes."
        return 1
    else
        log_action "INFO" "Container '$CONTAINER_NAME' is active and running."
    fi
}

# 4. Modular Check: Host Port Binding Audit
check_port_listening() {
    log_action "INFO" "Verifying host socket binding on port $HOST_PORT..."

    if ss -tulpn | grep -q ":${HOST_PORT}\b"; then
        log_action "INFO" "Host socket port $HOST_PORT is bound and listening."
    else
        log_action "ERROR" "Host socket port $HOST_PORT is NOT listening!"
        return 1
    fi
}

# 5. Modular Check: End-to-End HTTP Application Response
check_http_endpoint() {
    log_action "INFO" "Testing web endpoint at $TARGET_URL..."

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$TARGET_URL" || echo "000")

    if [[ "$http_code" == "200" ]]; then
        log_action "INFO" "HTTP endpoint check SUCCESS (HTTP status code $http_code OK)."
    else
        log_action "ERROR" "HTTP endpoint check FAILED! Received HTTP status code '$http_code' (Expected: 200)."
        return 1
    fi
}

# ------------------------------------------------------------
# Main Execution Entry Point
# ------------------------------------------------------------
main() {
    log_action "INFO" "=================================================="
    log_action "INFO" "Starting TechVille Network & Container Audit"
    log_action "INFO" "=================================================="

    local overall_status=0

    check_prerequisites
    check_network_connectivity || overall_status=1
    check_container_status      || overall_status=1
    check_port_listening        || overall_status=1
    check_http_endpoint         || overall_status=1

    log_action "INFO" "=================================================="
    if [[ $overall_status -eq 0 ]]; then
        log_action "INFO" "ALL NETWORK & CONTAINER CHECKS PASSED."
    else
        log_action "ERROR" "ONE OR MORE VERIFICATION CHECKS FAILED."
    fi
    log_action "INFO" "=================================================="

    exit $overall_status
}

main "$@"
