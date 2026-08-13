import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * Which output audio is going to, and a click to send it to the other one.
 */
MouseArea {
    id: root
    property color color: Appearance.colors.colOnLayer0

    // StyledToolTip reads `hovered` off its parent and stays permanently visible
    // when it finds nothing there — a MouseArea only has containsMouse.
    readonly property bool hovered: root.containsMouse

    implicitWidth: outputIcon.implicitWidth
    implicitHeight: outputIcon.implicitHeight
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    // Every other click in this pill opens the right sidebar. With only one
    // output there is nothing to switch to, so the press is better left to it.
    enabled: Audio.outputDevices.length > 1

    onClicked: Audio.cycleOutputDevice()

    MaterialSymbol {
        id: outputIcon
        anchors.centerIn: parent
        text: Audio.usingHeadphones ? "headphones" : "speaker"
        iconSize: Appearance.font.pixelSize.larger
        color: root.color
    }

    StyledToolTip {
        text: Audio.sink ? (root.enabled
            ? Translation.tr("%1 — click to switch").arg(Audio.friendlyDeviceName(Audio.sink))
            : Audio.friendlyDeviceName(Audio.sink)) : ""
    }
}
