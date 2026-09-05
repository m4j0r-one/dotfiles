#!/usr/bin/env bash
# CachyOS Clean Script – sichere und optimierte Version
#
# Bereinigt gezielt:
#   1. alte Pacman-Paketversionen mit paccache
#   2. nicht mehr benötigte Abhängigkeiten (nach Bestätigung)
#   3. AUR-Buildartefakte von paru/yay
#   4. ungenutzte Flatpak-Runtimes und Erweiterungen
#   5. archivierte systemd-Journale
#   6. Benutzer-Thumbnails
#   7. alte, eindeutig benannte Test-/Backup-Dateien in festen Benutzerpfaden
#
# Beispiele:
#   ./clean_cachyos.sh
#   ./clean_cachyos.sh --yes
#   ./clean_cachyos.sh --keep 2 --journal-age 7d
#   ./clean_cachyos.sh --aur-all
#   ./clean_cachyos.sh --backup-age 7
#   ./clean_cachyos.sh --dry-run

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

# ----------------------------- Einstellungen -----------------------------
KEEP_INSTALLED=3
KEEP_UNINSTALLED=1
JOURNAL_AGE='14d'
BACKUP_MIN_DAYS=7

DO_ORPHANS=true
DO_AUR_CACHE=true
DO_FLATPAK=true
DO_JOURNAL=true
DO_THUMBNAILS=true
DO_BACKUPS=true

AUR_ALL=false
ASSUME_YES=false
DRY_RUN=false

# ------------------------------- Darstellung -----------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_MAGENTA=$'\033[1;35m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'
  C_CYAN=$'\033[1;36m'
  C_DIM=$'\033[2m'
  C_RESET=$'\033[0m'
else
  C_MAGENTA=''
  C_GREEN=''
  C_YELLOW=''
  C_RED=''
  C_CYAN=''
  C_DIM=''
  C_RESET=''
fi

say()  { printf '\n%s==> %s%s\n' "$C_MAGENTA" "$*" "$C_RESET"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '%s[INFO]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[FEHLER]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'USAGE'
CachyOS sicher und gezielt bereinigen.

Optionen:
  --keep ANZAHL              Paketversionen installierter Pakete behalten
                             (Standard: 3)
  --uninstalled-keep ANZAHL  Versionen deinstallierter Pakete behalten
                             (Standard: 1)
  --journal-age ZEIT         Journal-Aufbewahrung, z. B. 7d, 14d, 1month
                             (Standard: 14d)
  --aur-all                  kompletten paru-/yay-Buildcache leeren;
                             sonst nur src/pkg und gebaute Paketdateien
  --no-orphans               verwaiste Pakete nicht entfernen
  --no-aur-cache             AUR-Buildcache nicht bereinigen
  --no-flatpak               ungenutzte Flatpak-Runtimes nicht entfernen
  --no-journal               systemd-Journal nicht verkleinern
  --no-thumbnails            Thumbnail-Cache nicht leeren
  --backup-age TAGE          nur eindeutig benannte Backup-Dateien löschen,
                             die mindestens TAGE alt sind (Standard: 7)
  --no-backups               Test-/Backup-Dateien nicht bereinigen
  -y, --yes                  Rückfragen automatisch bestätigen
  --dry-run                  nur anzeigen, nichts verändern
  -h, --help                 diese Hilfe anzeigen

Hinweise:
  Das Skript niemals mit "sudo ./..." starten. Es fordert benötigte Rechte
  selbst an. Ein vollständiges Löschen von ~/.cache findet nicht statt.

  Die Backup-Bereinigung arbeitet ausschließlich in diesen festen Pfaden:
    ~/.config/niri, ~/.config/ghostty, ~/.config/fastfetch, ~/.config/yazi,
    ~/.local/bin und ~/scripts/Conky
  Erfasst werden nur reguläre Dateien namens *.bak, *.bak-*, *.backup oder
  *.backup-*. Vor dem Löschen werden alle Treffer angezeigt und bestätigt.
USAGE
}

is_nonnegative_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

