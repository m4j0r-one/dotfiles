import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true

    property real contentPreferredWidth: 760 * Style.uiScaleRatio
    property real contentPreferredHeight: 720 * Style.uiScaleRatio

    anchors.fill: parent

    readonly property color cyan: "#7dcfff"
    readonly property color pink: "#f7768e"
    readonly property color bgDeep: "#0b1220"
    readonly property color cardBg: "#111a2a"
    readonly property color keyBg: "#172438"

    property string activeTab: "yazi"

    property var yaziRows: [
        { header: true, title: "NAVIGATION", accent: "cyan" },
        { key: "↑ / ↓", desc: "hoch / runter" },
        { key: "←", desc: "Ordner zurück" },
        { key: "→", desc: "Ordner betreten" },
        { key: "Backspace", desc: "Ordner zurück" },
        { key: "Enter", desc: "Datei / Ordner öffnen" },
        { key: "Home / End", desc: "Anfang / Ende" },
        { key: "PgUp / PgDn", desc: "seitenweise hoch / runter" },
        { key: "Space", desc: "Datei markieren" },

        { header: true, title: "DATEIEN", accent: "pink" },
        { key: "Ctrl+C", desc: "kopieren" },
        { key: "Ctrl+X", desc: "ausschneiden" },
        { key: "Ctrl+V", desc: "einfügen" },
        { key: "F2", desc: "umbenennen" },
        { key: "Delete", desc: "in den Papierkorb" },
        { key: "Ctrl+F", desc: "Dateien suchen" },
        { key: "F1", desc: "Yazi-Hilfe / Keymap" },

        { header: true, title: "SERVER & NETZWERK", accent: "cyan" },
        { key: "g → w", desc: "Webserver per SFTP öffnen" },
        { key: "M → a", desc: "neue Netzwerkfreigabe hinzufügen" },
        { key: "M → m", desc: "gespeicherte SMB-Freigabe mounten + öffnen" },
        { key: "g → m", desc: "zu bereits gemounteter Freigabe springen" }
    ]

    property var spotifyRows: [
        { header: true, title: "WIEDERGABE", accent: "pink" },
        { key: "Space", desc: "Play / Pause" },
        { key: "n / p", desc: "nächster / vorheriger Track" },
        { key: "Ctrl+S", desc: "Shuffle ein / aus" },
        { key: "Ctrl+R", desc: "Repeat-Modus wechseln" },
        { key: ".", desc: "zufälligen Track im aktuellen Kontext starten" },
        { key: "> / <", desc: "5 Sekunden vor / zurück" },
        { key: "+ / -", desc: "Lautstärke ±5 %" },
        { key: "_", desc: "Mute ein / aus" },

        { header: true, title: "BIBLIOTHEK & SEITEN", accent: "cyan" },
        { key: "g → y", desc: "Liked Songs" },
        { key: "g → l", desc: "Bibliothek" },
        { key: "u → p", desc: "eigene Playlists" },
        { key: "u → a", desc: "gefolgte Artists" },
        { key: "u → A", desc: "gespeicherte Alben" },
        { key: "g → r", desc: "zuletzt gespielt" },
        { key: "g → t", desc: "Top Tracks" },
        { key: "g → s", desc: "Suchseite" },
        { key: "g → b", desc: "Browse-Seite" },
        { key: "g → Space", desc: "Kontext des aktuell laufenden Tracks" },
        { key: "g → L / l", desc: "Lyrics" },

        { header: true, title: "QUEUE & AKTIONEN", accent: "pink" },
        { key: "z", desc: "Queue öffnen" },
        { key: "Ctrl+Z / Z", desc: "markierten Eintrag zur Queue hinzufügen" },
        { key: "a", desc: "Aktionen für aktuell laufenden Track" },
        { key: "g → a / Ctrl+Space", desc: "Aktionen für markierten Eintrag" },
        { key: "Ctrl+G", desc: "markierten Track im Kontext anspringen" },
        { key: "g → c", desc: "aktuell laufenden Track im Kontext anspringen" },

        { header: true, title: "NAVIGATION", accent: "cyan" },
        { key: "↑ / ↓ · j / k", desc: "Auswahl hoch / runter" },
        { key: "PgUp / PgDn", desc: "seite hoch / runter" },
        { key: "g → g / Home", desc: "zum Anfang" },
        { key: "G / End", desc: "zum Ende" },
        { key: "Tab / Shift+Tab", desc: "Fenster-Fokus weiter / zurück" },
        { key: "Backspace", desc: "vorherige Seite" },
        { key: "Enter", desc: "Auswahl öffnen / bestätigen" },
        { key: "/", desc: "Suche" },

        { header: true, title: "SONSTIGES", accent: "pink" },
        { key: "D", desc: "Spotify-Ausgabegerät wechseln" },
        { key: "R", desc: "integrierten Client neu starten" },
        { key: "O", desc: "Spotify-Link aus Zwischenablage öffnen" },
        { key: "T", desc: "Theme wechseln" },
        { key: "? / Ctrl+H", desc: "Spotify-Shortcut-Hilfe" },
        { key: "Esc", desc: "Popup schließen" },
        { key: "q / Ctrl+C", desc: "spotify_player beenden" },

        { header: true, title: "SORTIEREN", accent: "cyan" },
        { key: "s → t", desc: "Tracks nach Titel" },
        { key: "s → a", desc: "Tracks nach Artist" },
        { key: "s → A", desc: "Tracks nach Album" },
        { key: "s → d", desc: "Tracks nach Dauer" },
        { key: "s → D", desc: "Tracks nach Hinzufügedatum" },
        { key: "s → r", desc: "Reihenfolge umkehren" },
        { key: "s → l → a", desc: "Bibliothek alphabetisch" },
        { key: "s → l → r", desc: "Bibliothek nach zuletzt hinzugefügt" }
    ]

    property var niriRows: []
    property bool niriInBinds: false
    property int niriDepth: 0
    property string niriStatus: "Noch nicht eingelesen."

    property var currentRows: activeTab === "yazi"
                              ? yaziRows
                              : (activeTab === "spotify" ? spotifyRows : niriRows)

    function braceCount(text, needle) {
        var count = 0
        for (var i = 0; i < text.length; i++) {
            if (text[i] === needle) count++
        }
        return count
    }

    function prettyNiriAction(action) {
        action = action.replace(/;\s*$/, "").trim()

        var names = {
            "close-window": "Fenster schließen",
            "toggle-overview": "Übersicht umschalten",
            "show-hotkey-overlay": "Niri-Hotkey-Hilfe anzeigen",
            "fullscreen-window": "Fullscreen umschalten",
            "maximize-column": "Spalte maximieren",
            "center-column": "Spalte zentrieren",
            "switch-preset-column-width": "Spaltenbreite wechseln",
            "focus-column-left": "Spalte links fokussieren",
            "focus-column-right": "Spalte rechts fokussieren",
            "focus-window-up": "Fenster oben fokussieren",
            "focus-window-down": "Fenster unten fokussieren",
            "move-column-left": "Spalte nach links verschieben",
            "move-column-right": "Spalte nach rechts verschieben",
            "move-window-up": "Fenster nach oben verschieben",
            "move-window-down": "Fenster nach unten verschieben",
            "focus-workspace-up": "Workspace hoch",
            "focus-workspace-down": "Workspace runter"
        }

        if (names[action]) return names[action]

        var spawn = action.match(/^spawn\s+"([^"]+)"/)
        if (spawn) return "Start: " + spawn[1]

        var spawnSh = action.match(/^spawn-sh\s+"([^"]+)"/)
        if (spawnSh) {
            var txt = spawnSh[1]
            return txt.length > 72 ? txt.substring(0, 69) + "..." : txt
        }

        return action
    }

    function addNiriRow(key, desc) {
        var rows = niriRows.slice()
        rows.push({ key: key, desc: desc })
        niriRows = rows
    }

    function consumeNiriLine(raw) {
        var clean = raw.replace(/\/\/.*$/, "").trim()
        if (clean.length === 0) return

        if (!niriInBinds) {
            if (/^binds\s*\{/.test(clean)) {
                niriInBinds = true
                niriDepth = braceCount(clean, "{") - braceCount(clean, "}")
            }
            return
        }

        if (niriDepth === 1) {
            var match = clean.match(/^(\S+).*?\{\s*(.*?)\s*\}\s*$/)
            if (match && match[1] !== "}") {
                var titleMatch = clean.match(/hotkey-overlay-title="([^"]+)"/)
                var desc = titleMatch ? titleMatch[1] : prettyNiriAction(match[2])
                addNiriRow(match[1], desc)
            }
        }

        niriDepth += braceCount(clean, "{") - braceCount(clean, "}")
        if (niriDepth <= 0) {
            niriInBinds = false
            niriDepth = 0
        }
    }

    function reloadNiri() {
        niriRows = []
        niriInBinds = false
        niriDepth = 0
        niriStatus = "Lese ~/.config/niri/cfg/keybinds.kdl …"
        niriReader.running = true
    }

    Component.onCompleted: reloadNiri()

    Process {
        id: niriReader
        command: ["sh", "-lc", "cat \"$HOME/.config/niri/cfg/keybinds.kdl\""]
        stdout: SplitParser {
            onRead: data => root.consumeNiriLine(data)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.niriStatus = "Niri-Keybinds konnten nicht gelesen werden."
            } else if (root.niriRows.length === 0) {
                root.niriStatus = "binds-Block gefunden, aber keine unterstützten einzeiligen Bindings erkannt."
            } else {
                root.niriStatus = root.niriRows.length + " Bindings aus ~/.config/niri/cfg/keybinds.kdl"
            }
        }
    }

    component TabPill: Rectangle {
        required property string label
        required property string tabId
        required property color accent

        Layout.preferredHeight: 38 * Style.uiScaleRatio
        Layout.preferredWidth: 155 * Style.uiScaleRatio
        radius: 10 * Style.uiScaleRatio

        color: root.activeTab === tabId
       ? Qt.rgba(accent.r, accent.g, accent.b, 0.10)
       : "transparent"

border.width: 1
border.color: root.activeTab === tabId
              ? accent
              : Qt.rgba(accent.r, accent.g, accent.b, 0.45)

        Text {
            anchors.centerIn: parent
            text: parent.label
            color: root.activeTab === parent.tabId ? parent.accent : "#c7d1e0"
            font.family: "monospace"
            font.pixelSize: 13 * Style.uiScaleRatio
            font.bold: root.activeTab === parent.tabId
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.activeTab = parent.tabId
                if (parent.tabId === "niri") root.reloadNiri()
            }
        }
    }

    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"
        radius: 14 * Style.uiScaleRatio
        border.width: 1
        border.color: Qt.rgba(root.cyan.r, root.cyan.g, root.cyan.b, 0.30)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16 * Style.uiScaleRatio
            spacing: 12 * Style.uiScaleRatio

            RowLayout {
                Layout.fillWidth: true
                spacing: 10 * Style.uiScaleRatio

                NIcon {
                    icon: "keyboard"
                    color: root.cyan
                    pointSize: Style.fontSizeL
                }

                ColumnLayout {
                    spacing: 0

                    Text {
                        text: "m4j0r.one · SHORTCUTS"
                        color: root.cyan
                        font.family: "monospace"
                        font.bold: true
                        font.pixelSize: 16 * Style.uiScaleRatio
                    }

                    Text {
                        text: "Yazi · spotify_player · Niri"
                        color: root.pink
                        font.family: "monospace"
                        font.pixelSize: 12 * Style.uiScaleRatio
                    }
                }

                Item { Layout.fillWidth: true }

                NIconButton {
                    icon: "x"
                    tooltipText: "Schließen"
                    colorFg: root.pink
                    onClicked: {
                        if (pluginApi?.closePanel) {
                            pluginApi.closePanel(pluginApi.panelOpenScreen)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8 * Style.uiScaleRatio

                TabPill {
                    label: "YAZI"
                    tabId: "yazi"
                    accent: root.cyan
                }

                TabPill {
                    label: "SPOTIFY"
                    tabId: "spotify"
                    accent: root.pink
                }

                TabPill {
                    label: "NIRI"
                    tabId: "niri"
                    accent: root.cyan
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.activeTab === "niri"
                spacing: 8 * Style.uiScaleRatio

                Text {
                    Layout.fillWidth: true
                    text: root.niriStatus
                    color: "#a9b1d6"
                    font.family: "monospace"
                    font.pixelSize: 11 * Style.uiScaleRatio
                    elide: Text.ElideRight
                }

                NButton {
                    text: "Neu laden"
                    icon: "refresh"
                    onClicked: root.reloadNiri()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.rgba(root.pink.r, root.pink.g, root.pink.b, 0.22)
            }

            ScrollView {
                id: shortcutScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                Column {
                    id: shortcutsColumn
                    width: shortcutScroll.availableWidth
                    spacing: 8 * Style.uiScaleRatio

                    Repeater {
                        model: root.currentRows

                        delegate: Item {
                            required property var modelData

                            width: shortcutsColumn.width
                            height: modelData.header
                                    ? 34 * Style.uiScaleRatio
                                    : 50 * Style.uiScaleRatio

                            Text {
                                visible: !!modelData.header
                                anchors.left: parent.left
                                anchors.leftMargin: 4 * Style.uiScaleRatio
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 5 * Style.uiScaleRatio

                                text: modelData.header ? modelData.title : ""
                                color: modelData.accent === "pink" ? root.pink : root.cyan
                                font.family: "monospace"
                                font.bold: true
                                font.pixelSize: 12 * Style.uiScaleRatio
                            }

                            Rectangle {
                                visible: !modelData.header
                                anchors.fill: parent

                                color: Qt.rgba(0.05, 0.08, 0.13, 0.32)
                                radius: 9 * Style.uiScaleRatio
                                border.width: 1
                                border.color: Qt.rgba(root.cyan.r, root.cyan.g, root.cyan.b, 0.14)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8 * Style.uiScaleRatio
                                    anchors.rightMargin: 12 * Style.uiScaleRatio
                                    spacing: 14 * Style.uiScaleRatio

                                    Rectangle {
                                        Layout.preferredWidth: 185 * Style.uiScaleRatio
                                        Layout.minimumWidth: 185 * Style.uiScaleRatio
                                        Layout.maximumWidth: 185 * Style.uiScaleRatio
                                        Layout.preferredHeight: 34 * Style.uiScaleRatio

                                        radius: 7 * Style.uiScaleRatio
                                        color: Qt.rgba(0.07, 0.11, 0.17, 0.38)
                                        border.width: 1
                                        border.color: Qt.rgba(root.pink.r, root.pink.g, root.pink.b, 0.48)

                                        Text {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8 * Style.uiScaleRatio
                                            anchors.rightMargin: 8 * Style.uiScaleRatio

                                            text: modelData.header ? "" : modelData.key
                                            color: root.cyan
                                            font.family: "monospace"
                                            font.bold: true
                                            font.pixelSize: 12 * Style.uiScaleRatio
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter

                                        text: modelData.header ? "" : modelData.desc
                                        color: "#e4eaf2"
                                        font.family: "monospace"
                                        font.pixelSize: 12 * Style.uiScaleRatio
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: 1
                        height: 8 * Style.uiScaleRatio
                    }
                }
            }
        }
    }
}
