#!/bin/bash

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] This script must be run as root. Use sudo."
  exit 1
fi

# Default report directory - must match the testing script
DEFAULT_REPORT_DIR="/var/log/vm-disk-pgsql-test"

# Ask user for report directory or use the latest report from default location
read -rp "Enter path to benchmark reports (leave blank for $DEFAULT_REPORT_DIR): " USER_DIR
REPORT_DIR="${USER_DIR:-$DEFAULT_REPORT_DIR}"

if [ ! -d "$REPORT_DIR" ]; then
  echo "[ERROR] Report directory $REPORT_DIR does not exist. Please run the benchmark script first."
  exit 1
fi

# Find the most recent report
LATEST_REPORT=$(find "$REPORT_DIR" -name "report_*.md" -type f -printf "%T@ %p\n" | sort -nr | head -1 | cut -d' ' -f2-)

if [ -z "$LATEST_REPORT" ]; then
  echo "[ERROR] No benchmark reports found in $REPORT_DIR. Please run the benchmark script first."
  exit 1
fi

CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}[INFO] Found benchmark report: $LATEST_REPORT${NC}"
read -rp "Proceed with disk tuning based on this report? (y/n): " DO_TUNE
if [[ "$DO_TUNE" != [Yy]* ]]; then
  echo "[INFO] Tuning canceled by user."
  exit 0
fi

echo "[INFO] Analyzing disk performance data..."

# Create a tuning report
TUNING_FILE="$REPORT_DIR/tuning_$(date +%Y%m%d_%H%M%S).md"
echo "# Disk Auto-Tuning Report" > "$TUNING_FILE"
echo "_Generated on $(date)_" >> "$TUNING_FILE"
echo "Based on benchmark report: $(basename "$LATEST_REPORT")" >> "$TUNING_FILE"
echo "" >> "$TUNING_FILE"

# Extract disk device
DISK=$(grep -A 1 "Enter the disk device" "$LATEST_REPORT" | grep -oP '\/dev\/\w+' | head -1)
if [ -z "$DISK" ]; then
  # Try another pattern from debug output
  DISK=$(grep "Disk device selected:" "$LATEST_REPORT" | grep -oP '\/dev\/\w+' | head -1)
fi

if [ -z "$DISK" ]; then
  echo "[WARN] Could not determine disk device from report. Using system's primary disk."
  DISK=$(lsblk -d -o NAME,SIZE -n | sort -k2 -hr | head -n1 | awk '{print "/dev/"$1}')
fi

echo "[INFO] Target disk device: $DISK"

# Extract key metrics
echo "## Extracted Performance Metrics" >> "$TUNING_FILE"
echo "" >> "$TUNING_FILE"

# Get hdparm read speeds
READ_SPEED=$(grep -A 20 "hdparm Read Test" "$LATEST_REPORT" | grep -oP 'Timing buffered disk reads:[^=]+=\s+\K[\d.]+ MB/sec' | head -1)
if [ -n "$READ_SPEED" ]; then
  echo "* Read Speed: $READ_SPEED MB/s" >> "$TUNING_FILE"
fi

# Get dd write speeds
WRITE_SPEED=$(grep -A 20 "dd Write Test" "$LATEST_REPORT" | grep -oP '\d+(\.\d+)? MB/s' | head -1)
if [ -n "$WRITE_SPEED" ]; then
  echo "* Write Speed: $WRITE_SPEED" >> "$TUNING_FILE"
fi

# Extract fio IOPS
READ_IOPS=$(grep -A 50 "fio Benchmark Test" "$LATEST_REPORT" | grep -oP 'read: IOPS=\K\d+' | head -1)
WRITE_IOPS=$(grep -A 50 "fio Benchmark Test" "$LATEST_REPORT" | grep -oP 'write: IOPS=\K\d+' | head -1)

if [ -n "$READ_IOPS" ]; then
  echo "* Read IOPS: $READ_IOPS" >> "$TUNING_FILE"
fi
if [ -n "$WRITE_IOPS" ]; then
  echo "* Write IOPS: $WRITE_IOPS" >> "$TUNING_FILE"
fi

# Extract pgbench TPS
PG_TPS=$(grep -A 50 "Running pgbench benchmark test" "$LATEST_REPORT" | grep -oP 'tps = \K\d+(\.\d+)?' | head -1)
if [ -n "$PG_TPS" ]; then
  echo "* PostgreSQL TPS: $PG_TPS" >> "$TUNING_FILE"
fi