# ------------------------------- Argumente -------------------------------
while (($#)); do
  case "$1" in
    --keep)
      (($# >= 2)) || die "Für --keep fehlt eine Zahl."
      is_nonnegative_integer "$2" || die "Ungültiger Wert für --keep: $2"
      KEEP_INSTALLED=$2
      shift
      ;;
    --uninstalled-keep)
      (($# >= 2)) || die "Für --uninstalled-keep fehlt eine Zahl."
      is_nonnegative_integer "$2" || die "Ungültiger Wert für --uninstalled-keep: $2"
      KEEP_UNINSTALLED=$2
      shift
      ;;
    --journal-age)
      (($# >= 2)) || die "Für --journal-age fehlt ein Zeitraum."
      [[ -n "$2" && "$2" != -* ]] || die "Ungültiger Zeitraum für --journal-age: $2"
      JOURNAL_AGE=$2
      shift
      ;;
    --backup-age)
      (($# >= 2)) || die "Für --backup-age fehlt eine Zahl."
      is_nonnegative_integer "$2" || die "Ungültiger Wert für --backup-age: $2"
      BACKUP_MIN_DAYS=$2
      shift
      ;;
    --aur-all)       AUR_ALL=true ;;
    --no-orphans)    DO_ORPHANS=false ;;
    --no-aur-cache)  DO_AUR_CACHE=false ;;
    --no-flatpak)    DO_FLATPAK=false ;;
    --no-journal)    DO_JOURNAL=false ;;
    --no-thumbnails) DO_THUMBNAILS=false ;;
    --no-backups)    DO_BACKUPS=false ;;
    -y|--yes)        ASSUME_YES=true ;;
    --dry-run)       DRY_RUN=true ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "Unbekannte Option: $1 (siehe --help)" ;;
  esac
  shift
done

# -------------------------- Status und Laufzeit --------------------------
declare -A STATUS=(
  [Paketcache]='ausstehend'
  [Waisen]='übersprungen'
  [AUR-Cache]='übersprungen'
  [Flatpak]='übersprungen'
  [Journal]='übersprungen'
  [Thumbnails]='übersprungen'
  [Backups]='übersprungen'
)

OPTIONAL_FAILURES=0
START_SECONDS=$SECONDS
ROOT_BEFORE=0
HOME_BEFORE=0
ROOT_SOURCE=''
HOME_SOURCE=''

available_bytes() {
  df -B1 --output=avail "$1" 2>/dev/null | awk 'NR == 2 {print $1 + 0}'
}

filesystem_source() {
  df --output=source "$1" 2>/dev/null | awk 'NR == 2 {print $1}'
}

human_bytes() {
  local bytes=${1:-0}
  if have numfmt; then
    numfmt --to=iec-i --suffix=B -- "$bytes"
  else
    awk -v b="$bytes" 'BEGIN {
      split("B KiB MiB GiB TiB", u, " "); i=1;
      while (b >= 1024 && i < 5) { b/=1024; i++ }
      printf "%.1f %s", b, u[i]
    }'
  fi
}

record_space_before() {
  ROOT_SOURCE=$(filesystem_source /)
  HOME_SOURCE=$(filesystem_source "$HOME")
  ROOT_BEFORE=$(available_bytes /)
  HOME_BEFORE=$(available_bytes "$HOME")
}

# ------------------------------ Vorprüfung -------------------------------
preflight() {
  ((EUID != 0)) || die "Bitte als normaler Benutzer starten, nicht mit sudo."

  have sudo   || die "sudo wurde nicht gefunden."
  have pacman || die "pacman wurde nicht gefunden – das Skript ist nur für CachyOS/Arch gedacht."
  have find     || die "find wurde nicht gefunden."
  have realpath || die "realpath wurde nicht gefunden."
  have stat     || die "stat wurde nicht gefunden."

  if [[ -e /var/lib/pacman/db.lck ]]; then
    die "Pacmans Datenbank ist gesperrt. Prüfe, ob bereits ein Paketmanager läuft."
  fi

  if have flock; then
    local lock_file="${XDG_RUNTIME_DIR:-/tmp}/cachyos-clean-${UID}.lock"
    exec 9>"$lock_file"
    flock -n 9 || die "Das Bereinigungsskript läuft bereits in einem anderen Terminal."
  fi

  record_space_before

  if $DRY_RUN; then
    info "Trockenlauf aktiv: Es werden keine Dateien oder Pakete entfernt."
    return 0
  fi

  say "Administratorrechte prüfen …"
  sudo -v || die "sudo-Authentifizierung fehlgeschlagen."
}

