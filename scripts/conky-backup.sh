#!/usr/bin/env bash
# Conky-Komplettbackup für CachyOS/KDE
# Installationspfad: /home/m4j0r/scripts/conky-backup.sh
# Backup-Ziel:       /home/m4j0r/Backup/Conky

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="2026-07-10.6"
readonly USER_HOME="/home/m4j0r"
readonly BACKUP_ROOT="${USER_HOME}/Backup/Conky"
readonly INSTALLED_SCRIPT="${USER_HOME}/scripts/conky-backup.sh"
readonly SCRIPT_SOURCE="$(readlink -f "${BASH_SOURCE[0]}")"
readonly KEEP_BACKUPS=10

if [[ "${EUID}" -eq 0 ]]; then
    printf '\nDieses Skript bitte als Benutzer m4j0r und nicht mit sudo starten.\n\n' >&2
    exit 1
fi

mkdir -p "$BACKUP_ROOT"

cleanup_dir=""
cleanup() {
    if [[ -n "${cleanup_dir}" && -d "${cleanup_dir}" ]]; then
        rm -rf -- "${cleanup_dir}"
    fi
}
trap cleanup EXIT

pause() {
    printf '\nEnter drücken, um zum Menü zurückzukehren ...'
    read -r _
}

header() {
    clear
    printf '============================================================\n'
    printf '  CONKY BACKUP & RESTORE\n'
    printf '  Version: %s\n' "$SCRIPT_VERSION"
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

    mkdir -p "$(dirname "$destination")"
    cp -a -- "$source" "$destination"
}

copy_as() {
    local source="$1"
    local destination="$2"

    [[ -e "$source" || -L "$source" ]] || return 0

    mkdir -p "$(dirname "$destination")"
    cp -a -- "$source" "$destination"
}

copy_matching_files() {
    local source_dir="$1"
    local destination_root="$2"
    shift 2

    [[ -d "$source_dir" ]] || return 0

    local pattern file
    shopt -s nullglob nocaseglob
    for pattern in "$@"; do
        for file in "$source_dir"/$pattern; do
            copy_path "$file" "$destination_root"
        done
    done
    shopt -u nullglob nocaseglob
}

write_system_info() {
    local info_dir="$1"
    mkdir -p "$info_dir"

    {
        printf 'Backup erstellt: %s\n' "$(date --iso-8601=seconds)"
        printf 'Skriptversion: %s\n' "$SCRIPT_VERSION"
        printf 'Benutzer: %s\n' "$(id -un)"
        printf 'Hostname: %s\n' "$(hostname)"
        printf 'Kernel: %s\n' "$(uname -srmo)"
        printf '\n'

        command -v conky >/dev/null 2>&1 && conky --version || true
        printf '\n'
        command -v plasmashell >/dev/null 2>&1 && plasmashell --version || true
        command -v kwin_wayland >/dev/null 2>&1 && kwin_wayland --version || true
        command -v kwin_x11 >/dev/null 2>&1 && kwin_x11 --version || true
    } > "${info_dir}/system-info.txt" 2>&1

    if command -v pacman >/dev/null 2>&1; then
        pacman -Qqe > "${info_dir}/pacman-explicit-packages.txt" 2>/dev/null || true
        pacman -Qm  > "${info_dir}/pacman-foreign-packages.txt" 2>/dev/null || true
    fi

    if command -v fc-list >/dev/null 2>&1; then
        fc-list : family style file | sort -u > "${info_dir}/font-list.txt" 2>/dev/null || true
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user list-unit-files --no-pager \
            | grep -Ei 'conky|unraid|dns-node|spotify|tauon|radio' \
            > "${info_dir}/related-user-units.txt" 2>/dev/null || true
    fi
}

