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

    color: "transparent"
    readonly property real padding: Appearance.sizes.elevationMargin
    implicitWidth: menuColumn.implicitWidth + (menuBackground.padding + root.padding) * 2
    implicitHeight: menuColumn.implicitHeight + (menuBackground.padding + root.padding) * 2

    function close() {
        root.visible = false;
        root.menuClosed();
    }

    // Dismissed on purpose rather than on a hover-out timer; see the same change
    // in DictationModelMenu for why half a second was never enough.
    onVisibleChanged: {
        if (root.visible)
            GlobalFocusGrab.addPersistent(root);
        else
            GlobalFocusGrab.removePersistent(root);
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            root.close();
        }
    }

    MouseArea {
        id: menuMouseArea
        anchors.fill: parent

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

                StyledText {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    Layout.bottomMargin: 2
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Record audio")
                }

                // Toggles deliberately leave the menu open: both of them are
                // usually reviewed together before starting a recording.
                RippleButton {
                    id: desktopAudioEntry
                    Layout.fillWidth: true
                    buttonRadius: menuBackground.radius - menuBackground.padding
                    horizontalPadding: 12
                    implicitWidth: contentItem.implicitWidth + desktopAudioEntry.horizontalPadding * 2
                    implicitHeight: 36
                    toggled: ScreenRecording.desktopAudio

                    releaseAction: () => ScreenRecording.toggleDesktopAudio()

                    contentItem: RowLayout {
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: parent.right
                            leftMargin: desktopAudioEntry.horizontalPadding
                            rightMargin: desktopAudioEntry.horizontalPadding
                        }
                        spacing: 8

                        MaterialSymbol {
                            iconSize: 18
                            text: "volume_up"
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Desktop audio")
                        }

                        MaterialSymbol {
                            iconSize: 16
                            text: "check"
                            opacity: ScreenRecording.desktopAudio ? 1 : 0
                        }
                    }
                }

                RippleButton {
                    id: micEntry
                    Layout.fillWidth: true
                    buttonRadius: menuBackground.radius - menuBackground.padding
                    horizontalPadding: 12
                    implicitWidth: contentItem.implicitWidth + micEntry.horizontalPadding * 2
                    implicitHeight: 36
                    toggled: ScreenRecording.microphone

                    releaseAction: () => ScreenRecording.toggleMicrophone()

                    contentItem: RowLayout {
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: parent.right
                            leftMargin: micEntry.horizontalPadding
                            rightMargin: micEntry.horizontalPadding
                        }
                        spacing: 8

                        MaterialSymbol {
                            iconSize: 18
                            text: "mic"
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Microphone")
                        }

                        MaterialSymbol {
                            iconSize: 16
                            text: "check"
                            opacity: ScreenRecording.microphone ? 1 : 0
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }

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
