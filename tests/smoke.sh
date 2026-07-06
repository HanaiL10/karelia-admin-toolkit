#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0

check_syntax() {
    local file="$1"
    echo "Checking syntax: $file"
    if ! bash -n "$ROOT_DIR/$file"; then
        fail=1
    fi
}

check_exists() {
    local file="$1"
    echo "Checking exists: $file"
    if [[ ! -f "$ROOT_DIR/$file" ]]; then
        echo "Missing: $file" >&2
        fail=1
    fi
}

check_exists VERSION
check_exists README.md
check_exists install.sh
check_exists bin/kat
check_exists linux/common/functions.sh
check_exists linux/zabbix/update_agent2.sh

check_syntax install.sh
check_syntax bin/kat
check_syntax linux/common/functions.sh
check_syntax linux/zabbix/update_agent2.sh

if [[ "$fail" -ne 0 ]]; then
    echo "Smoke tests failed" >&2
    exit 1
fi

echo "Smoke tests passed"
