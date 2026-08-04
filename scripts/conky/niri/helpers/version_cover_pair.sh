#!/usr/bin/env bash

set -u

kind="${1:-}"

case "$kind" in
    spotify)
        cover_src="/tmp/spotify_cover_niri.jpg"
        blur_src="/tmp/spotify_cover_blur_niri.png"
        ;;
    tauon)
        cover_src="/tmp/tauon_radio_cover.jpg"
        blur_src="/tmp/tauon_radio_cover_blur_niri.png"
        ;;
    *)
        exit 2
        ;;
esac

[[ -s "$cover_src" && -s "$blur_src" ]] || exit 0

cache_dir="$HOME/.cache/conky/niri/render-cache/$kind"
state_file="$cache_dir/current.sha256"

cover_path_file="/tmp/conky_niri_${kind}_cover.path"
blur_path_file="/tmp/conky_niri_${kind}_blur.path"

mkdir -p "$cache_dir"

signature="$(
    {
        sha256sum "$cover_src"
        sha256sum "$blur_src"
    } |
    sha256sum |
    awk '{print $1}'
)"

cover_dst="$cache_dir/cover-$signature.jpg"
blur_dst="$cache_dir/blur-$signature.png"

if [[ ! -s "$cover_dst" ]]; then
    cp -f -- "$cover_src" "$cover_dst"
fi

if [[ ! -s "$blur_dst" ]]; then
    cp -f -- "$blur_src" "$blur_dst"
fi

printf '%s\n' "$cover_dst" > "${cover_path_file}.tmp.$$"
mv -f "${cover_path_file}.tmp.$$" "$cover_path_file"

printf '%s\n' "$blur_dst" > "${blur_path_file}.tmp.$$"
mv -f "${blur_path_file}.tmp.$$" "$blur_path_file"

printf '%s\n' "$signature" > "${state_file}.tmp.$$"
mv -f "${state_file}.tmp.$$" "$state_file"

# Alte, nicht mehr verwendete Render-Dateien später entfernen.
find "$cache_dir" -maxdepth 1 -type f \
    \( -name 'cover-*' -o -name 'blur-*' \) \
    ! -path "$cover_dst" \
    ! -path "$blur_dst" \
    -mmin +10 \
    -delete 2>/dev/null || true
