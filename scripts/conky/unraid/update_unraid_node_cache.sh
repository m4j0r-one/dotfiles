#!/usr/bin/env bash

set -u

UNRAID_HOST="root@192.168.178.169"
SSH_KEY="$HOME/.ssh/unraid_conky"

BASE_DIR="$HOME/.cache/conky/unraid"
OUT_FILE="$BASE_DIR/node_status.txt"
LOCK_FILE="$BASE_DIR/node_status.lock"

mkdir -p "$BASE_DIR"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

REMOTE_SCRIPT='
set +e

now="$(date +%H:%M:%S)"

tower="ONLINE"

array="STOPPED"
mountpoint -q /mnt/user && array="STARTED"

storage="$(df -P /mnt/user 2>/dev/null | awk "NR==2 {print \$5}")"
[ -z "$storage" ] && storage="n/a"

cache="$(df -P /mnt/cache 2>/dev/null | awk "NR==2 {print \$5}")"
[ -z "$cache" ] && cache="n/a"

running="$(docker ps -q 2>/dev/null | wc -l | tr -d " ")"
total="$(docker ps -aq 2>/dev/null | wc -l | tr -d " ")"
[ -z "$running" ] && running="0"
[ -z "$total" ] && total="0"

if [ "$total" = "0" ]; then
    docker_state="n/a"
else
    docker_state="${running}/${total}"
fi

if pgrep -f "/usr/local/sbin/mover" >/dev/null 2>&1; then
    mover="RUN"
else
    mover="idle"
fi

if md="$(/usr/local/sbin/mdcmd status 2>/dev/null)"; then
    md_rc=0
else
    md_rc=$?
fi

resync="$(printf "%s\n" "$md" | awk -F= "/^mdResync=/ {print \$2; exit}")"
resync_pos="$(printf "%s\n" "$md" | awk -F= "/^mdResyncPos=/ {print \$2; exit}")"
resync_size="$(printf "%s\n" "$md" | awk -F= "/^mdResyncSize=/ {print \$2; exit}")"
sync_errors="$(printf "%s\n" "$md" | awk -F= "/^sbSyncErrs=/ {print \$2; exit}")"

# Fehlende, unlesbare oder ungültige Werte sind kein erfolgreicher Paritätscheck.
parity="n/a"
if [ "$md_rc" -ne 0 ] ||
   ! [[ "$resync" =~ ^[0-9]+$ && "$resync_pos" =~ ^[0-9]+$ &&
        "$resync_size" =~ ^[0-9]+$ && "$sync_errors" =~ ^[0-9]+$ ]]; then
    parity="n/a"
elif [ "$sync_errors" -gt 0 ] 2>/dev/null; then
    parity="ERR"
elif [ "$resync" -gt 0 ] 2>/dev/null || [ "$resync_pos" -gt 0 ] 2>/dev/null; then
    pct="$(awk -v p="$resync_pos" -v s="$resync_size" "BEGIN { if (s > 0) printf \"%.0f%%\", (p/s)*100; else printf \"RUN\" }")"
    parity="$pct"
else
    parity="OK"
fi

load="$(awk "{print \$1}" /proc/loadavg 2>/dev/null)"
ram="$(free -m 2>/dev/null | awk "/Mem:/ {printf \"%d%%\", (\$3/\$2)*100}")"
[ -z "$load" ] && load="n/a"
[ -z "$ram" ] && ram="n/a"

printf "UPDATE=%s\n" "$now"
printf "TOWER=%s\n" "$tower"
printf "ARRAY=%s\n" "$array"
printf "PARITY=%s\n" "$parity"
printf "CACHE=%s\n" "$cache"
printf "STORAGE=%s\n" "$storage"
printf "DOCKER=%s\n" "$docker_state"
printf "MOVER=%s\n" "$mover"
printf "LOAD=%s\n" "$load"
printf "RAM=%s\n" "$ram"
'

TMP_FILE="$(mktemp)"

if ssh -i "$SSH_KEY" \
    -o BatchMode=yes \
    -o ConnectTimeout=4 \
    -o StrictHostKeyChecking=accept-new \
    "$UNRAID_HOST" "bash -s" <<< "$REMOTE_SCRIPT" > "$TMP_FILE" 2>/dev/null; then
    mv "$TMP_FILE" "$OUT_FILE"
else
    {
        echo "UPDATE=$(date +%H:%M:%S)"
        echo "TOWER=OFFLINE"
        echo "ARRAY=n/a"
        echo "PARITY=n/a"
        echo "CACHE=n/a"
        echo "STORAGE=n/a"
        echo "DOCKER=n/a"
        echo "MOVER=n/a"
        echo "LOAD=n/a"
        echo "RAM=n/a"
    } > "$TMP_FILE"

    mv "$TMP_FILE" "$OUT_FILE"
fi
