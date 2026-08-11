import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * What a command was and what it printed, for an expanded Bash chip.
 */
ColumnLayout {
    id: root
    property string command: ""
    property string output: ""
    property bool errored: false
    property bool running: false

    // Long output is cut here rather than laying out thousands of rows.
    readonly property int shownLimit: 40
    readonly property var lines: root.output.length > 0
        ? root.output.replace(/\n+$/, "").split("\n")
        : []

    spacing: 3

    CopyableBox { // in
        Layout.fillWidth: true
        implicitHeight: commandText.implicitHeight + 10
        copyText: root.command
        hint: Translation.tr("Click to copy the command")

        RowLayout {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 6
                rightMargin: 6
            }
            spacing: 5

            StyledText {
                Layout.alignment: Qt.AlignTop
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colPrimary
                text: "$"
            }
            StyledText {
                id: commandText
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colOnLayer2
                text: root.command
            }
        }
    }

    CopyableBox { // out
        Layout.fillWidth: true
        visible: root.lines.length > 0 || root.running
        implicitHeight: outputColumn.implicitHeight + 10
        // The whole thing, including the lines past shownLimit that the view
        // only counts — that is usually the reason for copying it at all.
        copyText: root.output
        hint: Translation.tr("Click to copy the output")

        ColumnLayout {
            id: outputColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 6
                rightMargin: 6
                topMargin: 5
            }
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                visible: root.running && root.lines.length === 0
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: Translation.tr("running…")
            }

            Repeater {
                model: root.lines.slice(0, root.shownLimit)

                StyledText {
                    required property string modelData
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    color: root.errored ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                    text: modelData
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: root.lines.length > root.shownLimit
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: Translation.tr("…and %1 more lines").arg(root.lines.length - root.shownLimit)
            }
        }
    }

    StyledText { // Finished with nothing on stdout
        Layout.fillWidth: true
        Layout.leftMargin: 6
        visible: !root.running && root.lines.length === 0
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colSubtext
        text: Translation.tr("no output")
    }
}
