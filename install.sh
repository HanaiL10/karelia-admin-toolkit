#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/karelia-admin-toolkit}"
BIN_DIR="${BIN_DIR:-/usr/local/sbin}"
DRY_RUN=0

usage() {
    cat <<USAGE
Karelia Admin Toolkit installer

Usage:
  sudo ./install.sh [options]

Options:
  --prefix DIR    Install directory. Default: /opt/karelia-admin-toolkit
  --bin-dir DIR   Symlink directory. Default: /usr/local/sbin
  --dry-run       Show actions without changing system
  -h, --help      Show help
USAGE
}

run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRY-RUN: $*"
    else
        echo "RUN: $*"
        "$@"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) INSTALL_DIR="${2:-}"; shift 2 ;;
        --bin-dir) BIN_DIR="${2:-}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run as root." >&2
    exit 1
fi

run mkdir -p "$INSTALL_DIR" "$BIN_DIR"
run cp -a "$SCRIPT_DIR/bin" "$SCRIPT_DIR/linux" "$SCRIPT_DIR/modules" "$SCRIPT_DIR/docs" "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/"
run chmod +x "$INSTALL_DIR/bin/kat" "$INSTALL_DIR/linux/zabbix/update_agent2.sh" "$INSTALL_DIR/modules/zabbix-agent2/status.sh"
run ln -sfn "$INSTALL_DIR/bin/kat" "$BIN_DIR/kat"
run ln -sfn "$INSTALL_DIR/linux/zabbix/update_agent2.sh" "$BIN_DIR/kat-zabbix-agent2-update"

echo "Installed to: $INSTALL_DIR"
echo "Commands:"
echo "  kat --help"
echo "  kat menu"
echo "  kat status zabbix-agent2"
echo "  kat update zabbix-agent2 --major 6.4 --dry-run"
