#!/bin/bash
# Filename: docker_setup.sh
# Purpose: Prepares host directories, permissions, and initial web assets for Phase 3 containerization.

set -euo pipefail

# Configuration Parameters
DASHBOARD_DIR="/srv/sysadmins/dashboard"
SYSADMIN_GROUP="sysadmins"
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"

log_info()  { echo -e "\e[32m[INFO]\e[0m $1"; }
log_warn()  { echo -e "\e[33m[WARN]\e[0m $1"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $1" >&2; }

# 1. Privilege Check
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be executed with root privileges (use sudo)."
    exit 1
fi

# 2. Docker Service Check & DNS Fix Configuration
log_info "Verifying Docker service status..."
if ! systemctl is-active --quiet docker; then
    log_warn "Docker service is not running. Starting Docker..."
    systemctl start docker
fi

# Check Docker DNS resolution fallback
if [[ ! -f "$DOCKER_DAEMON_JSON" ]]; then
    log_info "Configuring public DNS fallbacks (8.8.8.8, 1.1.1.1) for Docker..."
    mkdir -p /etc/docker
    cat <<EOF > "$DOCKER_DAEMON_JSON"
{
  "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF
    systemctl restart docker
fi

# 3. Create Host Directory & Enforce Permissions
log_info "Creating mapped volume host directory at $DASHBOARD_DIR..."
mkdir -p "$DASHBOARD_DIR"

if getent group "$SYSADMIN_GROUP" &>/dev/null; then
    chown -R root:"$SYSADMIN_GROUP" "$DASHBOARD_DIR"
else
    log_warn "Group '$SYSADMIN_GROUP' not found. Assigning root ownership."
    chown -R root:root "$DASHBOARD_DIR"
fi

# Enforce 2775 (SGID bit + rwxrwsr-x)
chmod 2775 "$DASHBOARD_DIR"
log_info "Permissions on $DASHBOARD_DIR set to 2775."

# 4. Generate Baseline Dashboard Template
INDEX_FILE="$DASHBOARD_DIR/index.html"
if [[ ! -f "$INDEX_FILE" ]]; then
    log_info "Generating baseline index.html in $DASHBOARD_DIR..."
    cat <<'EOF' > "$INDEX_FILE"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="30">
    <title>TechVille System Health Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f4f6f9; color: #333; }
        h1 { color: #0056b3; border-bottom: 2px solid #0056b3; padding-bottom: 10px; }
        .card { background: #fff; padding: 15px; margin-bottom: 15px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .status-ok { color: #28a745; font-weight: bold; }
    </style>
</head>
<body>
    <h1>TechVille System Health Dashboard</h1>
    <div class="card">
        <p><strong>Status:</strong> <span class="status-ok">ONLINE</span></p>
        <p><strong>Environment:</strong> Phase 3 Containerized NGINX</p>
        <p><strong>Container Memory Limit:</strong> 512MB</p>
    </div>
</body>
</html>
EOF
    chmod 664 "$INDEX_FILE"
fi

# 5. Enforce Execute Permissions on Diagnostic Scripts

log_info "Setting execute permissions on project scripts..."
chmod +x ./*.sh 2>/dev/null || true

cp "$INDEX_FILE" ./index.html
chmod 644 ./index.html

log_info "Host environment setup complete!"
