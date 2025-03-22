#!/bin/bash

# Integrated Disk Testing and Tuning
# This script orchestrates the disk benchmarking, auto-tuning, and diagnostics

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] This script must be run as root. Use sudo."
  exit 1
fi

# Define script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
BENCHMARK_SCRIPT="$SCRIPT_DIR/vm-disk-pgsql-test.sh"
TUNING_SCRIPT="$SCRIPT_DIR/disk-autotuner.sh"
DIAGNOSTIC_SCRIPT="$SCRIPT_DIR/post-test-diagnostics.sh"

# Default report directory
DEFAULT_REPORT_DIR="/var/log/vm-disk-pgsql-test"

# Define colors for better UI
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Simple spinner function
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while kill -0 "$pid" 2>/dev/null; do
    for char in $spinstr; do
      echo -ne "${CYAN}Working... $char\r${NC}"
      sleep $delay
    done
  done
  echo -ne "${CYAN}Done!         \r${NC}\n"
}

# Check if scripts exist
for script in "$BENCHMARK_SCRIPT" "$TUNING_SCRIPT" "$DIAGNOSTIC_SCRIPT"; do
  if [ ! -f "$script" ]; then
    echo "[ERROR] Required script not found: $script"
    exit 1
  fi
  
  # Make sure scripts are executable
  chmod +x "$script"
done

# Create a results directory
mkdir -p "$DEFAULT_REPORT_DIR"

echo "====================================================="
echo "🔍 INTEGRATED DISK TESTING AND TUNING WORKFLOW"
echo "====================================================="
echo ""
echo -e "${CYAN}This workflow will perform the following steps:\n1. Run disk and PostgreSQL benchmarks\n2. Analyze results and apply optimal tuning\n3. Perform post-test diagnostics${NC}"
echo ""
echo "All reports will be saved to: $DEFAULT_REPORT_DIR"
echo ""

read -rp "Would you like to proceed? (y/n): " CONFIRM
if [[ "$CONFIRM" != [Yy]* ]]; then
  echo -e "${RED}Operation canceled.${NC}"
  exit 0
fi

# Step 1: Run the benchmark script
echo ""
echo "====================================================="
echo -e "${GREEN}STEP 1: Running Disk & PostgreSQL Benchmark Tests${NC}"
echo "====================================================="
("$BENCHMARK_SCRIPT") &
spinner $!

STEP1_STATUS=$?
if [ $STEP1_STATUS -ne 0 ]; then
  echo "[ERROR] Benchmark testing failed with status $STEP1_STATUS"
  echo "Please check the logs and try again."
  exit 1
fi

echo ""
read -rp "Continue to disk auto-tuning? (y/n): " CONTINUE
if [[ "$CONTINUE" != [Yy]* ]]; then
  echo -e "${RED}Benchmark completed. Tuning steps skipped.${NC}"
  exit 0
fi

# Step 2: Run the auto-tuner script
echo ""
echo "====================================================="
echo -e "${GREEN}STEP 2: Analyzing Results & Applying Optimal Tuning${NC}"
echo "====================================================="
("$TUNING_SCRIPT") &
spinner $!

STEP2_STATUS=$?
if [ $STEP2_STATUS -ne 0 ]; then
  echo "[ERROR] Auto-tuning failed with status $STEP2_STATUS"
  echo "Please check the logs and try again."
  exit 1
fi

echo ""
read -rp "Continue to post-test diagnostics? (y/n): " CONTINUE
if [[ "$CONTINUE" != [Yy]* ]]; then
  echo -e "${RED}Tuning completed. Diagnostics step skipped.${NC}"
  exit 0
fi

# Step 3: Run the post-test diagnostics script
echo ""
echo "====================================================="
echo -e "${GREEN}STEP 3: Running Post-Test Diagnostics${NC}"
echo "====================================================="
("$DIAGNOSTIC_SCRIPT") &
spinner $!

STEP3_STATUS=$?
if [ $STEP3_STATUS -ne 0 ]; then
  echo "[ERROR] Post-test diagnostics failed with status $STEP3_STATUS"
  echo "Please check the logs for details."
  exit 1
fi

echo ""
echo "====================================================="
echo "✅ WORKFLOW COMPLETED SUCCESSFULLY"
echo "====================================================="
echo ""
echo -e "${CYAN}All reports have been saved to: $DEFAULT_REPORT_DIR\nYou may need to restart your system for all changes to take effect.${NC}"

exit 0
