#!/usr/bin/env bash

PIDFILE="$HOME/scripts/Conky/niri/runtime/pids"

if [[ -f "$PIDFILE" ]]; then
    while read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue

        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done < "$PIDFILE"

    rm -f "$PIDFILE"
fi
