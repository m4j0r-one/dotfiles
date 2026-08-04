#!/usr/bin/env bash

QML="$HOME/.config/quickshell/m4j0r-visualizer/shell.qml"
LOG="$HOME/.cache/m4j0r-visualizer.log"

# Nicht doppelt starten.
if pgrep -u "$UID" -f \
  '/usr/bin/qs -p .*/m4j0r-visualizer/shell.qml' \
  >/dev/null; then
    exit 0
fi

[[ -f "$QML" ]] || exit 1

mkdir -p "$HOME/.cache"
sleep 2

exec /usr/bin/qs -p "$QML" >"$LOG" 2>&1