echo "" >> "$TUNING_FILE"
echo "## Applied Tuning Settings" >> "$TUNING_FILE"

# Check if disk is an SSD
IS_SSD=false
if grep -q "Rotation Rate" "$LATEST_REPORT"; then
  ROTATION=$(grep -A 1 "Rotation Rate" "$LATEST_REPORT" | grep -oP '\d+' | head -1)
  if [ "$ROTATION" = "0" ] || [ -z "$ROTATION" ]; then
    IS_SSD=true
  fi
elif grep -q "Solid State Device" "$LATEST_REPORT"; then
  IS_SSD=true
fi

# Get disk name without /dev/ prefix
DISK_NAME=$(echo "$DISK" | sed 's/\/dev\///')

# Tune the I/O scheduler
echo "[INFO] Tuning I/O scheduler..."
if [ "$IS_SSD" = true ]; then
  echo "* Setting I/O scheduler for SSD ($DISK_NAME): none/mq-deadline" >> "$TUNING_FILE"
  if [ -f "/sys/block/$DISK_NAME/queue/scheduler" ]; then
    if grep -q "\[none\]" "/sys/block/$DISK_NAME/queue/scheduler"; then
      echo none > "/sys/block/$DISK_NAME/queue/scheduler" 2>/dev/null || echo "mq-deadline" > "/sys/block/$DISK_NAME/queue/scheduler" 2>/dev/null
    else
      echo "mq-deadline" > "/sys/block/$DISK_NAME/queue/scheduler" 2>/dev/null || echo "deadline" > "/sys/block/$DISK_NAME/queue/scheduler" 2>/dev/null
    fi
  fi
else
  echo "* Setting I/O scheduler for HDD ($DISK_NAME): bfq/cfq" >> "$TUNING_FILE"
  if [ -f "/sys/block/$DISK_NAME/queue/scheduler" ]; then
    if grep -q "\[bfq\]" "/sys/block/$DISK_NAME/queue/scheduler"; then
      echo bfq > "/sys/block/$DISK_NAME/queue/scheduler" 2>/dev/null
    else
      echo cfq > "/sys/block/$DISK_NAME/queue/scheduler" 2>/dev/null || echo "deadline" > "/sys/block/$DISK_NAME/queue/scheduler" 2>/dev/null
    fi
  fi
fi

# Tune readahead
echo "[INFO] Tuning read-ahead settings..."
if [ "$IS_SSD" = true ]; then
  # Lower readahead for SSDs
  echo "* Setting read-ahead for SSD ($DISK_NAME): 512 sectors" >> "$TUNING_FILE"
  if [ -f "/sys/block/$DISK_NAME/queue/read_ahead_kb" ]; then
    echo 256 > "/sys/block/$DISK_NAME/queue/read_ahead_kb"
  fi
else
  # Higher readahead for HDDs
  echo "* Setting read-ahead for HDD ($DISK_NAME): 2048 sectors" >> "$TUNING_FILE"
  if [ -f "/sys/block/$DISK_NAME/queue/read_ahead_kb" ]; then
    echo 1024 > "/sys/block/$DISK_NAME/queue/read_ahead_kb"
  fi
fi

# System-wide settings
echo "[INFO] Applying system-wide I/O settings..."

# VM dirty page settings
if [ "$IS_SSD" = true ]; then
  echo "* Setting VM dirty page ratio for SSD: 10%" >> "$TUNING_FILE"
  sysctl -w vm.dirty_background_ratio=5
  sysctl -w vm.dirty_ratio=10
else
  echo "* Setting VM dirty page ratio for HDD: 20%" >> "$TUNING_FILE"
  sysctl -w vm.dirty_background_ratio=10
  sysctl -w vm.dirty_ratio=20
fi

# Adjust swappiness based on available RAM
TOTAL_MEM=$(free -m | grep Mem | awk '{print $2}')
if [ "$TOTAL_MEM" -gt 16000 ]; then
  echo "* Setting swappiness for high memory system: 10" >> "$TUNING_FILE"
  sysctl -w vm.swappiness=10
elif [ "$TOTAL_MEM" -gt 8000 ]; then
  echo "* Setting swappiness for medium memory system: 20" >> "$TUNING_FILE"
  sysctl -w vm.swappiness=20
else
  echo "* Setting swappiness for low memory system: 30" >> "$TUNING_FILE"
  sysctl -w vm.swappiness=30
fi

