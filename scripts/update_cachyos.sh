#!/usr/bin/env bash
# CachyOS Update Script – optimierte Version
#
# Aktualisiert in sinnvoller Reihenfolge:
#   1. optional CachyOS-/Arch-Mirrors
#   2. offizielle Repository-Pakete mit pacman
#   3. ausschließlich AUR-Pakete mit paru/yay
#   4. Flatpaks
#   5. Firmware-Verfügbarkeit mit fwupd
#
# Aufruf:
#   ./update_cachyos.sh
#   ./update_cachyos.sh --refresh-mirrors
#   ./update_cachyos.sh --no-aur --no-firmware

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

# ----------------------------- Einstellungen -----------------------------
KEEP_GOING_AUR=true
REFRESH_MIRRORS=false
DO_AUR=true
DO_FLATPAK=true
DO_FIRMWARE=true

# ------------------------------- Darstellung -----------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_CYAN=$'\033[1;36m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'
  C_DIM=$'\033[2m'
  C_RESET=$'\033[0m'
else
  C_CYAN=''
  C_GREEN=''
  C_YELLOW=''
  C_RED=''
  C_DIM=''
  C_RESET=''
fi

say()  { printf '\n%s==> %s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[FEHLER]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'USAGE'
CachyOS vollständig aktualisieren.

Optionen:
  --refresh-mirrors   CachyOS- und Arch-Mirrors vorher neu bewerten
  --no-aur            AUR-Pakete nicht aktualisieren
  --no-flatpak        Flatpaks nicht aktualisieren
  --no-firmware       Firmware-Updates nicht prüfen
  -h, --help          Diese Hilfe anzeigen

Hinweis:
  Firmware wird nur geprüft, nicht automatisch installiert.
USAGE
}

# ------------------------------- Argumente -------------------------------
while (($#)); do
  case "$1" in
    --refresh-mirrors) REFRESH_MIRRORS=true ;;
    --no-aur)          DO_AUR=false ;;
    --no-flatpak)      DO_FLATPAK=false ;;
    --no-firmware)     DO_FIRMWARE=false ;;
    -h|--help)         usage; exit 0 ;;
    *)                 die "Unbekannte Option: $1 (siehe --help)" ;;
  esac
  shift
done

# --------------------------- Status und Aufräumen -------------------------
declare -A STATUS=(
  [Mirrors]="nicht angefordert"
  [System]="ausstehend"
  [AUR]="übersprungen"
  [Flatpak]="übersprungen"
  [Firmware]="übersprungen"
)

OPTIONAL_FAILURES=0
SUDO_KEEPALIVE_PID=''
START_SECONDS=$SECONDS
PACMAN_LOG='/var/log/pacman.log'
PACMAN_LOG_START=0

