#!/usr/bin/env bash
# Exitcode getrennt von der Anzahl ausgegebener Pakete auswerten.
if updates=$(checkupdates 2>/dev/null); then
    if [[ -n "$updates" ]]; then
        printf '%s\n' "$updates" | awk 'NF { count++ } END { print count+0 }'
    else
        echo ERR
    fi
else
    rc=$?
    if [[ "$rc" -eq 2 && -z "$updates" ]]; then
        echo OK
    else
        echo ERR
    fi
fi
