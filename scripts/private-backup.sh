#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_VERSION="2026-07-10.4"
readonly BACKUP_ROOT="${HOME}/Backup/Private"
readonly INSTALLED_SCRIPT="${HOME}/scripts/private-backup.sh"
readonly KEEP_BACKUPS=10
readonly PREFIX="private-backup"
readonly AUTO_CONFIG_DIR="${HOME}/.config/m4j0r-backup"
readonly AUTO_RECIPIENT_FILE="${AUTO_CONFIG_DIR}/private-recipient"
readonly ROOT_EXPORT_HELPER="/usr/local/libexec/m4j0r-private-root-export"
readonly ROOT_EXPORT_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/m4j0r-private-root-files.tar"

umask 077

declare -a USER_PATHS=(
    "${HOME}/.ssh"
    "${HOME}/.gnupg"
    "${HOME}/.password-store"
    "${HOME}/.git-credentials"
    "${HOME}/.config/gh/hosts.yml"
    "${HOME}/.config/rclone/rclone.conf"
    "${HOME}/.config/Nextcloud/nextcloud.cfg"
    "${HOME}/.config/remmina"
    "${HOME}/.config/filezilla"
    "${HOME}/.local/share/kwalletd"
    "${HOME}/.local/share/keyrings"
    "${HOME}/.config/kwalletrc"
    "${HOME}/.pki/nssdb"
)

declare -a ROOT_PATHS=(
    "/etc/NetworkManager/system-connections"
    "/etc/wireguard"
    "/etc/openvpn"
    "/etc/credstore"
    "/etc/credstore.encrypted"
)

RUNTIME_DIR=""
WORK_DIR=""

cleanup() {
    if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
        rm -rf -- "${WORK_DIR}"
    fi
}
trap cleanup EXIT INT TERM

die() {
    printf 'FEHLER: %s\n' "$*" >&2
    exit 1
}

pause() {
    printf '\nEnter drücken, um zum Menü zurückzukehren ...'
    read -r
}

