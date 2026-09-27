#!/usr/bin/env bash

# ============================================================
# Alibaba Cloud Cleaner
# Repository: https://github.com/kkkm0/alibaba-cleaner
#
# Purpose:
#   Remove Alibaba Cloud host-level agents:
#   - Alibaba Cloud Security Center / Aegis
#   - Alibaba CloudMonitor
#   - Alibaba Cloud Assistant
#   - Logtail / LoongCollector when detected
#
# Supported:
#   Debian / Ubuntu
#   CentOS / RHEL / Rocky / AlmaLinux
#   Alibaba Cloud Linux
#
# IMPORTANT:
#   This script does NOT remove:
#   - cloud-init
#   - sshd
#   - systemd
#   - kernel components
#   - normal Linux monitoring services
#
# ============================================================

set -u

VERSION="1.0.0"

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ------------------------------------------------------------
# Basic functions
# ------------------------------------------------------------

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[FAIL]${NC} $*"
}

section() {
    echo
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN} $*${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root."
    echo
    echo "Please run:"
    echo "  sudo bash $0"
    exit 1
fi

# ------------------------------------------------------------
# Banner
# ------------------------------------------------------------

clear 2>/dev/null || true

echo
echo "============================================================"
echo "        Alibaba Cloud Cleaner v${VERSION}"
echo "============================================================"
echo
echo "This script removes Alibaba Cloud host agents."
echo
echo "Targets:"
echo "  - Security Center / Aegis"
echo "  - CloudMonitor"
echo "  - Cloud Assistant"
echo "  - Logtail / LoongCollector"
echo
echo "It will NOT remove cloud-init or normal Linux services."
echo "============================================================"
echo

# ------------------------------------------------------------
# Detect OS
# ------------------------------------------------------------

OS_ID=""
OS_VERSION=""

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
fi

info "Detected OS: ${OS_ID} ${OS_VERSION}"

# ------------------------------------------------------------
# Stop related systemd services
# ------------------------------------------------------------

section "Stopping Alibaba Cloud services"

SERVICES=(
    "aliyun.service"
    "cloudmonitor.service"
    "aegis.service"
    "aegis_update.service"
    "aliyun-assist.service"
    "assist-daemon.service"
    "AssistDaemon.service"
    "loongcollector.service"
    "ilogtail.service"
    "logtaild.service"
)

for service in "${SERVICES[@]}"; do
    if systemctl list-unit-files --all 2>/dev/null | grep -q "^${service} "; then
        info "Stopping ${service}"
        systemctl stop "$service" 2>/dev/null || true
    fi
done

# ------------------------------------------------------------
# Disable known services
# ------------------------------------------------------------

section "Disabling Alibaba Cloud services"

for service in "${SERVICES[@]}"; do
    if systemctl list-unit-files --all 2>/dev/null | grep -q "^${service} "; then
        info "Disabling ${service}"
        systemctl disable "$service" 2>/dev/null || true
    fi
done

# ------------------------------------------------------------
# CloudMonitor official uninstall
# ------------------------------------------------------------

section "Removing CloudMonitor"

if [ -x /usr/local/cloudmonitor/cloudmonitorCtl.sh ]; then

    info "CloudMonitor control script detected."

    /usr/local/cloudmonitor/cloudmonitorCtl.sh stop \
        >/dev/null 2>&1 || true

    /usr/local/cloudmonitor/cloudmonitorCtl.sh uninstall \
        >/dev/null 2>&1 || true

    success "CloudMonitor uninstall command executed."

else
    info "CloudMonitor control script not found."
fi

# ------------------------------------------------------------
# Kill CloudMonitor residual processes
# ------------------------------------------------------------

info "Stopping CloudMonitor residual processes..."

pkill -9 -x argusagent 2>/dev/null || true
pkill -9 -f "/usr/local/cloudmonitor" 2>/dev/null || true

# ------------------------------------------------------------
# Security Center / Aegis
# ------------------------------------------------------------

section "Removing Security Center / Aegis"

AEGIS_FOUND=0

if [ -d /usr/local/aegis ]; then
    AEGIS_FOUND=1
fi

if pgrep -x AliYunDun >/dev/null 2>&1; then
    AEGIS_FOUND=1
fi

if pgrep -x AliYunDunMonitor >/dev/null 2>&1; then
    AEGIS_FOUND=1
fi

if pgrep -x AliYunDunUpdate >/dev/null 2>&1; then
    AEGIS_FOUND=1
fi

if [ "$AEGIS_FOUND" -eq 1 ]; then

    info "Alibaba Security Center / Aegis detected."

    # Try official uninstall method first.
    if command_exists curl; then
        info "Downloading official Aegis uninstall script..."

        curl -fsSL \
            "http://update2.aegis.aliyun.com/download/uninstall.sh" \
            -o /tmp/alibaba-aegis-uninstall.sh 2>/dev/null || true

    elif command_exists wget; then
        info "Downloading official Aegis uninstall script..."

        wget -q \
            "http://update2.aegis.aliyun.com/download/uninstall.sh" \
            -O /tmp/alibaba-aegis-uninstall.sh 2>/dev/null || true
    fi

    if [ -s /tmp/alibaba-aegis-uninstall.sh ]; then

        chmod +x /tmp/alibaba-aegis-uninstall.sh

        info "Running official Aegis uninstall script..."

        bash /tmp/alibaba-aegis-uninstall.sh \
            >/tmp/alibaba-aegis-uninstall.log 2>&1 || true

        rm -f /tmp/alibaba-aegis-uninstall.sh

        success "Official Aegis uninstall attempted."

    else
        warn "Official Aegis uninstall script could not be downloaded."
        warn "Continuing with local cleanup."
    fi

else

    success "Security Center / Aegis not detected."

fi

# ------------------------------------------------------------
# Kill Aegis processes
# ------------------------------------------------------------

info "Stopping Aegis residual processes..."

pkill -9 -x AliYunDun 2>/dev/null || true
pkill -9 -x AliYunDunMonitor 2>/dev/null || true
pkill -9 -x AliYunDunUpdate 2>/dev/null || true

pkill -9 -f "/usr/local/aegis" 2>/dev/null || true

# ------------------------------------------------------------
# Alibaba Cloud Assistant
# ------------------------------------------------------------

section "Removing Alibaba Cloud Assistant"

ASSIST_FOUND=0

if [ -d /usr/local/share/aliyun-assist ]; then
    ASSIST_FOUND=1
fi

if pgrep -f "/aliyun-service" >/dev/null 2>&1; then
    ASSIST_FOUND=1
fi

if [ "$ASSIST_FOUND" -eq 1 ]; then

    info "Alibaba Cloud Assistant detected."

    # Try package removal first.
    case "$OS_ID" in

        debian|ubuntu)
            if command_exists dpkg; then
                dpkg -l 2>/dev/null \
                    | awk '/aliyun-assist/ {print $2}' \
                    | while read -r pkg; do
                        [ -n "$pkg" ] && apt-get purge -y "$pkg" 2>/dev/null || true
                    done
            fi
            ;;

        centos|rhel|rocky|almalinux|alinux)
            if command_exists rpm; then
                rpm -qa 2>/dev/null \
                    | grep -i "aliyun-assist" \
                    | while read -r pkg; do
                        [ -n "$pkg" ] && rpm -e "$pkg" 2>/dev/null || true
                    done
            fi
            ;;

    esac

    # Stop processes after package removal.
    pkill -9 -f "/aliyun-service" 2>/dev/null || true
    pkill -9 -f "aliyun-assist" 2>/dev/null || true
    pkill -9 -f "assist-daemon" 2>/dev/null || true

    success "Cloud Assistant cleanup attempted."

