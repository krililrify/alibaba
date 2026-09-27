# Alibaba Cloud Cleaner

A one-click cleaner for pre-installed Alibaba Cloud host-level agents on ECS instances.

If you have purchased an Alibaba Cloud ECS instance but do not need CloudMonitor, Security Center, Cloud Assistant, or other host-level agents, this script can detect, uninstall, and clean up their remaining components.

## ✨ Features

This project targets the following Alibaba Cloud host agents:

* Alibaba Cloud Security Center / Aegis
* Alibaba CloudMonitor Agent
* Alibaba Cloud Assistant
* Logtail / LoongCollector, if installed

The script runs an eight-stage detect, stop/disable, official-uninstall attempt, attribute removal, exact process termination, file cleanup, systemd/cron cleanup, and final verification flow. Any detected residual is listed and causes a non-zero exit status. It prints `Alibaba Cloud Agent Cleanup: SUCCESS` only when its final checks pass.

**Aegis self-protection:** The script prefers an available local official uninstaller, or tries to fetch one from Alibaba's official endpoint. An uninstaller failure does not count as success: cleanup and verification continue. The script checks agent directories for immutable (`i`) and append-only (`a`) attributes and attempts to clear them before removal, then terminates Aegis processes by exact process name or confirmed agent path. If kernel-level protection, self-protection, or permissions still prevent stopping or deletion, the result is `FAILED / RESIDUALS DETECTED` with the remaining items. Some protection may need to be disabled in the Alibaba Cloud console before rerunning.

The script does not use fuzzy `pkill -f` matching. It removes systemd units only when their names identify a known agent or their contents explicitly reference an agent path/program. `cloud-init`, `systemd`, `sshd`, `lvm2-monitor`, and `mdmonitor` are protected. Cron cleanup removes only lines matching Alibaba agent identifiers and preserves other jobs in each file.

Package removal detects Debian/Ubuntu `dpkg`/`apt` and RHEL-family `rpm`/`dnf`/`yum`; it removes only packages with exact known-agent names.

The script performs:

1. Detect Alibaba Cloud agents
2. Stop related services
3. Disable automatic startup
4. Attempt official uninstall procedures
5. Kill remaining agent processes
6. Remove known agent files and directories
7. Clean related systemd units
8. Check for Cron remnants
9. Check for remaining processes
10. Check for agent network connections
11. Perform a final verification

## 🚀 One-Click Installation

Run as `root`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/krililrify/alibaba/main/install.sh)
```

Or using wget:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/krililrify/alibaba/main/install.sh)
```

## 🧹 What It Removes

### Security Center / Aegis

Removes:

```text
AliYunDun
AliYunDunMonitor
AliYunDunUpdate
/usr/local/aegis
```

### CloudMonitor

Removes:

```text
argusagent
cloudmonitor.service
/usr/local/cloudmonitor
```

### Cloud Assistant

Removes:

```text
aliyun-service
aliyun.service
/usr/local/share/aliyun-assist
```

### Logtail / LoongCollector

If detected, the script also attempts to remove:

```text
loongcollector
ilogtail
logtail
```

## 🛡️ What It Does NOT Remove

The script does not blindly remove anything containing `cloud`, `monitor`, or `agent`.

The following normal system components are intentionally preserved:

* `cloud-init`
* `systemd`
* `sshd`
* `lvm2-monitor`
* `mdmonitor`
* Linux kernel services
* Other non-Alibaba Cloud agents

This is designed to reduce the risk of affecting normal ECS boot and SSH functionality.

## 🔍 Final Verification

After cleanup, the script automatically checks:

```text
✓ Agent processes
✓ systemd services
✓ Agent directories
✓ systemd unit files
✓ Network connections
```

The script reports success only when all of its final checks pass. Aegis self-protection or another supervisor may prevent automatic removal; resolve the specific residuals reported by the script and run it again.

A reboot is recommended after cleanup:

```bash
reboot
```

After reboot, you can verify again:

```bash
ps auxww | grep -Ei 'aliyun|aliyundun|aegis|argusagent|cloudmonitor|loongcollector|ilogtail|logtail' | grep -v grep
```

## ⚠️ Important

Removing these agents may disable Alibaba Cloud features that depend on them, including:

* Cloud Assistant remote commands
* CloudMonitor host-level monitoring
* Security Center host protection
* Logtail / LoongCollector log collection

Some basic ECS infrastructure monitoring may still remain visible in the Alibaba Cloud console because it does not necessarily depend on these host agents.

## 📌 Use Cases

This project is useful for:

* Initializing newly purchased Alibaba Cloud ECS instances
* Removing unwanted host monitoring agents
* Servers that do not use Cloud Assistant
* Servers that do not use Security Center
* Reducing unnecessary background processes
* Reducing unnecessary resource usage
* Repeated one-click cleanup during server deployment

## 📂 Project Structure

```text
alibaba/
├── install.sh
├── README.md
└── README_EN.md
```

## 📄 License

MIT License
