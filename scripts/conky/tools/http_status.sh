#!/usr/bin/env bash
# Nur ein erfolgreich übertragener HTTP-2xx-Status gilt als OK.
if code=$(curl --silent --show-error --location --max-time 2 \
    --output /dev/null --write-out '%{http_code}' "$@" 2>/dev/null) &&
    [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
    echo OK
else
    echo DOWN
fi
