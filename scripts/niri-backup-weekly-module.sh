#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    --backup)
        exec "$HOME/scripts/Backup/niri-backup.sh" --force
        ;;
    *)
        printf 'Verwendung: %s --backup\n' "$0" >&2
        exit 2
        ;;
esac
