#!/usr/bin/env bash
# Backup wichtiger Benutzer- und Programmkonfigurationen fuer CachyOS/KDE
# Installationspfad: /home/m4j0r/scripts/program-config-backup.sh
# Backup-Ziel:       /home/m4j0r/Backup/Configs

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly SCRIPT_VERSION="2026-07-10.3"
readonly USER_HOME="/home/m4j0r"
readonly BACKUP_ROOT="${USER_HOME}/Backup/Configs"
readonly INSTALLED_SCRIPT="${USER_HOME}/scripts/program-config-backup.sh"
readonly SCRIPT_SOURCE="$(readlink -f "${BASH_SOURCE[0]}")"
readonly KEEP_BACKUPS=10

if [[ "${EUID}" -eq 0 ]]; then
    printf '\nDieses Skript bitte als Benutzer m4j0r und nicht mit sudo starten.\n\n' >&2
    exit 1
fi

mkdir -p "$BACKUP_ROOT" "${USER_HOME}/scripts"

cleanup_dir=""
backup_log=""
missing_log=""

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
    printf '  PROGRAMM-CONFIG BACKUP & RESTORE\n'
    printf '  Version: %s\n' "$SCRIPT_VERSION"
    printf '  Ziel: %s\n' "$BACKUP_ROOT"
    printf '  Aufbewahrung: die neuesten %d Backups\n' "$KEEP_BACKUPS"
    printf '============================================================\n\n'
}

record_backed_up() {
    [[ -n "$backup_log" ]] && printf '%s\n' "$1" >> "$backup_log"
}

record_missing() {
    [[ -n "$missing_log" ]] && printf '%s\n' "$1" >> "$missing_log"
}

copy_path() {
    local source="$1"
    local destination_root="$2"

    if [[ ! -e "$source" && ! -L "$source" ]]; then
        record_missing "$source"
        return 0
    fi

    local relative="${source#/}"
    local destination="${destination_root}/${relative}"

    mkdir -p "$(dirname "$destination")"
    cp -a -- "$source" "$destination"
    record_backed_up "$source"
}

copy_as() {
    local source="$1"
    local destination="$2"

    if [[ ! -e "$source" && ! -L "$source" ]]; then
        record_missing "$source"
        return 0
    fi

    mkdir -p "$(dirname "$destination")"
    cp -a -- "$source" "$destination"
    record_backed_up "$source"
}

copy_matching_entries() {
    local source_dir="$1"
    local destination_root="$2"
    shift 2

    if [[ ! -d "$source_dir" ]]; then
        record_missing "$source_dir"
        return 0
    fi

    local pattern entry found=0
    shopt -s nullglob nocaseglob
    for pattern in "$@"; do
        for entry in "$source_dir"/$pattern; do
            copy_path "$entry" "$destination_root"
            found=1
        done
    done
    shopt -u nullglob nocaseglob

    (( found == 1 )) || record_missing "${source_dir}/{patterns: $*}"
}

