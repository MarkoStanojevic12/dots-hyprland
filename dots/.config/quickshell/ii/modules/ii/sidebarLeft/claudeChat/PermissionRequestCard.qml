import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Asks before Claude runs a tool it isn't already allowed to use.
 *
 * The CLI hands us its own suggestion for what "always" should mean — usually
 * a rule for this exact command — so that is what the third button applies
 * rather than something broader we invented.
 */
Rectangle {
    id: root
    // { toolName, displayName, description, input, suggestions }
    required property var request

    readonly property var remember: ClaudeCode.rememberableSuggestion(root.request)
    readonly property string command: root.request?.input?.command ?? ""
    readonly property string filePath: root.request?.input?.file_path ?? ""

    implicitHeight: layout.implicitHeight + 20
    radius: Appearance.rounding.small
    color: Appearance.colors.colSecondaryContainer

    ColumnLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 10
        }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.m3colors.m3onSecondaryContainer
                text: "encrypted"
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSecondaryContainer
                text: Translation.tr("Allow %1?").arg(root.request?.displayName ?? "")
            }
        }

        StyledText { // What it actually wants to do
            Layout.fillWidth: true
            visible: text.length > 0
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: (root.command.length > 0 || root.filePath.length > 0)
                ? Appearance.font.family.monospace
                : Appearance.font.family.main
            color: Appearance.m3colors.m3onSecondaryContainer
            text: root.command.length > 0 ? root.command
                : root.filePath.length > 0 ? root.filePath
                : (root.request?.description ?? "")
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.command.length > 0 && (root.request?.description ?? "").length > 0
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            text: root.request?.description ?? ""
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6

            RippleButton {
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                toggled: true
                onClicked: ClaudeCode.answerPermission("allow", null)

                contentItem: StyledText {
                    anchors.centerIn: parent
                    leftPadding: 12
                    rightPadding: 12
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onPrimary
                    text: Translation.tr("Allow")
                }
            }

            RippleButton {
                visible: root.remember !== null
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                onClicked: ClaudeCode.answerPermission("allow", root.remember)

                contentItem: StyledText {
                    anchors.centerIn: parent
                    leftPadding: 12
                    rightPadding: 12
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                    text: Translation.tr("Always")
                }

                StyledToolTip {
                    text: root.remember?.type === "addRules"
                        ? Translation.tr("Stop asking for this exact command")
                        : Translation.tr("Stop asking for edits this session")
                }
            }

            Item { Layout.fillWidth: true }

            RippleButton {
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                onClicked: ClaudeCode.answerPermission("deny", null)

                contentItem: StyledText {
                    anchors.centerIn: parent
                    leftPadding: 12
                    rightPadding: 12
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3error
                    text: Translation.tr("Deny")
                }
            }
        }
    }
}
