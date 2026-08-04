#!/usr/bin/env bash

exec 9>/tmp/spotify_update.lock
flock -n 9 || exit 0

SPOTIFY_DIR="$HOME/scripts/Conky/spotify"

FALLBACK="$SPOTIFY_DIR/spotify_fallback_cached.jpg"
COVER="/tmp/spotify_cover.jpg"
BLUR="/tmp/spotify_cover_blur.jpg"
RAW="/tmp/spotify_cover_raw"
STATUS_FILE="/tmp/spotify_status_card.conky"

ART_KEY_FILE="/tmp/spotify_last_art.key"
COVER_HASH_FILE="/tmp/spotify_cover.hash"

shorten() {
  local s="$1"
  local max="$2"
  if (( ${#s} > max )); then
    echo "${s:0:max-1}…"
  else
    echo "$s"
  fi
}

safe_text() {
  printf '%s' "$1" | sed 's/\$/＄/g'
}

make_fallback() {
  if [[ -f "$FALLBACK" ]]; then
    return
  fi

  # Wenn dein altes Spotify-Cover noch existiert, als Fallback sichern.
  if [[ -f "$COVER" ]]; then
    cp "$COVER" "$FALLBACK"
    return
  fi

  if command -v magick >/dev/null 2>&1; then
    magick -size 600x360 gradient:'#07121c-#1b0630' \
      -gravity center \
      -fill '#FF2FAE' -font DejaVu-Sans-Bold -pointsize 42 -annotate 0 'SPOTIFY' \
      -fill '#00E5FF' -pointsize 22 -annotate +0+52 'm4j0r.one' \
      "$FALLBACK" 2>/dev/null
  else
    convert -size 600x360 gradient:'#07121c-#1b0630' \
      -gravity center \
      -fill '#FF2FAE' -font DejaVu-Sans-Bold -pointsize 42 -annotate 0 'SPOTIFY' \
      -fill '#00E5FF' -pointsize 22 -annotate +0+52 'm4j0r.one' \
      "$FALLBACK" 2>/dev/null
  fi
}

write_status_off() {
  local d t
  d="$(LC_TIME=de_DE.UTF-8 date '+%A, %d.%m.%Y' 2>/dev/null || date '+%A, %d.%m.%Y')"
  t="$(date '+%H:%M')"

  cat > "$STATUS_FILE" <<EOF2
\${goto 82}\${color2}\${font conthrax:size=7}${d}\${font}
\${goto 82}\${color2}\${font conthrax:size=7}${t}\${font}
\${goto 82}\${color1}\${font conthrax:size=7}Spotify inaktiv\${font}
EOF2
}

make_images_if_changed() {
  local src="$1"
  [[ -f "$src" ]] || src="$FALLBACK"

  local hash
  hash="$(stat -c '%n|%Y|%s' "$src" 2>/dev/null || echo none)"

  if [[ -f "$COVER_HASH_FILE" ]] && [[ "$(cat "$COVER_HASH_FILE")" == "$hash" ]] && [[ -f "$COVER" ]] && [[ -f "$BLUR" ]]; then
    return
  fi

  echo "$hash" > "$COVER_HASH_FILE"

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

get_player() {
  local players

  players="$(playerctl -l 2>/dev/null || true)"

  if grep -Fxq 'spotify_player' <<< "$players"; then
    printf '%s\n' 'spotify_player'
    return
  fi

  printf '%s\n' "$players" |
    grep -Ei '^(spotify|spotifyd)(\.|$)' |
    head -n1
}

format_time() {
  local sec="$1"
  [[ "$sec" =~ ^[0-9]+$ ]] || sec=0
  printf '%d:%02d' "$((sec / 60))" "$((sec % 60))"
}

make_fallback

PLAYER="$(get_player)"

if [[ -z "$PLAYER" ]]; then
  write_status_off
  make_images_if_changed "$FALLBACK"
  exit 0
fi

status="$(playerctl -p "$PLAYER" status 2>/dev/null || true)"

if [[ -z "$status" ]]; then
  write_status_off
  make_images_if_changed "$FALLBACK"
  exit 0
fi

metadata="$(playerctl -p "$PLAYER" metadata 2>/dev/null || true)"

title="$(printf '%s\n' "$metadata" | awk '$2=="xesam:title"{ $1=""; $2=""; sub(/^[ \t]+/,""); print; exit }')"
artist="$(printf '%s\n' "$metadata" | awk '$2=="xesam:artist"{ $1=""; $2=""; sub(/^[ \t]+/,""); print; exit }')"
album="$(printf '%s\n' "$metadata" | awk '$2=="xesam:album"{ $1=""; $2=""; sub(/^[ \t]+/,""); print; exit }')"
art="$(printf '%s\n' "$metadata" | awk '$2=="mpris:artUrl"{ $1=""; $2=""; sub(/^[ \t]+/,""); print; exit }')"
length_us="$(printf '%s\n' "$metadata" | awk '$2=="mpris:length"{ print $3; exit }')"

[[ -z "$title" ]] && title="Spotify"
[[ -z "$artist" ]] && artist="Unknown Artist"
[[ -z "$album" ]] && album="$status"

src="$FALLBACK"

if [[ -n "$art" ]]; then
  old_art="$(cat "$ART_KEY_FILE" 2>/dev/null || true)"

  if [[ "$art" != "$old_art" || ! -s "$RAW" ]]; then
    echo "$art" > "$ART_KEY_FILE"

    if [[ "$art" == file://* ]]; then
      path="${art#file://}"
      path="$(printf '%b' "${path//%/\\x}")"
      [[ -f "$path" ]] && cp "$path" "$RAW"
    elif [[ "$art" =~ ^https?:// ]]; then
      curl -fsSL --max-time 5 "$art" -o "$RAW" 2>/dev/null || true
    fi
  fi

  [[ -s "$RAW" ]] && src="$RAW"
fi

make_images_if_changed "$src"

position_raw="$(playerctl -p "$PLAYER" position 2>/dev/null | cut -d. -f1 || echo 0)"
length_sec=0
if [[ "$length_us" =~ ^[0-9]+$ ]] && (( length_us > 0 )); then
  length_sec="$((length_us / 1000000))"
fi

pos_txt="$(format_time "$position_raw")"
len_txt="$(format_time "$length_sec")"

title="$(safe_text "$(shorten "$title" 23)")"
artist="$(safe_text "$(shorten "$artist" 22)")"
album="$(safe_text "$(shorten "$album" 22)")"

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
\${goto 82}\${color1}\${font conthrax:size=6}SPOTIFY\${goto 178}${state_color}\${font conthrax:size=6:bold}${state}\${font}
\${goto 82}\${voffset 4}\${color2}\${font conthrax:size=7:bold}${title}\${font}
\${goto 82}\${color1}\${font conthrax:size=6}${artist}\${font}
\${goto 82}\${color5}\${font conthrax:size=6}${album}\${font}
\${goto 82}\${voffset 4}\${color4}\${font conthrax:size=6}${pos_txt} / ${len_txt}\${font}
EOF2
