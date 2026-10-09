#!/usr/bin/env python3

import fcntl
import json
import os
import random
import subprocess
import time
from pathlib import Path

HOME = Path.home()
WALLPAPER_DIR = HOME / "Bilder/Wallpapers/Niri-Random"

LOG_FILE = HOME / ".cache/niri-random-wallpaper-watcher.log"
LOCK_FILE = HOME / ".cache/niri-random-wallpaper-watcher.lock"

SUPPORTED_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
}

last_wallpaper = {}
last_workspace = {}


def log(message: str) -> None:
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

    with LOG_FILE.open("a", encoding="utf-8") as handle:
        handle.write(f"{message}\n")


def get_wallpapers() -> list[Path]:
    if not WALLPAPER_DIR.is_dir():
        return []

    return sorted(
        path
        for path in WALLPAPER_DIR.iterdir()
        if path.is_file()
        and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )


def choose_wallpaper(output: str) -> Path | None:
    wallpapers = get_wallpapers()

    if not wallpapers:
        log(f"Keine Wallpaper gefunden: {WALLPAPER_DIR}")
        return None

    previous = last_wallpaper.get(output)

    if len(wallpapers) > 1 and previous in wallpapers:
        wallpapers = [
            wallpaper
            for wallpaper in wallpapers
            if wallpaper != previous
        ]

    return random.choice(wallpapers)


def set_wallpaper(output: str) -> None:
    wallpaper = choose_wallpaper(output)

    if wallpaper is None:
        return

    command = [
        "/usr/bin/noctalia",
        "msg",
        "wallpaper-set",
        output,
        str(wallpaper),
    ]

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )

    if result.returncode == 0:
        last_wallpaper[output] = wallpaper
        log(f"{output}: {wallpaper.name}")
        return

    error = result.stderr.strip() or result.stdout.strip()
    log(f"Noctalia-Fehler auf {output}: {error}")


def watch_events() -> int:
    workspaces_by_id = {}

    process = subprocess.Popen(
        ["/usr/bin/niri", "msg", "--json", "event-stream"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )

    assert process.stdout is not None

    for line in process.stdout:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        changed = event.get("WorkspacesChanged")

        if changed is not None:
            workspaces = changed.get("workspaces", [])

            workspaces_by_id = {
                workspace.get("id"): workspace
                for workspace in workspaces
                if workspace.get("id") is not None
            }

            continue

        activated = event.get("WorkspaceActivated")

        if activated is None:
            continue

        workspace_id = activated.get("id")
        workspace = workspaces_by_id.get(workspace_id)

        if workspace is None:
            continue

        output = workspace.get("output")

        if not output:
            continue

        if last_workspace.get(output) == workspace_id:
            continue

        last_workspace[output] = workspace_id
        set_wallpaper(output)

    return process.wait()


def main() -> None:
    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)

    lock_handle = LOCK_FILE.open("w", encoding="utf-8")

    try:
        fcntl.flock(
            lock_handle.fileno(),
            fcntl.LOCK_EX | fcntl.LOCK_NB,
        )
    except BlockingIOError:
        return

    log("Watcher gestartet")

    niri_socket = os.environ.get("NIRI_SOCKET")
    log(f"NIRI_SOCKET={niri_socket or 'nicht gesetzt'}")

    while True:
        return_code = watch_events()
        log(f"Niri event-stream beendet: {return_code}")

        if niri_socket and not Path(niri_socket).exists():
            log("Niri-Socket verschwunden; Watcher wird beendet.")
            return

        time.sleep(1)


if __name__ == "__main__":
    main()
