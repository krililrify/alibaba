#!/usr/bin/env bash
# Alibaba Cloud ECS host-agent cleaner. Run as root.
set -u
export LC_ALL=C
VERSION=2.0.0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
AGENT_RE='(AliYunDun(Monitor|Update)?|aegis|argusagent|cloudmonitor|aliyun-service|aliyun-assist|assist-daemon|loongcollector|ilogtail|logtaild)'
PROC_NAMES='^(AliYunDun|AliYunDunMonitor|AliYunDunUpdate|AliHips|aegis|argusagent|aliyun-service|assist-daemon|AssistDaemon|loongcollector|ilogtail|logtail|logtaild)$'
PROTECTED='^(cloud-init|systemd|sshd|lvm2-monitor|mdmonitor)(\.service)?$'
DIRS=(/usr/local/aegis /usr/local/cloudmonitor /usr/local/share/aliyun-assist /usr/local/share/assist-daemon /usr/local/aliyun-assist /usr/local/ilogtail /usr/local/loongcollector /opt/loongcollector /etc/ilogtail /etc/loongcollector /etc/cloudmonitor)
FILES=(/usr/sbin/aliyun-service /usr/sbin/aliyun_installer /usr/share/doc/aliyun-assist)
UNIT_DIRS=(/etc/systemd/system /usr/lib/systemd/system /lib/systemd/system)
RESIDUALS=()
have(){ command -v "$1" >/dev/null 2>&1; }
known_unit(){ [[ "${1,,}" =~ (aegis|aliyun|aliyundun|argus|cloudmonitor|assist-daemon|loongcollector|ilogtail|logtail) ]]; }
protected(){ [[ "$1" =~ $PROTECTED ]]; }
residual(){ RESIDUALS+=("$*"); }
[[ $EUID -eq 0 ]] || { echo 'ERROR: run as root.' >&2; exit 1; }
have systemctl || { echo 'ERROR: systemctl is required.' >&2; exit 1; }
printf '\n============================================================\n Alibaba Cloud Agent Cleaner v%s\n============================================================\n' "$VERSION"
printf 'Only identified Alibaba Cloud agents are targeted. System services are protected.\n\n'

# PID match requires an exact comm name or an executable/cmdline under fixed agent roots.
agent_pids(){
    local p pid comm exe cmd
    for p in /proc/[0-9]*; do
        [[ -d $p ]] || continue; pid=${p##*/}; IFS= read -r comm < "$p/comm" 2>/dev/null || comm=''
        if [[ $comm =~ $PROC_NAMES ]]; then printf '%s\n' "$pid"; continue; fi
        exe=$(readlink -f "$p/exe" 2>/dev/null || true); cmd=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null || true)
        case "$exe $cmd" in */usr/local/aegis/*|*/usr/local/cloudmonitor/*|*/usr/local/share/aliyun-assist/*|*/usr/local/share/assist-daemon/*|*/usr/local/aliyun-assist/*|*/usr/local/ilogtail/*|*/usr/local/loongcollector/*|*/opt/loongcollector/*) printf '%s\n' "$pid";; esac
    done
}

printf '[1/8] Detecting Alibaba Cloud agents...\n'
for n in AliYunDun AliYunDunMonitor AliYunDunUpdate AliHips aegis argusagent aliyun-service; do p=$(pgrep -x "$n" 2>/dev/null || true); [[ -z $p ]] || echo "Detected $n PID(s): ${p//$'\n'/, }"; done
for d in "${DIRS[@]}"; do [[ ! -e $d ]] || echo "Detected $d"; done
systemctl show aegis.service -p LoadState --value 2>/dev/null | grep -qv '^not-found$' && echo 'Detected aegis.service'
if have lsattr; then for d in "${DIRS[@]}"; do [[ -e $d ]] || continue; a=$(lsattr -R "$d" 2>/dev/null | awk '$1 ~ /[ia]/ {print}' | head -20 || true); [[ -z $a ]] || printf 'Immutable/append-only entries under %s:\n%s\n' "$d" "$a"; done; fi

declare -A UNITS=()
while read -r u _; do [[ -n ${u:-} ]] || continue; b=${u##*/}; known_unit "$b" && ! protected "$b" && UNITS[$u]=1; done < <(systemctl list-unit-files --no-legend --no-pager 2>/dev/null || true)
for u in aegis.service aegis_update.service aliyun.service cloudmonitor.service aliyun-assist.service assist-daemon.service AssistDaemon.service loongcollector.service ilogtail.service logtaild.service; do s=$(systemctl show "$u" -p LoadState --value 2>/dev/null || true); [[ -z $s || $s == not-found ]] || UNITS[$u]=1; done
printf '[2/8] Stopping services...\n'
for u in "${!UNITS[@]}"; do systemctl stop "$u" 2>/dev/null || true; systemctl disable "$u" 2>/dev/null || true; done