require_commands() {
    local missing=()
    local cmd
    for cmd in tar gpg sha256sum find sort mktemp; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if ((${#missing[@]} > 0)); then
        printf 'Fehlende Programme: %s\n' "${missing[*]}" >&2
        printf 'Unter CachyOS installieren mit:\n  sudo pacman -S gnupg tar coreutils findutils\n' >&2
        exit 1
    fi
}

init_dirs() {
    cleanup
    WORK_DIR=""

    mkdir -p -- "${BACKUP_ROOT}"
    chmod 700 -- "${BACKUP_ROOT}"

    RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
    WORK_DIR="$(mktemp -d "${RUNTIME_DIR%/}/private-backup.XXXXXXXX")"
    chmod 700 -- "${WORK_DIR}"
}

header() {
    clear 2>/dev/null || true
    printf '%s\n' '============================================================'
    printf '  PRIVATDATEN BACKUP & RESTORE\n'
    printf '  Version: %s\n' "${SCRIPT_VERSION}"
    printf '  Ziel: %s\n' "${BACKUP_ROOT}"
    printf '  Verschlüsselung: manuell AES-256, automatisch GPG-Empfänger\n'
    printf '  Aufbewahrung: die neuesten %d Backups\n' "${KEEP_BACKUPS}"
    printf '%s\n\n' '============================================================'
}

safe_hostname() {
    local value
    value="$(hostname 2>/dev/null || printf 'localhost')"
    value="${value//[^[:alnum:]_.-]/_}"
    printf '%s' "${value}"
}

copy_path() {
    local src="$1"
    local payload="$2"
    local dest_parent

    [[ -e "${src}" || -L "${src}" ]] || return 1

    dest_parent="${payload}$(dirname "${src}")"
    mkdir -p -- "${dest_parent}"
    cp -a -- "${src}" "${dest_parent}/"
}

discover_extra_secret_files() {
    local base file

    for base in \
        "${HOME}/.mozilla/firefox" \
        "${HOME}/.config/google-chrome" \
        "${HOME}/.config/chromium"; do
        [[ -d "${base}" ]] || continue

        while IFS= read -r -d '' file; do
            printf '%s\0' "${file}"
        done < <(
            find "${base}" -maxdepth 3 -type f \
                \( -name 'logins.json' \
                -o -name 'key4.db' \
                -o -name 'cert9.db' \
                -o -name 'pkcs11.txt' \
                -o -name 'Login Data' \
                -o -name 'Local State' \) \
                -print0 2>/dev/null
        )
    done

    while IFS= read -r -d '' file; do
        printf '%s\0' "${file}"
    done < <(
        find "${HOME}" -maxdepth 5 -type f \
            \( -iname '*.kdbx' -o -iname '*.kdb' -o -iname '*.psafe3' \) \
            -not -path "${BACKUP_ROOT}/*" \
            -print0 2>/dev/null
    )
}

write_manifest() {
    local stage="$1"
    local encryption_description="${2:-GnuPG AES-256}"
    local manifest="${stage}/BACKUP-INFO.txt"

    {
        printf 'Privatdaten-Backup\n'
        printf '===================\n\n'
        printf 'Skriptversion: %s\n' "${SCRIPT_VERSION}"
        printf 'Erstellt: %s\n' "$(date --iso-8601=seconds)"
        printf 'Benutzer: %s\n' "${USER}"
        printf 'Host: %s\n' "$(hostname)"
        printf 'Home: %s\n' "${HOME}"
        printf 'Verschlüsselung: %s\n\n' "${encryption_description}"
        printf 'Enthaltene Bereiche:\n'
        printf '%s\n' '- SSH- und GPG-Schlüssel'
        printf '%s\n' '- KWallet/GNOME-Keyring'
        printf '%s\n' '- Git-, GitHub-, rclone-, Remmina- und FileZilla-Zugangsdaten'
        printf '%s\n' '- Firefox/Chromium-Schlüsseldateien und gespeicherte Logins'
        printf '%s\n' '- KeePass-/Password-Safe-Datenbanken in üblichen Home-Pfaden'
        printf '%s\n' '- Nextcloud-Client-Zugangsdaten'
        printf '%s\n\n' '- Netzwerk-, WireGuard- und OpenVPN-Profile, sofern verfügbar'
        printf 'Wiederherstellung ausschließlich über private-backup.sh empfohlen.\n'
    } > "${manifest}"
}

collect_user_data() {
    local stage="$1"
    local payload="${stage}/payload"
    local path copied=0

    mkdir -p -- "${payload}"

    for path in "${USER_PATHS[@]}"; do
        if copy_path "${path}" "${payload}"; then
            printf '  + %s\n' "${path}"
            ((copied += 1))
        fi
    done

    while IFS= read -r -d '' path; do
        if copy_path "${path}" "${payload}"; then
            printf '  + %s\n' "${path}"
            ((copied += 1))
        fi
    done < <(discover_extra_secret_files)

    if [[ -f "${BASH_SOURCE[0]}" ]]; then
        mkdir -p -- "${payload}$(dirname "${INSTALLED_SCRIPT}")"
        cp -a -- "${BASH_SOURCE[0]}" "${payload}${INSTALLED_SCRIPT}"
        printf '  + %s\n' "${INSTALLED_SCRIPT}"
        ((copied += 1))
    fi

    printf '%d' "${copied}" > "${stage}/user-file-count"
}

collect_root_data() {
    local stage="$1"
    local run_mode="${2:-manual}"
    local root_tar="${stage}/root-files.tar"
    local -a existing=()
    local path relative

    if [[ "${run_mode}" == "auto" ]]; then
        if [[ -x "${ROOT_EXPORT_HELPER}" ]] && sudo -n "${ROOT_EXPORT_HELPER}"; then
            if [[ -s "${ROOT_EXPORT_FILE}" ]]; then
                cp -a -- "${ROOT_EXPORT_FILE}" "${root_tar}"
                rm -f -- "${ROOT_EXPORT_FILE}"
                tar -tf "${root_tar}" > "${stage}/root-paths.txt" 2>/dev/null || true
                printf '  Systemprofile wurden automatisch aufgenommen.\n'
            else
                printf '  WARNUNG: Der Root-Helfer hat keine Systemprofile geliefert.\n' >&2
            fi
        else
            printf '  WARNUNG: Systemprofile übersprungen; Root-Helfer fehlt oder sudo-Regel ist nicht aktiv.\n' >&2
        fi
        return 0
    fi

    for path in "${ROOT_PATHS[@]}"; do
        if sudo test -e "${path}" 2>/dev/null; then
            relative="${path#/}"
            existing+=("${relative}")
        fi
    done

    if ((${#existing[@]} == 0)); then
        printf '  - Keine lesbaren System-Zugangsdaten gefunden.\n'
        return 0
    fi

    printf '  Systemprofile werden mit sudo aufgenommen ...\n'
    sudo tar -C / -cpf "${root_tar}" "${existing[@]}"
    sudo chown "${USER}:$(id -gn)" "${root_tar}"
    chmod 600 "${root_tar}"

    printf '%s\n' "${existing[@]}" > "${stage}/root-paths.txt"
}

compression_mode() {
    if command -v zstd >/dev/null 2>&1; then
        printf 'zstd'
    else
        printf 'gzip'
    fi
}

encrypt_stage_symmetric() {
    local stage="$1"
    local output="$2"
    local mode="$3"
    local tmp_output="${output}.partial"

    rm -f -- "${tmp_output}"

    export GPG_TTY
    GPG_TTY="$(tty 2>/dev/null || true)"

    printf '\nJetzt wird das Verschlüsselungspasswort über GnuPG abgefragt.\n'
    printf 'WICHTIG: Dieses Passwort kann nicht zurückgesetzt werden.\n\n'

    if [[ "${mode}" == "zstd" ]]; then
        if ! tar -C "${stage}" --zstd -cf - . |
            gpg --symmetric \
                --cipher-algo AES256 \
                --compress-algo none \
                --output "${tmp_output}"; then
            rm -f -- "${tmp_output}"
            return 1
        fi
    else
        if ! tar -C "${stage}" -czf - . |
            gpg --symmetric \
                --cipher-algo AES256 \
                --compress-algo none \
                --output "${tmp_output}"; then
            rm -f -- "${tmp_output}"
            return 1
        fi
    fi

    mv -- "${tmp_output}" "${output}"
    chmod 600 -- "${output}"
}

encrypt_stage_recipient() {
    local stage="$1"
    local output="$2"
    local mode="$3"
    local recipient="$4"
    local tmp_output="${output}.partial"

    rm -f -- "${tmp_output}"

    if [[ "${mode}" == "zstd" ]]; then
        if ! tar -C "${stage}" --zstd -cf - . |
            gpg --batch --yes --trust-model always \
                --compress-algo none \
                --recipient "${recipient}" \
                --encrypt \
                --output "${tmp_output}"; then
            rm -f -- "${tmp_output}"
            return 1
        fi
    else
        if ! tar -C "${stage}" -czf - . |
            gpg --batch --yes --trust-model always \
                --compress-algo none \
                --recipient "${recipient}" \
                --encrypt \
                --output "${tmp_output}"; then
            rm -f -- "${tmp_output}"
            return 1
        fi
    fi

    mv -- "${tmp_output}" "${output}"
    chmod 600 -- "${output}"
}

list_backup_files() {
    find "${BACKUP_ROOT}" -maxdepth 1 -type f \
        \( -name "${PREFIX}-*.tar.zst.gpg" -o -name "${PREFIX}-*.tar.gz.gpg" \) \
        -printf '%T@ %p\n' |
        sort -nr |
        cut -d' ' -f2-
}

cleanup_old_backups() {
    local -a backups=()
    local old

    mapfile -t backups < <(list_backup_files)

    if ((${#backups[@]} <= KEEP_BACKUPS)); then
        return 0
    fi

    for old in "${backups[@]:KEEP_BACKUPS}"; do
        rm -f -- "${old}" "${old}.sha256"
        printf 'Altes Backup gelöscht: %s\n' "$(basename "${old}")"
    done
}

create_backup() {
    local run_mode="${1:-manual}"
    local timestamp host mode archive stage count recipient="" encryption_description

    init_dirs
    stage="${WORK_DIR}/stage"
    mkdir -p -- "${stage}"

    timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
    host="$(safe_hostname)"
    mode="$(compression_mode)"

    if [[ "${mode}" == "zstd" ]]; then
        archive="${BACKUP_ROOT}/${PREFIX}-${timestamp}-${host}.tar.zst.gpg"
    else
        archive="${BACKUP_ROOT}/${PREFIX}-${timestamp}-${host}.tar.gz.gpg"
    fi

    header
    printf 'Persönliche und geheime Dateien werden gesammelt:\n\n'
    collect_user_data "${stage}"
    collect_root_data "${stage}" "${run_mode}"

    if [[ "${run_mode}" == "auto" ]]; then
        [[ -s "${AUTO_RECIPIENT_FILE}" ]] || die "Automatischer GPG-Empfänger fehlt: ${AUTO_RECIPIENT_FILE}"
        recipient="$(tr -d '[:space:]' < "${AUTO_RECIPIENT_FILE}")"
        [[ -n "${recipient}" ]] || die "Die Empfängerdatei ist leer: ${AUTO_RECIPIENT_FILE}"
        gpg --batch --list-keys "${recipient}" >/dev/null 2>&1 || die "Der GPG-Empfänger ${recipient} ist nicht im Schlüsselbund vorhanden."
        encryption_description="GPG Public-Key an ${recipient}"
    else
        encryption_description="GnuPG symmetrisch AES-256"
    fi

    write_manifest "${stage}" "${encryption_description}"

    count="$(cat "${stage}/user-file-count" 2>/dev/null || printf '0')"
    if [[ "${count}" == "0" && ! -f "${stage}/root-files.tar" ]]; then
        die "Es wurden keine zu sichernden Dateien gefunden."
    fi

    if [[ "${run_mode}" == "auto" ]]; then
        encrypt_stage_recipient "${stage}" "${archive}" "${mode}" "${recipient}"
    else
        encrypt_stage_symmetric "${stage}" "${archive}" "${mode}"
    fi

    (
        cd "${BACKUP_ROOT}"
        sha256sum "$(basename "${archive}")"
    ) > "${archive}.sha256.tmp"
    mv -- "${archive}.sha256.tmp" "${archive}.sha256"
    chmod 600 -- "${archive}.sha256"

    cleanup_old_backups

    printf '\nBackup erfolgreich erstellt:\n  %s\n' "${archive}"
    printf 'Prüfsumme:\n  %s\n' "${archive}.sha256"
    if [[ "${run_mode}" == "manual" ]]; then
        printf '\nBewahre das Passwort getrennt und sicher auf.\n'
    else
        printf '\nAutomatische Verschlüsselung für Empfänger: %s\n' "${recipient}"
    fi
}

select_backup() {
    local -n result_ref="$1"
    local -a backups=()
    local i choice

    mapfile -t backups < <(list_backup_files)

    if ((${#backups[@]} == 0)); then
        printf 'Keine verschlüsselten Backups gefunden.\n'
        return 1
    fi

    printf 'Vorhandene Backups:\n\n'
    for i in "${!backups[@]}"; do
        printf '%2d) %s\n' "$((i + 1))" "$(basename "${backups[$i]}")"
    done

    printf '\nAuswahl: '
    read -r choice

    [[ "${choice}" =~ ^[0-9]+$ ]] || {
        printf 'Ungültige Auswahl.\n'
        return 1
    }

    ((choice >= 1 && choice <= ${#backups[@]})) || {
        printf 'Ungültige Auswahl.\n'
        return 1
    }

    result_ref="${backups[$((choice - 1))]}"
}

verify_checksum() {
    local archive="$1"
    local checksum="${archive}.sha256"

    [[ -f "${checksum}" ]] || {
        printf 'Keine SHA256-Datei vorhanden.\n'
        return 1
    }

    (
        cd "${BACKUP_ROOT}"
        sha256sum -c "$(basename "${checksum}")"
    )
}

decrypt_backup() {
    local archive="$1"
    local output="$2"

    export GPG_TTY
    GPG_TTY="$(tty 2>/dev/null || true)"

    gpg --output "${output}" --decrypt "${archive}"
    chmod 600 -- "${output}"
}

extract_plain_archive() {
    local archive="$1"
    local destination="$2"

    mkdir -p -- "${destination}"

    case "${archive}" in
        *.tar.zst)
            tar -C "${destination}" --zstd -xpf "${archive}"
            ;;
        *.tar.gz)
            tar -C "${destination}" -xzpf "${archive}"
            ;;
        *)
            die "Unbekanntes internes Archivformat: ${archive}"
            ;;
    esac
}

restore_backup() {
    local archive plain extract_dir payload_home answer

    init_dirs
    header
    select_backup archive || return 0

    printf '\nPrüfsumme wird geprüft ...\n'
    verify_checksum "${archive}" || die "Prüfsummenprüfung fehlgeschlagen."

    printf '\nACHTUNG: Vorhandene Schlüssel und Zugangsdaten können überschrieben werden.\n'
    printf 'Vorher sollte ein aktuelles Privatdaten-Backup erstellt worden sein.\n'
    printf 'Wirklich wiederherstellen? [j/N]: '
    read -r answer
    [[ "${answer,,}" == "j" || "${answer,,}" == "ja" ]] || {
        printf 'Wiederherstellung abgebrochen.\n'
        return 0
    }

    if [[ "${archive}" == *.tar.zst.gpg ]]; then
        plain="${WORK_DIR}/decrypted.tar.zst"
    else
        plain="${WORK_DIR}/decrypted.tar.gz"
    fi
    extract_dir="${WORK_DIR}/extracted"

    printf '\nPasswort zum Entschlüsseln eingeben ...\n'
    decrypt_backup "${archive}" "${plain}"
    extract_plain_archive "${plain}" "${extract_dir}"
    rm -f -- "${plain}"

    payload_home="${extract_dir}/payload${HOME}"
    if [[ -d "${payload_home}" ]]; then
        printf '\nBenutzerdaten werden wiederhergestellt ...\n'
        if command -v rsync >/dev/null 2>&1; then
            rsync -a -- "${payload_home}/" "${HOME}/"
        else
            cp -a -- "${payload_home}/." "${HOME}/"
        fi
    fi

    [[ -d "${HOME}/.ssh" ]] && chmod 700 "${HOME}/.ssh"
    [[ -d "${HOME}/.gnupg" ]] && chmod 700 "${HOME}/.gnupg"

    if [[ -f "${extract_dir}/root-files.tar" ]]; then
        printf '\nSystemweite Netzwerk- und VPN-Profile ebenfalls wiederherstellen? [j/N]: '
        read -r answer
        if [[ "${answer,,}" == "j" || "${answer,,}" == "ja" ]]; then
            sudo tar -C / -xpf "${extract_dir}/root-files.tar"
            printf 'Systemweite Profile wurden wiederhergestellt.\n'
        fi
    fi

    printf '\nWiederherstellung abgeschlossen.\n'
    printf 'Danach einmal ab- und wieder anmelden; Netzwerk/VPN bei Bedarf neu starten.\n'
}

show_backups() {
    local -a backups=()
    local file size

    mapfile -t backups < <(list_backup_files)

    if ((${#backups[@]} == 0)); then
        printf 'Keine Backups vorhanden.\n'
        return 0
    fi

    printf '%-66s %12s\n' 'Backup' 'Größe'
    printf '%-66s %12s\n' '------' '-----'

    for file in "${backups[@]}"; do
        size="$(du -h "${file}" | awk '{print $1}')"
        printf '%-66s %12s\n' "$(basename "${file}")" "${size}"
    done
}

show_contents() {
    local archive plain

    init_dirs
    header
    select_backup archive || return 0

    verify_checksum "${archive}" || die "Prüfsummenprüfung fehlgeschlagen."

    if [[ "${archive}" == *.tar.zst.gpg ]]; then
        plain="${WORK_DIR}/decrypted.tar.zst"
    else
        plain="${WORK_DIR}/decrypted.tar.gz"
    fi

    printf '\nPasswort zum Anzeigen des Inhalts eingeben ...\n'
    decrypt_backup "${archive}" "${plain}"

    printf '\nArchivinhalt:\n\n'
    case "${plain}" in
        *.tar.zst) tar --zstd -tf "${plain}" ;;
        *.tar.gz)  tar -tzf "${plain}" ;;
    esac

    rm -f -- "${plain}"
}

manual_cleanup() {
    local before after

    before="$(list_backup_files | wc -l)"
    cleanup_old_backups
    after="$(list_backup_files | wc -l)"

    if [[ "${before}" == "${after}" ]]; then
        printf 'Keine alten Backups zu löschen. Maximal %d werden behalten.\n' "${KEEP_BACKUPS}"
    else
        printf '%d alte Backups wurden gelöscht.\n' "$((before - after))"
    fi
}

main_menu() {
    local choice

    require_commands
    mkdir -p -- "${BACKUP_ROOT}"
    chmod 700 -- "${BACKUP_ROOT}"

    while true; do
        header
        printf '1) Neues verschlüsseltes Privatdaten-Backup erstellen\n'
        printf '2) Backup wiederherstellen\n'
        printf '3) Vorhandene Backups anzeigen\n'
        printf '4) Inhalt eines Backups anzeigen\n'
        printf '5) Alte Backups jetzt bereinigen\n'
        printf '0) Beenden\n\n'
        printf 'Auswahl: '
        read -r choice

        case "${choice}" in
            1) create_backup; pause ;;
            2) restore_backup; pause ;;
            3) header; show_backups; pause ;;
            4) show_contents; pause ;;
            5) header; manual_cleanup; pause ;;
            0) exit 0 ;;
            *) printf 'Ungültige Auswahl.\n'; sleep 1 ;;
        esac
    done
}

case "${1:-}" in
    --backup|--auto)
        require_commands
        mkdir -p -- "${BACKUP_ROOT}"
        chmod 700 -- "${BACKUP_ROOT}"
        create_backup auto
        exit 0
        ;;
    --help|-h)
        printf 'Aufruf: %s [--backup]\n' "$0"
        printf 'Ohne Argument startet das interaktive Menü.\n'
        exit 0
        ;;
esac

main_menu
