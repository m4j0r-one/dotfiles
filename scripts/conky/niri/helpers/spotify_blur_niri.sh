#!/usr/bin/env bash

set -u

SOURCE="/tmp/spotify_cover.jpg"
TARGET="/tmp/spotify_cover_blur_niri.png"
CACHE_DIR="$HOME/.cache/conky/niri"
STATE="$CACHE_DIR/spotify-cover.state"

mkdir -p "$CACHE_DIR"

[[ -s "$SOURCE" ]] || exit 0

current_state="$(stat -c '%Y:%s' "$SOURCE" 2>/dev/null)" || exit 0
previous_state="$(cat "$STATE" 2>/dev/null || true)"

# ImageMagick nur ausführen, wenn sich das Cover verändert hat.
if [[ "$current_state" == "$previous_state" && -s "$TARGET" ]]; then
    exit 0
fi

temporary="${TARGET}.tmp.$$.png"
trap 'rm -f "$temporary"' EXIT

magick "$SOURCE" \
    -auto-orient \
    -resize '275x122^' \
    -gravity center \
    -extent 275x122 \
    -blur 0x16 \
    -modulate 82,118,100 \
    "$temporary" || exit 1

mv -f "$temporary" "$TARGET"
printf '%s\n' "$current_state" > "$STATE"

trap - EXIT
