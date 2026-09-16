import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * The open conversations, above the chat.
 *
 * Every tab gets the same share of the row rather than sizing to its label: a
 * strip whose tabs move as conversations are opened and closed is one you have
 * to read before clicking.
 *
 * Browser-style: only the current tab is a surface, the rest are labels on the
 * sidebar background with a hairline between them. The side margins are the
 * room the current tab's flared bottom corners need to stay inside the strip.
 *
 * Under the tabs runs a solid baseline in the same colour as the current one,
 * edge to edge and with nothing below it — the chat starts immediately after —
 * so the current tab has a surface to flare into instead of ending in mid-air.
 *
 * The height is stated rather than left to the layout because the Revealer this
 * sits in measures its child, and a layout reports nothing until it is polished.
 */
Item {
    id: root
    readonly property int baselineHeight: 3
    implicitHeight: 34 + root.baselineHeight

    // Which tab the pointer is on, so a tab can drop the hairline it shares
    // with its neighbour. A tab only knows its own hover state.
    property int hoveredIndex: -1

    Rectangle { // The baseline the current tab runs into
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: root.baselineHeight
        color: Appearance.colors.colPrimaryContainer
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: 6
            rightMargin: 6
            topMargin: 3
            bottomMargin: root.baselineHeight
        }
        // Tabs meet edge to edge; the hairline, not a gap, is what separates them.
        spacing: 0

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
                stripHoveredIndex: root.hoveredIndex
                onHoverRequested: (hoveredTab, entered) => {
                    if (entered) root.hoveredIndex = hoveredTab;
                    else if (root.hoveredIndex === hoveredTab) root.hoveredIndex = -1;
                }
            }
        }
    }
}
