#!/usr/bin/env bash

set -Eeuo pipefail

KAT_ROOT="${KAT_ROOT:-/opt/karelia-admin-toolkit}"
exec "$KAT_ROOT/linux/zabbix/update_agent2.sh" "$@"
