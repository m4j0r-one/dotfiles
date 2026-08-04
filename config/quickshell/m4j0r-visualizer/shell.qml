import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    property int barCount: 64
    property var levels: Array(barCount).fill(0)

    function updateFrame(line) {
        const parts = line.trim().split(";")
        const nextLevels = []

        for (let i = 0; i < parts.length; ++i) {
            const number = Number(parts[i])

            if (!isNaN(number)) {
                nextLevels.push(
                    Math.max(0, Math.min(1, number / 1000))
                )
            }
        }

        if (nextLevels.length > 0) {
            while (nextLevels.length < barCount) {
                nextLevels.push(0)
            }

            levels = nextLevels.slice(0, barCount)
        }
    }

    function barColor(index) {
        const position = index / Math.max(1, barCount - 1)

        let r
        let g
        let b

        if (position < 0.5) {
            const mix = position * 2

            r = 255 + (138 - 255) * mix
            g = 47  + (44  - 47)  * mix
            b = 174 + (255 - 174) * mix
        } else {
            const mix = (position - 0.5) * 2

            r = 138 + (0   - 138) * mix
            g = 44  + (229 - 44)  * mix
            b = 255
        }

        return Qt.rgba(r / 255, g / 255, b / 255, 1)
    }

    Process {
        id: cavaProcess

        command: [
            "/usr/bin/cava",
            "-p",
            "/home/YOUR_USERNAME/.config/cava/m4j0r-visualizer.conf"
        ]

        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.updateFrame(data)
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => console.warn("Cava:", data)
        }

        onRunningChanged: {
            if (!running) {
                restartTimer.restart()
            }
        }
    }

    Timer {
        id: restartTimer

        interval: 1500
        repeat: false

        onTriggered: {
            cavaProcess.running = true
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                required property var modelData

                screen: modelData
                visible: modelData.name === "DP-2"

                WlrLayershell.namespace:
                    "m4j0r-audio-visualizer"

                WlrLayershell.layer:
                    WlrLayer.Bottom

                anchors {
                    left: true
                    right: true
                    bottom: true
                }

                margins {
                    left: 850
                    right: 12
                    bottom: 12
                }

                implicitHeight: 92
                exclusiveZone: 104
                focusable: false
                color: "transparent"

                Rectangle {
                    id: background

                    anchors.fill: parent

                    radius: 16
                    clip: true
                    antialiasing: true

                    color: "#B5070B14"

                    border.width: 1
                    border.color: "#6600E5FF"

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top

                            leftMargin: background.radius
                            rightMargin: background.radius
                            topMargin: 1
                        }

                        height: 1
                        radius: 1
                        antialiasing: true

                        gradient: Gradient {
                            orientation:
                                Gradient.Horizontal

                            GradientStop {
                                position: 0
                                color: "#CCFF2FAE"
                            }

                            GradientStop {
                                position: 0.5
                                color: "#998A2CFF"
                            }

                            GradientStop {
                                position: 1
                                color: "#CC00E5FF"
                            }
                        }
                    }

                    Item {
                        id: barArea

                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.topMargin: 12
                        anchors.bottomMargin: 10

                        Repeater {
                            model: root.barCount

                            Rectangle {
                                required property int index

                                readonly property real level:
                                    root.levels[index] || 0

                                readonly property real slotWidth:
                                    barArea.width / root.barCount

                                x: index * slotWidth
                                anchors.bottom:
                                    barArea.bottom

                                width: Math.max(
                                    3,
                                    slotWidth - 4
                                )

                                height: Math.max(
                                    3,
                                    level * barArea.height
                                )

                                radius: width / 2
                                color: root.barColor(index)

                                opacity:
                                    0.32 + level * 0.68

                                Behavior on height {
                                    NumberAnimation {
                                        duration: 55
                                        easing.type:
                                            Easing.OutCubic
                                    }
                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 55
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
