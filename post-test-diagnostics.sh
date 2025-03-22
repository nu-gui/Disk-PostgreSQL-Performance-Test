#!/bin/bash

# Define where reports will be saved
REPORT_DIR="/var/log/vm-disk-pgsql-test"
SUMMARY_FILE="$REPORT_DIR/post_test_diagnostics_$(date +%Y%m%d_%H%M%S).md"

# Create the report directory if it doesn't exist
echo "[DEBUG] Report directory created or already exists: $REPORT_DIR"
mkdir -p "$REPORT_DIR"

# Initialize the summary report file
echo "# Post-Test Diagnostics & Optimization Summary" > "$SUMMARY_FILE"
echo "_Generated on $(date)_" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

echo -e "[INFO] By default, this script changes settings on /dev/sda."
read -rp "Enter disk device to apply diagnostics (e.g., /dev/sda) or leave blank for /dev/sda: " USER_DISK
DISK="${USER_DISK:-/dev/sda}"

if [ ! -b "$DISK" ]; then
    echo "[ERROR] Disk device $DISK not found. Exiting."
    exit 1
fi

echo "[INFO] Target disk device: $DISK"

# If user wants to skip certain modifications
read -rp "Would you like to skip direct system modifications? (y/n): " SKIP_MODS
if [[ "$SKIP_MODS" == [Yy]* ]]; then
    echo "[INFO] Disk modifications will be skipped. Only reporting."
fi

# -------------------------------
# 1. Write Performance Tuning
# -------------------------------
echo "## 1. Write Performance Tuning" | tee -a "$SUMMARY_FILE"
echo "[INFO] Current scheduler for $DISK:" | tee -a "$SUMMARY_FILE"

# Check if the I/O scheduler file exists before modifying it
if [ "$SKIP_MODS" != [Yy]* ] && [ -f "/sys/block/$(basename "$DISK")/queue/scheduler" ]; then
    echo "[DEBUG] Scheduler path found. Displaying current scheduler..."
    cat "/sys/block/$(basename "$DISK")/queue/scheduler" | tee -a "$SUMMARY_FILE"
    echo "[DEBUG] Setting scheduler to deadline..."
    echo deadline > "/sys/block/$(basename "$DISK")/queue/scheduler" && echo "[OK] Scheduler set to deadline" | tee -a "$SUMMARY_FILE"
else
    echo "[WARN] Scheduler path not found. Skipping..." | tee -a "$SUMMARY_FILE"
fi

# Enable disk write caching
if [ "$SKIP_MODS" != [Yy]* ]; then
    echo "[INFO] Enabling write cache on $DISK..." | tee -a "$SUMMARY_FILE"
    hdparm -W1 "$DISK" | tee -a "$SUMMARY_FILE"
fi

# Tuning kernel writeback parameters
if [ "$SKIP_MODS" != [Yy]* ]; then
    echo "[WARN] Modifying kernel parameters — consider backing up current values." | tee -a "$SUMMARY_FILE"
    echo "[DEBUG] Setting vm.dirty_ratio to 10..."
    sysctl -w vm.dirty_ratio=10 | tee -a "$SUMMARY_FILE"
    echo "[DEBUG] Setting vm.dirty_background_ratio to 5..."
    sysctl -w vm.dirty_background_ratio=5 | tee -a "$SUMMARY_FILE"
    echo "[INFO] VM dirty limits tuned." | tee -a "$SUMMARY_FILE"
fi
echo "" >> "$SUMMARY_FILE"

# -------------------------------
# 2. PostgreSQL Benchmark Section
# -------------------------------
echo "## 2. PostgreSQL Service & Benchmark" | tee -a "$SUMMARY_FILE"
echo "[INFO] Checking PostgreSQL readiness..." | tee -a "$SUMMARY_FILE"

# Ensure PostgreSQL service is available via systemctl
if command -v systemctl >/dev/null 2>&1; then
    echo "[DEBUG] systemctl found. Verifying PostgreSQL status..."
    pg_isready || { echo "[WARN] PostgreSQL not ready, attempting to start..." | tee -a "$SUMMARY_FILE"; systemctl start postgresql; }
else
    echo "[ERROR] systemctl not found. Cannot ensure PostgreSQL is running." | tee -a "$SUMMARY_FILE"
fi

# Prompt user for the PostgreSQL database name
read -rp "Enter PostgreSQL database name to run benchmark on: " PGDB

# Validate the DB name using regex for allowed characters
if [[ -z "$PGDB" || "$PGDB" =~ [^a-zA-Z0-9_] ]]; then
    echo "[ERROR] Invalid database name. Use alphanumeric or underscore characters only." | tee -a "$SUMMARY_FILE"
    exit 1
fi

# Check if the DB exists or create it
echo "[DEBUG] Checking if database $PGDB exists..."
if ! sudo -u postgres psql -lqt | awk '{print $1}' | grep -qw "$PGDB"; then
    echo "[INFO] Creating database $PGDB..." | tee -a "$SUMMARY_FILE"
    sudo -u postgres createdb "$PGDB"
else
    echo "[INFO] Database $PGDB already exists." | tee -a "$SUMMARY_FILE"
fi

# Run pgbench initialization and performance test
echo "[DEBUG] Running pgbench initialization for $PGDB..."
sudo -u postgres pgbench -i -s 10 "$PGDB" | tee -a "$SUMMARY_FILE"
echo "[DEBUG] Running pgbench benchmark for $PGDB..."
sudo -u postgres pgbench -c 10 -j 2 -T 60 "$PGDB" | tee -a "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# -------------------------------
# 3. Disk Cache Configuration
# -------------------------------
echo "## 3. Disk Cache Mode Tuning" | tee -a "$SUMMARY_FILE"
echo "[DEBUG] Checking write cache status with hdparm..."
hdparm -I "$DISK" | grep 'Write cache' | tee -a "$SUMMARY_FILE"
echo "[INFO] Write cache enabled using hdparm -W1" | tee -a "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# -------------------------------
# 4. stress-ng Output Verification
# -------------------------------
echo "## 4. stress-ng Output Validation" | tee -a "$SUMMARY_FILE"
echo "[INFO] Searching for stress-ng metrics in raw log..." | tee -a "$SUMMARY_FILE"
RAW_LOG="$REPORT_DIR/raw_output.log"
echo "[DEBUG] Raw log file: $RAW_LOG"

# Search for stress-ng metrics in raw log output
if grep -i 'stress-ng' "$RAW_LOG" | grep -q metrics; then
    echo "[DEBUG] stress-ng output found. Displaying snippet..."
    grep -A 10 -i 'stress-ng' "$RAW_LOG" | tee -a "$SUMMARY_FILE"
else
    echo "[WARN] stress-ng summary not found in raw logs." | tee -a "$SUMMARY_FILE"
    echo "[SUGGESTION] Re-run manually: stress-ng --hdd 4 --hdd-bytes 4G --timeout 180s --metrics-brief" | tee -a "$SUMMARY_FILE"
fi

echo "" >> "$SUMMARY_FILE"
echo "## ✅ Post-Test Diagnostics Completed" >> "$SUMMARY_FILE"
echo "Logs saved to: $SUMMARY_FILE"
echo "[INFO] Script finished successfully."
