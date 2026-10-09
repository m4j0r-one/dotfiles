#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

BACKUP_ROOT="$HOME/Backup/Niri"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/m4j0r-backup"
LAST_SUCCESS_FILE="$STATE_DIR/niri-last-success.epoch"
LOG_FILE="$STATE_DIR/niri-backup.log"
KEEP_BACKUPS=10
INTERVAL_SECONDS=$((7 * 24 * 60 * 60))
FORCE=0

if [[ "${1:-}" == "--force" ]]; then
    FORCE=1
elif [[ $# -gt 0 ]]; then
    printf 'Verwendung: %s [--force]\n' "$0" >&2
    exit 2
fi

mkdir -p "$BACKUP_ROOT" "$STATE_DIR"
touch "$LOG_FILE"
exec >>"$LOG_FILE" 2>&1

printf '\n[%s] Niri-Backup gestartet.\n' "$(date '+%F %T')"

LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/m4j0r-niri-backup.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "Ein Niri-Backup läuft bereits; dieser Lauf wird beendet."
    exit 0
fi

now_epoch=$(date +%s)
if (( FORCE == 0 )) && [[ -s "$LAST_SUCCESS_FILE" ]]; then
    last_epoch=$(<"$LAST_SUCCESS_FILE")
    if [[ "$last_epoch" =~ ^[0-9]+$ ]] && (( now_epoch - last_epoch < INTERVAL_SECONDS )); then
        echo "Noch nicht fällig; letzter erfolgreicher Lauf: $(date -d "@$last_epoch" '+%F %T')."
        exit 0
    fi
fi

is_gaming() {
    if command -v gamemoded >/dev/null 2>&1 \
       && gamemoded -s 2>/dev/null | grep -qiE '^gamemode is active$|active clients?:[[:space:]]*[1-9]'; then
        return 0
    fi

    local built_in='(Wow([.]exe)?|World of Warcraft|Diablo ?IV|DiabloIV|PathOfExile|Path of Exile|gamescope|lutris|umu-run|proton.*(waitforexitandrun|run))'
    if pgrep -afi "$built_in" >/dev/null 2>&1; then
        return 0
    fi

    local pattern_file="$HOME/.config/m4j0r-backup/game-patterns"
    if [[ -r "$pattern_file" ]]; then
        local pattern
        while IFS= read -r pattern; do
            [[ -z "$pattern" || "$pattern" == \#* ]] && continue
            if pgrep -afi -- "$pattern" >/dev/null 2>&1; then
                return 0
            fi
        done < "$pattern_file"
    fi

    return 1
}

if (( FORCE == 0 )) && is_gaming; then
    echo "Gaming erkannt; das fällige Backup wird beim nächsten Stundenlauf erneut versucht."
    exit 0
fi

stamp=$(date '+%Y-%m-%d_%H-%M-%S')
final_dir="$BACKUP_ROOT/Niri-$stamp"
tmp_dir="$BACKUP_ROOT/.Niri-$stamp.tmp"
rm -rf -- "$tmp_dir"
mkdir -p "$tmp_dir/inventory"

cleanup() {
    local rc=$?
    if (( rc != 0 )); then
        echo "Backup fehlgeschlagen (Exit $rc). Temporäre Daten werden entfernt."
        echo "$(date --iso-8601=seconds)|ERROR|Exit $rc" > "$STATE_DIR/niri-last-result.txt"
        rm -rf -- "$tmp_dir"
    fi
}
trap cleanup EXIT

home_items=(
    ".config/niri"
    ".config/noctalia"
    ".config/quickshell"
    ".config/easyeffects"
    ".config/conky"
    ".config/systemd/user"
    ".config/autostart"
    ".config/m4j0r-backup"
    ".config/gtk-3.0"
    ".config/gtk-4.0"
    ".config/Kvantum"
    ".config/qt5ct"
    ".config/qt6ct"
    ".config/fontconfig"
    ".config/environment.d"
    ".config/matugen"
    ".config/wallust"
    ".config/fuzzel"
    ".config/kitty"
    ".config/foot"
    ".config/alacritty"
    ".config/fastfetch"
    ".config/mako"
    ".config/swaync"
    ".config/waypaper"
    ".config/swappy"
    ".config/uwsm"
    ".config/xdg-desktop-portal"
    ".config/mimeapps.list"
    ".config/user-dirs.dirs"
    ".config/user-dirs.locale"
    ".local/share/noctalia"
    ".local/state/noctalia"
    ".local/share/applications"
    ".local/share/fonts"
    ".local/share/icons"
    ".local/share/themes"
    ".local/bin"
    ".fonts"
    ".icons"
    ".themes"
    "scripts"
    ".zshrc"
    ".p10k.zsh"
    "Bilder/Wallpapers"
    "Pictures/Wallpapers"
)

existing_home=()
for item in "${home_items[@]}"; do
    [[ -e "$HOME/$item" || -L "$HOME/$item" ]] && existing_home+=("$item")
done

if ((${#existing_home[@]} == 0)); then
    echo "Keine Niri-Konfigurationsdaten gefunden." >&2
    exit 1
fi

printf '%s\n' "${existing_home[@]}" > "$tmp_dir/inventory/home-paths.txt"
tar --zstd -cpf "$tmp_dir/home-configs.tar.zst" -C "$HOME" "${existing_home[@]}"

system_items=(
    "etc/sddm.conf"
    "etc/sddm.conf.d"
    "etc/environment"
    "etc/environment.d"
    "etc/profile.d"
    "etc/modprobe.d"
    "etc/udev/rules.d"
    "etc/systemd/system"
    "etc/pacman.conf"
    "etc/pacman.d/hooks"
    "usr/local/bin"
    "usr/local/sbin"
    "usr/share/backgrounds/m4j0r-one-cachyos-login-3440x1440.png"
    "usr/share/sddm/themes/breeze/theme.conf.user"
)

existing_system=()
for item in "${system_items[@]}"; do
    [[ -e "/$item" || -L "/$item" ]] && existing_system+=("$item")
done

if ((${#existing_system[@]} > 0)); then
    printf '%s\n' "${existing_system[@]}" > "$tmp_dir/inventory/system-paths.txt"
    tar --zstd --ignore-failed-read -cpf "$tmp_dir/system-customizations.tar.zst" \
        -C / "${existing_system[@]}" \
        2>"$tmp_dir/inventory/system-archive-warnings.txt"
fi

pacman -Qqe  > "$tmp_dir/inventory/pacman-explicit-all.txt"
pacman -Qqen > "$tmp_dir/inventory/pacman-explicit-repo.txt"
pacman -Qqem > "$tmp_dir/inventory/pacman-explicit-aur.txt" || true
pacman -Q    > "$tmp_dir/inventory/pacman-packages-with-versions.txt"

niri_candidates=(
    cachyos-niri-noctalia niri noctalia noctalia-shell noctalia-qs xwayland-satellite
    quickshell quickshell-git matugen wallust fuzzel kitty foot alacritty
    sddm conky cava easyeffects playerctl imagemagick ffmpeg jq curl rsync zstd
    wl-clipboard grim slurp swappy swaybg swww waypaper
    xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk
    pipewire pipewire-pulse wireplumber qt6-wayland
    python python-pillow git
)
: > "$tmp_dir/inventory/niri-stack-installed.txt"
for pkg in "${niri_candidates[@]}"; do
    pacman -Q "$pkg" >> "$tmp_dir/inventory/niri-stack-installed.txt" 2>/dev/null || true
done

if command -v flatpak >/dev/null 2>&1; then
    flatpak list --app --columns=application > "$tmp_dir/inventory/flatpak-apps.txt" || true
fi

systemctl --user list-unit-files --state=enabled --no-legend 2>/dev/null \
    | awk '{print $1}' > "$tmp_dir/inventory/enabled-user-units.txt" || true
systemctl list-unit-files --state=enabled --no-legend 2>/dev/null \
    | awk '{print $1}' > "$tmp_dir/inventory/enabled-system-units.txt" || true

{
    echo "Backup-Zeit: $(date --iso-8601=seconds)"
    echo "Host: $(hostnamectl --static 2>/dev/null || hostname)"
    echo "Kernel: $(uname -srmo)"
    echo "Session: ${XDG_CURRENT_DESKTOP:-unbekannt} / ${XDG_SESSION_TYPE:-unbekannt}"
    echo
    niri --version 2>/dev/null || true
    noctalia --version 2>/dev/null || true
    qs --version 2>/dev/null || true
} > "$tmp_dir/inventory/system-info.txt"

cat > "$tmp_dir/RESTORE-HINWEISE.txt" <<'RESTORE'
NIRI-BACKUP – WIEDERHERSTELLUNG AUF EINER FRISCHEN INSTALLATION

1. CachyOS/Arch ohne KDE installieren. Ein Login-Manager wie SDDM darf vorhanden sein.
2. Zuerst Niri, die native Noctalia-v5-Shell (Paket: noctalia) und
   die benötigten Programme installieren.
   Für den eigenständigen Quickshell-Audio-Visualizer zusätzlich prüfen,
   ob noctalia-qs oder ein kompatibles quickshell-Paket benötigt wird.
   Die damaligen Versionen stehen unter inventory/niri-stack-installed.txt.
3. Prüfen:
      sha256sum -c SHA256SUMS
4. Benutzerkonfiguration zurückspielen:
      tar --zstd -xpf home-configs.tar.zst -C "$HOME"
5. Optionale eigene Systemdateien zurückspielen:
      sudo tar --zstd -xpf system-customizations.tar.zst -C /
6. Danach:
      systemctl --user daemon-reload
      niri validate

WICHTIG:
- pacman-explicit-all.txt kann alte bzw. nicht mehr benötigte Desktop-Pakete enthalten.
  Die Liste NICHT ungeprüft vollständig installieren; zuerst den tatsächlich
  benötigten Niri-/Noctalia-Stack aus niri-stack-installed.txt prüfen.
- Die Shell verwendet Noctalia v5 (Paket noctalia). Eine separat weiterhin
  verwendete Quickshell-Visualisierung ist nicht die Noctalia-v4-Shell.
- Für ein Niri-only-System niri-stack-installed.txt als Orientierung nutzen.
- Benutzereinstellungen und Plugins liegen unter .config/noctalia,
  .local/share/noctalia und ggf. .local/state/noctalia.
- /usr/share/sddm/themes/breeze/theme.conf.user gehört zum KDE/Breeze-SDDM-Theme.
  Ohne Breeze-Theme wird diese eine Datei nicht verwendet; Niri selbst ist davon unabhängig.
- Persönliche Dateien und Passwörter werden weiterhin von den bestehenden allgemeinen/private
  Backup-Skripten gesichert. Dieses Archiv ist das reproduzierbare Niri-/Desktop-Setup.
RESTORE

cat > "$tmp_dir/restore-niri.sh" <<'RESTORE_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

backup_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$backup_dir"

echo "Prüfe Backup..."
sha256sum -c SHA256SUMS

echo "Spiele Benutzerkonfiguration nach $HOME zurück..."
tar --zstd -xpf home-configs.tar.zst -C "$HOME"

if [[ "${1:-}" == "--with-system" ]]; then
    if [[ -f system-customizations.tar.zst ]]; then
        echo "Spiele eigene Systemdateien nach / zurück..."
        sudo tar --zstd -xpf system-customizations.tar.zst -C /
    else
        echo "Kein Systemarchiv in diesem Backup vorhanden."
    fi
elif [[ $# -gt 0 ]]; then
    echo "Verwendung: $0 [--with-system]" >&2
    exit 2
fi

systemctl --user daemon-reload

if command -v niri >/dev/null 2>&1; then
    niri validate
else
    echo "Niri ist noch nicht installiert. Installiere zuerst den Niri/Noctalia-Stack."
fi

echo "Wiederherstellung abgeschlossen. Danach einmal ab- und wieder in Niri anmelden."
RESTORE_SCRIPT
chmod 700 "$tmp_dir/restore-niri.sh"

(
    cd "$tmp_dir"
    find . -type f ! -name SHA256SUMS -print0 \
        | sort -z \
        | xargs -0 sha256sum > SHA256SUMS
)

mv -- "$tmp_dir" "$final_dir"
printf '%s\n' "$now_epoch" > "$LAST_SUCCESS_FILE"

find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'Niri-*' \
    -printf '%T@ %p\n' \
    | sort -nr \
    | tail -n +$((KEEP_BACKUPS + 1)) \
    | cut -d' ' -f2- \
    | while IFS= read -r old_backup; do
        [[ -n "$old_backup" ]] && rm -rf -- "$old_backup"
      done

size=$(du -sh "$final_dir" | awk '{print $1}')
echo "Backup erfolgreich: $final_dir ($size)"
echo "$(date --iso-8601=seconds)|OK|$final_dir|$size" > "$STATE_DIR/niri-last-result.txt"
trap - EXIT