# ---------------------------- Paket-Cache --------------------------------
clean_package_cache() {
  say "Pacman-Paketcache gezielt bereinigen …"

  if ! have paccache; then
    STATUS[Paketcache]='paccache fehlt'
    ((OPTIONAL_FAILURES += 1))
    warn "paccache fehlt. Installiere es mit: sudo pacman -S pacman-contrib"
    warn "pacman -Sc wird absichtlich nicht als grober Ersatz ausgeführt."
    return 0
  fi

  if $DRY_RUN; then
    info "Kandidaten installierter Pakete; $KEEP_INSTALLED Version(en) bleiben erhalten:"
    sudo -n paccache -d -v -k "$KEEP_INSTALLED" 2>/dev/null || paccache -d -v -k "$KEEP_INSTALLED" || true
    info "Kandidaten deinstallierter Pakete; $KEEP_UNINSTALLED Version(en) bleiben erhalten:"
    sudo -n paccache -d -v -u -k "$KEEP_UNINSTALLED" 2>/dev/null || paccache -d -v -u -k "$KEEP_UNINSTALLED" || true
    STATUS[Paketcache]='Vorschau'
    return 0
  fi

  local failed=false

  if ! sudo paccache -r -k "$KEEP_INSTALLED"; then
    failed=true
    warn "Alte Versionen installierter Pakete konnten nicht vollständig entfernt werden."
  fi

  if ! sudo paccache -r -u -k "$KEEP_UNINSTALLED"; then
    failed=true
    warn "Cache deinstallierter Pakete konnte nicht vollständig bereinigt werden."
  fi

  if $failed; then
    STATUS[Paketcache]='Fehler'
    ((OPTIONAL_FAILURES += 1))
  else
    STATUS[Paketcache]='OK'
    ok "Paketcache bereinigt; installiert=$KEEP_INSTALLED, deinstalliert=$KEEP_UNINSTALLED Version(en) behalten."
  fi
}

# ----------------------------- Waisen ------------------------------------
confirm_action() {
  local prompt=$1

  $ASSUME_YES && return 0

  if [[ ! -t 0 ]]; then
    warn "Keine interaktive Eingabe verfügbar. Nutze --yes, um diesen Schritt automatisch zu bestätigen."
    return 1
  fi

  local answer
  read -r -p "$prompt [j/N] " answer
  [[ "$answer" =~ ^[jJyY]$ ]]
}

