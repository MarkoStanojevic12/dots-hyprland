import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A thinking pause in the timeline.
 *
 * Deliberately lighter than ToolCallChip: no background, no expander. The
 * thinking text never reaches the client, so there is nothing to open — this is
 * a time marker, and it should read as one rather than compete with the tool
 * calls around it.
 *
 * The height matches a collapsed ToolCallChip on purpose, so its label lands on
 * the same line as its neighbours' and the rail dots stay evenly spaced.
 */
Item {
    id: root
    required property var toolCall

    implicitHeight: 32

    RowLayout {
        anchors {
            left: parent.left
            right: parent.right
            leftMargin: 8
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        spacing: 6

        MaterialSymbol {
            text: root.toolCall?.icon ?? "neurology"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.toolCall?.detail ?? ""
        }
    }
}
