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
    implicitWidth: Math.max(180, menuColumn.implicitWidth) + (menuBackground.padding + root.padding) * 2
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
                bottom: parent.bottom
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

                StyledText {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    Layout.bottomMargin: 2
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Dictation model")
                }

                Repeater {
                    model: ScriptModel {
                        values: ClaudeCode.dictationModels
                    }

                    delegate: RippleButton {
                        id: entry
                        required property string modelData
                        readonly property bool current: modelData === ClaudeCode.dictationServerModel

                        Layout.fillWidth: true
                        buttonRadius: menuBackground.radius - menuBackground.padding
                        horizontalPadding: 12
                        implicitHeight: 34
                        toggled: entry.current

                        releaseAction: () => {
                            ClaudeCode.selectDictationModel(entry.modelData);
                            root.close();
                        }

                        contentItem: RowLayout {
                            anchors {
                                verticalCenter: parent.verticalCenter
                                left: parent.left
                                right: parent.right
                                leftMargin: entry.horizontalPadding
                                rightMargin: entry.horizontalPadding
                            }
                            spacing: 8

                            MaterialSymbol {
                                iconSize: 16
                                text: "check"
                                opacity: entry.current ? 1 : 0
                            }

                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                text: entry.modelData
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    Layout.topMargin: 2
                    visible: ClaudeCode.dictationModels.length === 0
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Dictation server not reachable")
                }
            }
        }
    }
}
