#!/usr/bin/env bash

set -uo pipefail

PLAYER="spotify_player"
COVER="/tmp/spotify_cover_niri.jpg"
BLUR="/tmp/spotify_cover_blur_niri.png"
STATE="$HOME/.cache/conky/niri/spotify-art-url.txt"
LOG="/tmp/spotify_cover_niri.log"
LOCK="/tmp/spotify_cover_niri.lock"

mkdir -p "$(dirname "$STATE")"
touch "$LOG"

log() {
    printf '%s  %s\n' "$(date '+%F %T')" "$*" >> "$LOG"
}

exec 9>"$LOCK"
flock -n 9 || exit 0

status="$(playerctl -p "$PLAYER" status 2>/dev/null || true)"

if [[ "$status" != "Playing" && "$status" != "Paused" ]]; then
    log "Spotify nicht aktiv: ${status:-unbekannt}"
    exit 0
fi

art_url="$(
    playerctl -p "$PLAYER" metadata mpris:artUrl \
        2>/dev/null || true
)"

if [[ -z "$art_url" ]]; then
    log "Keine Cover-URL erhalten."
    exit 1
fi

scheme="${art_url%%:*}"

if [[ "$scheme" != "http" && "$scheme" != "https" ]]; then
    log "Nicht unterstütztes URL-Schema: $scheme"
    exit 1
fi

old_url="$(cat "$STATE" 2>/dev/null || true)"

if [[ "$art_url" == "$old_url" &&
      -s "$COVER" &&
      -s "$BLUR" ]]; then
    exit 0
fi

tmpdir="$(mktemp -d /tmp/spotify-niri.XXXXXX)" || exit 1
raw="$tmpdir/raw"
cover_tmp="$tmpdir/cover.jpg"
blur_tmp="$tmpdir/blur.png"

cleanup() {
    rm -rf "$tmpdir"
}

trap cleanup EXIT

if ! curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --connect-timeout 5 \
    --max-time 15 \
    --output "$raw" \
    "$art_url" >> "$LOG" 2>&1
then
    log "Cover-Download fehlgeschlagen: $art_url"
    exit 1
fi

if ! magick identify "$raw" >> "$LOG" 2>&1; then
    log "Heruntergeladene Datei ist kein gültiges Bild."
    exit 1
fi

if ! magick "$raw" \
    -auto-orient \
    -resize '300x300^' \
    -gravity center \
    -extent 300x300 \
    -strip \
    -quality 92 \
    "$cover_tmp" >> "$LOG" 2>&1
then
    log "Cover-Konvertierung fehlgeschlagen."
    exit 1
fi

if ! magick "$raw" \
    -auto-orient \
    -resize '275x122^' \
    -gravity center \
    -extent 275x122 \
    -blur 0x16 \
    -modulate 82,118,100 \
    "$blur_tmp" >> "$LOG" 2>&1
then
    log "Blur-Konvertierung fehlgeschlagen."
    exit 1
fi

mv -f "$cover_tmp" "$COVER"
mv -f "$blur_tmp" "$BLUR"
printf '%s\n' "$art_url" > "$STATE"

log "Spotify-Cover erfolgreich aktualisiert."