else

    success "Cloud Assistant not detected."

fi

# ------------------------------------------------------------
# Logtail / LoongCollector
# ------------------------------------------------------------

section "Removing Logtail / LoongCollector"

LOG_AGENT_FOUND=0

if pgrep -f "loongcollector" >/dev/null 2>&1; then
    LOG_AGENT_FOUND=1
fi

if pgrep -f "ilogtail" >/dev/null 2>&1; then
    LOG_AGENT_FOUND=1
fi

if pgrep -f "logtail" >/dev/null 2>&1; then
    LOG_AGENT_FOUND=1
fi

if [ "$LOG_AGENT_FOUND" -eq 1 ]; then

    warn "Log collection agent detected."

    systemctl stop loongcollector.service 2>/dev/null || true
    systemctl disable loongcollector.service 2>/dev/null || true

    systemctl stop ilogtail.service 2>/dev/null || true
    systemctl disable ilogtail.service 2>/dev/null || true

    systemctl stop logtaild.service 2>/dev/null || true
    systemctl disable logtaild.service 2>/dev/null || true

    pkill -9 -f loongcollector 2>/dev/null || true
    pkill -9 -f ilogtail 2>/dev/null || true
    pkill -9 -f logtail 2>/dev/null || true

    rm -rf /usr/local/ilogtail
    rm -rf /usr/local/loongcollector
    rm -rf /opt/loongcollector
    rm -rf /etc/ilogtail
    rm -rf /etc/loongcollector

    success "Log collection agent cleanup attempted."

