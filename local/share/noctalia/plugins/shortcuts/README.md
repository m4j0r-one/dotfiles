# m4j0r Shortcuts · Noctalia v5 — CPU-budget-Fix (2.0.1)

**V5-Test-Patch, kein produktiv validierter Release.**

Änderungen gegenüber dem bisherigen Preview:

- Niri-Keybinds werden per `noctalia.runAsync()` außerhalb der Luau-CPU-Budget-Grenze durch `niri_keys.py` eingelesen und geparst.
- Der Niri-Reiter zeigt 12 Bindings pro Seite; Blättern mit „Zurück“/„Weiter“.
- Beim Umschalten zu Niri und beim Neuladen bleibt der UI-Callback kurz; parallele alte Ergebnisse werden verworfen.
- Die Yazi- und ncspot-Listen, Farbwerte und das Bar-Widget bleiben gleich.
- `plugin_api = 24` für das sichere Argument-Array von `noctalia.runAsync` (Noctalia 5.2.1 unterstützt das).

Der Helper liest nur `~/.config/niri/cfg/keybinds.kdl`; er schreibt keine Datei und führt keine Bindings aus. Der Parser unterstützt wie v4 einzeilige Bindings; er ist kein allgemeiner KDL-Parser.

Der erste Test soll außerhalb des produktiven Autostarts stattfinden. Failsafe-Rückkehr zu v4 beibehalten.
