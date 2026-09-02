#!/usr/bin/env bash
# Komplettbackup fuer /home/m4j0r/Projekte/Python
# Installationspfad: /home/m4j0r/scripts/python-projects-backup.sh
# Backup-Ziel:       /home/m4j0r/Backup/Python-Projekte

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly SCRIPT_VERSION="2026-09-02.1"
readonly USER_HOME="/home/m4j0r"
readonly SOURCE_DIR="${USER_HOME}/Projekte/Python"
readonly BACKUP_ROOT="${USER_HOME}/Backup/Python-Projekte"
readonly INSTALLED_SCRIPT="${USER_HOME}/scripts/python-projects-backup.sh"
readonly SCRIPT_SOURCE="$(readlink -f "${BASH_SOURCE[0]}")"
readonly KEEP_BACKUPS=10

if [[ "${EUID}" -eq 0 ]]; then
    printf '\nDieses Skript bitte als Benutzer m4j0r und nicht mit sudo starten.\n\n' >&2
    exit 1
fi

mkdir -p "$BACKUP_ROOT" "$SOURCE_DIR"

cleanup_dir=""
cleanup() {
    if [[ -n "$cleanup_dir" && -d "$cleanup_dir" ]]; then
        rm -rf -- "$cleanup_dir"
    fi
}
trap cleanup EXIT

pause() {
    printf '\nEnter druecken, um zum Menue zurueckzukehren ...'
    read -r _
}

header() {
    clear
    printf '============================================================\n'
    printf '  PYTHON PROJECTS BACKUP & RESTORE\n'
    printf '  Version: %s\n' "$SCRIPT_VERSION"
    printf '  Quelle: %s\n' "$SOURCE_DIR"
    printf '  Ziel: %s\n' "$BACKUP_ROOT"
    printf '  Aufbewahrung: die neuesten %d Backups\n' "$KEEP_BACKUPS"
    printf '============================================================\n\n'
}

copy_path() {
    local source="$1"
    local destination_root="$2"

    [[ -e "$source" || -L "$source" ]] || return 0

    local relative="${source#/}"
    local destination="${destination_root}/${relative}"

    mkdir -p "$destination"

    rsync -a \
        --exclude='.venv/' \
        -- "$source/" "$destination/"
}

copy_as() {
    local source="$1"
    local destination="$2"

    [[ -e "$source" || -L "$source" ]] || return 0

    mkdir -p "$(dirname "$destination")"
    cp -a -- "$source" "$destination"
}

write_backup_info() {
    local info_dir="$1"
    mkdir -p "$info_dir"

    {
        printf 'Backup erstellt: %s\n' "$(date --iso-8601=seconds)"
        printf 'Skriptversion: %s\n' "$SCRIPT_VERSION"
        printf 'Benutzer: %s\n' "$(id -un)"
        printf 'Hostname: %s\n' "$(hostname)"
        printf 'Kernel: %s\n' "$(uname -srmo)"
        printf 'Quelle: %s\n' "$SOURCE_DIR"
        printf '\nGroesse des Python-Projektordners:\n'
        du -sh "$SOURCE_DIR" 2>/dev/null || true
        printf '\nDateien und Symlinks:\n'
        find "$SOURCE_DIR" -xdev \( -type f -o -type l \) -printf '%P\n' 2>/dev/null | sort
    } > "${info_dir}/python-projects-info.txt" 2>&1

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user list-unit-files --no-pager > "${info_dir}/user-unit-files.txt" 2>/dev/null || true
    fi
}

create_restore_readme() {
    local target="$1"
    cat > "$target" <<'README'
PYTHON-PROJEKTE-BACKUP – WIEDERHERSTELLUNG
=================================

Empfohlen:
1. ~/scripts/python-projects-backup.sh starten.
2. Im Menue „Backup wiederherstellen“ auswaehlen.
3. Das gewuenschte Archiv auswaehlen.

Gesichert wird der komplette Ordner:
/home/m4j0r/Projekte/Python

Darin enthalten sind auch die Backup-Skripte selbst, sofern sie im
Python-Projektordner enthalten sind.

Vor jeder Wiederherstellung wird automatisch ein Sicherheitsbackup des
aktuellen Python-Projektordners erstellt. Vorhandene Dateien werden ersetzt,
zusaetzliche Dateien werden nicht geloescht.

Nach der Wiederherstellung gegebenenfalls ausfuehren:
  systemctl --user daemon-reload

Falls Programme oder Conky bereits laufen, diese danach neu starten.
README
}

get_backups() {
    find "$BACKUP_ROOT" -maxdepth 1 -type f \
        \( -name 'python-projects-backup-*.tar.zst' -o -name 'python-projects-backup-*.tar.gz' \) \
        -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr \
        | cut -d' ' -f2-
}

