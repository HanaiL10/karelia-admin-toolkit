#!/usr/bin/env bash

set -Eeuo pipefail

HOSTS_FILE="${1:-}"
if [[ -z "$HOSTS_FILE" || ! -f "$HOSTS_FILE" ]]; then
    echo "Usage: kat fleet plan zabbix-agent2 hosts.txt" >&2
    exit 1
fi

printf '%-32s %-12s\n' "HOST" "ACTION"
printf '%-32s %-12s\n' "----" "------"

while IFS= read -r host; do
    [[ -z "$host" ]] && continue
    [[ "$host" == \#* ]] && continue
    printf '%-32s %-12s\n' "$host" "PLAN"
done < "$HOSTS_FILE"
