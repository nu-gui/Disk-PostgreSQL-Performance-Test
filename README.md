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

---
