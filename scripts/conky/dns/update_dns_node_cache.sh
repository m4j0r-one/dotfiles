#!/usr/bin/env bash

set -u

MAIN_DNS="192.168.178.61"
BACKUP_DNS="192.168.178.62"
EXPECTED_LOCAL_IP="192.168.178.60"

DOMAIN_CLOUD="cloud.m4j0r.one"
DOMAIN_HA="ha.m4j0r.one"
UPSTREAM_TEST="cloudflare.com"

BASE_DIR="$HOME/.cache/conky/dns"
OUT_FILE="$BASE_DIR/node_status.txt"
LOCK_FILE="$BASE_DIR/node_status.lock"
COUNT_FILE="$BASE_DIR/.dns_fail_counts"

FAIL_THRESHOLD=2
DIG_TIMEOUT=2

mkdir -p "$BASE_DIR"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

NOW="$(date '+%H:%M:%S')"

get_count() {
    local key="$1"
    [[ -f "$COUNT_FILE" ]] || { echo 0; return; }

    local value
    value="$(awk -F= -v key="$key" '$1 == key {print $2; exit}' "$COUNT_FILE" 2>/dev/null)"
    value="${value//[^0-9]/}"
    echo "${value:-0}"
}

apply_tolerance() {
    local count_key="$1"
    local raw_state="$2"

    local count

    count="$(get_count "$count_key")"

    case "$raw_state" in
        OK|ONLINE)
            T_STATE="$raw_state"
            T_COUNT=0
            ;;
        *)
            count=$((count + 1))
            if (( count < FAIL_THRESHOLD )); then
                T_STATE="UNKNOWN"
            else
                T_STATE="$raw_state"
            fi
            T_COUNT="$count"
            ;;
    esac
}

check_dns_node() {
    local dns_ip="$1"
    local prefix="$2"

    local raw_server="OFFLINE"
    local raw_port="FAIL"
    local raw_upstream="FAIL"
    local latency="n/a"

    if ping -c1 -W1 "$dns_ip" >/dev/null 2>&1; then
        raw_server="ONLINE"
    fi

    local dig_out
    dig_out="$(dig +time="$DIG_TIMEOUT" +tries=1 @"$dns_ip" "$UPSTREAM_TEST" A 2>/dev/null || true)"

    local upstream_ip
    upstream_ip="$(
        dig +time="$DIG_TIMEOUT" +tries=1 +short @"$dns_ip" "$UPSTREAM_TEST" A 2>/dev/null \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
        | head -n1 || true
    )"

    if printf "%s\n" "$dig_out" | grep -q "status: NOERROR"; then
        raw_port="OK"
    fi

    if [[ -n "$upstream_ip" ]]; then
        raw_upstream="OK"
    fi

    latency="$(printf "%s\n" "$dig_out" | awk -F': ' '/Query time:/ {gsub(/ msec/,"",$2); print $2"ms"; exit}')"
    [[ -z "$latency" ]] && latency="n/a"

    eval "${prefix}_RAW_SERVER=\"\$raw_server\""
    eval "${prefix}_RAW_PORT=\"\$raw_port\""
    eval "${prefix}_RAW_UPSTREAM=\"\$raw_upstream\""
    eval "${prefix}_LATENCY=\"\$latency\""
}

resolve_one() {
    local dns_ip="$1"
    local domain="$2"

    dig +time="$DIG_TIMEOUT" +tries=1 +short @"$dns_ip" "$domain" A 2>/dev/null \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
        | head -n1 || true
}

check_dns_node "$MAIN_DNS" "MAIN"
check_dns_node "$BACKUP_DNS" "BACKUP"

CLOUD_MAIN_IP="$(resolve_one "$MAIN_DNS" "$DOMAIN_CLOUD")"
CLOUD_BACKUP_IP="$(resolve_one "$BACKUP_DNS" "$DOMAIN_CLOUD")"
HA_MAIN_IP="$(resolve_one "$MAIN_DNS" "$DOMAIN_HA")"
HA_BACKUP_IP="$(resolve_one "$BACKUP_DNS" "$DOMAIN_HA")"

RAW_CLOUD="FAIL"
RAW_HA="FAIL"
RAW_SPLIT="FAIL"
RAW_SYNC="UNKNOWN"
RAW_NPM="FAIL"

