#!/usr/bin/env bash

STATUS_FILE="/tmp/spotify_status_card.conky"

[[ -r "$STATUS_FILE" ]] || exit 0

# Textblock rechts neben dem 62x62-Cover positionieren.
# PLAYING/PAUSED wird rechtsbündig dargestellt.
sed \
  -e 's/${goto 82}/${offset 82}/g' \
  -e 's/${goto 178}/${alignr 10}/g' \
  "$STATUS_FILE"
