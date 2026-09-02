#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly SCRIPT_VERSION="2026-09-02.1"
readonly BACKUP_BASE="${HOME}/Backup"
readonly STATE_DIR="${HOME}/.local/state/m4j0r-weekly-backup"
readonly LAST_SUCCESS="${STATE_DIR}/last-success"
readonly PAUSE_FILE="${STATE_DIR}/paused"
readonly LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/m4j0r-weekly-backup.lock"
readonly CONFIG_DIR="${HOME}/.config/m4j0r-backup"
readonly GAME_PATTERNS_FILE="${CONFIG_DIR}/game-patterns"
readonly PRIVATE_RECIPIENT_FILE="${CONFIG_DIR}/private-recipient"
readonly PRIVATE_RECOVERY_DIR="${BACKUP_BASE}/Private-Recovery"
readonly WEEK_SECONDS=$((7 * 24 * 60 * 60))

FORCE=0
IGNORE_GAME=0
STATUS_ONLY=0

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send --app-name='m4j0r Backup' "$1" "$2" >/dev/null 2>&1 || true
}

usage() {
    cat <<USAGE
Aufruf: $(basename "$0") [--force] [--ignore-game] [--status]

  --force        Sieben-Tage-Frist ignorieren und jetzt sichern
  --ignore-game  Gaming-Erkennung für diesen manuellen Lauf ignorieren
  --status       Nur Zustand anzeigen
USAGE
}

while (($#)); do
    case "$1" in
        --force) FORCE=1 ;;
        --ignore-game) IGNORE_GAME=1 ;;
        --status) STATUS_ONLY=1 ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unbekanntes Argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

mkdir -p -- "${STATE_DIR}" "${CONFIG_DIR}"
chmod 700 -- "${STATE_DIR}" "${CONFIG_DIR}"

backup_folder_available() {
    local testfile

    [[ -d "${BACKUP_BASE}" ]] || return 1
    [[ -w "${BACKUP_BASE}" && -x "${BACKUP_BASE}" ]] || return 1

    testfile="${BACKUP_BASE}/.weekly-backup-write-test.$$"
    if ! (umask 077; : > "${testfile}") 2>/dev/null; then
        return 1
    fi
    rm -f -- "${testfile}"
    return 0
}

nextcloud_client_active() {
    pgrep -u "$(id -u)" -x nextcloud >/dev/null 2>&1 ||
        pgrep -u "$(id -u)" -f '(^|/)nextcloud([[:space:]]|$)' >/dev/null 2>&1
}

private_backup_ready() {
    local recipient

    [[ -s "${PRIVATE_RECIPIENT_FILE}" ]] || return 1
    recipient="$(tr -d '[:space:]' < "${PRIVATE_RECIPIENT_FILE}")"
    [[ -n "${recipient}" ]] || return 1
    gpg --batch --list-keys "${recipient}" >/dev/null 2>&1 || return 1
    compgen -G "${PRIVATE_RECOVERY_DIR}/private-backup-secret-key-${recipient}.asc" >/dev/null || return 1
    return 0
}

gamemode_active() {
    local status
    command -v gamemoded >/dev/null 2>&1 || return 1
    status="$(gamemoded -s 2>/dev/null || true)"
    grep -Eiq 'gamemode is active|active clients:[[:space:]]*[1-9]' <<< "${status}"
}

