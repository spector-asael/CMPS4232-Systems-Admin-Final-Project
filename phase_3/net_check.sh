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
# Mount path targets for NGINX dashboard integration
DASHBOARD_DIR="/srv/sysadmins/dashboard"
METRICS_DIR="${DASHBOARD_DIR}/metrics"
METRICS_FILE="${METRICS_DIR}/net_status.html"


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
    local req_cmds=("curl" "ping" "docker" "ss" "ip" "awk")
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


# 5. HTML Metric Publishing & Interface Statistics Generation
publish_dashboard_metrics() {
    log_action "INFO" "Generating diagnostic HTML metrics into $METRICS_FILE..."

    mkdir -p "$METRICS_DIR"
    chmod 755 "$METRICS_DIR"

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')

    local iface_rows
    iface_rows=$(ip -s link | awk '
        /^[0-9]+:/ { iface=$2; gsub(":", "", iface); next }
        /RX:/ { getline; rx_bytes=$1; rx_packets=$2; next }
        /TX:/ { getline; tx_bytes=$1; tx_packets=$2; 
                printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n", iface, rx_bytes, rx_packets, tx_bytes, tx_packets }
    ' 2>/dev/null || echo "<tr><td colspan='5'>Interface stats unavailable</td></tr>")

    local port_rows
    port_rows=$(ss -tulpn | awk 'NR>1 { printf "<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n", $1, $5, $7 }' 2>/dev/null || echo "<tr><td colspan='3'>Port stats unavailable</td></tr>")

    cat <<EOF > "$METRICS_FILE"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="15">
    <title>TechVille Network & Container Metrics</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f8f9fa; color: #212529; }
        h1, h2 { color: #0d6efd; border-bottom: 2px solid #0d6efd; padding-bottom: 6px; }
        .card { background: #fff; padding: 15px; margin-bottom: 20px; border-radius: 6px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { border: 1px solid #dee2e6; padding: 8px; text-align: left; }
        th { background-color: #e9ecef; }
        code { background: #e9ecef; padding: 2px 6px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>TechVille System & Network Diagnostic Metrics</h1>
    <p><em>Last Updated: ${timestamp}</em></p>

    <div class="card">
        <h2>Network Interface Statistics</h2>
        <table>
            <thead>
                <tr>
                    <th>Interface</th>
                    <th>RX Bytes</th>
                    <th>RX Packets</th>
                    <th>TX Bytes</th>
                    <th>TX Packets</th>
                </tr>
            </thead>
            <tbody>
                ${iface_rows}
            </tbody>
        </table>
    </div>

    <div class="card">
        <h2>Active Host Socket Listeners</h2>
        <table>
            <thead>
                <tr>
                    <th>Protocol</th>
                    <th>Local Address:Port</th>
                    <th>Process / Service</th>
                </tr>
            </thead>
            <tbody>
                ${port_rows}
            </tbody>
        </table>
    </div>
</body>
</html>
EOF

    chmod 644 "$METRICS_FILE"
    log_action "INFO" "Dashboard metrics successfully written to $METRICS_FILE."
}

# 6. Modular Check: End-to-End HTTP Application & Metric Endpoint Response
check_http_endpoint() {
    log_action "INFO" "Testing main web endpoint at $TARGET_URL..."

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$TARGET_URL" || echo "000")

    if [[ "$http_code" == "200" ]]; then
        log_action "INFO" "Main HTTP endpoint check SUCCESS (HTTP status code $http_code OK)."
    else
        log_action "ERROR" "Main HTTP endpoint check FAILED! Received HTTP status code '$http_code' (Expected: 200)."
        return 1
    fi

    local metrics_url="${TARGET_URL}/metrics/net_status.html"
    log_action "INFO" "Testing metrics web endpoint at $metrics_url..."

    local metrics_code
    metrics_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$metrics_url" || echo "000")

    if [[ "$metrics_code" == "200" ]]; then
        log_action "INFO" "Metrics HTTP endpoint check SUCCESS (HTTP status code $metrics_code OK)."
    else
        log_action "ERROR" "Metrics HTTP endpoint check FAILED! Received HTTP status code '$metrics_code' (Expected: 200)."
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
    check_network_connectivity	|| overall_status=1
    check_container_status      || overall_status=1
    check_port_listening        || overall_status=1
    publish_dashboard_metrics 	|| overall_status=1
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