printf '[3/8] Running official uninstall procedures...\n'
if [[ -d /usr/local/aegis ]]; then
    official=''; for c in /usr/local/aegis/uninstall.sh /usr/local/aegis/aegis_client/uninstall.sh /usr/local/aegis/uninstall; do [[ -x $c ]] && official=$c && break; done
    if [[ -n $official ]]; then "$official" >/tmp/alibaba-aegis-uninstall.log 2>&1 || echo 'Official Aegis uninstaller failed; continuing verification.'
    elif have curl || have wget; then
        t=$(mktemp /tmp/alibaba-aegis-uninstall.XXXXXX) || t=''
        if [[ -n $t ]]; then
            if { have curl && curl -fsSL --max-time 20 https://update2.aegis.aliyun.com/download/uninstall.sh -o "$t"; } || { have wget && wget -q --timeout=20 https://update2.aegis.aliyun.com/download/uninstall.sh -O "$t"; }; then bash "$t" >/tmp/alibaba-aegis-uninstall.log 2>&1 || echo 'Official Aegis uninstaller failed; continuing verification.'; else echo 'Official Aegis uninstaller unavailable; continuing local cleanup.'; fi
            rm -f -- "$t"
        fi
    else echo 'curl/wget unavailable; skipped official uninstaller.'; fi
fi
if [[ -x /usr/local/cloudmonitor/cloudmonitorCtl.sh ]]; then /usr/local/cloudmonitor/cloudmonitorCtl.sh stop >/dev/null 2>&1 || true; /usr/local/cloudmonitor/cloudmonitorCtl.sh uninstall >/dev/null 2>&1 || true; fi
# Remove only packages whose package names explicitly identify these agents.
# No wildcard package expressions are passed to apt/rpm/dnf/yum.
PKG_RE='^(aegis|aegis-client|aliyun-assist|aliyun-service|cloudmonitor|cloudmonitor-agent|ilogtail|loongcollector|logtail|logtaild)((:[^[:space:]]+)?)$'
if have dpkg-query && have apt-get; then
    while IFS= read -r pkg; do [[ $pkg =~ $PKG_RE ]] && DEBIAN_FRONTEND=noninteractive apt-get purge -y "$pkg" >/dev/null 2>&1 || true; done < <(dpkg-query -W -f='${binary:Package}\n' 2>/dev/null || true)
elif have rpm; then
    while IFS= read -r pkg; do [[ $pkg =~ $PKG_RE ]] && { if have dnf; then dnf remove -y "$pkg" >/dev/null 2>&1 || true; elif have yum; then yum remove -y "$pkg" >/dev/null 2>&1 || true; else rpm -e "$pkg" >/dev/null 2>&1 || true; fi; }; done < <(rpm -qa --qf '%{NAME}\n' 2>/dev/null || true)
fi

printf '[4/8] Removing self-protection attributes...\n'
if have chattr; then for d in "${DIRS[@]}"; do [[ -e $d ]] && chattr -R -i -a -- "$d" 2>/dev/null || true; done; for f in "${FILES[@]}"; do [[ -e $f ]] && chattr -i -a -- "$f" 2>/dev/null || true; done; else echo 'chattr unavailable; attributes may block removal.'; fi

printf '[5/8] Terminating remaining processes...\n'
p=$(agent_pids | sort -un); [[ -z $p ]] || { kill -TERM $p 2>/dev/null || true; sleep 2; }
p=$(agent_pids | sort -un); [[ -z $p ]] || { kill -KILL $p 2>/dev/null || true; sleep 2; }

printf '[6/8] Removing agent files...\n'
for d in "${DIRS[@]}"; do [[ -e $d || -L $d ]] || continue; chattr -R -i -a -- "$d" 2>/dev/null || true; rm -rf --one-file-system -- "$d" 2>/dev/null || echo "Could not completely remove $d"; done
for f in "${FILES[@]}"; do [[ -e $f || -L $f ]] || continue; chattr -i -a -- "$f" 2>/dev/null || true; rm -f -- "$f" 2>/dev/null || echo "Could not remove $f"; done

printf '[7/8] Cleaning systemd / cron...\n'
for d in "${UNIT_DIRS[@]}"; do
    [[ -d $d ]] || continue
    while IFS= read -r -d '' f; do u=${f##*/}; b=${u%%.*}; known_unit "$u" || grep -Eiq "$AGENT_RE|/usr/local/aegis|/usr/local/cloudmonitor" "$f" 2>/dev/null || continue; protected "$b" && continue; systemctl stop "$u" 2>/dev/null || true; systemctl disable "$u" 2>/dev/null || true; rm -f -- "$f" 2>/dev/null || true; done < <(find "$d" -maxdepth 3 \( -type f -o -type l \) -print0 2>/dev/null)
done
systemctl daemon-reload 2>/dev/null || true; systemctl reset-failed 2>/dev/null || true
clean_cron(){
    local f=$1 t; [[ -f $f && ! -L $f ]] || return 0
    grep -Eiq "$AGENT_RE|/usr/local/aegis|/usr/local/cloudmonitor" "$f" || return 0
    t=$(mktemp "${f}.clean.XXXXXX") || return 1
    awk -v re="$AGENT_RE|/usr/local/aegis|/usr/local/cloudmonitor" 'tolower($0) !~ tolower(re)' "$f" > "$t" || { rm -f "$t"; return 1; }
    chown --reference="$f" "$t" 2>/dev/null || true; chmod --reference="$f" "$t" 2>/dev/null || true
    cat "$t" > "$f" || echo "Could not update cron file $f"; rm -f "$t"
}
for f in /etc/crontab /etc/cron.d/* /etc/cron.hourly/* /etc/cron.daily/* /etc/cron.weekly/* /etc/cron.monthly/* /var/spool/cron/* /var/spool/cron/crontabs/*; do [[ ! -e $f ]] || clean_cron "$f"; done
# A supervisor may have relaunched a process during the earlier cleanup. Stop
# the already disabled service sources above, make one more exact-PID pass,
# and verify after the grace period.
p=$(agent_pids | sort -un); [[ -z $p ]] || { echo "Agent process reappeared; terminating exact PID(s): ${p//$'\n'/, }"; kill -TERM $p 2>/dev/null || true; sleep 2; }
p=$(agent_pids | sort -un); [[ -z $p ]] || { kill -KILL $p 2>/dev/null || true; sleep 2; }

printf '[8/8] Final verification...\n'
for n in AliYunDun AliYunDunMonitor AliYunDunUpdate AliHips aegis argusagent aliyun-service; do p=$(pgrep -x "$n" 2>/dev/null || true); [[ -z $p ]] || residual "Process $n remains (PID(s): ${p//$'\n'/, })"; done
p=$(agent_pids | sort -un); [[ -z $p ]] || residual "Agent path process remains (PID(s): ${p//$'\n'/, })"
for d in "${DIRS[@]}"; do [[ ! -e $d && ! -L $d ]] || residual "Directory remains: $d"; done
for f in "${FILES[@]}"; do [[ ! -e $f && ! -L $f ]] || residual "Agent file remains: $f"; done
while read -r u _; do [[ -n ${u:-} ]] || continue; b=${u##*/}; known_unit "$b" && ! protected "$b" && residual "systemd unit remains: $u ($(systemctl show "$u" -p ActiveState --value 2>/dev/null || echo unknown))"; done < <(systemctl list-unit-files --no-legend --no-pager 2>/dev/null || true)
while read -r u _; do [[ -n ${u:-} ]] || continue; b=${u##*/}; known_unit "$b" && ! protected "$b" || continue; state=$(systemctl show "$u" -p ActiveState --value 2>/dev/null || true); [[ $state != active && $state != activating ]] || residual "Agent service is still running: $u ($state)"; done < <(systemctl list-units --type=service --all --no-legend --no-pager 2>/dev/null || true)
for d in "${UNIT_DIRS[@]}"; do [[ -d $d ]] || continue; while IFS= read -r -d '' f; do u=${f##*/}; b=${u%%.*}; if { known_unit "$u" || grep -Eiq "$AGENT_RE|/usr/local/aegis|/usr/local/cloudmonitor" "$f" 2>/dev/null; } && ! protected "$b"; then residual "systemd unit file remains: $f"; fi; done < <(find "$d" -maxdepth 3 \( -type f -o -type l \) -print0 2>/dev/null); done
for f in /etc/crontab /etc/cron.d/* /etc/cron.hourly/* /etc/cron.daily/* /etc/cron.weekly/* /etc/cron.monthly/* /var/spool/cron/* /var/spool/cron/crontabs/*; do [[ -f $f ]] && grep -Eiq "$AGENT_RE|/usr/local/aegis|/usr/local/cloudmonitor" "$f" && residual "Cron entry remains in $f"; done
if have ss; then n=$(ss -ntup 2>/dev/null | grep -Ei "$AGENT_RE|100\.100\.(88\.88|80\.184)" || true); [[ -z $n ]] || while IFS= read -r line; do residual "Agent-related network connection: $line"; done <<< "$n"; fi
if ((${#RESIDUALS[@]})); then printf '\n============================================================\n Alibaba Cloud Agent Cleanup: FAILED / RESIDUALS DETECTED\n============================================================\nCleanup completed, but residuals were detected:\n'; printf ' - %s\n' "${RESIDUALS[@]}"; exit 1; fi
printf '\n============================================================\n Alibaba Cloud Agent Cleanup: SUCCESS\n============================================================\nAll checked processes, services, directories, cron entries, and network connections are absent.\n'
