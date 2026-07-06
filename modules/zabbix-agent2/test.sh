#!/usr/bin/env bash

set -Eeuo pipefail

keys=(
    service.zabbix_agent2.status
    copyfail.kernel.running
    copyfail.algif_aead.loaded
    copyfail.algif_aead.blocked
    copyfail.reboot.required
    copyfail.pkg.kernel
)

if ! command -v zabbix_agent2 >/dev/null 2>&1; then
    echo "ERROR: zabbix_agent2 not found" >&2
    exit 1
fi

fail=0
for key in "${keys[@]}"; do
    if ! zabbix_agent2 -t "$key"; then
        fail=1
    fi
done

exit "$fail"