game_process_active() {
    local all_processes pattern

    all_processes="$(ps -u "${USER}" -o comm=,args= 2>/dev/null || true)"

    # Bekannte Spiele und typische aktive Spiel-Wrapper. Der dauerhaft laufende
    # Steam- oder Lutris-Client allein zählt ausdrücklich nicht als Gaming.
    grep -Eiq -- \
        'Wow(Classic)?(-64)?\.exe|World of Warcraft|Diablo IV\.exe|PathOfExile[^ ]*\.exe|SteamLaunch[[:space:]]+AppId=[0-9]+|proton[[:space:]].*waitforexitandrun|lutris-wrapper|(^|[ /])umu-run([[:space:]]|$)|(^|[ /])gamescope([[:space:]]|$)' \
        <<< "${all_processes}" && return 0

    if [[ -s "${GAME_PATTERNS_FILE}" ]]; then
        while IFS= read -r pattern; do
            [[ -n "${pattern}" && "${pattern}" != \#* ]] || continue
            grep -Eiq -- "${pattern}" <<< "${all_processes}" && return 0
        done < "${GAME_PATTERNS_FILE}"
    fi
    return 1
}

gaming_active() {
    ((IGNORE_GAME == 1)) && return 1
    gamemode_active || game_process_active
}

backup_due() {
    local now last
    ((FORCE == 1)) && return 0
    [[ -e "${LAST_SUCCESS}" ]] || return 0
    now="$(date +%s)"
    last="$(stat -c %Y "${LAST_SUCCESS}" 2>/dev/null || printf '0')"
    (( now - last >= WEEK_SECONDS ))
}

show_status() {
    local due='nein' game='nein' folder='nein' nextcloud='nein' private='nein' last='noch nie'

    backup_due && due='ja'
    gaming_active && game='ja'
    backup_folder_available && folder='ja'
    nextcloud_client_active && nextcloud='ja'
    private_backup_ready && private='ja'
    [[ -e "${LAST_SUCCESS}" ]] && last="$(date -r "${LAST_SUCCESS}" '+%d.%m.%Y %H:%M:%S')"

    printf 'Version:              %s\n' "${SCRIPT_VERSION}"
    printf 'Backupordner lokal:   %s\n' "${folder}"
    printf 'Nextcloud-Client:     %s\n' "${nextcloud}"
    printf 'Privat-Automatik:     %s\n' "${private}"
    printf 'Backup fällig:        %s\n' "${due}"
    printf 'Gaming erkannt:       %s\n' "${game}"
    printf 'Letzter Erfolg:       %s\n' "${last}"
}

if ((STATUS_ONLY == 1)); then
    show_status
    exit 0
fi

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    log 'Ein Backup-Lauf ist bereits aktiv.'
    exit 0
fi

if [[ -e "${PAUSE_FILE}" ]]; then
    log "Automatik ist pausiert: ${PAUSE_FILE}"
    exit 0
fi

if ! backup_due; then
    log 'Noch nicht fällig; der letzte erfolgreiche Lauf ist jünger als sieben Tage.'
    exit 0
fi

if ! backup_folder_available; then
    log "Lokaler Nextcloud-Backupordner fehlt oder ist nicht beschreibbar: ${BACKUP_BASE}"
    notify 'Backup verschoben' 'Der lokale Nextcloud-Backupordner ist nicht verfügbar.'
    exit 0
fi

if gaming_active; then
    log 'Aktives Spiel erkannt. Lauf wird verschoben und beim nächsten Timer-Termin erneut geprüft.'
    notify 'Backup verschoben' 'Es läuft gerade ein Spiel.'
    exit 0
fi

if ! private_backup_ready; then
    log 'Automatische GPG-Verschlüsselung für das Privat-Backup ist noch nicht vollständig eingerichtet.'
    log "Einrichtung erneut starten: ${HOME}/scripts/private-backup-key-setup.sh"
    notify 'Backup verschoben' 'Privat-Backup-Schlüssel ist noch nicht vollständig eingerichtet.'
    exit 0
fi

if ! nextcloud_client_active; then
    log 'HINWEIS: Der Nextcloud-Client läuft aktuell nicht. Das lokale Backup wird trotzdem erstellt und später synchronisiert.'
fi

scripts=(
    "${HOME}/scripts/conky-backup.sh"
    "${HOME}/scripts/scripts-backup.sh"
    "${HOME}/scripts/program-config-backup.sh"
    "${HOME}/scripts/niri-backup-weekly-module.sh"
    "${HOME}/scripts/python-projects-backup.sh"
    "${HOME}/scripts/private-backup.sh"
)

log 'Wöchentlicher Backup-Lauf startet.'
notify 'Backup startet' 'Conky, Scripts, Konfigurationen, Niri, Python-Projekte und Privatdaten werden lokal gesichert.'

for script in "${scripts[@]}"; do
    [[ -x "${script}" ]] || {
        log "FEHLER: Skript fehlt oder ist nicht ausführbar: ${script}"
        notify 'Backup fehlgeschlagen' "Fehlendes Skript: $(basename "${script}")"
        exit 1
    }

    if gaming_active; then
        log "Vor $(basename "${script}") wurde ein Spiel erkannt. Gesamtlauf bleibt fällig und wird später neu gestartet."
        notify 'Backup unterbrochen' 'Ein Spiel wurde gestartet; später wird erneut gesichert.'
        exit 0
    fi

    log "Starte $(basename "${script}") --backup"
    if ! "${script}" --backup; then
        log "FEHLER bei $(basename "${script}")"
        notify 'Backup fehlgeschlagen' "Fehler bei $(basename "${script}")."
        exit 1
    fi
done

touch -- "${LAST_SUCCESS}"
chmod 600 -- "${LAST_SUCCESS}"
log 'Alle sechs Backups wurden erfolgreich abgeschlossen.'
notify 'Backup abgeschlossen' 'Alle Backups wurden erstellt; Nextcloud übernimmt die Synchronisierung zum Server.'
