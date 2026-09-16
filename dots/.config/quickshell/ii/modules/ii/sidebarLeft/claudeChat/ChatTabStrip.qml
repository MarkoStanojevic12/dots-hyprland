import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * The open conversations, above the chat.
 *
 * Every chip gets the same share of the row rather than sizing to its label: a
 * strip whose tabs move as conversations are opened and closed is one you have
 * to read before clicking.
 *
 * The tabs sit on a recessed rail and run down into its baseline: the rail's
 * edges, not the chips' own contrast, are what say where a tab starts and ends.
 *
 * The height is stated rather than left to the layout because the Revealer this
 * sits in measures its child, and a layout reports nothing until it is polished.
 */
Item {
    id: root
    implicitHeight: 34

    Rectangle { // The rail
        anchors.fill: parent
        color: Appearance.colors.colLayer2
        topLeftRadius: Appearance.rounding.small
        topRightRadius: Appearance.rounding.small
        bottomLeftRadius: 0
        bottomRightRadius: 0
    }

    Rectangle { // Baseline, so a tab's bottom edge is a line and not a guess
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: Appearance.colors.colOutlineVariant
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: 3
            rightMargin: 3
            topMargin: 3
            bottomMargin: 1
        }
        spacing: 6

        Repeater {
            model: ClaudeCode.tabs

            delegate: ChatTab {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                // Equal shares: without this the widest label takes the row.
                Layout.preferredWidth: 0
                Layout.minimumWidth: 44
                Layout.fillHeight: true

                session: modelData
                tabIndex: index
            }
        }
    }
}
