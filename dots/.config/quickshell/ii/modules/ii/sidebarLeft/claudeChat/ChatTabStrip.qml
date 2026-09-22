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
 * Nothing is filled — the tabs are labels and the current one is underlined —
 * so the only line the strip draws itself is a hairline along its foot, which
 * is what separates the header from the messages under it. It runs edge to
 * edge, behind whatever a header layout parks at the right end: it is the
 * bottom of the header, not of the tabs.
 *
 * The height is stated rather than left to the layout because the Revealer this
 * sits in measures its child, and a layout reports nothing until it is polished.
 */
Item {
    id: root
    readonly property int baselineHeight: 1
    implicitHeight: 34 + root.baselineHeight

    // Room kept free at the right end of the tab row for whatever a header
    // layout parks there — a new-tab button, a cluster of them.
    property int trailingReserve: 0

    Rectangle { // The line under the header
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: root.baselineHeight
        color: Appearance.colors.colOutlineVariant
    }

    RowLayout {
        anchors {
            fill: parent
            // Barely inset: with no fill to keep clear of the strip's edges,
            // a margin here only steals width from the labels.
            leftMargin: 2
            rightMargin: 2 + root.trailingReserve
            topMargin: 3
            bottomMargin: root.baselineHeight
        }
        // The rules under the tabs are what divide them; a gap as well would
        // leave the underline of the current tab floating short of its label.
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
            }
        }
    }
}
