#!/usr/bin/env python3
"""Read single-line Niri bindings outside Noctalia's time-limited Luau callback.

Outputs one JSON list, preserving the old plugin's German action labels.
"""
import json
import re
import sys
from pathlib import Path

NAMES = {
    'close-window': 'Fenster schließen',
    'toggle-overview': 'Übersicht umschalten',
    'show-hotkey-overlay': 'Niri-Hotkey-Hilfe anzeigen',
    'fullscreen-window': 'Fullscreen umschalten',
    'maximize-column': 'Spalte maximieren',
    'center-column': 'Spalte zentrieren',
    'switch-preset-column-width': 'Spaltenbreite wechseln',
    'focus-column-left': 'Spalte links fokussieren',
    'focus-column-right': 'Spalte rechts fokussieren',
    'focus-window-up': 'Fenster oben fokussieren',
    'focus-window-down': 'Fenster unten fokussieren',
    'move-column-left': 'Spalte nach links verschieben',
    'move-column-right': 'Spalte nach rechts verschieben',
    'focus-workspace-up': 'Workspace hoch',
    'focus-workspace-down': 'Workspace runter',
}


def describe(action):
    action = action.strip().removesuffix(';').strip()
    if action in NAMES:
        return NAMES[action]
    m = re.match(r'^spawn\s+"([^"]+)"', action)
    if m:
        return 'Start: ' + m.group(1)
    m = re.match(r'^spawn-sh\s+"([^"]+)"', action)
    if m:
        text = m.group(1)
        return text[:69] + '...' if len(text) > 72 else text
    return action


def parse_niri(source):
    rows = []
    in_binds = False
    depth = 0
    for raw in source.splitlines():
        clean = re.sub(r'//.*$', '', raw).strip()
        if not clean:
            continue
        if not in_binds:
            if re.match(r'^binds\s*\{', clean):
                in_binds = True
                depth = clean.count('{') - clean.count('}')
            continue
        if depth == 1:
            m = re.match(r'^(\S+).*?\{\s*(.*?)\s*\}\s*$', clean)
            if m and m.group(1) != '}':
                key, action = m.groups()
                title = re.search(r'hotkey-overlay-title="([^"]+)"', clean)
                rows.append({'key': key, 'desc': title.group(1) if title else describe(action)})
        depth += clean.count('{') - clean.count('}')
        if depth <= 0:
            in_binds = False
            depth = 0
    return rows


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: niri_keys.py /path/to/keybinds.kdl')
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    rows = parse_niri(source)
    print(json.dumps(rows, ensure_ascii=False, separators=(',', ':')))


if __name__ == '__main__':
    main()
