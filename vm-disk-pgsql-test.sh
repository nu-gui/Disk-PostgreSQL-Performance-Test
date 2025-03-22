#!/bin/bash

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] This script must be run as root. Use sudo."
  exit 1
fi

# Define test duration parameters - placing at the top so they're available throughout
SHORT_TEST=60  # seconds
LONG_TEST=180  # seconds

# Add error handling function
function check_error() {
    if [ $? -ne 0 ]; then
        echo "[ERROR] $1 failed" | tee -a "$REPORT_FILE"
        exit 1
    fi
}

# Add cleanup trap - fix the pattern to match actual files created by fio
function cleanup() {
    echo "[DEBUG] Cleaning up temporary files"
    rm -f tempfile test_* stress_* 2>/dev/null
}
trap cleanup EXIT

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Prompt user for disk device, show a short notice
echo -e "${GREEN}[INFO] Starting disk and PostgreSQL benchmark...${NC}"
read -rp "Enter the disk device to test (e.g., /dev/sda): " DISK
if [ ! -b "$DISK" ]; then
  echo -e "${RED}[ERROR] Disk device $DISK does not exist.${NC}"
  exit 1
fi

echo "[DEBUG] Disk device selected: $DISK"
MAIN_DISK=$(lsblk -d -o NAME,SIZE -n | sort -k2 -hr | head -n1 | awk '{print "/dev/"$1}')
echo "[INFO] Detected primary disk: $MAIN_DISK"
read -rp "Enter pgbench scale factor (e.g., 10): " PGSCALE
echo "[DEBUG] pgbench scale factor: $PGSCALE"
read -rp "Enter the PostgreSQL database name to use for benchmarking: " PGDB
# Improve pipe character handling with awk instead of cut
if ! sudo -u postgres psql -lqt | awk '{ print $1 }' | grep -qw "$PGDB"; then
  echo "[INFO] Creating new database $PGDB..."
  sudo -u postgres createdb "$PGDB"
fi
echo "[DEBUG] PostgreSQL benchmark database: $PGDB"
read -rp "Enter path to save report (leave blank for /var/log/vm-disk-pgsql-test): " USER_DIR

REPORT_DIR="${USER_DIR:-/var/log/vm-disk-pgsql-test}"
REPORT_FILE="$REPORT_DIR/report_$(date +%Y%m%d_%H%M%S).md"
LOG="$REPORT_DIR/raw_output.log"
echo "[DEBUG] Report directory: $REPORT_DIR"
echo "[DEBUG] Report file: $REPORT_FILE"
echo "[DEBUG] Log file: $LOG"

mkdir -p "$REPORT_DIR"
echo "[DEBUG] Creating report directory at $REPORT_DIR"

# Disk space verification before tests
FREE_SPACE=$(df -BG --output=avail "$REPORT_DIR" | tail -n1 | tr -d 'G')
echo "[DEBUG] Free space in $REPORT_DIR: ${FREE_SPACE}G"
if [ "$FREE_SPACE" -lt 10 ]; then
    echo -e "${RED}[WARN] Less than 10GB free. Tests may fail.${NC}"
    read -rp "Continue anyway? (y/n): " CONTINUE
    [[ $CONTINUE != [Yy]* ]] && exit 0
fi

# Use stdbuf to prevent buffering issues
echo "[DEBUG] Redirecting output to $LOG"
exec > >(stdbuf -oL tee -a "$LOG") 2>&1

echo "[DEBUG] Initializing report file: $REPORT_FILE"
echo "# Debian 11 VM Disk & PostgreSQL Performance Report" > "$REPORT_FILE"
echo "_Generated on $(date)_" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "## Step 1: Installing Dependencies" | tee -a "$REPORT_FILE"
echo "[INFO] Updating package list..."
apt update -y || { echo "[ERROR] apt update failed."; exit 1; }

echo "[INFO] Installing required packages..."
apt install -y smartmontools hdparm fio stress-ng sysstat iotop postgresql-contrib bonnie++ sysbench || { echo "[ERROR] Package installation failed."; exit 1; }

echo "[INFO] Dependencies installation complete."
echo "Dependencies installed." >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "## Step 2: SMART Disk Health Check" >> "$REPORT_FILE"
echo "[INFO] Running smartctl on $DISK..."
smartctl -a "$DISK" >> "$REPORT_FILE" || echo "[WARN] smartctl failed on $DISK."
echo "[INFO] SMART check complete."
echo "" >> "$REPORT_FILE"

echo "## Step 3: Disk Read/Write Speed Tests" >> "$REPORT_FILE"
echo "### hdparm Read Test" >> "$REPORT_FILE"
echo "[INFO] Running hdparm read speed test on $DISK..."
hdparm -Tt "$DISK" >> "$REPORT_FILE" || echo "[WARN] hdparm failed on $DISK."
echo "[INFO] hdparm test complete."
echo "" >> "$REPORT_FILE"

echo "### dd Write Test" >> "$REPORT_FILE"
echo -e "${GREEN}### Running dd write speed test...${NC}"
dd if=/dev/zero of=tempfile bs=1G count=1 oflag=dsync >> "$REPORT_FILE" 2>&1 || echo "[WARN] dd write test failed."

