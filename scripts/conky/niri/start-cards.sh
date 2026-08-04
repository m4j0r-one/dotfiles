#!/usr/bin/env bash

set -u

BASE="$HOME/scripts/Conky/niri"
CONKY_BIN="${CONKY_BIN:-$HOME/.local/opt/conky-niri/bin/conky}"

# Prefer the custom Conky build when installed, otherwise use the
# regular system executable.
if [[ ! -x "$CONKY_BIN" ]]; then
    CONKY_BIN="$(command -v conky || true)"
fi

if [[ -z "$CONKY_BIN" || ! -x "$CONKY_BIN" ]]; then
    echo "Conky executable not found." >&2
    exit 1
fi
CARD_DIR="$BASE/cards"
LOG_DIR="$BASE/logs"
PIDFILE="$BASE/runtime/pids"

mkdir -p "$LOG_DIR" "$BASE/runtime"

"$BASE/stop-cards.sh"
sleep 1

ORIGINAL_OUTPUT="$(
    niri msg --json focused-output 2>/dev/null |
    jq -r '.name // empty'
)"

# Conky-Layer-Surfaces auf dem linken Monitor DP-2 erzeugen.
if [[ "$ORIGINAL_OUTPUT" != "DP-2" ]]; then
    niri msg action focus-monitor-left
    sleep 1
fi

: > "$PIDFILE"

for cfg in "$CARD_DIR"/*.cfg; do
    name="$(basename "$cfg" .cfg)"

    env -u DISPLAY "$CONKY_BIN" -c "$cfg" \
        >"$LOG_DIR/$name.log" 2>&1 &

    echo "$!" >> "$PIDFILE"
    sleep 0.18
done

# Ursprünglichen Fokus wiederherstellen.
if [[ "$ORIGINAL_OUTPUT" == "DP-1" ]]; then
    niri msg action focus-monitor-right
fi