copy_firefox_settings() {
    local payload="$1"
    local firefox_root="${USER_HOME}/.mozilla/firefox"

    [[ -d "$firefox_root" ]] || {
        record_missing "$firefox_root"
        return 0
    }

    copy_path "${firefox_root}/profiles.ini" "$payload"
    copy_path "${firefox_root}/installs.ini" "$payload"

    local profile item
    while IFS= read -r -d '' profile; do
        copy_path "${profile}/chrome" "$payload"

        for item in \
            user.js \
            prefs.js \
            containers.json \
            handlers.json \
            search.json.mozlz4 \
            extensions.json \
            extension-preferences.json \
            extension-settings.json; do
            [[ -e "${profile}/${item}" ]] && copy_path "${profile}/${item}" "$payload"
        done
    done < <(find "$firefox_root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    return 0
}

copy_tauon_settings() {
    local payload="$1"
    local tauon_root="${USER_HOME}/.local/share/TauonMusicBox"

    copy_path "${USER_HOME}/.config/TauonMusicBox" "$payload"
    copy_path "${USER_HOME}/.config/tauonmb" "$payload"

    if [[ -d "$tauon_root" ]]; then
        copy_matching_entries "$tauon_root" "$payload" \
            'config*' 'input*' 'state*' 'playlist*' 'radio*' 'theme*'
    else
        record_missing "$tauon_root"
    fi
}

copy_spotify_settings() {
    local payload="$1"
    copy_path "${USER_HOME}/.config/spotify/prefs" "$payload"

    local user_prefs
    shopt -s nullglob
    for user_prefs in "${USER_HOME}/.config/spotify/Users/"*/prefs; do
        copy_path "$user_prefs" "$payload"
    done
    shopt -u nullglob
}

copy_steam_nonsecret_settings() {
    local payload="$1"
    local steam_root="${USER_HOME}/.local/share/Steam"

    # Nur benutzerdefinierte Bibliotheks- und Shortcut-Konfigurationen.
    # Login- und Account-Tokens werden absichtlich nicht gesichert.
    copy_path "${steam_root}/config/libraryfolders.vdf" "$payload"

    local shortcut
    shopt -s nullglob
    for shortcut in "${steam_root}/userdata/"*/config/shortcuts.vdf; do
        copy_path "$shortcut" "$payload"
    done
    shopt -u nullglob
}

copy_user_configs() {
    local payload="$1"
    local path

    local -a files=(
        "${USER_HOME}/.zshrc"
        "${USER_HOME}/.zprofile"
        "${USER_HOME}/.zshenv"
        "${USER_HOME}/.p10k.zsh"
        "${USER_HOME}/.bashrc"
        "${USER_HOME}/.bash_profile"
        "${USER_HOME}/.profile"
        "${USER_HOME}/.gitconfig"
        "${USER_HOME}/.xprofile"
        "${USER_HOME}/.Xresources"
        "${USER_HOME}/.gtkrc-2.0"
        "${USER_HOME}/.config/kdeglobals"
        "${USER_HOME}/.config/kwinrc"
        "${USER_HOME}/.config/kwinrulesrc"
        "${USER_HOME}/.config/kglobalshortcutsrc"
        "${USER_HOME}/.config/kscreenlockerrc"
        "${USER_HOME}/.config/ksmserverrc"
        "${USER_HOME}/.config/plasmashellrc"
        "${USER_HOME}/.config/plasma-localerc"
        "${USER_HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc"
        "${USER_HOME}/.config/dolphinrc"
        "${USER_HOME}/.config/konsolerc"
        "${USER_HOME}/.config/katerc"
        "${USER_HOME}/.config/katepartrc"
        "${USER_HOME}/.config/kiorc"
        "${USER_HOME}/.config/kservicemenurc"
        "${USER_HOME}/.config/mimeapps.list"
        "${USER_HOME}/.config/user-dirs.dirs"
        "${USER_HOME}/.config/user-dirs.locale"
        "${USER_HOME}/.config/gamemode.ini"
        "${USER_HOME}/.config/Nextcloud/nextcloud.cfg"
        "${USER_HOME}/.config/nextcloud/nextcloud.cfg"
        "${USER_HOME}/.ssh/config"
    )

    local -a directories=(
        "${USER_HOME}/.config/MangoHud"
        "${USER_HOME}/.config/fastfetch"
        "${USER_HOME}/.config/neofetch"
        "${USER_HOME}/.config/Kvantum"
        "${USER_HOME}/.config/qt5ct"
        "${USER_HOME}/.config/qt6ct"
        "${USER_HOME}/.config/gtk-3.0"
        "${USER_HOME}/.config/gtk-4.0"
        "${USER_HOME}/.config/environment.d"
        "${USER_HOME}/.config/autostart"
        "${USER_HOME}/.config/autostart-scripts"
        "${USER_HOME}/.config/systemd/user"
        "${USER_HOME}/.config/plasma-workspace/env"
        "${USER_HOME}/.config/konsole"
        "${USER_HOME}/.config/kscreen"
        "${USER_HOME}/.config/lutris"
        "${USER_HOME}/.config/bottles"
        "${USER_HOME}/.local/share/konsole"
        "${USER_HOME}/.local/share/kscreen"
        "${USER_HOME}/.local/share/kxmlgui5"
        "${USER_HOME}/.local/share/color-schemes"
        "${USER_HOME}/.local/share/aurorae"
        "${USER_HOME}/.local/share/plasma"
        "${USER_HOME}/.local/share/kwin"
        "${USER_HOME}/.local/share/icons"
        "${USER_HOME}/.local/share/themes"
        "${USER_HOME}/.local/share/applications"
        "${USER_HOME}/.local/share/fonts"
        "${USER_HOME}/.local/share/wallpapers"
        "${USER_HOME}/.icons"
        "${USER_HOME}/.themes"
        "${USER_HOME}/.fonts"
    )

    printf '\nSichere ausgewaehlte Benutzer- und Programmkonfigurationen ...\n'

    for path in "${files[@]}"; do
        copy_path "$path" "$payload"
    done

    for path in "${directories[@]}"; do
        copy_path "$path" "$payload"
    done

    # Zusaetzliche Programme und KDE-Erweiterungen mit variierenden Namen.
    copy_matching_entries "${USER_HOME}/.config" "$payload" \
        '*andromeda*' '*panel*colorizer*' '*better*blur*'
    copy_matching_entries "${USER_HOME}/.local/share" "$payload" \
        '*andromeda*' '*panel*colorizer*' '*better*blur*'

    # Nur oeffentliche SSH-Schluessel, keine privaten Schluessel.
    copy_matching_entries "${USER_HOME}/.ssh" "$payload" '*.pub'

    copy_firefox_settings "$payload"
    copy_tauon_settings "$payload"
    copy_spotify_settings "$payload"
    copy_steam_nonsecret_settings "$payload"

    # Die tatsaechlich laufende Version des Backup-Skripts wird mitgesichert.
    copy_as "$SCRIPT_SOURCE" "${payload}${INSTALLED_SCRIPT}"
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
        printf '\nDesktop-Sitzung:\n'
        printf 'XDG_CURRENT_DESKTOP=%s\n' "${XDG_CURRENT_DESKTOP:-}"
        printf 'XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-}"
        printf '\nLocale:\n'
        locale 2>/dev/null || true
    } > "${info_dir}/system-info.txt" 2>&1

    if command -v pacman >/dev/null 2>&1; then
        pacman -Qqen > "${info_dir}/pacman-native-explicit.txt" 2>/dev/null || true
        pacman -Qqem > "${info_dir}/pacman-foreign-explicit.txt" 2>/dev/null || true
        pacman -Qqe  > "${info_dir}/pacman-all-explicit.txt" 2>/dev/null || true
    fi

    if command -v flatpak >/dev/null 2>&1; then
        flatpak list --app --columns=application,origin \
            > "${info_dir}/flatpak-apps.txt" 2>/dev/null || true
    fi

    if command -v fc-list >/dev/null 2>&1; then
        fc-list : family style file | sort -u \
            > "${info_dir}/font-list.txt" 2>/dev/null || true
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user list-unit-files --state=enabled --no-pager \
            > "${info_dir}/enabled-user-services.txt" 2>/dev/null || true
        systemctl list-unit-files --state=enabled --no-pager \
            > "${info_dir}/enabled-system-services.txt" 2>/dev/null || true
    fi

    if command -v plasmashell >/dev/null 2>&1; then
        plasmashell --version > "${info_dir}/plasma-version.txt" 2>&1 || true
    fi

    if command -v kwin_wayland >/dev/null 2>&1; then
        kwin_wayland --version > "${info_dir}/kwin-version.txt" 2>&1 || true
    elif command -v kwin_x11 >/dev/null 2>&1; then
        kwin_x11 --version > "${info_dir}/kwin-version.txt" 2>&1 || true
    fi

    sort -u "$backup_log" -o "$backup_log" 2>/dev/null || true
    sort -u "$missing_log" -o "$missing_log" 2>/dev/null || true
}

