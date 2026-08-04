#!/usr/bin/env python3

import fcntl
import json
import subprocess
import time
from datetime import datetime
from pathlib import Path

HOME = Path.home()
OUTPUT = "DP-2"

WALLPAPERS = {
    1: HOME / "Bilder/Wallpapers/Niri-Workspaces/workspace-1.jpg",
    2: HOME / "Bilder/Wallpapers/Niri-Workspaces/workspace-2.jpg",
    3: HOME / "Bilder/Wallpapers/Niri-Workspaces/workspace-3.jpg",
}

LOG_FILE = HOME / ".cache/niri-dp2-wallpaper-watcher.log"
LOCK_FILE = HOME / ".cache/niri-dp2-wallpaper-watcher.lock"

last_wallpaper = None


def log(message: str) -> None:
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with LOG_FILE.open("a", encoding="utf-8") as handle:
        handle.write(f"[{timestamp}] {message}\n")


def set_wallpaper(workspace_index: int) -> None:
    global last_wallpaper

    wallpaper = WALLPAPERS.get(workspace_index)

    # Workspaces ab Nummer 4 verändern das aktuelle Bild nicht.
    if wallpaper is None:
        return

    if not wallpaper.is_file():
        log(f"Datei fehlt: {wallpaper}")
        return

    if wallpaper == last_wallpaper:
        return

    command = [
        "/usr/bin/qs",
        "-c",
        "noctalia-shell",
        "ipc",
        "call",
        "wallpaper",
        "set",
        str(wallpaper),
        OUTPUT,
    ]

    # Beim Sitzungsstart könnte Noctalia noch laden.
    for attempt in range(1, 11):
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
        except subprocess.TimeoutExpired:
            log(f"Noctalia-Zeitüberschreitung, Versuch {attempt}/10")
        else:
            if result.returncode == 0:
                last_wallpaper = wallpaper
                log(
                    f"Workspace {workspace_index}: "
                    f"{wallpaper.name} auf {OUTPUT}"
                )
                return

            error = result.stderr.strip() or result.stdout.strip()
            log(f"Noctalia-Fehler, Versuch {attempt}/10: {error}")

        time.sleep(0.5)

    log(f"Wallpaper konnte nicht gesetzt werden: {wallpaper}")


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

            # Beim Start direkt das Bild des sichtbaren DP-2-Workspace setzen.
            for workspace in workspaces:
                if (
                    workspace.get("output") == OUTPUT
                    and workspace.get("is_active") is True
                ):
                    set_wallpaper(int(workspace["idx"]))
                    break

            continue

        activated = event.get("WorkspaceActivated")
        if activated is None:
            continue

        workspace = workspaces_by_id.get(activated.get("id"))

        if workspace and workspace.get("output") == OUTPUT:
            set_wallpaper(int(workspace["idx"]))

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

    while True:
        return_code = watch_events()
        log(f"Niri-Ereignisstrom beendet: Code {return_code}")
        time.sleep(1)


if __name__ == "__main__":
    main()
