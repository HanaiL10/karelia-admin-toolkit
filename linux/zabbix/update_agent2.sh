#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/linux/common/functions.sh"

ZBX_MAJOR="6.4"
CONFIGURE_ONLY=0
ZBX_CONF="/etc/zabbix/zabbix_agent2.conf"
ZBX_CONF_DIR="/etc/zabbix/zabbix_agent2.d"
KAT_CONF="$ZBX_CONF_DIR/karelia-admin-toolkit.conf"

usage() {
    cat <<USAGE
Update or configure Zabbix Agent2

Usage:
  sudo update_agent2.sh [options]

Options:
  --major VERSION    Zabbix major version. Default: 6.4
  --configure-only   Only install Karelia UserParameters and restart agent
  --dry-run          Show actions without changing system
  -h, --help         Show help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --major) ZBX_MAJOR="${2:-}"; shift 2 ;;
        --configure-only) CONFIGURE_ONLY=1; shift ;;
        --dry-run) KAT_DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

write_userparameters() {
    kat_run mkdir -p "$ZBX_CONF_DIR"

    if [[ "$KAT_DRY_RUN" == "1" ]]; then
        kat_info "DRY-RUN: write $KAT_CONF"
        return 0
    fi

    cat > "$KAT_CONF" <<'EOF'
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

    kat_backup_path "$ZBX_CONF"
    kat_backup_path "$ZBX_CONF_DIR"

    if [[ "$CONFIGURE_ONLY" != "1" ]]; then
        install_repo_package
    else
        kat_info "Configure-only mode: package update skipped"
    fi

    write_userparameters
    ensure_include
    restart_and_test

    kat_info "Done"
}

main "$@"
