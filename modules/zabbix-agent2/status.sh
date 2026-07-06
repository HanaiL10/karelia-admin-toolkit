#!/usr/bin/env bash

set -Eeuo pipefail

KAT_ROOT="${KAT_ROOT:-/opt/karelia-admin-toolkit}"
LIB="$KAT_ROOT/linux/common/functions.sh"
if [[ -r "$LIB" ]]; then
    source "$LIB"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../../linux/common/functions.sh"
fi

ZBX_CONF="/etc/zabbix/zabbix_agent2.conf"
ZBX_CONF_DIR="/etc/zabbix/zabbix_agent2.d"
KAT_CONF="$ZBX_CONF_DIR/karelia-admin-toolkit.conf"

ok() { echo "OK"; }
fail() { echo "FAIL"; }
missing() { echo "MISSING"; }

pkg_version() {
    if command -v dpkg-query >/dev/null 2>&1 && dpkg-query -W -f='${Version}' zabbix-agent2 >/dev/null 2>&1; then
        dpkg-query -W -f='${Version}' zabbix-agent2
        return 0
    fi

    if command -v rpm >/dev/null 2>&1 && rpm -q zabbix-agent2 >/dev/null 2>&1; then
        rpm -q --qf '%{VERSION}-%{RELEASE}' zabbix-agent2
        return 0
    fi

    echo "not installed"
}

service_state() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active zabbix-agent2 2>/dev/null || echo unknown
    else
        echo unknown
    fi
}

service_enabled() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-enabled zabbix-agent2 2>/dev/null || echo unknown
    else
        echo unknown
    fi
}

check_key() {
    local key="$1"
    if ! command -v zabbix_agent2 >/dev/null 2>&1; then
        echo "MISSING"
        return 0
    fi
    if zabbix_agent2 -t "$key" >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAIL"
    fi
}

include_state() {
    if [[ ! -f "$ZBX_CONF" ]]; then
        missing
        return 0
    fi
    if grep -Eq '^Include=.*/zabbix_agent2\.d/\*\.conf' "$ZBX_CONF"; then
        ok
    else
        fail
    fi
}

server_value() {
    if [[ -f "$ZBX_CONF" ]]; then
        awk -F= '/^Server=/{print $2; exit}' "$ZBX_CONF"
    fi
}

main() {
    kat_detect_os || true

    echo "Karelia Admin Toolkit - Zabbix Agent2 status"
    echo
    echo "OS:"
    echo "  Name      : ${KAT_OS_ID:-unknown} ${KAT_OS_VERSION_ID:-}"
    echo "  Kernel    : $(uname -r)"
    echo
    echo "Agent:"
    echo "  Installed : $(command -v zabbix_agent2 >/dev/null 2>&1 && echo YES || echo NO)"
    echo "  Version   : $(pkg_version)"
    echo
    echo "Service:"
    echo "  Status    : $(service_state)"
    echo "  Enabled   : $(service_enabled)"
    echo
    echo "Configuration:"
    echo "  Main conf : $([[ -f "$ZBX_CONF" ]] && ok || missing)"
    echo "  Include   : $(include_state)"
    echo "  Toolkit   : $([[ -f "$KAT_CONF" ]] && ok || missing)"
    echo "  Server    : $(server_value || true)"
    echo
    echo "UserParameters:"
    echo "  service.zabbix_agent2.status      : $(check_key service.zabbix_agent2.status)"
    echo "  copyfail.kernel.running           : $(check_key copyfail.kernel.running)"
    echo "  copyfail.algif_aead.loaded        : $(check_key copyfail.algif_aead.loaded)"
    echo "  copyfail.algif_aead.blocked       : $(check_key copyfail.algif_aead.blocked)"
    echo "  copyfail.reboot.required          : $(check_key copyfail.reboot.required)"
    echo "  copyfail.pkg.kernel               : $(check_key copyfail.pkg.kernel)"
}

main "$@"
