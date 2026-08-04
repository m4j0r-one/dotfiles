#!/usr/bin/env bash

"$HOME/scripts/Conky/unraid/home_server_compact_conky_dnsbackup.sh" |
sed \
  -e 's/${goto 72}/ /g' \
  -e 's/${goto 150}/${alignr}/g' \
  -e 's/${goto 220}/ /g' \
  -e 's/${goto 70}/ /g' \
  -e 's/${goto 145}/${alignr}/g' \
  -e 's/${goto 225}/ /g'
