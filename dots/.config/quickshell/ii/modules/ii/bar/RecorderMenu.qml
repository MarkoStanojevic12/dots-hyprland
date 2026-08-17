pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root

    signal menuClosed

    property bool anchorHovered: false
    readonly property bool keepOpen: root.anchorHovered || menuMouseArea.containsMouse

    color: "transparent"
    readonly property real padding: Appearance.sizes.elevationMargin
    implicitWidth: menuColumn.implicitWidth + (menuBackground.padding + root.padding) * 2
    implicitHeight: menuColumn.implicitHeight + (menuBackground.padding + root.padding) * 2

    function close() {
        root.visible = false;
        root.menuClosed();
    }

    onKeepOpenChanged: {
        if (root.keepOpen)
            closeTimer.stop();
        else
            closeTimer.restart();
    }

    Timer {
        id: closeTimer
        interval: 500
        onTriggered: root.close()
    }

    MouseArea {
        id: menuMouseArea
        anchors.fill: parent
        hoverEnabled: true

        StyledRectangularShadow {
            target: menuBackground
        }

        Rectangle {
            id: menuBackground
            readonly property real padding: 4

            anchors {
                left: parent.left
                right: parent.right
                top: Config.options.bar.bottom ? undefined : parent.top
                bottom: Config.options.bar.bottom ? parent.bottom : undefined
                margins: root.padding
            }

            implicitHeight: menuColumn.implicitHeight + menuBackground.padding * 2
            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.windowRounding
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            ColumnLayout {
                id: menuColumn
                anchors {
                    fill: parent
                    margins: menuBackground.padding
                }
                spacing: 0

                RippleButton {
                    id: openFolderEntry
                    Layout.fillWidth: true
                    buttonRadius: menuBackground.radius - menuBackground.padding
                    horizontalPadding: 12
                    implicitWidth: contentItem.implicitWidth + openFolderEntry.horizontalPadding * 2
                    implicitHeight: 36

                    releaseAction: () => {
                        ScreenRecording.openFolder();
                        root.close();
                    }

                    contentItem: RowLayout {
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: parent.right
                            leftMargin: openFolderEntry.horizontalPadding
                            rightMargin: openFolderEntry.horizontalPadding
                        }
                        spacing: 8

                        MaterialSymbol {
                            iconSize: 18
                            text: "animated_images"
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Open recordings folder")
                        }
                    }
                }
            }
        }
    }
}
