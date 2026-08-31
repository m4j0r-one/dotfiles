import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

NIconButton {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    icon: "keyboard"
    tooltipText: "Shortcuts · Yazi · Spotify · Niri"
    tooltipDirection: BarService.getTooltipDirection(screen?.name)

    baseSize: Style.getCapsuleHeightForScreen(screen?.name)
    applyUiScale: false
    customRadius: Style.radiusL

    colorBg: Style.capsuleColor
    colorFg: "#7dcfff"
    colorBgHover: Color.mHover
    colorFgHover: "#f7768e"
    colorBorder: "transparent"
    colorBorderHover: "#f7768e"

    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    onClicked: {
        if (pluginApi?.openPanel) {
            pluginApi.openPanel(screen, this)
        }
    }
}
