#!/usr/bin/env bash

exec 9>/tmp/tauon_radio_update.lock
flock -n 9 || exit 0

PLAYER="tauon"

FALLBACK="/tmp/tauon_radio_fallback.jpg"
COVER="/tmp/tauon_radio_cover.jpg"
BLUR="/tmp/tauon_radio_cover_blur.jpg"
STATUS_FILE="/tmp/tauon_radio_status.conky"
DEBUG="/tmp/tauon_radio_art_debug.txt"

META_FILE="/tmp/tauon_radio_last_meta.key"
SRC_FILE="/tmp/tauon_radio_cover_source.path"
HASH_FILE="/tmp/tauon_radio_cover_source.hash"
SCAN_TIME_FILE="/tmp/tauon_radio_last_scan.time"

shorten() {
  local s="$1"
  local max="$2"
  if (( ${#s} > max )); then
    echo "${s:0:max-1}…"
  else
    echo "$s"
  fi
}

make_fallback() {
  [[ -f "$FALLBACK" ]] && return

  if command -v magick >/dev/null 2>&1; then
    magick -size 600x360 gradient:'#07121c-#1b0630' \
      -gravity center \
      -fill '#00E5FF' -font DejaVu-Sans-Bold -pointsize 46 -annotate 0 'RADIO' \
      -fill '#FF2FAE' -pointsize 26 -annotate +0+54 'TAUON' \
      "$FALLBACK" 2>/dev/null
  else
    convert -size 600x360 gradient:'#07121c-#1b0630' \
      -gravity center \
      -fill '#00E5FF' -font DejaVu-Sans-Bold -pointsize 46 -annotate 0 'RADIO' \
      -fill '#FF2FAE' -pointsize 26 -annotate +0+54 'TAUON' \
      "$FALLBACK" 2>/dev/null
  fi
}

write_status_off() {
  cat > "$STATUS_FILE" <<'EOS'
${goto 112}${color1}${font conthrax:size=6}TAUON${goto 202}${color3}OFF${font}
${goto 112}${color2}${font conthrax:size=7:bold}Radio inactive${font}
${goto 112}${color1}${font conthrax:size=6}No stream active${font}
${voffset 30}${goto 14}${color6}${hr 1}
${goto 14}${color6}${font conthrax:size=7:bold}PLAY${goto 62}STOP${goto 108}PREV${goto 158}NEXT${alignr}${color4}RADIO${font}
EOS
}

make_images_if_changed() {
  local src="$1"

  [[ -f "$src" ]] || src="$FALLBACK"

  local hash
  hash="$(stat -c '%n|%Y|%s' "$src" 2>/dev/null || echo "none")"

  if [[ -f "$HASH_FILE" ]] && [[ "$(cat "$HASH_FILE")" == "$hash" ]] && [[ -f "$COVER" ]] && [[ -f "$BLUR" ]]; then
    return
  fi

  echo "$hash" > "$HASH_FILE"

  if command -v magick >/dev/null 2>&1; then
    magick "$src" -auto-orient -resize 300x300^ -gravity center -extent 300x300 "$COVER" 2>/dev/null || cp "$FALLBACK" "$COVER"

    magick "$COVER" -resize 600x360^ -gravity center -extent 600x360 \
      -blur 0x18 -modulate 70,120,100 \
      -fill '#05091480' -colorize 35 \
      "$BLUR" 2>/dev/null || cp "$FALLBACK" "$BLUR"
  else
    convert "$src" -auto-orient -resize 300x300^ -gravity center -extent 300x300 "$COVER" 2>/dev/null || cp "$FALLBACK" "$COVER"

    convert "$COVER" -resize 600x360^ -gravity center -extent 600x360 \
      -blur 0x18 -modulate 70,120,100 \
      -fill '#05091480' -colorize 35 \
      "$BLUR" 2>/dev/null || cp "$FALLBACK" "$BLUR"
  fi
}

find_tauon_cover() {
  local now last_scan
  now="$(date +%s)"
  last_scan="$(cat "$SCAN_TIME_FILE" 2>/dev/null || echo 0)"

  # Höchstens alle 60 Sekunden teuer suchen, außer Trackwechsel triggert es.
  echo "$now" > "$SCAN_TIME_FILE"

  # Erst vorhandenen Debug-Pfad wiederverwenden
  if [[ ! -f "$SRC_FILE" && -f "$DEBUG" ]]; then
    grep -oP 'Using newest Tauon cache image: \K.*' "$DEBUG" 2>/dev/null | head -n1 > "$SRC_FILE"
  fi

  local latest=""
  latest="$(
    for root in \
      "$HOME/.cache" \
      "$HOME/.local/share" \
      "$HOME/.config" \
      "$HOME/.var/app/com.github.taiko2k.tauonmb/cache" \
      "$HOME/.var/app/com.github.taiko2k.tauonmb/data" \
      "$HOME/.var/app/com.github.taiko2k.tauonmb/config"
    do
      [[ -d "$root" ]] || continue
      find "$root" \
        -ipath '*tauon*' \
        -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        -size +8k \
        -printf '%T@ %p\n' 2>/dev/null
    done | sort -nr | head -n 1 | cut -d' ' -f2-
  )"

  if [[ -n "$latest" && -f "$latest" ]]; then
    echo "$latest" > "$SRC_FILE"
    echo "Using newest Tauon cache image: $latest" > "$DEBUG"
  fi
}

make_fallback

status="$(playerctl -p "$PLAYER" status 2>/dev/null || true)"

if [[ -z "$status" ]]; then
  write_status_off
  make_images_if_changed "$FALLBACK"
  echo "Tauon not running / no MPRIS status" > "$DEBUG"
  exit 0
fi

metadata="$(playerctl -p "$PLAYER" metadata 2>/dev/null || true)"

title="$(printf '%s\n' "$metadata" | awk '$2=="xesam:title"{ $1=""; $2=""; sub(/^[ \t]+/,""); print; exit }')"
artist="$(printf '%s\n' "$metadata" | awk '$2=="xesam:artist"{ $1=""; $2=""; sub(/^[ \t]+/,""); print; exit }')"
album="$(printf '%s\n' "$metadata" | awk '$2=="xesam:album"{ $1=""; $2=""; sub(/^[ \t]+/,""); print; exit }')"

[[ -z "$title" ]] && title="Radio Stream"
[[ -z "$artist" ]] && artist="Tauon"
[[ -z "$album" ]] && album="$status"

meta_key="$title|$artist|$album|$status"
old_meta="$(cat "$META_FILE" 2>/dev/null || true)"

if [[ "$meta_key" != "$old_meta" ]]; then
  echo "$meta_key" > "$META_FILE"
  find_tauon_cover
else
  now="$(date +%s)"
  last_scan="$(cat "$SCAN_TIME_FILE" 2>/dev/null || echo 0)"
  if (( now - last_scan > 60 )); then
    find_tauon_cover
  fi
fi

src="$(cat "$SRC_FILE" 2>/dev/null || true)"
[[ -f "$src" ]] || src="$FALLBACK"

make_images_if_changed "$src"

title="$(shorten "$title" 19)"
artist="$(shorten "$artist" 18)"
album="$(shorten "$album" 18)"

case "$status" in
  Playing)
    state_color='${color2}'
    state='PLAYING'
    ;;
  Paused)
    state_color='${color3}'
    state='PAUSED'
    ;;
  Stopped)
    state_color='${color6}'
    state='STOPPED'
    ;;
  *)
    state_color='${color1}'
    state="$status"
    ;;
esac

cat > "$STATUS_FILE" <<EOF2
\${goto 112}\${color1}\${font conthrax:size=6}TAUON\${goto 190}${state_color}\${font conthrax:size=6:bold}${state}\${font}
\${goto 112}\${voffset 5}\${color2}\${font conthrax:size=7:bold}${title}\${font}
\${goto 112}\${color1}\${font conthrax:size=6}${artist}\${font}
\${goto 112}\${color5}\${font conthrax:size=6}${album}\${font}
\${voffset 34}\${goto 14}\${color6}\${hr 1}
\${goto 14}${state_color}\${font conthrax:size=7:bold}PLAY\${goto 62}\${color6}STOP\${goto 108}PREV\${goto 158}NEXT\${alignr}\${color4}RADIO\${font}
EOF2
