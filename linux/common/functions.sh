#!/usr/bin/env bash

set -Eeuo pipefail

KAT_LOG_DIR="${KAT_LOG_DIR:-/var/log/karelia-admin-toolkit}"
KAT_BACKUP_DIR="${KAT_BACKUP_DIR:-/var/backups/karelia-admin-toolkit}"
KAT_DRY_RUN="${KAT_DRY_RUN:-0}"

kat_ts() {
    date '+%Y-%m-%d %H:%M:%S'
}

kat_info() {
    echo "[$(kat_ts)] [INFO] $*"
}

kat_warn() {
    echo "[$(kat_ts)] [WARN] $*" >&2
}

kat_error() {
    echo "[$(kat_ts)] [ERROR] $*" >&2
}

kat_die() {
    kat_error "$*"
    exit 1
}

kat_need_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        kat_die "Run as root"
    fi
}

kat_run() {
    if [[ "$KAT_DRY_RUN" == "1" ]]; then
        kat_info "DRY-RUN: $*"
    else
        kat_info "RUN: $*"
        "$@"
    fi
}

kat_init_dirs() {
    kat_run mkdir -p "$KAT_LOG_DIR" "$KAT_BACKUP_DIR"
}

kat_backup_path() {
    local path="$1"
    local stamp
    stamp="$(date '+%Y%m%d-%H%M%S')"

    if [[ ! -e "$path" ]]; then
        return 0
    fi

    kat_run mkdir -p "$KAT_BACKUP_DIR/$stamp"
    kat_run cp -a "$path" "$KAT_BACKUP_DIR/$stamp/"
}

kat_detect_os() {
    if [[ ! -r /etc/os-release ]]; then
        kat_die "/etc/os-release not found"
    fi

    . /etc/os-release
    KAT_OS_ID="${ID:-unknown}"
    KAT_OS_VERSION_ID="${VERSION_ID:-unknown}"
    KAT_OS_CODENAME="${VERSION_CODENAME:-}"
    KAT_ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
}

kat_need_command() {
    command -v "$1" >/dev/null 2>&1 || kat_die "Required command not found: $1"
}
