import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The state of a ticket, PR, issue or crash, coloured by what it means rather
 * than what it is called: in review, open, blocked, merged or finished.
 */
Rectangle {
    id: root
    property string status: ""
    property string category: ""
    readonly property string tone: ChatLinks.statusTone(root.status, root.category)

    visible: root.status.length > 0
    implicitWidth: label.implicitWidth + 14
    implicitHeight: label.implicitHeight + 4
    radius: height / 2
    color: root.tone === "review" ? Appearance.m3colors.m3tertiaryContainer
        : root.tone === "open" ? Appearance.colors.colPrimaryContainer
        : root.tone === "blocked" ? Appearance.colors.colErrorContainer
        : root.tone === "merged" ? Appearance.colors.colSecondaryContainer
        : root.tone === "done" ? "transparent"
        : Appearance.colors.colLayer3
    border.width: root.tone === "done" ? 1 : 0
    border.color: Appearance.colors.colOutlineVariant

    StyledText {
        id: label
        anchors.centerIn: parent
        font.pixelSize: Appearance.font.pixelSize.smallest * ClaudeCode.textScale
        color: root.tone === "review" ? Appearance.m3colors.m3onTertiaryContainer
            : root.tone === "open" ? Appearance.colors.colOnPrimaryContainer
            : root.tone === "blocked" ? Appearance.colors.colOnErrorContainer
            : root.tone === "merged" ? Appearance.colors.colOnSecondaryContainer
            : Appearance.colors.colSubtext
        textFormat: Text.PlainText
        text: root.status
    }
}
