#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/linux/common/functions.sh"

ZBX_MAJOR="6.4"
CONFIGURE_ONLY=0
ZBX_SERVER="${ZBX_SERVER:-172.31.254.101}"
ZBX_SERVER_ACTIVE="${ZBX_SERVER_ACTIVE:-$ZBX_SERVER}"
ZBX_HOSTNAME=""
ZBX_HOSTNAME_ITEM="system.hostname"
ZBX_TIMEOUT="30"
ZBX_CONF="/etc/zabbix/zabbix_agent2.conf"
ZBX_CONF_DIR="/etc/zabbix/zabbix_agent2.d"
KAT_BASE_CONF="$ZBX_CONF_DIR/00-karelia-base.conf"
KAT_USERPARAM_CONF="$ZBX_CONF_DIR/10-karelia-userparameters.conf"

usage() {
    cat <<USAGE
Update or configure Zabbix Agent2

Usage:
  sudo update_agent2.sh [options]

Options:
  --major VERSION         Zabbix major version. Default: 6.4
  --server IP_OR_DNS      Zabbix Server. Default: 172.31.254.101
  --server-active VALUE   Zabbix ServerActive. Default: same as --server
  --hostname NAME         Static Hostname. If omitted, HostnameItem is used
  --hostname-item KEY     HostnameItem. Default: system.hostname
  --timeout SECONDS       Agent timeout. Default: 30
  --configure-only        Only configure Agent2 and restart service
  --dry-run               Show actions without changing system
  -h, --help              Show help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --major) ZBX_MAJOR="${2:-}"; shift 2 ;;
        --server) ZBX_SERVER="${2:-}"; ZBX_SERVER_ACTIVE="${ZBX_SERVER_ACTIVE:-${2:-}}"; shift 2 ;;
        --server-active) ZBX_SERVER_ACTIVE="${2:-}"; shift 2 ;;
        --hostname) ZBX_HOSTNAME="${2:-}"; shift 2 ;;
        --hostname-item) ZBX_HOSTNAME_ITEM="${2:-}"; shift 2 ;;
        --timeout) ZBX_TIMEOUT="${2:-}"; shift 2 ;;
        --configure-only) CONFIGURE_ONLY=1; shift ;;
        --dry-run) KAT_DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

write_base_config() {
    kat_run mkdir -p "$ZBX_CONF_DIR"

    if [[ "$KAT_DRY_RUN" == "1" ]]; then
        kat_info "DRY-RUN: write $KAT_BASE_CONF"
        kat_info "DRY-RUN: Server=$ZBX_SERVER ServerActive=$ZBX_SERVER_ACTIVE Timeout=$ZBX_TIMEOUT"
        return 0
    fi

    {
        echo "# Managed by Karelia Admin Toolkit"
        echo "Server=$ZBX_SERVER"
        echo "ServerActive=$ZBX_SERVER_ACTIVE"
        if [[ -n "$ZBX_HOSTNAME" ]]; then
            echo "Hostname=$ZBX_HOSTNAME"
        else
            echo "HostnameItem=$ZBX_HOSTNAME_ITEM"
        fi
        echo "Timeout=$ZBX_TIMEOUT"
    } > "$KAT_BASE_CONF"
}

write_userparameters() {
    kat_run mkdir -p "$ZBX_CONF_DIR"

    if [[ "$KAT_DRY_RUN" == "1" ]]; then
        kat_info "DRY-RUN: write $KAT_USERPARAM_CONF"
        return 0
    fi

    cat > "$KAT_USERPARAM_CONF" <<'EOF'
# Managed by Karelia Admin Toolkit
UserParameter=service.zabbix_agent2.status,systemctl is-active zabbix-agent2 2>/dev/null || echo inactive
UserParameter=copyfail.kernel.running,uname -r
UserParameter=copyfail.algif_aead.loaded,grep -q '^algif_aead ' /proc/modules && echo 1 || echo 0
UserParameter=copyfail.algif_aead.blocked,grep -Rqs 'blacklist algif_aead' /etc/modprobe.d /usr/lib/modprobe.d 2>/dev/null && echo 1 || echo 0
UserParameter=copyfail.reboot.required,test -f /var/run/reboot-required && echo 1 || echo 0
UserParameter=copyfail.pkg.kernel,uname -r
EOF
}

ensure_include() {
    if [[ ! -f "$ZBX_CONF" ]]; then
        return 0
    fi

    if grep -Eq '^Include=.*/zabbix_agent2\.d/\*\.conf' "$ZBX_CONF"; then
        return 0
    fi

    if [[ "$KAT_DRY_RUN" == "1" ]]; then
        kat_info "DRY-RUN: append Include to $ZBX_CONF"
    else
        printf '\nInclude=/etc/zabbix/zabbix_agent2.d/*.conf\n' >> "$ZBX_CONF"
    fi
}

install_deb_package() {
    kat_need_command apt-get

    if ! command -v curl >/dev/null 2>&1; then
        kat_run apt-get update
        kat_run apt-get install -y curl ca-certificates gnupg
    fi

    kat_run apt-get update
    kat_run apt-get install -y zabbix-agent2
}

install_rpm_package() {
    local pm=""

    if command -v dnf >/dev/null 2>&1; then
        pm="dnf"
    elif command -v yum >/dev/null 2>&1; then
        pm="yum"
    else
        kat_die "Neither dnf nor yum found"
    fi

    kat_info "Package manager: $pm"
    kat_run "$pm" install -y zabbix-agent2
}

install_repo_package() {
    kat_detect_os
    kat_info "Detected: $KAT_OS_ID $KAT_OS_VERSION_ID $KAT_OS_CODENAME $KAT_ARCH"

    case "$KAT_OS_ID" in
        debian|ubuntu)
            install_deb_package
            ;;
        rocky|rhel|centos|almalinux|ol)
            install_rpm_package
            ;;
        *)
            kat_die "Unsupported OS: $KAT_OS_ID"
            ;;
    esac
}

restart_and_test() {
    kat_run systemctl enable zabbix-agent2
    kat_run systemctl restart zabbix-agent2

    if [[ "$KAT_DRY_RUN" != "1" ]]; then
        zabbix_agent2 -t service.zabbix_agent2.status || true
        zabbix_agent2 -t copyfail.kernel.running || true
    fi
}

main() {
    kat_need_root
    kat_init_dirs

    kat_info "Karelia Admin Toolkit: Zabbix Agent2"
    kat_info "Target Zabbix major: $ZBX_MAJOR"
    kat_info "Zabbix server: $ZBX_SERVER"

    kat_backup_path "$ZBX_CONF"
    kat_backup_path "$ZBX_CONF_DIR"

    if [[ "$CONFIGURE_ONLY" != "1" ]]; then
        install_repo_package
    else
        kat_info "Configure-only mode: package update skipped"
    fi

    write_base_config
    write_userparameters
    ensure_include
    restart_and_test

    kat_info "Done"
}

main "$@"