copy_system_reference() {
    local reference_root="$1"
    local path
    local -a files=(
        /etc/fstab
        /etc/hostname
        /etc/hosts
        /etc/locale.conf
        /etc/vconsole.conf
        /etc/environment
        /etc/pacman.conf
        /etc/makepkg.conf
        /etc/mkinitcpio.conf
        /etc/default/grub
    )

    for path in "${files[@]}"; do
        if [[ -r "$path" && -f "$path" ]]; then
            mkdir -p "${reference_root}$(dirname "$path")"
            cp -a -- "$path" "${reference_root}${path}"
        fi
    done
}

create_restore_readme() {
    local target="$1"
    cat > "$target" <<'README'
PROGRAMM-CONFIG-BACKUP – WIEDERHERSTELLUNG
=========================================

Empfohlen:
1. Programme wie Firefox, Tauon, Spotify, Steam, Kate und Konsole schliessen.
2. ~/scripts/program-config-backup.sh starten.
3. Im Menue „Backup wiederherstellen“ auswaehlen.
4. Danach einmal ab- und wieder anmelden.

Das Skript stellt nur Dateien unter /home/m4j0r wieder her. Die Dateien im
Ordner system-reference sind lediglich als Nachschlagekopie enthalten und
werden nicht automatisch nach /etc geschrieben.

Mitgesichert werden unter anderem:
- KDE Plasma, KWin, Fensterregeln, Shortcuts und Panel-/Desktop-Layout
- lokale Plasma-Erweiterungen, KWin-Effekte, Themes, Icons und Fonts
- Konsole, Kate, Dolphin, GTK, Kvantum und Qt-Konfigurationen
- zsh, Powerlevel10k, Shell- und Git-Konfigurationen
- Autostart und systemd-User-Units
- MangoHud, Fastfetch, Lutris und Bottles-Konfiguration
- Firefox chrome/user.js/prefs und Erweiterungslisten
- Tauon-Konfiguration, Playlists und Radio-Einstellungen
- Spotify-Prefs, Steam-Bibliothek und benutzerdefinierte Shortcuts
- Nextcloud-Desktop-Client-Konfiguration
- Paket-, Flatpak-, Font- und Service-Listen

Bewusst NICHT gesichert werden:
- Browser-Passwoerter, Cookies, Verlauf und Lesezeichen-Datenbanken
- KWallet/Keyring und gespeicherte Zugangsdaten
- Steam-Login- und Account-Tokens
- private SSH-Schluessel, insbesondere ~/.ssh/unraid_conky
- Wine-/Proton-Prefixe, Spiele, Downloads, Caches und Logs
- komplette Programm-Datenbanken oder persoenliche Dokumente

Wichtig fuer eine vollstaendige Neuinstallation:
Private SSH-Schluessel und Passwortspeicher separat und verschluesselt sichern.
Ohne ~/.ssh/unraid_conky muss der SSH-Zugriff fuer die Unraid-Conky-Skripte neu
eingerichtet werden.

Pakete nach einer CachyOS/Arch-Neuinstallation:
  sudo pacman -S --needed - < backup-info/pacman-native-explicit.txt

AUR-/Fremdpakete anschliessend mit einem AUR-Helper anhand von
backup-info/pacman-foreign-explicit.txt installieren.
README
}

