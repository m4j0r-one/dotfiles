#!/usr/bin/env bash
set -u

export LC_ALL=C.UTF-8
readonly RUNNER="$HOME/scripts/weekly-backup-runner.sh"
readonly TIMER="m4j0r-weekly-backup.timer"
readonly SERVICE="m4j0r-weekly-backup.service"

# Conky-Farben aus der bestehenden Karte:
# color2 = normal/OK, color3 = aktiv, color4 = Hinweis/Fehler.
ok()     { printf '${color2}%s' "$1"; }
active() { printf '${color3}%s' "$1"; }
warn()   { printf '${color4}%s' "$1"; }

if systemctl --user is-active --quiet "${SERVICE}" 2>/dev/null; then
    active "LAEUFT"
    exit 0
fi

if systemctl --user is-failed --quiet "${SERVICE}" 2>/dev/null; then
    warn "FEHLER"
    exit 0
fi

if ! systemctl --user is-active --quiet "${TIMER}" 2>/dev/null; then
    warn "TIMER AUS"
    exit 0
fi

if [[ ! -x "${RUNNER}" ]]; then
    warn "FEHLT"
    exit 0
fi

status="$("${RUNNER}" --status 2>/dev/null || true)"

private_auto="$(
    awk -F: '/^Privat-Automatik:/ {
        sub(/^[[:space:]]+/, "", $2)
        print $2
        exit
    }' <<< "${status}"
)"
due="$(
    awk -F: '/^Backup fällig:/ {
        sub(/^[[:space:]]+/, "", $2)
        print $2
        exit
    }' <<< "${status}"
)"
gaming="$(
    awk -F: '/^Gaming erkannt:/ {
        sub(/^[[:space:]]+/, "", $2)
        print $2
        exit
    }' <<< "${status}"
)"
last_success="$(
    sed -n 's/^Letzter Erfolg:[[:space:]]*//p' <<< "${status}" | head -n 1
)"

if [[ "${private_auto}" != "ja" ]]; then
    warn "SETUP"
elif [[ "${due}" == "ja" && "${gaming}" == "ja" ]]; then
    warn "GAME"
elif [[ "${due}" == "ja" ]]; then
    warn "FAELLIG"
elif [[ -z "${last_success}" || "${last_success}" == "noch nie" ]]; then
    warn "OFFEN"
else
    # Aus "10.07.2026 17:10:19" wird kompakt "OK 10.07".
    short_date="${last_success:0:5}"
    ok "OK ${short_date}"
fi
