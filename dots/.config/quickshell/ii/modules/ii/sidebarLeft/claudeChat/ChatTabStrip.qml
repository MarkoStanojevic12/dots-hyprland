import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * The open conversations, above the chat.
 *
 * Every chip gets the same share of the row rather than sizing to its label: a
 * strip whose tabs move as conversations are opened and closed is one you have
 * to read before clicking.
 *
 * The height is stated rather than left to the layout because the Revealer this
 * sits in measures its child, and a layout reports nothing until it is polished.
 */
Item {
    id: root
    implicitHeight: 28

    RowLayout {
        anchors.fill: parent
        spacing: 4

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