else

    success "Logtail / LoongCollector not detected."

fi

# ------------------------------------------------------------
# Remove known systemd units
# ------------------------------------------------------------

section "Cleaning systemd residuals"

UNIT_PATHS=(
    "/etc/systemd/system/aliyun.service"
    "/etc/systemd/system/cloudmonitor.service"
    "/etc/systemd/system/aegis.service"
    "/etc/systemd/system/aegis_update.service"
    "/etc/systemd/system/aliyun-assist.service"
    "/etc/systemd/system/assist-daemon.service"
    "/etc/systemd/system/AssistDaemon.service"
    "/etc/systemd/system/loongcollector.service"
    "/etc/systemd/system/ilogtail.service"
    "/etc/systemd/system/logtaild.service"
)

for unit in "${UNIT_PATHS[@]}"; do
    if [ -e "$unit" ]; then
        info "Removing $unit"
        rm -f "$unit"
    fi
done

# Remove known wants symlinks.
find /etc/systemd/system \
    -type l \
    \( -iname '*aliyun*' \
    -o -iname '*cloudmonitor*' \
    -o -iname '*aegis*' \
    -o -iname '*loongcollector*' \
    -o -iname '*ilogtail*' \
    -o -iname '*logtail*' \) \
    -delete 2>/dev/null || true

systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

# ------------------------------------------------------------
# Remove known Alibaba directories/files
# ------------------------------------------------------------

section "Removing Alibaba Cloud agent files"

PATHS=(
    "/usr/local/aegis"
    "/usr/local/cloudmonitor"
    "/usr/local/share/aliyun-assist"
    "/usr/local/share/assist-daemon"
    "/usr/local/aliyun-assist"
    "/usr/local/ilogtail"
    "/usr/local/loongcollector"
    "/opt/loongcollector"
    "/etc/ilogtail"
    "/etc/loongcollector"
    "/etc/cloudmonitor"
    "/usr/sbin/aliyun-service"
    "/usr/sbin/aliyun_installer"
    "/usr/share/doc/aliyun-assist"
)

for path in "${PATHS[@]}"; do
    if [ -e "$path" ]; then
        info "Removing $path"
        rm -rf "$path"
    fi
done

# ------------------------------------------------------------
# Remove known cron entries
# ------------------------------------------------------------

section "Checking cron entries"

CRON_FILES=(
    "/etc/crontab"
    "/etc/cron.d"
    "/etc/cron.hourly"
    "/etc/cron.daily"
    "/etc/cron.weekly"
    "/etc/cron.monthly"
    "/var/spool/cron"
    "/var/spool/cron/crontabs"
)

for dir in "${CRON_FILES[@]}"; do
    if [ -e "$dir" ]; then
        grep -RIlE \
            'aliyun|aliyundun|aegis|argusagent|cloudmonitor|loongcollector|ilogtail|logtail' \
            "$dir" 2>/dev/null \
            | while read -r file; do
                warn "Possible Alibaba Cloud cron entry: $file"
            done
    fi
done

# ------------------------------------------------------------
# Kill any remaining known processes
# ------------------------------------------------------------

section "Final process cleanup"

PROCESS_PATTERNS=(
    "AliYunDun"
    "AliYunDunMonitor"
    "AliYunDunUpdate"
    "argusagent"
    "/aliyun-service"
    "aliyun-assist"
    "assist-daemon"
    "loongcollector"
    "ilogtail"
)