# Advanced disk tuning parameters
echo "[INFO] Applying advanced disk tuning parameters..."
if [ -f "/sys/block/$DISK_NAME/queue/nr_requests" ]; then
  echo "* Setting nr_requests to 128" >> "$TUNING_FILE"
  echo 128 > "/sys/block/$DISK_NAME/queue/nr_requests"
fi

if [ -f "/sys/block/$DISK_NAME/queue/max_sectors_kb" ]; then
  echo "* Setting max_sectors_kb to 512" >> "$TUNING_FILE"
  echo 512 > "/sys/block/$DISK_NAME/queue/max_sectors_kb"
fi

if [ -f "/sys/block/$DISK_NAME/device/queue_depth" ]; then
  echo "* Setting queue_depth to 32" >> "$TUNING_FILE"
  echo 32 > "/sys/block/$DISK_NAME/device/queue_depth"
fi

# Enable or disable write cache
if hdparm -W "$DISK" | grep -q "write-caching = 1"; then
  echo "* Write cache is already enabled" >> "$TUNING_FILE"
else
  echo "* Enabling write cache" >> "$TUNING_FILE"
  hdparm -W1 "$DISK"
fi

# Enable or disable read cache
if hdparm -I "$DISK" | grep -q "Read cache"; then
  echo "* Read cache is already enabled" >> "$TUNING_FILE"
else
  echo "* Enabling read cache" >> "$TUNING_FILE"
  hdparm -W1 "$DISK"
fi

# Enable or disable write barriers
if [ "$IS_SSD" = true ]; then
  echo "* Disabling write barriers for SSD" >> "$TUNING_FILE"
  mount -o remount,nobarrier "$DISK"
else
  echo "* Enabling write barriers for HDD" >> "$TUNING_FILE"
  mount -o remount,barrier "$DISK"
fi

# Prompt user if they want to skip PostgreSQL tuning
if [ -n "$PG_TPS" ]; then
  echo -e "${CYAN}[INFO] PostgreSQL performance metrics detected.${NC}"
  read -rp "Apply PostgreSQL tuning changes? (y/n): " DO_PG_TUNE
  if [[ "$DO_PG_TUNE" != [Yy]* ]]; then
    echo "[INFO] Skipping PostgreSQL tuning as requested."
    echo "" >> "$TUNING_FILE"
    echo "## Tuning Results" >> "$TUNING_FILE"
    echo "Settings have been applied to optimize disk performance based on the benchmark results." >> "$TUNING_FILE"
    echo "Some changes require a system reboot to fully take effect." >> "$TUNING_FILE"
    echo "[INFO] Tuning complete! Report saved to: $TUNING_FILE"
    echo "To make all changes fully effective, consider rebooting the system."
    exit 0
  fi
fi

# PostgreSQL tuning if applicable
if [ -n "$PG_TPS" ]; then
  echo "[INFO] Tuning PostgreSQL settings..."
  
  # Check if we can modify PostgreSQL settings
  PG_CONF_PATH="/etc/postgresql/*/main/postgresql.conf"
  PG_CONF=$(ls $PG_CONF_PATH 2>/dev/null | head -1)
  
  if [ -n "$PG_CONF" ] && [ -w "$PG_CONF" ]; then
    echo "* Updating PostgreSQL configuration at $PG_CONF" >> "$TUNING_FILE"
    
    # Calculate shared_buffers (25% of RAM, up to 8GB)
    SHARED_BUFFERS=$((TOTAL_MEM / 4))
    if [ "$SHARED_BUFFERS" -gt 8192 ]; then
      SHARED_BUFFERS=8192
    fi
    
    # Calculate effective_cache_size (50% of RAM)
    EFFECTIVE_CACHE=$((TOTAL_MEM / 2))
    
    # Set maintenance_work_mem (10% of RAM up to 1GB)
    MAINT_WORK_MEM=$((TOTAL_MEM / 10))
    if [ "$MAINT_WORK_MEM" -gt 1024 ]; then
      MAINT_WORK_MEM=1024
    fi
    
    # Create a PostgreSQL tuning file
    PG_TUNING_FILE="/tmp/pg_tuning.conf"
    cat > "$PG_TUNING_FILE" << EOF
# Automatically generated tuning parameters

# Memory Settings
shared_buffers = ${SHARED_BUFFERS}MB
effective_cache_size = ${EFFECTIVE_CACHE}MB
maintenance_work_mem = ${MAINT_WORK_MEM}MB
work_mem = 16MB

