#!/usr/bin/env bash
set -u

SOURCE="/tmp/tauon_radio_cover.jpg"
TARGET="/tmp/tauon_radio_cover_blur_niri.png"
CACHE_DIR="$HOME/.cache/conky/niri"
STATE="$CACHE_DIR/tauon-cover.state"

mkdir -p "$CACHE_DIR"

[[ -s "$SOURCE" ]] || exit 0

current_state="$(stat -c '%Y:%s' "$SOURCE" 2>/dev/null)" || exit 0
previous_state="$(cat "$STATE" 2>/dev/null || true)"

if [[ "$current_state" == "$previous_state" && -s "$TARGET" ]]; then
    exit 0
fi

tmp="${TARGET}.tmp.$$.png"
trap 'rm -f "$tmp"' EXIT

magick "$SOURCE" \
    -auto-orient \
    -resize '275x188^' \
    -gravity center \
    -extent 275x188 \
    -blur 0x16 \
    -modulate 82,118,100 \
    "$tmp" || exit 1

mv -f "$tmp" "$TARGET"
printf '%s\n' "$current_state" > "$STATE"

trap - EXIT