remove_orphans() {
  if ! $DO_ORPHANS; then
    STATUS[Waisen]='deaktiviert'
    return 0
  fi

  say "Verwaiste Abhängigkeiten prüfen …"

  local -a orphans=()
  mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)

  if ((${#orphans[@]} == 0)); then
    STATUS[Waisen]='keine'
    ok "Keine verwaisten Pakete gefunden."
    return 0
  fi

  printf '  %s\n' "${orphans[@]}"
  info "Gefunden: ${#orphans[@]} Paket(e)."

  if $DRY_RUN; then
    STATUS[Waisen]="Vorschau (${#orphans[@]})"
    return 0
  fi

  if ! confirm_action "Diese verwaisten Pakete mit ihren ungenutzten Abhängigkeiten entfernen?"; then
    STATUS[Waisen]='nicht bestätigt'
    warn "Verwaiste Pakete wurden nicht entfernt."
    return 0
  fi

  if sudo pacman -Rns --noconfirm "${orphans[@]}"; then
    STATUS[Waisen]="OK (${#orphans[@]})"
    ok "Verwaiste Pakete wurden entfernt."
  else
    STATUS[Waisen]='Fehler'
    ((OPTIONAL_FAILURES += 1))
    warn "Verwaiste Pakete konnten nicht vollständig entfernt werden."
  fi
}

# ----------------------------- AUR-Cache ---------------------------------
safe_cache_dir() {
  local dir=$1
  local cache_root=${XDG_CACHE_HOME:-"$HOME/.cache"}

  [[ -n "$dir" && "$dir" != '/' && "$dir" != "$HOME" && "$dir" != "$cache_root" ]] || return 1
  [[ "$dir" == "$cache_root"/* ]] || return 1
}

clear_directory_contents() {
  local dir=$1
  safe_cache_dir "$dir" || {
    warn "Unsicherer Cachepfad wurde nicht gelöscht: $dir"
    return 1
  }
  [[ -d "$dir" ]] || return 0
  find "$dir" -xdev -mindepth 1 -delete
}

clean_aur_tree_artifacts() {
  local dir=$1
  [[ -d "$dir" ]] || return 0
  safe_cache_dir "$dir" || {
    warn "Unsicherer Cachepfad wurde übersprungen: $dir"
    return 1
  }

  # Git-/PKGBUILD-Checkout bleibt erhalten. Entfernt werden nur die großen,
  # jederzeit reproduzierbaren Build-Verzeichnisse und Paketarchive.
  find "$dir" -xdev -mindepth 2 -maxdepth 2 -type d \
    \( -name src -o -name pkg \) -exec rm -rf -- {} +
  find "$dir" -xdev -type f -name '*.pkg.tar.*' -delete
}

clean_aur_cache() {
  if ! $DO_AUR_CACHE; then
    STATUS[AUR-Cache]='deaktiviert'
    return 0
  fi

  say "AUR-Buildcache bereinigen …"

  local cache_root=${XDG_CACHE_HOME:-"$HOME/.cache"}
  local -a cache_dirs=()
  [[ -d "$cache_root/paru/clone" ]] && cache_dirs+=("$cache_root/paru/clone")
  [[ -d "$cache_root/yay" ]] && cache_dirs+=("$cache_root/yay")

  if ((${#cache_dirs[@]} == 0)); then
    STATUS[AUR-Cache]='nicht vorhanden'
    ok "Kein paru-/yay-Buildcache gefunden."
    return 0
  fi

  local dir
  for dir in "${cache_dirs[@]}"; do
    info "$dir"
  done

  if $DRY_RUN; then
    if $AUR_ALL; then
      STATUS[AUR-Cache]='Vorschau: komplett'
      info "Der komplette aufgeführte AUR-Buildcache würde geleert."
    else
      STATUS[AUR-Cache]='Vorschau: Artefakte'
      info "Nur src/pkg-Verzeichnisse und *.pkg.tar.* würden entfernt."
    fi
    return 0
  fi

  local failed=false
  for dir in "${cache_dirs[@]}"; do
    if $AUR_ALL; then
      clear_directory_contents "$dir" || failed=true
    else
      clean_aur_tree_artifacts "$dir" || failed=true
    fi
  done

  if $failed; then
    STATUS[AUR-Cache]='Fehler'
    ((OPTIONAL_FAILURES += 1))
    warn "Mindestens ein AUR-Cache konnte nicht vollständig bereinigt werden."
  elif $AUR_ALL; then
    STATUS[AUR-Cache]='OK, komplett'
    ok "AUR-Buildcache vollständig geleert."
  else
    STATUS[AUR-Cache]='OK, Artefakte'
    ok "AUR-Buildartefakte entfernt; Checkouts bleiben für spätere Updates erhalten."
  fi
}

# ------------------------------- Flatpak ---------------------------------
clean_flatpak() {
  if ! $DO_FLATPAK; then
    STATUS[Flatpak]='deaktiviert'
    return 0
  fi

  if ! have flatpak; then
    STATUS[Flatpak]='nicht installiert'
    return 0
  fi

  say "Ungenutzte Flatpak-Runtimes und Erweiterungen entfernen …"

  if $DRY_RUN; then
    STATUS[Flatpak]='Vorschau'
    info "Im echten Lauf würde ausgeführt: flatpak uninstall --unused -y"
    return 0
  fi

  if flatpak uninstall --unused -y; then
    STATUS[Flatpak]='OK'
    ok "Nicht mehr benötigte Flatpak-Komponenten wurden entfernt."
  else
    STATUS[Flatpak]='Fehler'
    ((OPTIONAL_FAILURES += 1))
    warn "Flatpak-Bereinigung ist fehlgeschlagen."
  fi
}

# ------------------------------- Journal ---------------------------------
clean_journal() {
  if ! $DO_JOURNAL; then
    STATUS[Journal]='deaktiviert'
    return 0
  fi

  if ! have journalctl; then
    STATUS[Journal]='nicht verfügbar'
    return 0
  fi

  say "Systemjournal verkleinern; Aufbewahrung: $JOURNAL_AGE …"

  if $DRY_RUN; then
    journalctl --disk-usage 2>/dev/null || true
    STATUS[Journal]='Vorschau'
    return 0
  fi

  # --rotate archiviert die aktuell aktive Journaldatei zuerst, damit die
  # anschließende Vacuum-Regel möglichst vollständig greifen kann.
  if sudo journalctl --rotate --vacuum-time="$JOURNAL_AGE"; then
    STATUS[Journal]='OK'
    ok "Archivierte Journaldateien außerhalb der Aufbewahrungszeit wurden entfernt."
  else
    STATUS[Journal]='Fehler'
    ((OPTIONAL_FAILURES += 1))
    warn "Systemjournal konnte nicht vollständig bereinigt werden."
  fi
}

# ----------------------------- Thumbnails --------------------------------
clean_thumbnails() {
  if ! $DO_THUMBNAILS; then
    STATUS[Thumbnails]='deaktiviert'
    return 0
  fi

  say "Benutzer-Thumbnailcache leeren …"

  local thumbnail_dir="$HOME/.cache/thumbnails"
  if [[ ! -d "$thumbnail_dir" ]]; then
    STATUS[Thumbnails]='nicht vorhanden'
    ok "Kein Thumbnailcache vorhanden."
    return 0
  fi

  if $DRY_RUN; then
    STATUS[Thumbnails]='Vorschau'
    info "Inhalt von $thumbnail_dir würde entfernt."
    return 0
  fi

  if safe_cache_dir "$thumbnail_dir" && find "$thumbnail_dir" -xdev -mindepth 1 -delete; then
    STATUS[Thumbnails]='OK'
    ok "Thumbnailcache geleert; Vorschaubilder werden bei Bedarf neu erstellt."
  else
    STATUS[Thumbnails]='Fehler'
    ((OPTIONAL_FAILURES += 1))
    warn "Thumbnailcache konnte nicht vollständig geleert werden."
  fi
}

# ------------------------- Test-/Backup-Dateien ---------------------------
# Diese Bereinigung ist absichtlich eng begrenzt:
#   - nur vier feste Verzeichnisse im Home des Benutzers
#   - nur reguläre Dateien, keine Verzeichnisse und keine Symlinks
#   - nur eindeutige Backup-Namensmuster
#   - Altersgrenze, Vorschau und Bestätigung vor dem Löschen
BACKUP_ROOTS=(
  "$HOME/.config/niri"
  "$HOME/.config/ghostty"
  "$HOME/.config/fastfetch"
  "$HOME/.config/yazi"
  "$HOME/.local/bin"
  "$HOME/scripts/Conky"
)

BACKUP_CANDIDATES=()

is_allowed_backup_file() {
  local file=$1
  local base resolved_file root resolved_root

  [[ -f "$file" && ! -L "$file" ]] || return 1

  base=${file##*/}
  case "$base" in
    *.bak|*.bak-*|*.backup|*.backup-*) ;;
    *) return 1 ;;
  esac

  resolved_file=$(realpath -m -- "$file") || return 1

  for root in "${BACKUP_ROOTS[@]}"; do
    resolved_root=$(realpath -m -- "$root") || continue
    [[ "$resolved_file" == "$resolved_root"/* ]] && return 0
  done

  return 1
}

collect_backup_candidates() {
  BACKUP_CANDIDATES=()

  local root file
  local -a age_filter=()

  if ((BACKUP_MIN_DAYS > 0)); then
    age_filter=(-mmin "+$((BACKUP_MIN_DAYS * 1440))")
  fi

  for root in "${BACKUP_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue

    while IFS= read -r -d '' file; do
      if is_allowed_backup_file "$file"; then
        BACKUP_CANDIDATES+=("$file")
      else
        warn "Unsicherer Backup-Kandidat wurde übersprungen: $file"
      fi
    done < <(
      find "$root" -xdev -type f \
        \( -name '*.bak' -o -name '*.bak-*' -o \
           -name '*.backup' -o -name '*.backup-*' \) \
        "${age_filter[@]}" -print0 2>/dev/null
    )
  done
}

clean_old_backups() {
  if ! $DO_BACKUPS; then
    STATUS[Backups]='deaktiviert'
    return 0
  fi

  say "Alte Test-/Backup-Dateien sicher prüfen …"
  collect_backup_candidates

  if ((${#BACKUP_CANDIDATES[@]} == 0)); then
    STATUS[Backups]='keine'
    ok "Keine passenden Backup-Dateien gefunden, die mindestens $BACKUP_MIN_DAYS Tag(e) alt sind."
    return 0
  fi

  local file display size modified total_bytes=0
  printf '  %-10s  %-16s  %s\n' 'Größe' 'Geändert' 'Datei'

  for file in "${BACKUP_CANDIDATES[@]}"; do
    size=$(stat -c '%s' -- "$file" 2>/dev/null || printf '0')
    modified=$(stat -c '%y' -- "$file" 2>/dev/null | cut -d'.' -f1 || printf '?')
    display=${file/#$HOME/\~}
    total_bytes=$((total_bytes + size))
    printf '  %-10s  %-16s  %s\n' "$(human_bytes "$size")" "$modified" "$display"
  done

  info "Gefunden: ${#BACKUP_CANDIDATES[@]} Datei(en), zusammen $(human_bytes "$total_bytes")."
  info "Es werden keine Verzeichnisse, Symlinks oder anders benannten Dateien gelöscht."

  if $DRY_RUN; then
    STATUS[Backups]="Vorschau (${#BACKUP_CANDIDATES[@]})"
    return 0
  fi

  if ! confirm_action "Diese eindeutig benannten Backup-Dateien dauerhaft löschen?"; then
    STATUS[Backups]='nicht bestätigt'
    warn "Backup-Dateien wurden nicht entfernt."
    return 0
  fi

  local removed=0 failed=0
  for file in "${BACKUP_CANDIDATES[@]}"; do
    # Vor jedem Löschvorgang erneut alle Sicherheitsbedingungen prüfen.
    if ! is_allowed_backup_file "$file"; then
      warn "Datei hat sich geändert oder liegt nicht mehr sicher: $file"
      ((failed += 1))
      continue
    fi

    if rm -- "$file"; then
      ((removed += 1))
    else
      warn "Konnte nicht entfernt werden: $file"
      ((failed += 1))
    fi
  done

  if ((failed > 0)); then
    STATUS[Backups]="teilweise ($removed entfernt, $failed Fehler)"
    ((OPTIONAL_FAILURES += 1))
  else
    STATUS[Backups]="OK ($removed)"
    ok "$removed alte Backup-Datei(en) sicher entfernt."
  fi
}

# ----------------------------- Zusammenfassung ---------------------------
print_space_delta() {
  local root_after home_after root_delta home_delta
  root_after=$(available_bytes /)
  home_after=$(available_bytes "$HOME")
  root_delta=$((root_after - ROOT_BEFORE))
  home_delta=$((home_after - HOME_BEFORE))

  if [[ "$ROOT_SOURCE" == "$HOME_SOURCE" ]]; then
    if ((root_delta >= 0)); then
      printf '  %-17s +%s\n' 'Freier Speicher:' "$(human_bytes "$root_delta")"
    else
      printf '  %-17s %s\n' 'Speicheränderung:' "$(human_bytes "$root_delta")"
    fi
  else
    printf '  %-17s %+s (%s)\n' 'Root:' "$(human_bytes "$root_delta")" "$ROOT_SOURCE"
    printf '  %-17s %+s (%s)\n' 'Home:' "$(human_bytes "$home_delta")" "$HOME_SOURCE"
  fi
}

summary() {
  local duration=$((SECONDS - START_SECONDS))

  say "Zusammenfassung"
  printf '  %-17s %s\n' 'Paketcache:' "${STATUS[Paketcache]}"
  printf '  %-17s %s\n' 'Waisen:' "${STATUS[Waisen]}"
  printf '  %-17s %s\n' 'AUR-Cache:' "${STATUS[AUR-Cache]}"
  printf '  %-17s %s\n' 'Flatpak:' "${STATUS[Flatpak]}"
  printf '  %-17s %s\n' 'Journal:' "${STATUS[Journal]}"
  printf '  %-17s %s\n' 'Thumbnails:' "${STATUS[Thumbnails]}"
  printf '  %-17s %s\n' 'Backups:' "${STATUS[Backups]}"
  printf '  %-17s %ss\n' 'Dauer:' "$duration"

  if $DRY_RUN; then
    printf '\n%sTrockenlauf beendet – es wurde nichts verändert.%s\n' "$C_DIM" "$C_RESET"
  else
    print_space_delta
  fi

  if ((OPTIONAL_FAILURES > 0)); then
    warn "$OPTIONAL_FAILURES Bereinigungsschritt(e) hatten Fehler oder fehlende Voraussetzungen."
    return 2
  fi

  ok "Bereinigung abgeschlossen."
}

main() {
  preflight

  say "CachyOS-Bereinigung starten …"
  clean_package_cache
  remove_orphans
  clean_aur_cache
  clean_flatpak
  clean_journal
  clean_thumbnails
  clean_old_backups
  summary
}

main "$@"