echo "[INFO] Removing temporary file..."
rm -f tempfile

echo "[DEBUG] Temporary file cleanup complete."
echo "" >> "$REPORT_FILE"
echo "### fio Benchmark Test" >> "$REPORT_FILE"
echo "[INFO] Running fio read/write benchmark..."
fio --name=test --filename=test_file --size=512m --rw=readwrite --bs=4k --numjobs=4 --runtime=$SHORT_TEST --group_reporting >> "$REPORT_FILE" || echo "[WARN] fio benchmark failed."
echo "[INFO] fio benchmark test complete."
echo "" >> "$REPORT_FILE"

echo "### bonnie++ Disk Benchmark Test" >> "$REPORT_FILE"
echo "[INFO] Running bonnie++ disk benchmark..."
bonnie++ -d /tmp -s 2G -r 1G -u root -q >> "$REPORT_FILE" || echo "[WARN] bonnie++ benchmark failed."
echo "[INFO] bonnie++ benchmark test complete."
echo "" >> "$REPORT_FILE"

echo "### sysbench Disk Benchmark Test" >> "$REPORT_FILE"
echo "[INFO] Running sysbench disk benchmark..."
sysbench fileio --file-total-size=2G --file-test-mode=rndrw --time=$SHORT_TEST --max-requests=0 --max-time=$SHORT_TEST --num-threads=4 run >> "$REPORT_FILE" || echo "[WARN] sysbench benchmark failed."
echo "[INFO] sysbench benchmark test complete."
echo "" >> "$REPORT_FILE"

echo "## Step 4: High-Pressure Disk Stress Tests" >> "$REPORT_FILE"
echo "### fio Intensive Stress Test" >> "$REPORT_FILE"
echo "[INFO] Running fio intensive stress test..."
fio --name=stress --filename=stress_file --size=4G --rw=randrw --bs=16k --numjobs=8 --iodepth=32 --runtime=$LONG_TEST --time_based --group_reporting >> "$REPORT_FILE" || echo "[WARN] fio stress test failed."
echo "[INFO] fio stress test complete."
echo "" >> "$REPORT_FILE"

echo "### stress-ng Disk Load Test" >> "$REPORT_FILE"
echo "[INFO] Running stress-ng disk load test..."
stress-ng --hdd 4 --hdd-bytes 4G --timeout ${LONG_TEST}s --metrics-brief >> "$REPORT_FILE" || echo "[WARN] stress-ng test failed."
echo "[INFO] stress-ng test complete."
echo "" >> "$REPORT_FILE"

echo "## Step 5: Real-Time I/O Snapshot" >> "$REPORT_FILE"
echo "### iostat Snapshot" >> "$REPORT_FILE"
echo "[INFO] Running iostat snapshot..."
iostat -xz 1 3 >> "$REPORT_FILE" || echo "[WARN] iostat failed."
echo "[INFO] iostat snapshot complete."
echo "" >> "$REPORT_FILE"

echo "### iotop Snapshot (top 10 processes)" >> "$REPORT_FILE"
echo "[INFO] Running iotop snapshot..."
iotop -b -n 3 | head -n 20 >> "$REPORT_FILE" || echo "[WARN] iotop failed."
echo "[INFO] iotop snapshot complete."
echo "" >> "$REPORT_FILE"

echo "## Step 6: PostgreSQL Benchmark" >> "$REPORT_FILE"
# Check for systemd availability before using systemctl
if command -v systemctl >/dev/null 2>&1; then
    echo "[INFO] Checking PostgreSQL service status..."
    if ! systemctl is-active --quiet postgresql; then
        echo "[WARN] PostgreSQL service not running. Attempting to start..."
        systemctl start postgresql || { 
            echo "[ERROR] Failed to start PostgreSQL. Skipping PostgreSQL tests."
            SKIP_PGSQL=true
        }
    fi
else
    echo "[INFO] systemctl not found. Checking PostgreSQL using pg_isready..."
    if ! pg_isready >/dev/null 2>&1; then
        echo "[ERROR] Unable to connect to PostgreSQL. Skipping PostgreSQL tests."
        SKIP_PGSQL=true
    fi
fi

if [ -z "$SKIP_PGSQL" ]; then
    echo "[INFO] Initializing pgbench test database with scale $PGSCALE..."
    sudo -u postgres pgbench -i -s "$PGSCALE" "$PGDB" >> "$REPORT_FILE" || echo "[WARN] pgbench init failed."
    echo -e "${GREEN}[INFO] Running PostgreSQL tests...${NC}"
    sudo -u postgres pgbench -c 10 -j 2 -T $SHORT_TEST "$PGDB" >> "$REPORT_FILE" || echo "[WARN] pgbench test failed."
    echo "[INFO] pgbench test complete."
fi
echo "" >> "$REPORT_FILE"

echo "## Test Summary" >> "$REPORT_FILE"
echo "Raw logs saved at: $LOG" >> "$REPORT_FILE"
echo "Markdown report generated at: $REPORT_FILE" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "--- END OF REPORT ---" >> "$REPORT_FILE"

echo "[DEBUG] Script completed successfully"
echo -e "\n✅ All tests complete. Report saved to: $REPORT_FILE"