if [[ "$CLOUD_MAIN_IP" == "$EXPECTED_LOCAL_IP" && "$CLOUD_BACKUP_IP" == "$EXPECTED_LOCAL_IP" ]]; then
    RAW_CLOUD="OK"
fi

if [[ "$HA_MAIN_IP" == "$EXPECTED_LOCAL_IP" && "$HA_BACKUP_IP" == "$EXPECTED_LOCAL_IP" ]]; then
    RAW_HA="OK"
fi

if [[ "$RAW_CLOUD" == "OK" && "$RAW_HA" == "OK" ]]; then
    RAW_SPLIT="OK"
fi

# Proxy-Antworten über die erwartete lokale IP prüfen, inklusive TLS/HTTP-Status.
HTTP_CHECK="$HOME/scripts/Conky/tools/http_status.sh"
if [[ "$(bash "$HTTP_CHECK" --resolve "$DOMAIN_CLOUD:443:$EXPECTED_LOCAL_IP" "https://$DOMAIN_CLOUD")" == "OK" &&
      "$(bash "$HTTP_CHECK" --resolve "$DOMAIN_HA:443:$EXPECTED_LOCAL_IP" "https://$DOMAIN_HA")" == "OK" ]]; then
    RAW_NPM="OK"
fi

# Echten Sync-Nachweis lesend auf Unraid prüfen; keine Synchronisation auslösen.
check_sync() {
    local result
    if result=$(timeout 12 ssh -i "$HOME/.ssh/unraid_conky" \
        -o BatchMode=yes -o ConnectTimeout=3 \
        -o StrictHostKeyChecking=yes -o UpdateHostKeys=no \
        root@192.168.178.169 'bash -s' 2>/dev/null <<'SYNC_REMOTE'
set -euo pipefail
container=adguardhome-sync
info=$(docker inspect --format '{{.State.Running}} {{.State.Pid}} {{.State.StartedAt}}' "$container")
read -r running pid started <<< "$info"
if [[ "$running" != true ]]; then
    echo FAIL
    exit 0
fi
[[ "$pid" =~ ^[1-9][0-9]*$ ]] || exit 1
started_epoch=$(date -d "$started" +%s)
now_epoch=$(date +%s)
startup_age=$((now_epoch - started_epoch))

# Zugriff im Container-Netzwerk: keine Freigabe zusätzlicher Ports erforderlich.
code=$(nsenter -t "$pid" -n curl --noproxy '*' --silent --show-error \
    --connect-timeout 2 --max-time 3 --output /dev/null \
    --write-out '%{http_code}' http://127.0.0.1:8080/healthz)
case "$code" in
    200) ;;
    503)
        if (( startup_age >= 0 && startup_age < 1200 )); then
            echo UNKNOWN
        else
            echo FAIL
        fi
        exit 0
        ;;
    *) exit 1 ;;
esac

logs=$(docker logs --since 25m "$container" 2>&1)
# Das bestehende Console-Log hat TSV-Felder: Zeit, Level, Logger, Aufrufstelle, Meldung, JSON.
# Nur erfolgreiche Abschlüsse für die konfigurierte Richtung .62 -> .61 zählen.
last=$(printf '%s\n' "$logs" | awk -F '\t' '
    $2 == "INFO" && $3 == "sync" && $5 == "Sync done" &&
    $6 ~ /"from"[[:space:]]*:[[:space:]]*"192\.168\.178\.62"/ &&
    $6 ~ /"to"[[:space:]]*:[[:space:]]*"192\.168\.178\.61"/ { stamp=$1 }
    END { print stamp }
')
if [[ -z "$last" ]]; then
    if (( startup_age >= 0 && startup_age < 1200 )); then
        echo UNKNOWN
    else
        echo FAIL
    fi
    exit 0
fi
last_epoch=$(date -d "$last" +%s)
age=$((now_epoch - last_epoch))
if (( age >= 0 && age <= 1500 && last_epoch >= started_epoch )); then
    echo OK
elif (( startup_age >= 0 && startup_age < 1200 )); then
    echo UNKNOWN
else
    echo FAIL
fi
SYNC_REMOTE
    ); then
        case "$result" in
            OK|FAIL) printf '%s\n' "$result" ;;
            *) echo UNKNOWN ;;
        esac
    else
        echo UNKNOWN
    fi
}
RAW_SYNC="$(check_sync)"

apply_tolerance "MAIN_FAIL" "$MAIN_RAW_SERVER"
MAIN_STATE="$T_STATE"
MAIN_COUNT="$T_COUNT"