for pattern in "${PROCESS_PATTERNS[@]}"; do
    pkill -9 -f "$pattern" 2>/dev/null || true
done

sleep 2

# ------------------------------------------------------------
# Verification
# ------------------------------------------------------------

section "Final verification"

FOUND=0

echo
echo "[1] Processes"
PROCESS_RESULT="$(
    ps auxww 2>/dev/null \
    | grep -Ei \
    'aliyun|aliyundun|aegis|argusagent|cloudmonitor|loongcollector|ilogtail|logtail' \
    | grep -vE 'grep|alibaba-cleaner|install.sh' \
    || true
)"

if [ -n "$PROCESS_RESULT" ]; then
    echo "$PROCESS_RESULT"
    FOUND=1
else
    success "No known Alibaba Cloud agent processes found."
fi

echo
echo "[2] systemd services"

SERVICE_RESULT="$(
    systemctl list-units --type=service --all 2>/dev/null \
    | grep -Ei \
    'aliyun|aliyundun|aegis|argus|cloudmonitor|loongcollector|ilogtail|logtail' \
    | grep -vE 'cloud-init|lvm2-monitor|mdmonitor|ubuntu-advantage' \
    || true
)"

if [ -n "$SERVICE_RESULT" ]; then
    echo "$SERVICE_RESULT"
    FOUND=1
else
    success "No known Alibaba Cloud agent services found."
fi

echo
echo "[3] Agent directories"

DIR_RESULT=""

for path in \
    /usr/local/aegis \
    /usr/local/cloudmonitor \
    /usr/local/share/aliyun-assist \
    /usr/local/share/assist-daemon \
    /usr/local/ilogtail \
    /usr/local/loongcollector \
    /opt/loongcollector \
    /etc/ilogtail \
    /etc/loongcollector \
    /etc/cloudmonitor
do
    if [ -e "$path" ]; then
        DIR_RESULT="${DIR_RESULT}${path}"$'\n'
    fi
done

if [ -n "$DIR_RESULT" ]; then
    echo "$DIR_RESULT"
    FOUND=1
else
    success "Known Alibaba Cloud agent directories are clean."
fi

echo
echo "[4] Network connections"

NET_RESULT="$(
    ss -ntp 2>/dev/null \
    | grep -Ei \
    'AliYunDun|argusagent|aliyun|cloudmonitor|aegis|loongcollector|ilogtail|logtail' \
    || true
)"

if [ -n "$NET_RESULT" ]; then
    echo "$NET_RESULT"
    FOUND=1
else
    success "No known Alibaba Cloud agent network connections found."
fi

echo
echo "[5] Systemd unit files"

UNIT_RESULT="$(
    find /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system \
    -type f 2>/dev/null \
    | grep -Ei \
    '/(aliyun|aliyundun|aegis|argus|cloudmonitor|loongcollector|ilogtail|logtail)' \
    || true
)"

if [ -n "$UNIT_RESULT" ]; then
    echo "$UNIT_RESULT"
    FOUND=1
else
    success "No known Alibaba Cloud agent unit files found."
fi

# ------------------------------------------------------------
# Result
# ------------------------------------------------------------

section "Cleanup result"

if [ "$FOUND" -eq 0 ]; then

    echo
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN} Alibaba Cloud agents successfully cleaned.${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo
    echo "Detected and removed where applicable:"
    echo "  - Security Center / Aegis"
    echo "  - CloudMonitor"
    echo "  - Cloud Assistant"
    echo "  - Logtail / LoongCollector"
    echo
    echo "Normal system components were intentionally preserved:"
    echo "  - cloud-init"
    echo "  - systemd"
    echo "  - sshd"
    echo "  - LVM monitoring"
    echo "  - mdmonitor"
    echo
    echo "A reboot is recommended."
    echo

else

    echo
    echo -e "${YELLOW}============================================================${NC}"
    echo -e "${YELLOW} Cleanup completed, but residuals were detected.${NC}"
    echo -e "${YELLOW}============================================================${NC}"
    echo
    echo "Please review the items listed above."
    echo

fi

exit 0
