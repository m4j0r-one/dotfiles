-- m4j0r.one · SHORTCUTS | Noctalia v5 (Luau)
-- Static cheat sheets carried across from v4; Niri bindings reread from disk.
local CYAN = "#7dcfff"
local PINK = "#f7768e"
local LIGHT = "#e4eaf2"
local MONO = "monospace"
local activeTab = "yazi"
local niriRows = {}
local niriPage = 1
local NIRI_PAGE_SIZE = 12
local pendingNiriRequest = 0
local panelIsOpen = false
local niriStatus = "Noch nicht eingelesen."

local yaziRows = {
    { header = "NAVIGATION", accent = "cyan" },
    { key = "↑ / ↓", desc = "hoch / runter" },
    { key = "←", desc = "Ordner zurück" },
    { key = "→", desc = "Ordner betreten" },
    { key = "Backspace", desc = "Ordner zurück" },
    { key = "Enter", desc = "Datei / Ordner öffnen" },
    { key = "Home / End", desc = "Anfang / Ende" },
    { key = "PgUp / PgDn", desc = "seitenweise hoch / runter" },
    { key = "Space", desc = "Datei markieren" },
    { header = "DATEIEN", accent = "pink" },
    { key = "Ctrl+C", desc = "kopieren" },
    { key = "Ctrl+X", desc = "ausschneiden" },
    { key = "Ctrl+V", desc = "einfügen" },
    { key = "F2", desc = "umbenennen" },
    { key = "Delete", desc = "in den Papierkorb" },
    { key = "Ctrl+F", desc = "Dateien suchen" },
    { key = "F1", desc = "Yazi-Hilfe / Keymap" },
    { header = "SERVER & NETZWERK", accent = "cyan" },
    { key = "g → w", desc = "Webserver per SFTP öffnen" },
    { key = "M → a", desc = "neue Netzwerkfreigabe hinzufügen" },
    { key = "M → m", desc = "gespeicherte SMB-Freigabe mounten + öffnen" },
    { key = "g → m", desc = "zu bereits gemounteter Freigabe springen" },
}

local spotifyRows = {
    { header = "WIEDERGABE", accent = "pink" },
    { key = "Shift+P", desc = "Play / Pause" },
    { key = "< / >", desc = "vorheriger / nächster Track" },
    { key = "R", desc = "Repeat-Modus wechseln" },
    { key = "Z", desc = "Shuffle ein / aus" },
    { key = "Shift+S", desc = "Wiedergabe stoppen" },
    { key = "F / Shift+F", desc = "1 / 10 Sekunden vor" },
    { key = "B / Shift+B", desc = "1 / 10 Sekunden zurück" },
    { key = "+ / -", desc = "Lautstärke ±1 %" },
    { key = "[ / ]", desc = "Lautstärke ±5 %" },
    { header = "BIBLIOTHEK & SEITEN", accent = "cyan" },
    { key = "F1", desc = "Queue öffnen" },
    { key = "F2", desc = "Suche öffnen" },
    { key = "F3", desc = "Bibliothek öffnen" },
    { key = "Shift+U", desc = "Bibliotheks-Cache aktualisieren" },
    { key = "S", desc = "laufenden Titel in Bibliothek speichern" },
    { key = "D", desc = "laufenden Titel aus Bibliothek entfernen" },
    { header = "NAVIGATION", accent = "pink" },
    { key = "Enter", desc = "Track / Playlist abspielen" },
    { key = "Space", desc = "Track / Playlist zur Queue hinzufügen" },
    { key = ".", desc = "Auswahl direkt nach aktuellem Track abspielen" },
    { key = "P", desc = "zum aktuell laufenden Track in Queue springen" },
    { key = "g / G", desc = "zum Anfang / Ende der Ansicht" },
    { key = "/", desc = "Vim-Suche öffnen" },
    { key = "Backspace", desc = "aktuelle Ansicht schließen" },
    { header = "KONTEXT & AKTIONEN", accent = "cyan" },
    { key = "O", desc = "Details / Kontext für Auswahl" },
    { key = "Shift+O", desc = "Kontext für laufenden Track" },
    { key = "A", desc = "Album der Auswahl öffnen" },
    { key = "Shift+A", desc = "Artist der Auswahl öffnen" },
    { key = "M", desc = "Empfehlungen zur Auswahl" },
    { key = "Shift+M", desc = "Empfehlungen zum laufenden Track" },
    { header = "QUEUE", accent = "pink" },
    { key = "C", desc = "Queue komplett leeren" },
    { key = "D", desc = "markierten Track aus Queue entfernen" },
    { key = "Ctrl+S", desc = "aktuelle Queue speichern" },
    { header = "SONSTIGES", accent = "cyan" },
    { key = "?", desc = "ncspot-Shortcut-Hilfe" },
    { key = ":", desc = "ncspot-Kommandozeile öffnen" },
    { key = "Q", desc = "ncspot beenden" },
}

local render -- forward declaration; async callback calls render after it is assigned

