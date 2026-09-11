import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Picks the working directory: a path field and a grid of everywhere Claude
 * has already been used. Covers the whole tab and dims the chat behind it.
 */
Item {
    id: root
    property real dialogPadding: 12
    property real dialogMargin: 12
    readonly property int columns: Math.max(1, Math.floor((dialog.width - root.dialogPadding * 2) / 200))

    signal closed()

    // Typed paths are resolved by a script, so the answer arrives later as
    // either a new working directory or an error.
    property bool submitted: false
    Connections {
        target: ClaudeCode
        function onWorkingDirectoryChanged() {
            if (root.submitted) root.closed();
        }
    }

    function submit(path) {
        const trimmed = path.trim();
        if (trimmed.length === 0 || ClaudeCode.busy) return;
        if (trimmed === ClaudeCode.workingDirectory) {
            root.closed();
            return;
        }
        root.submitted = true;
        ClaudeCode.setWorkingDirectory(trimmed);
    }

    function choose(path) {
        if (path === ClaudeCode.workingDirectory) {
            root.closed();
            return;
        }
        root.submitted = true;
        ClaudeCode.setWorkingDirectory(path);
    }

    Component.onCompleted: {
        ClaudeCode.clearDirectoryError();
        ClaudeCode.refreshDirectories();
        directoryInput.text = ClaudeCode.workingDirectory;
        directoryInput.selectAll();
        directoryInput.forceActiveFocus();
    }

    Keys.onPressed: event => {
        if (event.key !== Qt.Key_Escape) return;
        root.closed();
        event.accepted = true;
    }

    Rectangle { // Scrim
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: Appearance.colors.colScrim

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            onClicked: root.closed()
        }
    }

    Rectangle { // The dialog
        id: dialog
        anchors.centerIn: parent
        width: (parent.width - root.dialogMargin * 2) / 2
        height: Math.min(dialogColumn.implicitHeight + root.dialogPadding * 2, parent.height - root.dialogMargin * 2)
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerHigh

        MouseArea { // Keeps clicks inside from reaching the scrim
            anchors.fill: parent
            hoverEnabled: true
        }

        ColumnLayout {
            id: dialogColumn
            anchors {
                fill: parent
                margins: root.dialogPadding
            }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.m3colors.m3onSurface
                    text: "folder_open"
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.m3colors.m3onSurface
                    text: Translation.tr("Working directory")
                }

                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.closed()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.m3colors.m3onSurface
                        text: "close"
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                MaterialTextField {
                    id: directoryInput
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    placeholderText: Translation.tr("Path to a directory…")
                    onAccepted: root.submit(directoryInput.text)
                    Keys.onPressed: event => {
                        if (event.key !== Qt.Key_Escape) return;
                        root.closed();
                        event.accepted = true;
                    }
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    enabled: directoryInput.text.trim().length > 0 && !ClaudeCode.busy
                    onClicked: root.submit(directoryInput.text)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        color: parent.enabled ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnLayer2Disabled
                        text: "subdirectory_arrow_left"
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: ClaudeCode.directoryError.length > 0
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.m3colors.m3error
                text: ClaudeCode.directoryError
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: Translation.tr("Somewhere Claude has already been used")
            }

            Rectangle { // The grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 60
                implicitHeight: Math.min(directoryGrid.contentHeight + 8, 6 * directoryGrid.cellHeight + 8)
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                GridView {
                    id: directoryGrid
                    anchors {
                        fill: parent
                        margins: 4
                    }
                    clip: true
                    cellWidth: Math.floor(width / root.columns)
                    cellHeight: 64
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel {
                        values: ClaudeCode.knownDirectories
                    }
                    delegate: DirectoryGridItem {
                        required property var modelData
                        width: directoryGrid.cellWidth - 4
                        height: directoryGrid.cellHeight - 4
                        directory: modelData
                        current: ClaudeCode.workingDirectory === modelData.path
                        onClicked: root.choose(modelData.path)
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - 16
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: ClaudeCode.knownDirectories.length === 0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: ClaudeCode.directoriesLoading
                        ? Translation.tr("Looking for directories…")
                        : Translation.tr("Nothing yet — type a path above")
                }
            }
        }
    }
}