create_restore_readme() {
    local target="$1"
    cat > "$target" <<'README'
CONKY-BACKUP – WIEDERHERSTELLUNG
================================

Empfohlen:
1. Das Skript ~/scripts/conky-backup.sh starten.
2. Im Menü „Backup wiederherstellen“ auswählen.
3. Das gewünschte Archiv auswählen.

Das Backup-Skript selbst befindet sich im Archiv unter:
payload/home/m4j0r/scripts/conky-backup.sh

Bei einer Wiederherstellung wird es zusammen mit den übrigen Dateien
wieder an seinen ursprünglichen Pfad zurückkopiert.

Das Skript erstellt vor einer Wiederherstellung automatisch ein neues
Sicherheitsbackup des aktuellen Zustands.

Gesichert werden – sofern vorhanden:
- /home/m4j0r/scripts/Conky
- /home/m4j0r/scripts/conky-backup.sh
- ~/.config/conky
- passende Conky-Autostartdateien
- passende systemd-User-Services und -Timer
- KDE/KWin-Konfiguration für Fensterregeln und Blur
- lokale KWin-Skripte/Effekte mit Bezug zu Blur oder Conky
- Paket-, Versions- und Schriftinformationen

Bewusst nicht gesichert werden:
- temporäre Conky-Cachedateien unter ~/.cache/conky
- laufende Logs
- fremde persönliche Dateien außerhalb der oben genannten Pfade

Nach einer Wiederherstellung:
- systemctl --user daemon-reload ausführen.
- Ab- und wieder anmelden oder Plasma/KWin neu starten.
- Danach das Conky-Startskript erneut starten.
README
}

get_backups() {
    find "$BACKUP_ROOT" -maxdepth 1 -type f \
        \( -name 'conky-backup-*.tar.zst' -o -name 'conky-backup-*.tar.gz' \) \
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
            printf 'Altes Backup gelöscht: %s\n' "$(basename "$old")"
            ((deleted += 1))
        done
    fi

    # Verwaiste Prüfsummendateien entfernen, falls das zugehörige Archiv fehlt.
    shopt -s nullglob
    for checksum in "$BACKUP_ROOT"/conky-backup-*.tar.zst.sha256 \
                    "$BACKUP_ROOT"/conky-backup-*.tar.gz.sha256; do
        [[ -e "${checksum%.sha256}" ]] || rm -f -- "$checksum"
    done
    shopt -u nullglob

    if (( deleted == 0 )); then
        printf 'Keine alten Backups zu löschen. Maximal %d werden behalten.\n' "$KEEP_BACKUPS"
    else
        printf '%d alte(s) Backup(s) entfernt. Die neuesten %d bleiben erhalten.\n' \
            "$deleted" "$KEEP_BACKUPS"
    fi
}

create_backup() {
    local reason="${1:-manual}"
    local timestamp hostname_safe archive extension

    timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
    hostname_safe="$(hostname)"
    hostname_safe="${hostname_safe//[^[:alnum:]_.-]/_}"

    cleanup_dir="$(mktemp -d "${BACKUP_ROOT}/.conky-backup-tmp.XXXXXX")"
    local payload="${cleanup_dir}/payload"
    local info_dir="${cleanup_dir}/backup-info"

    mkdir -p "$payload" "$info_dir"

    printf '\nSichere Conky-Dateien ...\n'

    copy_path "${USER_HOME}/scripts/Conky" "$payload"

    # Die tatsächlich laufende Skriptdatei wird direkt ins Archiv kopiert.
    # Im Archiv erhält sie ihren vorgesehenen Installationspfad. Auf dem
    # laufenden System wird dabei keine zusätzliche Kopie angelegt.
    copy_as "$SCRIPT_SOURCE" "${payload}${INSTALLED_SCRIPT}"

    copy_path "${USER_HOME}/.config/conky" "$payload"

    copy_matching_files "${USER_HOME}/.config/autostart" "$payload" \
        '*conky*.desktop' '*spotify*.desktop' '*tauon*.desktop' '*radio*.desktop'

    copy_matching_files "${USER_HOME}/.config/systemd/user" "$payload" \
        '*conky*' '*unraid*' '*dns-node*' '*spotify*' '*tauon*' '*radio*'

    # Diese Dateien können auch Regeln für andere Fenster enthalten und werden
    # deshalb vollständig gesichert.
    copy_path "${USER_HOME}/.config/kwinrulesrc" "$payload"
    copy_path "${USER_HOME}/.config/kwinrc" "$payload"

    copy_matching_files "${USER_HOME}/.local/share/kwin/scripts" "$payload" \
        '*blur*' '*better*' '*conky*'
    copy_matching_files "${USER_HOME}/.local/share/kwin/effects" "$payload" \
        '*blur*' '*better*' '*conky*'

    write_system_info "$info_dir"
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
        archive="${BACKUP_ROOT}/conky-backup-${timestamp}-${hostname_safe}.${extension}"
        tar --zstd -cpf "$archive" -C "$cleanup_dir" \
            payload backup-info RESTORE-README.txt MANIFEST.sha256
    else
        extension="tar.gz"
        archive="${BACKUP_ROOT}/conky-backup-${timestamp}-${hostname_safe}.${extension}"
        tar -czpf "$archive" -C "$cleanup_dir" \
            payload backup-info RESTORE-README.txt MANIFEST.sha256
    fi

    sha256sum "$archive" > "${archive}.sha256"

    rm -rf -- "$cleanup_dir"
    cleanup_dir=""

    printf '\nBackup erfolgreich erstellt:\n%s\n' "$archive"
    printf '\nPrüfsumme:\n%s.sha256\n\n' "$archive"

    prune_old_backups
}

