#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

error_report() {
    local rc=$?
    printf 'FEHLER: GPG-Einrichtung in Zeile %d fehlgeschlagen (Code %d).\n' \
        "${BASH_LINENO[0]:-${LINENO}}" "${rc}" >&2
    exit "${rc}"
}
trap error_report ERR

readonly SCRIPT_VERSION="2026-07-10.3"
readonly KEY_UID='m4j0r Automatic Backup <backup@m4j0r.one>'
readonly CONFIG_DIR="${HOME}/.config/m4j0r-backup"
readonly RECIPIENT_FILE="${CONFIG_DIR}/private-recipient"
readonly PUBLIC_KEY_FILE="${CONFIG_DIR}/private-backup-public.asc"
readonly RECOVERY_DIR="${HOME}/Backup/Private-Recovery"

command -v gpg >/dev/null 2>&1 || {
    printf 'GnuPG fehlt. Installieren: sudo pacman -S gnupg\n' >&2
    exit 1
}

mkdir -p -- "${CONFIG_DIR}" "${RECOVERY_DIR}"
chmod 700 -- "${CONFIG_DIR}" "${RECOVERY_DIR}"

export GPG_TTY
gpg_tty="$(tty 2>/dev/null || true)"
GPG_TTY="${gpg_tty}"
[[ -n "${GPG_TTY}" ]] && gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true

fingerprint="$(
    gpg --batch --with-colons --list-keys "${KEY_UID}" 2>/dev/null |
        awk -F: '$1=="fpr" {print $10; exit}' || true
)"

if [[ -z "${fingerprint}" ]]; then
    printf '\nEin eigener GPG-Schlüssel für automatische Privat-Backups wird erstellt.\n'
    printf 'In der Pinentry-Abfrage ein starkes Wiederherstellungspasswort setzen.\n\n'
    gpg --pinentry-mode ask --quick-generate-key "${KEY_UID}" rsa3072 cert 0
    fingerprint="$(gpg --batch --with-colons --list-keys "${KEY_UID}" | awk -F: '$1=="fpr" {print $10; exit}')"
    [[ -n "${fingerprint}" ]] || {
        printf 'Fingerabdruck konnte nicht ermittelt werden.\n' >&2
        exit 1
    }
fi

if ! gpg --batch --with-colons --list-keys "${fingerprint}" |
    awk -F: '$1=="sub" && $12 ~ /e/ {found=1} END {exit !found}'; then
    printf 'Ein Verschlüsselungs-Unterschlüssel wird ergänzt.\n'
    gpg --pinentry-mode ask --quick-add-key "${fingerprint}" rsa3072 encr 0
fi

secret_file="${RECOVERY_DIR}/private-backup-secret-key-${fingerprint}.asc"
public_recovery="${RECOVERY_DIR}/private-backup-public-key-${fingerprint}.asc"
ownertrust_file="${RECOVERY_DIR}/private-backup-ownertrust-${fingerprint}.txt"

workdir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/m4j0r-gpg-setup.XXXXXXXX")"
trap 'rm -rf -- "${workdir}"' EXIT INT TERM

recipient_tmp="${workdir}/private-recipient"
public_tmp="${workdir}/private-backup-public.asc"
secret_tmp="${workdir}/private-backup-secret.asc"
public_recovery_tmp="${workdir}/private-backup-public-recovery.asc"
ownertrust_tmp="${workdir}/private-backup-ownertrust.txt"

printf '%s\n' "${fingerprint}" > "${recipient_tmp}"
gpg --batch --yes --armor --output "${public_tmp}" --export "${fingerprint}"

printf '\nDer geheime Wiederherstellungsschlüssel wird exportiert.\n'
printf 'Dieser Export bleibt durch dein GPG-Schlüsselpasswort geschützt.\n\n'
gpg --pinentry-mode ask --yes --armor --output "${secret_tmp}" --export-secret-keys "${fingerprint}"
gpg --batch --yes --armor --output "${public_recovery_tmp}" --export "${fingerprint}"
gpg --export-ownertrust | awk -F: -v fpr="${fingerprint}" '$1==fpr {print}' > "${ownertrust_tmp}" || true

[[ -s "${secret_tmp}" ]] || {
    printf 'Der geheime Wiederherstellungsschlüssel wurde nicht exportiert.\n' >&2
    exit 1
}

plain_test="${workdir}/plain.txt"
encrypted_test="${workdir}/plain.txt.gpg"
printf 'm4j0r backup encryption test\n' > "${plain_test}"
gpg --batch --yes --trust-model always \
    --recipient "${fingerprint}" \
    --encrypt \
    --output "${encrypted_test}" \
    "${plain_test}"
[[ -s "${encrypted_test}" ]] || {
    printf 'Testverschlüsselung fehlgeschlagen.\n' >&2
    exit 1
}

install -m 600 "${recipient_tmp}" "${RECIPIENT_FILE}"
install -m 600 "${public_tmp}" "${PUBLIC_KEY_FILE}"
install -m 600 "${secret_tmp}" "${secret_file}"
install -m 600 "${public_recovery_tmp}" "${public_recovery}"
install -m 600 "${ownertrust_tmp}" "${ownertrust_file}"

printf '\nGPG-Automatik ist vollständig eingerichtet.\n'
printf 'Version: %s\n' "${SCRIPT_VERSION}"
printf 'Empfänger: %s\n' "${fingerprint}"
printf 'Wiederherstellungsschlüssel: %s\n' "${secret_file}"
printf '\nSchlüsseldatei und Passwort niemals verlieren.\n'