apply_tolerance "BACKUP_FAIL" "$BACKUP_RAW_SERVER"
BACKUP_STATE="$T_STATE"
BACKUP_COUNT="$T_COUNT"

apply_tolerance "PORT53_FAIL" "$MAIN_RAW_PORT"
PORT53_STATE="$T_STATE"
PORT53_COUNT="$T_COUNT"

apply_tolerance "BACKUP_PORT53_FAIL" "$BACKUP_RAW_PORT"
BACKUP_PORT53_STATE="$T_STATE"
BACKUP_PORT53_COUNT="$T_COUNT"

apply_tolerance "UPSTREAM_FAIL" "$MAIN_RAW_UPSTREAM"
UPSTREAM_STATE="$T_STATE"
UPSTREAM_COUNT="$T_COUNT"

apply_tolerance "CLOUD_FAIL" "$RAW_CLOUD"
CLOUD_STATE="$T_STATE"
CLOUD_COUNT="$T_COUNT"

apply_tolerance "HA_FAIL" "$RAW_HA"
HA_STATE="$T_STATE"
HA_COUNT="$T_COUNT"

apply_tolerance "SPLIT_FAIL" "$RAW_SPLIT"
SPLIT_STATE="$T_STATE"
SPLIT_COUNT="$T_COUNT"

apply_tolerance "SYNC_FAIL" "$RAW_SYNC"
SYNC_STATE="$RAW_SYNC" # Keine Verzögerung bei abgelaufenem Erfolgsnachweis.
SYNC_COUNT="$T_COUNT"

apply_tolerance "NPM_FAIL" "$RAW_NPM"
NPM_STATE="$T_STATE"
NPM_COUNT="$T_COUNT"

LATENCY="$BACKUP_LATENCY"
[[ "$LATENCY" == "n/a" ]] && LATENCY="$MAIN_LATENCY"

OVERALL="OK"
for value in "$MAIN_STATE" "$BACKUP_STATE" "$PORT53_STATE" "$BACKUP_PORT53_STATE" "$UPSTREAM_STATE" "$CLOUD_STATE" "$HA_STATE" "$SPLIT_STATE" "$SYNC_STATE" "$NPM_STATE"; do
    case "$value" in
        ONLINE|OK) ;;
        *) OVERALL="WARN" ;;
    esac
done

{
    echo "UPDATE=$NOW"

    # Legacy keys für bestehende Scripts
    echo "SERVER=$MAIN_STATE"
    echo "PORT53=$PORT53_STATE"
    echo "UPSTREAM=$UPSTREAM_STATE"
    echo "CLOUD=$CLOUD_STATE"
    echo "HA=$HA_STATE"
    echo "NPM=$NPM_STATE"
    echo "LATENCY=$LATENCY"
    echo "OVERALL=$OVERALL"

    # Neue Keys
    echo "MAIN=$MAIN_STATE"
    echo "BACKUP=$BACKUP_STATE"
    echo "BACKUP_PORT53=$BACKUP_PORT53_STATE"
    echo "SPLIT=$SPLIT_STATE"
    echo "SYNC=$SYNC_STATE"
    echo "MAIN_LATENCY=$MAIN_LATENCY"
    echo "BACKUP_LATENCY=$BACKUP_LATENCY"
    echo "CLOUD_MAIN_IP=$CLOUD_MAIN_IP"
    echo "CLOUD_BACKUP_IP=$CLOUD_BACKUP_IP"
    echo "HA_MAIN_IP=$HA_MAIN_IP"
    echo "HA_BACKUP_IP=$HA_BACKUP_IP"
} > "$OUT_FILE"

{
    echo "MAIN_FAIL=$MAIN_COUNT"
    echo "BACKUP_FAIL=$BACKUP_COUNT"
    echo "PORT53_FAIL=$PORT53_COUNT"
    echo "BACKUP_PORT53_FAIL=$BACKUP_PORT53_COUNT"
    echo "UPSTREAM_FAIL=$UPSTREAM_COUNT"
    echo "CLOUD_FAIL=$CLOUD_COUNT"
    echo "HA_FAIL=$HA_COUNT"
    echo "SPLIT_FAIL=$SPLIT_COUNT"
    echo "SYNC_FAIL=$SYNC_COUNT"
    echo "NPM_FAIL=$NPM_COUNT"
} > "$COUNT_FILE"
