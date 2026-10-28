import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Consecutive ticket, PR, issue and crash lines of a reply, each as a card
 * with whatever was said after the link underneath it.
 */
ColumnLayout {
    id: root
    required property var cards
    property int bodyFontSize: Appearance.font.pixelSize.small

    spacing: 6

    Repeater {
        model: root.cards
        delegate: ColumnLayout {
            id: entry
            required property var modelData
            Layout.fillWidth: true
            spacing: 3

            LinkCard {
                Layout.fillWidth: true
                link: entry.modelData
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                visible: entry.modelData.rest.length > 0
                wrapMode: Text.Wrap
                textFormat: Text.MarkdownText
                font.family: Appearance.font.family.reading
                font.pixelSize: Math.round(root.bodyFontSize * 0.9)
                color: Appearance.colors.colSubtext
                linkColor: Appearance.colors.colPrimary
                text: ChatLinks.decorate(entry.modelData.rest, Math.round(root.bodyFontSize * 0.85))
                onLinkActivated: link => {
                    ClaudeCode.openFileReference(link);
                    GlobalStates.sidebarLeftOpen = false;
                }
            }
        }
    }
}
