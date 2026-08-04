#!/usr/bin/env bash

ORIG="$HOME/scripts/Conky/unraid/home_server_compact_conky.sh"
DNS_CACHE="$HOME/.cache/conky/dns/node_status.txt"
DNS_UPDATE="$HOME/scripts/Conky/dns/update_dns_node_cache.sh"

[[ -f "$DNS_CACHE" ]] || "$DNS_UPDATE" >/dev/null 2>&1
source "$DNS_CACHE" 2>/dev/null

MAIN="${MAIN:-${SERVER:-FAIL}}"
BACKUP="${BACKUP:-FAIL}"
CLOUD="${CLOUD:-FAIL}"
HA="${HA:-FAIL}"
SYNC="${SYNC:-FAIL}"
LATENCY="${LATENCY:--}"

short_state() {
    case "$1" in
        ONLINE|OK)
            echo "OK"
            ;;
        *)
            echo "FAIL"
            ;;
    esac
}

color_state() {
    case "$1" in
        ONLINE|OK)
            echo '${color2}'
            ;;
        *)
            echo '${color3}'
            ;;
    esac
}

MAIN_S="$(short_state "$MAIN")"
BACKUP_S="$(short_state "$BACKUP")"
CLOUD_S="$(short_state "$CLOUD")"
HA_S="$(short_state "$HA")"
SYNC_S="$(short_state "$SYNC")"

MAIN_C="$(color_state "$MAIN")"
BACKUP_C="$(color_state "$BACKUP")"
CLOUD_C="$(color_state "$CLOUD")"
HA_C="$(color_state "$HA")"
SYNC_C="$(color_state "$SYNC")"

DNS_BLOCK="$(
cat <<EOF_BLOCK
\${color3}DNS\${alignr}\${color6}-----
\${color1}Main\${goto 70}${MAIN_C}${MAIN_S}\${goto 145}\${color1}Backup\${goto 225}${BACKUP_C}${BACKUP_S}
\${color1}Cloud\${goto 70}${CLOUD_C}${CLOUD_S}\${goto 145}\${color1}HA\${goto 225}${HA_C}${HA_S}
\${color1}Sync\${goto 70}${SYNC_C}${SYNC_S}\${goto 145}\${color1}Resp\${goto 225}\${color2}${LATENCY}
EOF_BLOCK
)"

"$ORIG" | awk -v block="$DNS_BLOCK" '
    BEGIN { found=0 }
    {
        if ($0 ~ /DNS/) {
            print block
            found=1
            exit
        }
        print
    }
    END {
        if (found == 0) {
            print block
        }
    }
'
