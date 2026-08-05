import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One agent tool invocation, shown as a compact row: what it ran and whether
 * it's still running.
 */
Rectangle {
    id: root
    required property var toolCall

    readonly property bool running: root.toolCall?.status === "running"
    readonly property bool errored: root.toolCall?.status === "error"

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + 8 * 2
    radius: Appearance.rounding.small
    color: root.errored ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    RowLayout {
        id: rowLayout
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 8
            rightMargin: 8
        }
        spacing: 6

        MaterialSymbol {
            text: root.errored ? "error" : (root.toolCall?.icon ?? "build")
            iconSize: Appearance.font.pixelSize.large
            color: root.errored ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colSubtext
        }

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: root.errored ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnLayer2
            text: root.toolCall?.name ?? ""
        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            visible: text.length > 0
            text: root.toolCall?.detail ?? ""
        }

        // A quiet pulse while the tool is running; nothing once it's done, so
        // finished calls fade into the background instead of competing.
        Rectangle {
            implicitWidth: 6
            implicitHeight: 6
            radius: 3
            visible: root.running
            color: Appearance.colors.colPrimary

            SequentialAnimation on opacity {
                running: root.running
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.25; duration: 600; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.25; to: 1; duration: 600; easing.type: Easing.InOutQuad }
            }
        }
    }
}