get_backups() {
    find "$BACKUP_ROOT" -maxdepth 1 -type f \
        \( -name 'program-config-backup-*.tar.zst' -o -name 'program-config-backup-*.tar.gz' \) \
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
    for checksum in "$BACKUP_ROOT"/program-config-backup-*.tar.zst.sha256 \
                    "$BACKUP_ROOT"/program-config-backup-*.tar.gz.sha256; do
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

    cleanup_dir="$(mktemp -d "${BACKUP_ROOT}/.program-config-backup-tmp.XXXXXX")"
    local payload="${cleanup_dir}/payload"
    local info_dir="${cleanup_dir}/backup-info"
    local reference_root="${cleanup_dir}/system-reference"

    mkdir -p "$payload" "$info_dir" "$reference_root"
    backup_log="${info_dir}/backed-up-paths.txt"
    missing_log="${info_dir}/not-found-paths.txt"
    : > "$backup_log"
    : > "$missing_log"

    copy_user_configs "$payload"
    copy_system_reference "$reference_root"
    write_system_info "$info_dir"
    create_restore_readme "${cleanup_dir}/RESTORE-README.txt"
    printf '%s\n' "$reason" > "${info_dir}/backup-reason.txt"

    (
        cd "$cleanup_dir"
        find payload backup-info system-reference RESTORE-README.txt -type f -print0 \
            | sort -z \
            | xargs -0 sha256sum > MANIFEST.sha256
    )

    if command -v zstd >/dev/null 2>&1; then
        extension="tar.zst"
        archive="${BACKUP_ROOT}/program-config-backup-${timestamp}-${hostname_safe}.${extension}"
        tar --zstd -cpf "$archive" -C "$cleanup_dir" \
            payload backup-info system-reference RESTORE-README.txt MANIFEST.sha256
    else
        extension="tar.gz"
        archive="${BACKUP_ROOT}/program-config-backup-${timestamp}-${hostname_safe}.${extension}"
        tar -czpf "$archive" -C "$cleanup_dir" \
            payload backup-info system-reference RESTORE-README.txt MANIFEST.sha256
    fi

    chmod 600 "$archive"
    sha256sum "$archive" > "${archive}.sha256"
    chmod 600 "${archive}.sha256"

    rm -rf -- "$cleanup_dir"
    cleanup_dir=""
    backup_log=""
    missing_log=""

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
        printf 'Noch keine Programm-Config-Backups vorhanden.\n'
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
        printf 'Noch keine Programm-Config-Backups vorhanden.\n'
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
    printf '\nBitte laufende Programme vor dem Restore schliessen.\n'
    printf 'Vorhandene Konfigurationsdateien werden ueberschrieben.\n'
    printf 'Zusaetzliche Dateien werden nicht geloescht.\n\n'

    local confirmation
    read -r -p 'Wiederherstellung wirklich starten? [j/N]: ' confirmation
    [[ "$confirmation" =~ ^[jJyY]$ ]] || {
        printf 'Wiederherstellung abgebrochen.\n'
        return 0
    }

    printf '\nErstelle zuerst ein Sicherheitsbackup des aktuellen Zustands ...\n'
    create_backup "pre-restore-$(basename "$archive")" "no"

    cleanup_dir="$(mktemp -d "${BACKUP_ROOT}/.program-config-restore-tmp.XXXXXX")"
    tar -xpf "$archive" -C "$cleanup_dir"

    if [[ ! -d "${cleanup_dir}/payload/home/m4j0r" ]]; then
        printf '\nUngueltiges Backup: payload/home/m4j0r fehlt.\n' >&2
        return 1
    fi

    if [[ -f "${cleanup_dir}/MANIFEST.sha256" ]]; then
        printf '\nPruefe interne Dateipruefsummen ...\n'
        (cd "$cleanup_dir" && sha256sum -c MANIFEST.sha256)
    fi

    printf '\nStelle Benutzer- und Programmkonfigurationen wieder her ...\n'

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

    prune_old_backups

    printf '\nWiederherstellung abgeschlossen.\n'
    printf 'Bitte einmal ab- und wieder anmelden, bevor du alle Programme startest.\n'
    printf 'Dateien unter system-reference wurden nicht automatisch nach /etc kopiert.\n'
}

show_backup_contents() {
    local archive=""
    select_backup archive || return 0

    printf '\nInhalt von %s:\n\n' "$(basename "$archive")"
    tar -tf "$archive" | sed \
        -e 's#^payload/home/m4j0r/#~/#' \
        -e 's#^system-reference/#SYSTEM-REFERENZ: /#'
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
    printf '1) Neues Konfigurationsbackup erstellen\n'
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
