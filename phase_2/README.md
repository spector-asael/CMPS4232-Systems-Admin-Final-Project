# Phase 2: System Installation & Setup Guide

This document details the file placement, permission configurations, and crontab automation setup required to execute Phase 2 components (`log_analyzer.sh` and `process_watchdog.sh`).

---

## File Placement Overview

To adhere to the Linux Filesystem Hierarchy Standard (FHS), all executable administration scripts are stored in `/usr/local/sbin/`.

---

## 1. Move Files & Set Ownership/Permissions

Run the following commands to place the scripts into `/usr/local/sbin/` and enforce strict root ownership and executable rights:

```bash
# Move scripts to system binary path
sudo mv log_analyzer.sh /usr/local/sbin/
sudo mv process_watchdog.sh /usr/local/sbin/

# Set root ownership and grant executable rights exclusively to root
sudo chown root:root /usr/local/sbin/log_analyzer.sh /usr/local/sbin/process_watchdog.sh
sudo chmod 700 /usr/local/sbin/log_analyzer.sh /usr/local/sbin/process_watchdog.sh
```

---

## 2. Crontab Setup Instructions

Because both scripts require root privileges to read authentication logs (`/var/log/auth.log`) and manage system process priorities or issue signals (`SIGTERM`/`SIGKILL`), the automated schedule must be configured inside **root's crontab**.

1. Open root's crontab editor in the terminal:
   ```bash
   sudo crontab -e
   ```

2. Append the environment path variables and automated execution schedules to the bottom of the file:
   ```cron
   SHELL=/bin/bash
   PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

   # Automated log analysis triggered daily at midnight
   0 0 * * * /usr/local/sbin/log_analyzer.sh >> /var/log/log_analyzer_cron.log 2>&1

   # Process watchdog active monitoring triggered every minute
   * * * * * /usr/local/sbin/process_watchdog.sh >> /var/log/process_watchdog_cron.log 2>&1
   ```

3. Save and close the editor, then verify the active root cron schedule:
   ```bash
   sudo crontab -l
   ```

---

## 3. Log & Output File Locations

Once installed and scheduled, all script outputs and execution logs will automatically accumulate under `/var/log/`:

* **Security Audit Report:** `/var/log/audit_report.txt`
* **Watchdog Activity Log:** `/var/log/process_watchdog.log`
* **Cron Output Logs:** `/var/log/log_analyzer_cron.log` and `/var/log/process_watchdog_cron.log`
