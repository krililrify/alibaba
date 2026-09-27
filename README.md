# Alibaba Cloud Cleaner

一键清理 Alibaba Cloud ECS 中预装的主机级 Agent。

如果你购买了 Alibaba Cloud ECS，但不需要 CloudMonitor、Security Center、Cloud Assistant 等主机 Agent，可以使用本脚本进行检测、卸载和残留清理。

## ✨ 功能

本项目主要清理以下 Alibaba Cloud 主机 Agent：

* Alibaba Cloud Security Center / Aegis
* Alibaba CloudMonitor Agent
* Alibaba Cloud Assistant
* Logtail / LoongCollector（如果已安装）

脚本会执行：

1. 检测 Alibaba Cloud Agent
2. 停止相关服务
3. 禁用开机启动
4. 尝试使用官方卸载方式
5. 清理残留进程
6. 清理已知 Agent 文件和目录
7. 清理相关 systemd unit
8. 检查 Cron 残留
9. 检查残留进程
10. 检查 Agent 网络连接
11. 最终执行完整检查

## 🚀 一键运行

以 `root` 身份执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/krililrify/alibaba/main/install.sh)
```

或者使用 wget：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/krililrify/alibaba/main/install.sh)
```

## 🧹 清理内容

### Security Center / Aegis

清理：

```text
AliYunDun
AliYunDunMonitor
AliYunDunUpdate
/usr/local/aegis
```

### CloudMonitor

清理：

```text
argusagent
cloudmonitor.service
/usr/local/cloudmonitor
```

### Cloud Assistant

清理：

```text
aliyun-service
aliyun.service
/usr/local/share/aliyun-assist
```

### Logtail / LoongCollector

如果检测到，也会尝试清理：

```text
loongcollector
ilogtail
logtail
```

## 🛡️ 不会删除什么？

本项目不会因为名称中包含 `cloud`、`monitor` 或 `agent` 就进行暴力删除。

以下正常系统组件会保留：

* `cloud-init`
* `systemd`
* `sshd`
* `lvm2-monitor`
* `mdmonitor`
* Linux kernel services
* 其他非 Alibaba Cloud Agent

这样可以尽量避免影响 ECS 的正常启动和 SSH 登录。

## 🔍 最终检查

脚本执行结束后，会自动检查：

```text
✓ Agent processes
✓ systemd services
✓ Agent directories
✓ systemd unit files
✓ Network connections
```

如果没有发现相关项目，会显示清理完成。

建议清理完成后重启服务器：

```bash
reboot
```

重启后可以再次检查：

```bash
ps auxww | grep -Ei 'aliyun|aliyundun|aegis|argusagent|cloudmonitor|loongcollector|ilogtail|logtail' | grep -v grep
```

## ⚠️ 注意

卸载这些 Agent 后，依赖它们的 Alibaba Cloud 功能可能无法继续使用，例如：

* Cloud Assistant 远程命令
* CloudMonitor 主机级监控
* Security Center 主机安全功能
* Logtail / LoongCollector 日志采集

Alibaba Cloud ECS 本身提供的部分基础平台监控并不一定依赖这些 Agent，因此卸载后控制台仍可能显示 CPU、网络流量等基础数据。

## 📌 适用场景

适合以下场景：

* 新购买 Alibaba Cloud ECS 后进行初始化
* 不需要 Alibaba Cloud 主机监控
* 不使用 Cloud Assistant
* 不使用 Security Center
* 希望减少后台 Agent
* 希望降低不必要的资源占用
* 希望拥有一个可重复执行的一键清理脚本

## 📂 项目结构

```text
alibaba/
├── install.sh
├── README.md
└── README_EN.md
```

## 📄 License

MIT License
