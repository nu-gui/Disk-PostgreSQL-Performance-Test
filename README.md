# Disk-PostgreSQL-Performance-Test

---

# 📘 **VM Disk & PostgreSQL Performance Test – User Manual**

---

## 🔧 Overview

This manual explains how to run the performance test script on any Debian 11-based Virtual Machine. The script evaluates:

- Disk health and I/O performance
- Disk pressure and stress scenarios
- PostgreSQL database throughput using `pgbench`
- System I/O snapshots in real time
- Generates a clean Markdown report for review

---

## 🚀 How to Run the Script

### 1. **Login to the VM**

Use an SSH client like PuTTY or terminal:

```bash
ssh root@<your-server-ip>
```

### 2. **Ensure the Script is Present**

The script file should be named:

```bash
vm-disk-pgsql-test.sh
```

### 3. **Make It Executable**

```bash
chmod +x vm-disk-pgsql-test.sh
```

### 4. **Run the Script as Root**

```bash
sudo ./vm-disk-pgsql-test.sh
```

---

## 🚀 How to Run the Full Integrated Workflow
1. Ensure all scripts are present in the same folder and marked executable:
   ```bash
   chmod +x vm-disk-pgsql-test.sh disk-autotuner.sh post-test-diagnostics.sh integrated-disk-testing.sh
   ```
2. Run the integrated script as root:
   ```bash
   sudo ./integrated-disk-testing.sh
   ```
3. Follow on-screen prompts to:
   - Perform disk & PostgreSQL benchmarks
   - Apply auto-tuning based on benchmark results (optional)
   - Run post-test diagnostics (optional)

## 🧰 Individual Scripts (Optional)
If you wish to run each script separately:
1. Benchmark:
   ```bash
   sudo ./vm-disk-pgsql-test.sh
   ```
2. Tune results:
   ```bash
   sudo ./disk-autotuner.sh
   ```
3. Diagnostics:
   ```bash
   sudo ./post-test-diagnostics.sh
   ```

---

## 🖥️ CLI Walkthrough (What the Script Will Ask)

1. `Enter the disk device to test (e.g., /dev/sda):`  
   ➤ Choose your primary or test disk device.

2. `Enter pgbench scale factor (e.g., 10):`  
   ➤ Defines how large the test database should be.

3. `Enter the PostgreSQL database name to use for benchmarking:`  
   ➤ If it doesn’t exist, the script will create it.

4. `Enter path to save report (leave blank for default):`  
   ➤ Example: `/root/reports/` or press Enter to use `/var/log/vm-disk-pgsql-test`.

5. If disk space is low (<10GB), you'll be asked:  
   `Continue anyway? (y/n):`  
   ➤ You can choose to proceed or abort the test.

---

## 📝 Generated Report

### 📍 Location

The Markdown report and raw log file are saved in the directory you provided or:

```
/var/log/vm-disk-pgsql-test/
```

### 📄 Files Created

| File                        | Description                                      |
|----------------------------|--------------------------------------------------|
| `report_<timestamp>.md`    | The full Markdown-formatted performance report  |
| `raw_output.log`           | Raw execution logs for debugging or auditing    |

---

## 📖 How to Read the Report

The Markdown report is human-readable and divided into these sections:

| Section                          | Description                                                                 |
|----------------------------------|-----------------------------------------------------------------------------|
| Step 1: Installing Dependencies  | Ensures all tools are installed                                            |
| Step 2: SMART Health Check       | Verifies disk health using `smartctl`                                      |
| Step 3: Disk Speed Tests         | Measures read/write speeds via `hdparm`, `dd`, and `fio`                   |
| Step 4: Stress Tests             | Applies load via `fio` and `stress-ng` to simulate high I/O usage          |
| Step 5: I/O Snapshots            | Captures real-time disk metrics using `iostat` and top I/O processes       |
| Step 6: PostgreSQL Benchmark     | Runs `pgbench` to simulate DB load and generate TPS & latency stats        |
| Test Summary                     | Output file locations                                                       |

---

## 🧪 Debugging Tips

If something goes wrong:

- **Disk device doesn't exist:** Ensure you input a valid block device (e.g., `/dev/sda`).
- **Permission denied:** Ensure you run the script as `sudo` or `root`.
- **PostgreSQL connection fails:** Ensure the service is running. The script attempts to auto-start it.
- **Low disk space warning:** You may continue the test, but results could be affected.
- **Script aborts with `[ERROR]`:** Review `raw_output.log` for detailed errors.

---

## 🔁 Optional Cleanup (PostgreSQL)

If you want to remove the test database afterward:

```bash
sudo -u postgres dropdb <your-database-name>
```

---

## ✅ Final Notes

- This script is non-destructive: it writes temporary test files only to the selected disk.
- Useful for staging or benchmark environments.
- Ideal for server qualification or VM performance comparisons.
- For the new integrated workflow, most changes only take effect after the script's suggestions are applied and (potentially) after a reboot.

---

# Disk PostgreSQL Performance Testing & Tuning

This toolkit provides a comprehensive workflow for testing and optimizing disk performance for PostgreSQL database servers.

## Components

1. **vm-disk-pgsql-test.sh** - Performs disk benchmarking and PostgreSQL performance testing
2. **disk-autotuner.sh** - Analyzes benchmark results and applies optimal disk tuning
3. **post-test-diagnostics.sh** - Performs additional diagnostics and optimization
4. **integrated-disk-testing.sh** - Orchestrates the entire workflow

## Usage

For the complete integrated workflow, run:

```bash
sudo ./integrated-disk-testing.sh
```

This will guide you through the entire process of testing and tuning your system.

### Individual Components

If you prefer to run the scripts individually:

1. First run the benchmarking:
   ```bash
   sudo ./vm-disk-pgsql-test.sh
   ```

2. Then analyze and tune based on results:
   ```bash
   sudo ./disk-autotuner.sh
   ```

3. Finally run post-test diagnostics:
   ```bash
   sudo ./post-test-diagnostics.sh
   ```

## Reports

All reports are saved to `/var/log/vm-disk-pgsql-test/` by default, including:
- Benchmark reports (`report_*.md`)
- Tuning reports (`tuning_*.md`) 
- Diagnostic reports (`post_test_diagnostics_*.md`)

## Requirements

- Debian/Ubuntu Linux
- Root privileges
- PostgreSQL installed
- Utilities: smartmontools, hdparm, fio, stress-ng, sysstat, iotop

## Best Practices

For optimal results:
- Run on a system with minimal other activity
- Ensure you have at least 10GB of free disk space
- After tuning is applied, a system reboot is recommended for all changes to take effect
