#!/usr/bin/env bash

set -Eeuo pipefail

fail=0
warn=0

line() {
    printf '%-28s %s\n' "$1" "$2"
}

pass() {
    line "$1" "OK"
}

warning() {
    warn=$((warn + 1))
    line "$1" "WARN"
}

bad() {
    fail=$((fail + 1))
    line "$1" "FAIL"
}

check_os() {
    if [[ -r /etc/os-release ]]; then
        pass "OS release"
    else
        bad "OS release"
    fi
}

check_systemd() {
    if command -v systemctl >/dev/null 2>&1; then
        pass "systemd"
    else
        warning "systemd"
    fi
}

check_dns() {
    if getent hosts github.com >/dev/null 2>&1; then
        pass "DNS github.com"
    else
        bad "DNS github.com"
    fi
}

check_network() {
    if ip route get 1.1.1.1 >/dev/null 2>&1; then
        pass "Default route"
    else
        bad "Default route"
    fi
}

check_disk() {
    local pct
    pct="$(df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"
    if [[ -z "$pct" ]]; then
        warning "Root disk usage"
    elif [[ "$pct" -ge 95 ]]; then
        bad "Root disk usage ${pct}%"
    elif [[ "$pct" -ge 85 ]]; then
        warning "Root disk usage ${pct}%"
    else
        pass "Root disk usage ${pct}%"
    fi
}

check_time() {
    if command -v timedatectl >/dev/null 2>&1; then
        if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qx yes; then
            pass "Time sync"
        else
            warning "Time sync"
        fi
    else
        warning "Time sync"
    fi
}

check_zabbix() {
    if command -v zabbix_agent2 >/dev/null 2>&1; then
        pass "Zabbix Agent2 binary"
    else
        warning "Zabbix Agent2 binary"
        return 0
    fi

    if systemctl is-active zabbix-agent2 >/dev/null 2>&1; then
        pass "Zabbix Agent2 service"
    else
        bad "Zabbix Agent2 service"
    fi
}

main() {
    echo "Karelia Admin Toolkit - doctor"
    echo
    check_os
    check_systemd
    check_dns
    check_network
    check_disk
    check_time
    check_zabbix
    echo

    if [[ "$fail" -gt 0 ]]; then
        echo "Overall: FAIL ($fail failed, $warn warnings)"
        exit 1
    elif [[ "$warn" -gt 0 ]]; then
        echo "Overall: WARN ($warn warnings)"
        exit 0
    else
        echo "Overall: OK"
        exit 0
    fi
}

main "$@"
