#!/usr/bin/env bash
set -euo pipefail

# system_report.sh
# Ausgabe: umfassender Hardware-/System-Report im Terminal

have() { command -v "$1" >/dev/null 2>&1; }
hr() { printf "\n%s\n" "============================================================"; }
title() { hr; printf "%s\n" "$1"; hr; }

SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if have sudo; then SUDO="sudo"; fi
fi

title "SYSTEM (Kernel, OS, Uptime)"
uname -a || true
if have hostnamectl; then
  echo
  hostnamectl || true
fi
if have uptime; then
  echo
  uptime || true
fi

title "CPU (Details + aktueller Takt)"
if have lscpu; then
  lscpu || true
fi
echo
if have grep && [ -r /proc/cpuinfo ]; then
  echo "CPU model + cores (from /proc/cpuinfo):"
  grep -m1 -E 'model name|Hardware' /proc/cpuinfo || true
  echo "CPU MHz (per core snapshot):"
  grep -E '^cpu MHz' /proc/cpuinfo | head -n 16 || true
fi

title "MEMORY (RAM/Swap + RAM Speed)"
if have free; then
  free -h || true
fi

echo
echo "RAM speed (dmidecode) - 'Configured Memory Speed' ist entscheidend:"
if have dmidecode; then
  # dmidecode braucht root; versuchen wir es, sonst Hinweis
  if [ -n "$SUDO" ]; then
    $SUDO dmidecode -t memory 2>/dev/null | \
      grep -iE 'Configured Memory Speed:|Speed:' | \
      sed 's/^[[:space:]]*//' | \
      awk 'NF' | head -n 50 || true
  else
    echo "Hinweis: dmidecode ist vorhanden, aber ohne sudo/root kann der RAM-Speed nicht gelesen werden."
  fi
else
  echo "dmidecode nicht installiert."
fi

title "MAINBOARD / BIOS"
if have dmidecode; then
  if [ -n "$SUDO" ]; then
    echo "-- Baseboard --"
    $SUDO dmidecode -t baseboard 2>/dev/null | sed 's/^[[:space:]]*//' | awk 'NF' || true
    echo
    echo "-- BIOS --"
    $SUDO dmidecode -t bios 2>/dev/null | sed 's/^[[:space:]]*//' | awk 'NF' || true
  else
    echo "Hinweis: dmidecode braucht sudo/root für Mainboard/BIOS-Infos."
  fi
else
  echo "dmidecode nicht installiert."
fi

title "GPU / DISPLAY"
if have lspci; then
  echo "PCI display devices:"
  lspci | grep -iE 'vga|3d|display' || true
fi
echo
if have glxinfo; then
  echo "OpenGL renderer (glxinfo):"
  glxinfo -B 2>/dev/null | grep -E 'OpenGL vendor|OpenGL renderer|OpenGL version' || true
else
  echo "glxinfo nicht installiert (optional: mesa-utils)."
fi

title "STORAGE (Disks, Partitions, Filesystems)"
if have lsblk; then
  lsblk -o NAME,MODEL,SIZE,TYPE,FSTYPE,MOUNTPOINTS,UUID || true
fi
echo
if have df; then
  df -hT --exclude-type=tmpfs --exclude-type=devtmpfs || true
fi

title "SMART (nur wenn smartctl vorhanden)"
if have smartctl; then
  echo "SMART summary (requires sudo for full data):"
  if [ -n "$SUDO" ]; then
    # Zeige nur eine kurze Übersicht pro Device (best effort)
    while read -r dev; do
      echo
      echo "== $dev =="
      $SUDO smartctl -H "$dev" 2>/dev/null || true
    done < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}')
  else
    echo "Hinweis: smartctl ohne sudo liefert oft unvollständige Infos."
  fi
else
  echo "smartctl nicht installiert (optional: smartmontools)."
fi

title "NETWORK (Interfaces, IPs, Routes, DNS)"
if have ip; then
  echo "-- Interfaces (brief) --"
  ip -br link || true
  echo
  echo "-- IP addresses --"
  ip -br addr || true
  echo
  echo "-- Routes --"
  ip route || true
  echo
  echo "-- DNS (resolvectl oder /etc/resolv.conf) --"
  if have resolvectl; then
    resolvectl status 2>/dev/null | sed -n '1,160p' || true
  elif [ -r /etc/resolv.conf ]; then
    cat /etc/resolv.conf || true
  fi
else
  echo "ip (iproute2) nicht gefunden."
fi

title "SENSORS (Temperaturen, Lüfter, Spannungen)"
if have sensors; then
  sensors || true
else
  echo "sensors nicht installiert (optional: lm_sensors)."
  echo "Auf CachyOS/Arch: sudo pacman -S lm_sensors && sudo sensors-detect"
fi

title "TOP PROCESSES (CPU/RAM, Snapshot)"
if have ps; then
  echo "-- Top 10 by CPU --"
  ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 11 || true
  echo
  echo "-- Top 10 by MEM --"
  ps -eo pid,comm,%mem,%cpu --sort=-%mem | head -n 11 || true
fi

title "OPTIONAL: INXI (wenn installiert, sehr kompakt)"
if have inxi; then
  inxi -Fxxxza --no-host || true
else
  echo "inxi nicht installiert (optional, sehr empfehlenswert für Gesamtübersicht)."
fi

hr
echo "Fertig."

