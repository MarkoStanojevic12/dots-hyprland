import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Effects

/**
 * One pasted image, in the composer before it is sent and in the message bubble
 * afterwards.
 */
Rectangle {
    id: root
    required property string path
    property bool canRemove: false
    property real size: 64
    signal remove

    implicitWidth: root.size
    implicitHeight: root.size
    radius: Appearance.rounding.verysmall
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant

    StyledImage {
        id: thumbnail
        anchors.fill: parent
        anchors.margins: 1
        source: Qt.resolvedUrl(root.path)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        visible: false // Only ever seen through the mask below
    }

    MultiEffect {
        anchors.fill: thumbnail
        source: thumbnail
        maskEnabled: true
        maskSource: thumbnailMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
        maskSpreadAtMax: 1
    }

    Rectangle {
        id: thumbnailMask
        width: thumbnail.width
        height: thumbnail.height
        radius: root.radius
        color: "black"
        antialiasing: true
        layer.enabled: true
        visible: false
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Qt.openUrlExternally(Qt.resolvedUrl(root.path))
    }

    RippleButton {
        visible: root.canRemove
        anchors {
            top: parent.top
            right: parent.right
            margins: 2
        }
        implicitWidth: 20
        implicitHeight: 20
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2
        onClicked: root.remove()

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnSurfaceVariant
            text: "close"
        }
    }
}
