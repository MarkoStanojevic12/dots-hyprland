import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One slash command suggestion. The list comes from the CLI itself, so it
 * matches whatever skills and commands are actually installed.
 */
RippleButton {
    id: root
    // { name, description, argumentHint }
    required property var command

    implicitHeight: 34
    buttonRadius: Appearance.rounding.small

    contentItem: RowLayout {
        anchors {
            fill: parent
            leftMargin: 8
            rightMargin: 8
        }
        spacing: 8

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colOnLayer1
            text: `/${root.command?.name ?? ""}`
        }

        StyledText {
            visible: text.length > 0
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colSubtext
            text: root.command?.argumentHint ?? ""
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            text: root.command?.description ?? ""
        }
    }
}