-- Parsing is delegated to Python via runAsync, not performed in Luau callbacks.
-- Noctalia v5 applies strict callback CPU budgets.
local function reloadNiri()
    pendingNiriRequest = pendingNiriRequest + 1
    local requestId = pendingNiriRequest
    niriStatus = "Lese Niri-Tastenkombinationen …"
    niriRows = {}
    niriPage = 1

    local helper = noctalia.pluginDir() .. "/niri_keys.py"
    local file = noctalia.expandPath("~/.config/niri/cfg/keybinds.kdl")
    local accepted = noctalia.runAsync({ "python3", helper, file }, function(result)
        if requestId ~= pendingNiriRequest then return end
        if result.timedOut or result.exitCode ~= 0 or result.stdoutTruncated then
            niriStatus = "Niri-Keybinds konnten nicht eingelesen werden."
        else
            local rows, err = noctalia.json.decode(result.stdout or "")
            if type(rows) ~= "table" then
                niriStatus = "Ungültige Niri-Daten: " .. tostring(err or "JSON")
            else
                niriRows = rows
                niriStatus = tostring(#niriRows) .. " Bindings aus ~/.config/niri/cfg/keybinds.kdl"
            end
        end
        if panelIsOpen and activeTab == "niri" then render() end
    end, 5000)

    if not accepted then
        niriStatus = "Niri-Abfrage konnte nicht gestartet werden."
    end
end

local function currentRows()
    if activeTab == "spotify" then return spotifyRows end
    if activeTab == "niri" then
        local rows = {}
        local first = (niriPage - 1) * NIRI_PAGE_SIZE + 1
        for i = first, math.min(first + NIRI_PAGE_SIZE - 1, #niriRows) do
            table.insert(rows, niriRows[i])
        end
        return rows
    end
    return yaziRows
end

local function buildRows()
    local nodes = {}
    for i, item in ipairs(currentRows()) do
        if item.header then
            table.insert(nodes, ui.label({
                key = activeTab .. ":h:" .. tostring(i),
                text = item.header,
                fontSize = 12,
                fontWeight = "bold",
                fontFamily = MONO,
                color = item.accent == "pink" and PINK or CYAN,
            }))
        else
            table.insert(nodes, ui.row({
                key = activeTab .. ":r:" .. tostring(i),
                gap = 14,
                align = "center",
                padding = 7,
                radius = 9,
                fill = "#111a2aa6",
                border = "#7dcfff30",
                borderWidth = 1,
            }, {
                ui.column({ minWidth = 185, padding = 8, fill = "#172438ad", radius = 7,
                    border = "#f7768e77", borderWidth = 1 }, {
                    ui.label({ text = item.key, color = CYAN,
                        fontFamily = MONO, fontSize = 12, fontWeight = "bold" }),
                }),
                ui.label({ text = item.desc, color = LIGHT, fontFamily = MONO,
                    fontSize = 12, flexGrow = 1 }),
            }))
        end
    end
    return nodes
end

render = function()
    panel.render(ui.column({ flexGrow = 1, gap = 12, padding = 14,
        fill = "#0b1220e8", border = "#7dcfff55", borderWidth = 1, radius = 14 }, {
        ui.row({ gap = 10, align = "center" }, {
            ui.glyph({ name = "keyboard", size = 24, color = CYAN }),
            ui.column({ gap = 2, flexGrow = 1 }, {
                ui.label({ text = "m4j0r.one · SHORTCUTS", fontSize = 16,
                    fontFamily = MONO, fontWeight = "bold", color = CYAN }),
                ui.label({ text = "Yazi · ncspot · Niri", fontSize = 12,
                    fontFamily = MONO, color = PINK }),
            }),
            ui.button({ glyph = "x", variant = "ghost", onClick = "onCloseClicked" }),
        }),
        ui.row({ gap = 8, align = "center" }, {
            ui.button({ text = "YAZI", controlSize = "md", variant = "outline",
                selected = activeTab == "yazi", onClick = "onYaziClicked" }),
            ui.button({ text = "SPOTIFY", controlSize = "md", variant = "outline",
                selected = activeTab == "spotify", onClick = "onSpotifyClicked" }),
            ui.button({ text = "NIRI", controlSize = "md", variant = "outline",
                selected = activeTab == "niri", onClick = "onNiriClicked" }),
            ui.spacer({ flexGrow = 1 }),
            ui.button({ text = "Zurück", controlSize = "sm",
                visible = activeTab == "niri" and #niriRows > NIRI_PAGE_SIZE,
                enabled = niriPage > 1, onClick = "onPrevPage" }),
            ui.label({ text = tostring(niriPage) .. "/" ..
                tostring(math.max(1, math.ceil(#niriRows / NIRI_PAGE_SIZE))),
                fontSize = 11, color = CYAN,
                visible = activeTab == "niri" and #niriRows > NIRI_PAGE_SIZE }),
            ui.button({ text = "Weiter", controlSize = "sm",
                visible = activeTab == "niri" and #niriRows > NIRI_PAGE_SIZE,
                enabled = niriPage * NIRI_PAGE_SIZE < #niriRows,
                onClick = "onNextPage" }),
            ui.button({ text = "Neu laden", glyph = "refresh", controlSize = "sm",
                visible = activeTab == "niri", onClick = "onReloadClicked" }),
        }),
        ui.label({ text = niriStatus, color = "#a9b1d6", fontSize = 11,
            fontFamily = MONO, visible = activeTab == "niri" }),
        ui.separator({ thickness = 1, color = "#f7768e55" }),
        ui.scroll({ key = activeTab .. ":" .. tostring(niriPage),
            flexGrow = 1, gap = 8, align = "stretch" }, buildRows()),
    }))
end

function onOpen(_context)
    panelIsOpen = true
    if activeTab == "niri" then reloadNiri() end
    render()
end

function onYaziClicked()
    activeTab = "yazi"
    render()
end

function onSpotifyClicked()
    activeTab = "spotify"
    render()
end

function onNiriClicked()
    activeTab = "niri"
    niriStatus = "Lade …"
    niriRows = {}
    niriPage = 1
    render()
    reloadNiri()
end

function onReloadClicked()
    reloadNiri()
    render()
end

function onPrevPage()
    if niriPage > 1 then
        niriPage = niriPage - 1
        render()
    end
end

function onNextPage()
    if niriPage * NIRI_PAGE_SIZE < #niriRows then
        niriPage = niriPage + 1
        render()
    end
end

function onCloseClicked()
    panel.close()
end

function onClose()
    panelIsOpen = false
end