# Checkpoint Settings
checkpoint_timeout = 1h
checkpoint_completion_target = 0.9
max_wal_size = 2GB
min_wal_size = 1GB

# Disk Settings
EOF

    # Add disk specific settings based on type
    if [ "$IS_SSD" = true ]; then
      cat >> "$PG_TUNING_FILE" << EOF
# SSD optimized settings
random_page_cost = 1.1
effective_io_concurrency = 200
EOF
    else
      cat >> "$PG_TUNING_FILE" << EOF
# HDD optimized settings
random_page_cost = 4.0
effective_io_concurrency = 2
EOF
    fi
    
    # Append the tuning parameters to PostgreSQL config
    echo "* Setting shared_buffers = ${SHARED_BUFFERS}MB" >> "$TUNING_FILE"
    echo "* Setting effective_cache_size = ${EFFECTIVE_CACHE}MB" >> "$TUNING_FILE"
    echo "* Setting maintenance_work_mem = ${MAINT_WORK_MEM}MB" >> "$TUNING_FILE"
    
    if [ "$IS_SSD" = true ]; then
      echo "* Setting SSD-optimized PostgreSQL parameters" >> "$TUNING_FILE" 
    else
      echo "* Setting HDD-optimized PostgreSQL parameters" >> "$TUNING_FILE"
    fi
    
    # Backup the original configuration
    cp "$PG_CONF" "${PG_CONF}.backup_$(date +%Y%m%d_%H%M%S)"
    
    # Append our tuning parameters
    echo "" >> "$PG_CONF"
    echo "# Auto-tuning parameters added $(date)" >> "$PG_CONF"
    cat "$PG_TUNING_FILE" >> "$PG_CONF"
    
    # Ask if the user wants to restart PostgreSQL
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet postgresql; then
      echo "[INFO] PostgreSQL configuration updated. A restart is required to apply changes."
      read -rp "Restart PostgreSQL now? (y/n): " RESTART_PG
      if [[ $RESTART_PG == [Yy]* ]]; then
        systemctl restart postgresql
        echo "* PostgreSQL restarted to apply new settings" >> "$TUNING_FILE"
      else
        echo "* PostgreSQL restart skipped. Changes will apply after next restart." >> "$TUNING_FILE"
      fi
    fi
  else
    echo "[WARN] PostgreSQL configuration file not found or not writable. Skipping PostgreSQL tuning."
    echo "* PostgreSQL tuning skipped - configuration file not accessible" >> "$TUNING_FILE"
  fi
fi

# Make system settings persistent across reboots
if [ -d "/etc/sysctl.d" ]; then
  echo "[INFO] Making system settings persistent..."
  cat > /etc/sysctl.d/60-disk-tuning.conf << EOF
# Disk performance tuning parameters
# Generated by disk-autotuner.sh on $(date)

# VM settings
vm.dirty_background_ratio = $(cat /proc/sys/vm/dirty_background_ratio)
vm.dirty_ratio = $(cat /proc/sys/vm/dirty_ratio)
vm.swappiness = $(cat /proc/sys/vm/swappiness)
EOF

  echo "* Created persistent sysctl configuration: /etc/sysctl.d/60-disk-tuning.conf" >> "$TUNING_FILE"
fi

# Make I/O scheduler settings persistent
if [ -d "/etc/udev/rules.d" ]; then
  SCHEDULER=$(cat "/sys/block/$DISK_NAME/queue/scheduler" | grep -Po '\[\K[^\]]+')
  READAHEAD=$(cat "/sys/block/$DISK_NAME/queue/read_ahead_kb")
  
  cat > /etc/udev/rules.d/60-ioscheduler.rules << EOF
# Set I/O scheduler and disk parameters
# Generated by disk-autotuner.sh on $(date)
ACTION=="add|change", KERNEL=="$DISK_NAME", ATTR{queue/scheduler}="$SCHEDULER", ATTR{queue/read_ahead_kb}="$READAHEAD"
EOF

  echo "* Created persistent udev rules: /etc/udev/rules.d/60-ioscheduler.rules" >> "$TUNING_FILE"
fi

echo "" >> "$TUNING_FILE"
echo "## Tuning Results" >> "$TUNING_FILE"
echo "Settings have been applied to optimize disk performance based on the benchmark results." >> "$TUNING_FILE"
echo "Some changes require a system reboot to fully take effect." >> "$TUNING_FILE"

echo "[INFO] Tuning complete! Report saved to: $TUNING_FILE"
echo "To make all changes fully effective, consider rebooting the system."