list_backups() {
    local -a backups=()
    mapfile -t backups < <(get_backups)

    if (( ${#backups[@]} == 0 )); then
        printf 'Noch keine Conky-Backups vorhanden.\n'
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
        printf 'Noch keine Conky-Backups vorhanden.\n'
        return 1
    fi

    local index
    for index in "${!backups[@]}"; do
        printf '%2d) %s\n' "$((index + 1))" "$(basename "${backups[$index]}")"
    done
    printf ' 0) Abbrechen\n\n'

    local selection
    read -r -p 'Backup auswählen: ' selection

    [[ "$selection" =~ ^[0-9]+$ ]] || {
        printf 'Ungültige Eingabe.\n'
        return 1
    }

    (( selection == 0 )) && return 1
    (( selection >= 1 && selection <= ${#backups[@]} )) || {
        printf 'Ungültige Auswahl.\n'
        return 1
    }

    result_ref="${backups[$((selection - 1))]}"
}

verify_archive() {
    local archive="$1"

    if [[ -f "${archive}.sha256" ]]; then
        printf '\nPrüfe Archiv-Prüfsumme ...\n'
        (cd "$(dirname "$archive")" && sha256sum -c "$(basename "${archive}.sha256")")
    else
        printf '\nHinweis: Keine externe SHA256-Datei gefunden.\n'
    fi

    printf 'Prüfe Archivstruktur ...\n'
    tar -tf "$archive" >/dev/null
}

restore_backup() {
    local archive=""
    select_backup archive || return 0

    verify_archive "$archive" || {
        printf '\nDas Archiv ist beschädigt oder konnte nicht gelesen werden.\n'
        return 1
    }

    printf '\nAusgewählt: %s\n' "$(basename "$archive")"
    printf '\nDie enthaltenen Dateien überschreiben vorhandene Dateien.\n'
    printf 'Zusätzliche, später angelegte Dateien werden nicht gelöscht.\n\n'

    local confirmation
    read -r -p 'Wiederherstellung wirklich starten? [j/N]: ' confirmation
    [[ "$confirmation" =~ ^[jJyY]$ ]] || {
        printf 'Wiederherstellung abgebrochen.\n'
        return 0
    }

    printf '\nErstelle zuerst ein Sicherheitsbackup des aktuellen Zustands ...\n'
    create_backup "pre-restore-$(basename "$archive")"

    cleanup_dir="$(mktemp -d "${BACKUP_ROOT}/.conky-restore-tmp.XXXXXX")"
    tar -xpf "$archive" -C "$cleanup_dir"

    if [[ ! -d "${cleanup_dir}/payload/home/m4j0r" ]]; then
        printf '\nUngültiges Backup: payload/home/m4j0r fehlt.\n' >&2
        return 1
    fi

    if [[ -f "${cleanup_dir}/MANIFEST.sha256" ]]; then
        printf '\nPrüfe interne Dateiprüfsummen ...\n'
        (
            cd "$cleanup_dir"
            sha256sum -c MANIFEST.sha256
        )
    fi

    printf '\nStelle Dateien wieder her ...\n'

    if command -v rsync >/dev/null 2>&1; then
        rsync -a --human-readable --info=NAME \
            "${cleanup_dir}/payload/home/m4j0r/" "${USER_HOME}/"
    else
        cp -a -- "${cleanup_dir}/payload/home/m4j0r/." "${USER_HOME}/"
    fi

    chmod 755 "$INSTALLED_SCRIPT" 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true

    rm -rf -- "$cleanup_dir"
    cleanup_dir=""

    printf '\nWiederherstellung abgeschlossen.\n'
    printf 'Bitte einmal ab- und wieder anmelden oder Plasma/KWin neu starten.\n'
    printf 'Anschließend Conky über dein Startskript neu starten.\n'
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
            printf '\nUngültige Auswahl.\n'
            pause
            ;;
    esac
done