prune_old_backups() {
    local -a backups=()
    mapfile -t backups < <(get_backups)

    local deleted=0 old checksum

    if (( ${#backups[@]} > KEEP_BACKUPS )); then
        for old in "${backups[@]:KEEP_BACKUPS}"; do
            checksum="${old}.sha256"
            rm -f -- "$old" "$checksum"
            printf 'Altes Backup geloescht: %s\n' "$(basename "$old")"
            ((deleted += 1))
        done
    fi

    shopt -s nullglob
    for checksum in "$BACKUP_ROOT"/python-projects-backup-*.tar.zst.sha256 \
                    "$BACKUP_ROOT"/python-projects-backup-*.tar.gz.sha256; do
        [[ -e "${checksum%.sha256}" ]] || rm -f -- "$checksum"
    done
    shopt -u nullglob

    if (( deleted == 0 )); then
        printf 'Keine alten Backups zu loeschen. Maximal %d werden behalten.\n' "$KEEP_BACKUPS"
    else
        printf '%d alte(s) Backup(s) entfernt. Die neuesten %d bleiben erhalten.\n' \
            "$deleted" "$KEEP_BACKUPS"
    fi
}

create_backup() {
    local reason="${1:-manual}"
    local do_prune="${2:-yes}"
    local timestamp hostname_safe archive extension

    timestamp="$(date '+%Y-%m-%d_%H-%M-%S_%3N')"
    hostname_safe="$(hostname)"
    hostname_safe="${hostname_safe//[^[:alnum:]_.-]/_}"

    cleanup_dir="$(mktemp -d "${BACKUP_ROOT}/.python-projects-backup-tmp.XXXXXX")"
    local payload="${cleanup_dir}/payload"
    local info_dir="${cleanup_dir}/backup-info"

    mkdir -p "$payload" "$info_dir"

    printf '\nSichere %s ...\n' "$SOURCE_DIR"
    copy_path "$SOURCE_DIR" "$payload"

    # Falls das Skript direkt aus dem Download-Ordner gestartet wurde, wird
    # trotzdem genau diese laufende Version im Archiv am Installationspfad abgelegt.
    copy_as "$SCRIPT_SOURCE" "${payload}${INSTALLED_SCRIPT}"

    write_backup_info "$info_dir"
    create_restore_readme "${cleanup_dir}/RESTORE-README.txt"
    printf '%s\n' "$reason" > "${info_dir}/backup-reason.txt"

    (
        cd "$cleanup_dir"
        find payload backup-info RESTORE-README.txt -type f -print0 \
            | sort -z \
            | xargs -0 sha256sum > MANIFEST.sha256
    )

    if command -v zstd >/dev/null 2>&1; then
        extension="tar.zst"
        archive="${BACKUP_ROOT}/python-projects-backup-${timestamp}-${hostname_safe}.${extension}"
        tar --zstd -cpf "$archive" -C "$cleanup_dir" \
            payload backup-info RESTORE-README.txt MANIFEST.sha256
    else
        extension="tar.gz"
        archive="${BACKUP_ROOT}/python-projects-backup-${timestamp}-${hostname_safe}.${extension}"
        tar -czpf "$archive" -C "$cleanup_dir" \
            payload backup-info RESTORE-README.txt MANIFEST.sha256
    fi

    chmod 600 "$archive"
    sha256sum "$archive" > "${archive}.sha256"
    chmod 600 "${archive}.sha256"

    rm -rf -- "$cleanup_dir"
    cleanup_dir=""

    printf '\nBackup erfolgreich erstellt:\n%s\n' "$archive"
    printf '\nPruefsumme:\n%s.sha256\n\n' "$archive"

    if [[ "$do_prune" == "yes" ]]; then
        prune_old_backups
    fi
}

list_backups() {
    local -a backups=()
    mapfile -t backups < <(get_backups)

    if (( ${#backups[@]} == 0 )); then
        printf 'Noch keine Python-Projekt-Backups vorhanden.\n'
        return 1
    fi

    local index file size modified
    for index in "${!backups[@]}"; do
        file="${backups[$index]}"
        size="$(du -h "$file" | awk '{print $1}')"
        modified="$(date -r "$file" '+%d.%m.%Y %H:%M:%S')"
        printf '%2d) %s  |  %7s  |  %s\n' \
            "$((index + 1))" "$(basename "$file")" "$size" "$modified"
    done
}

select_backup() {
    local -n result_ref="$1"
    local -a backups=()
    mapfile -t backups < <(get_backups)

    if (( ${#backups[@]} == 0 )); then
        printf 'Noch keine Python-Projekt-Backups vorhanden.\n'
        return 1
    fi

    local index
    for index in "${!backups[@]}"; do
        printf '%2d) %s\n' "$((index + 1))" "$(basename "${backups[$index]}")"
    done
    printf ' 0) Abbrechen\n\n'

    local selection
    read -r -p 'Backup auswaehlen: ' selection

    [[ "$selection" =~ ^[0-9]+$ ]] || {
        printf 'Ungueltige Eingabe.\n'
        return 1
    }

    (( selection == 0 )) && return 1
    (( selection >= 1 && selection <= ${#backups[@]} )) || {
        printf 'Ungueltige Auswahl.\n'
        return 1
    }

    result_ref="${backups[$((selection - 1))]}"
}

verify_archive() {
    local archive="$1"

    if [[ -f "${archive}.sha256" ]]; then
        printf '\nPruefe Archiv-Pruefsumme ...\n'
        (cd "$(dirname "$archive")" && sha256sum -c "$(basename "${archive}.sha256")")
    else
        printf '\nHinweis: Keine externe SHA256-Datei gefunden.\n'
    fi

    printf 'Pruefe Archivstruktur ...\n'
    tar -tf "$archive" >/dev/null
}

restore_backup() {
    local archive=""
    select_backup archive || return 0

    verify_archive "$archive" || {
        printf '\nDas Archiv ist beschaedigt oder konnte nicht gelesen werden.\n'
        return 1
    }

    printf '\nAusgewaehlt: %s\n' "$(basename "$archive")"
    printf '\nVorhandene Dateien werden ueberschrieben.\n'
    printf 'Zusaetzliche Dateien im Python-Projektordner werden nicht geloescht.\n\n'

    local confirmation
    read -r -p 'Wiederherstellung wirklich starten? [j/N]: ' confirmation
    [[ "$confirmation" =~ ^[jJyY]$ ]] || {
        printf 'Wiederherstellung abgebrochen.\n'
        return 0
    }

    printf '\nErstelle zuerst ein Sicherheitsbackup des aktuellen Zustands ...\n'
    create_backup "pre-restore-$(basename "$archive")" "no"

    cleanup_dir="$(mktemp -d "${BACKUP_ROOT}/.python-projects-restore-tmp.XXXXXX")"
    tar -xpf "$archive" -C "$cleanup_dir"

    if [[ ! -d "${cleanup_dir}/payload/home/m4j0r/Projekte/Python" ]]; then
        printf '\nUngueltiges Backup: payload/home/m4j0r/Projekte/Python fehlt.\n' >&2
        return 1
    fi

    if [[ -f "${cleanup_dir}/MANIFEST.sha256" ]]; then
        printf '\nPruefe interne Dateipruefsummen ...\n'
        (cd "$cleanup_dir" && sha256sum -c MANIFEST.sha256)
    fi

    printf '\nStelle Python-Projekte wieder her ...\n'
    mkdir -p "$SOURCE_DIR"

    if command -v rsync >/dev/null 2>&1; then
        rsync -a --human-readable --info=NAME \
            "${cleanup_dir}/payload/home/m4j0r/Projekte/Python/" "${SOURCE_DIR}/"
    else
        cp -a -- "${cleanup_dir}/payload/home/m4j0r/Projekte/Python/." "$SOURCE_DIR/"
    fi

    systemctl --user daemon-reload 2>/dev/null || true

    rm -rf -- "$cleanup_dir"
    cleanup_dir=""

    prune_old_backups

    printf '\nWiederherstellung abgeschlossen.\n'
    printf 'Laufende Programme oder Conky bei Bedarf neu starten.\n'
}

show_backup_contents() {
    local archive=""
    select_backup archive || return 0

    printf '\nInhalt von %s:\n\n' "$(basename "$archive")"
    tar -tf "$archive" | sed 's#^payload/home/m4j0r/#~/#'
}


# Nichtinteraktiver Modus fuer systemd/Automatisierung.
case "${1:-}" in
    --backup|--auto)
        create_backup "automatic"
        exit 0
        ;;
    --prune)
        prune_old_backups
        exit 0
        ;;
    --help|-h)
        printf 'Aufruf: %s [--backup|--prune]\n' "$0"
        exit 0
        ;;
esac

while true; do
    header
    printf '1) Neues Komplettbackup erstellen\n'
    printf '2) Backup wiederherstellen\n'
    printf '3) Vorhandene Backups anzeigen\n'
    printf '4) Inhalt eines Backups anzeigen\n'
    printf '5) Alte Backups jetzt bereinigen\n'
    printf '0) Beenden\n\n'

    read -r -p 'Auswahl: ' choice

    case "$choice" in
        1)
            create_backup "manual"
            pause
            ;;
        2)
            restore_backup
            pause
            ;;
        3)
            printf '\n'
            list_backups || true
            pause
            ;;
        4)
            show_backup_contents
            pause
            ;;
        5)
            printf '\n'
            prune_old_backups
            pause
            ;;
        0)
            printf '\nBeendet.\n'
            exit 0
            ;;
        *)
            printf '\nUngueltige Auswahl.\n'
            pause
            ;;
    esac
done
