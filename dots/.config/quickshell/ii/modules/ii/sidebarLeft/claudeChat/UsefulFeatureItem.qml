import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One saved prompt in the useful features dropdown.
 */
RippleButton {
    id: root
    // { title, description, icon, prompt }
    required property var feature

    implicitHeight: featureRow.implicitHeight + 12
    buttonRadius: Appearance.rounding.small

    contentItem: RowLayout {
        id: featureRow
        anchors {
            fill: parent
            leftMargin: 8
            rightMargin: 8
        }
        spacing: 8

        MaterialSymbol {
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
            text: root.feature?.icon ?? "bolt"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
                text: root.feature?.title ?? ""
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: root.feature?.description ?? ""
            }
        }
    }
}