cleanup() {
  if [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ------------------------------ Vorprüfung -------------------------------
preflight() {
  ((EUID != 0)) || die "Bitte als normaler Benutzer starten, nicht mit sudo. Das Skript fragt selbst nach dem Passwort."

  have sudo   || die "sudo wurde nicht gefunden."
  have pacman || die "pacman wurde nicht gefunden – dieses Skript ist nur für CachyOS/Arch geeignet."

  if [[ -e /var/lib/pacman/db.lck ]]; then
    die "Pacmans Datenbank ist gesperrt (/var/lib/pacman/db.lck). Prüfe zuerst, ob bereits ein Paketmanager läuft."
  fi

  # Verhindert zwei parallele Starts dieses Skripts.
  if have flock; then
    local lock_file="${XDG_RUNTIME_DIR:-/tmp}/cachyos-update-${UID}.lock"
    exec 9>"$lock_file"
    flock -n 9 || die "Das Update-Skript läuft bereits in einem anderen Terminal."
  fi

  [[ -r "$PACMAN_LOG" ]] && PACMAN_LOG_START=$(wc -l < "$PACMAN_LOG")

  say "Administratorrechte prüfen …"
  sudo -v || die "sudo-Authentifizierung fehlgeschlagen."

  # Hält das sudo-Ticket während längerer AUR-Builds gültig.
  (
    while sleep 45; do
      sudo -n true || exit 0
    done
  ) 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
}

# ------------------------------ Updates ----------------------------------
refresh_mirrors() {
  if ! $REFRESH_MIRRORS; then
    return 0
  fi

  say "CachyOS- und Arch-Mirrors neu bewerten …"
  if ! have cachyos-rate-mirrors; then
    STATUS[Mirrors]="Tool fehlt"
    ((OPTIONAL_FAILURES += 1))
    warn "cachyos-rate-mirrors wurde nicht gefunden; vorhandene Mirrorlisten bleiben unverändert."
    return 0
  fi

  if sudo cachyos-rate-mirrors; then
    STATUS[Mirrors]="OK"
    ok "Mirrorlisten wurden aktualisiert."
  else
    STATUS[Mirrors]="Fehler"
    ((OPTIONAL_FAILURES += 1))
    warn "Mirror-Refresh fehlgeschlagen; Update wird mit den vorhandenen Listen versucht."
  fi
}

update_system() {
  say "Offizielle CachyOS-/Arch-Pakete aktualisieren …"

  # Absichtlich nur ein vollständiges Repository-Upgrade.
  # Keyrings werden dabei regulär als Systempakete mit aktualisiert.
  if sudo pacman -Syu; then
    STATUS[System]="OK"
    ok "Systempakete sind aktuell."
  else
    STATUS[System]="Fehler"
    err "Das Systemupdate ist fehlgeschlagen. AUR und Flatpak werden nicht mehr gestartet."
    warn "Bei Mirrorfehlern: erneut mit --refresh-mirrors starten."
    warn "Bei Signatur-/Keyringfehlern: CachyOS Hello → Apps/Tweaks → Reset keyrings verwenden."
    return 1
  fi
}

update_aur() {
  if ! $DO_AUR; then
    STATUS[AUR]="deaktiviert"
    return 0
  fi

  local helper=''
  if have paru; then
    helper='paru'
  elif have yay; then
    helper='yay'
  else
    STATUS[AUR]="kein Helper"
    warn "Kein AUR-Helper (paru/yay) gefunden; AUR wurde übersprungen."
    return 0
  fi

  say "Ausschließlich AUR-Pakete mit $helper aktualisieren …"

  # -Sua aktualisiert nur AUR-Pakete. Die Repository-Pakete wurden bereits
  # vollständig durch pacman -Syu aktualisiert und werden nicht doppelt geprüft.
  if "$helper" -Sua; then
    STATUS[AUR]="OK ($helper)"
    ok "AUR-Prüfung abgeschlossen."
  else
    STATUS[AUR]="Fehler ($helper)"
    ((OPTIONAL_FAILURES += 1))
    if $KEEP_GOING_AUR; then
      warn "AUR-Update hatte Fehler; die übrigen optionalen Schritte laufen weiter."
    else
      return 1
    fi
  fi
}

update_flatpak() {
  if ! $DO_FLATPAK; then
    STATUS[Flatpak]="deaktiviert"
    return 0
  fi

  if ! have flatpak; then
    STATUS[Flatpak]="nicht installiert"
    return 0
  fi

  say "Flatpaks aktualisieren …"
  # Ohne --user/--system werden die Standard-Systeminstallation und die
  # benutzerspezifische Installation berücksichtigt.
  if flatpak update -y; then
    STATUS[Flatpak]="OK"
    ok "Flatpak-Prüfung abgeschlossen."
  else
    STATUS[Flatpak]="Fehler"
    ((OPTIONAL_FAILURES += 1))
    warn "Flatpak-Update ist fehlgeschlagen."
  fi
}

fwupd_success_or_no_action() {
  local rc
  set +e
  "$@"
  rc=$?
  set -e
  [[ $rc -eq 0 || $rc -eq 2 ]]
}

check_firmware() {
  if ! $DO_FIRMWARE; then
    STATUS[Firmware]="deaktiviert"
    return 0
  fi

  if ! have fwupdmgr; then
    STATUS[Firmware]="nicht installiert"
    return 0
  fi

  say "Firmware-Metadaten und verfügbare Updates prüfen …"

  if ! fwupd_success_or_no_action fwupdmgr refresh; then
    STATUS[Firmware]="Refresh-Fehler"
    ((OPTIONAL_FAILURES += 1))
    warn "Firmware-Metadaten konnten nicht aktualisiert werden."
    return 0
  fi

  if fwupd_success_or_no_action fwupdmgr get-updates; then
    STATUS[Firmware]="geprüft"
    ok "Firmware-Prüfung abgeschlossen. Gefundene Updates werden nicht automatisch installiert."
  else
    STATUS[Firmware]="Prüffehler"
    ((OPTIONAL_FAILURES += 1))
    warn "Firmware-Updates konnten nicht abgefragt werden."
  fi
}

# -------------------------- Neustart-Erkennung ---------------------------
reboot_recommended() {
  [[ -r "$PACMAN_LOG" ]] || return 1

  local first_new_line=$((PACMAN_LOG_START + 1))
  local package

  while IFS= read -r package; do
    case "$package" in
      amd-ucode|intel-ucode|systemd|glibc)
        return 0
        ;;
      linux|linux-lts|linux-zen|linux-hardened|linux-cachyos|linux-cachyos-*)
        # Reine Header-/API-Pakete benötigen allein keinen Neustart.
        [[ "$package" == *-headers || "$package" == linux-api-headers ]] || return 0
        ;;
    esac
  done < <(
    tail -n +"$first_new_line" "$PACMAN_LOG" 2>/dev/null |
      awk '$2 == "[ALPM]" && ($3 == "upgraded" || $3 == "installed") {print $4}'
  )

  return 1
}

summary() {
  local duration=$((SECONDS - START_SECONDS))

  say "Zusammenfassung"
  printf '  %-10s %s\n' "Mirrors:"  "${STATUS[Mirrors]}"
  printf '  %-10s %s\n' "System:"   "${STATUS[System]}"
  printf '  %-10s %s\n' "AUR:"      "${STATUS[AUR]}"
  printf '  %-10s %s\n' "Flatpak:"  "${STATUS[Flatpak]}"
  printf '  %-10s %s\n' "Firmware:" "${STATUS[Firmware]}"
  printf '  %-10s %ss\n' "Dauer:"    "$duration"

  if reboot_recommended; then
    printf '\n%sNeustart empfohlen:%s Kernel, Microcode oder zentrale Systemkomponenten wurden aktualisiert.\n' \
      "$C_YELLOW" "$C_RESET"
  else
    printf '\n%sKein offensichtlicher Neustartbedarf erkannt.%s\n' "$C_DIM" "$C_RESET"
  fi

  if ((OPTIONAL_FAILURES > 0)); then
    warn "$OPTIONAL_FAILURES optionaler Schritt bzw. optionale Schritte hatten Fehler. Das Systemupdate selbst war erfolgreich."
    return 2
  fi

  ok "Alles abgeschlossen."
}

# -------------------------------- Main -----------------------------------
preflight
refresh_mirrors
update_system
update_aur
update_flatpak
check_firmware
summary
