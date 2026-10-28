import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A list in a reply made of nothing but plain links, as one compact box.
 */
Rectangle {
    id: root
    // [{ url, text, label, rest, info }]
    required property var rows
    readonly property real scale: ClaudeCode.textScale

    implicitHeight: column.implicitHeight + 8
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer2

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 4
        }
        spacing: 0

        Repeater {
            model: root.rows
            delegate: RippleButton {
                id: row
                required property var modelData
                readonly property string name: {
                    const text = (row.modelData.text ?? "").replace(/`|\*\*/g, "").trim();
                    return text.length > 0 && text !== row.modelData.url ? text : row.modelData.info.short;
                }
                Layout.fillWidth: true
                implicitHeight: 28 * root.scale
                buttonRadius: Appearance.rounding.verysmall
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: {
                    ClaudeCode.openFileReference(row.modelData.url);
                    GlobalStates.sidebarLeftOpen = false;
                }

                contentItem: RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 7
                        rightMargin: 8
                    }
                    spacing: 7

                    LinkIcon {
                        info: row.modelData.info
                        size: 14 * root.scale
                    }
                    StyledText {
                        visible: text.length > 0
                        font.pixelSize: Appearance.font.pixelSize.smaller * root.scale
                        color: Appearance.colors.colSubtext
                        textFormat: Text.PlainText
                        text: row.modelData.label ?? ""
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallie * root.scale
                        color: Appearance.colors.colOnLayer2
                        textFormat: Text.PlainText
                        text: row.name
                    }
                    StyledText {
                        Layout.maximumWidth: column.width * 0.4
                        elide: Text.ElideMiddle
                        font.pixelSize: Appearance.font.pixelSize.smallest * root.scale
                        color: Appearance.colors.colSubtext
                        textFormat: Text.PlainText
                        text: row.modelData.info.host
                    }
                }

                StyledToolTip {
                    text: row.modelData.url
                }
            }
        }
    }
}
