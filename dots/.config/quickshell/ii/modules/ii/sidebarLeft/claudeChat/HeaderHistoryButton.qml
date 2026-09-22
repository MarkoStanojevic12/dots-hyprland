import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The way into past conversations, and the label that says which one this is.
 *
 * With a label it is a pill that fills the header row; without one it is a
 * plain 32px icon, for the layouts where the tab strip already carries the
 * title and a second copy of it would only repeat the tabs.
 */
RippleButton {
    id: root

    property string label: ""
    property bool expanded: false
    property string tooltipText: ""
    readonly property bool labelled: root.label.length > 0

    implicitWidth: 32
    implicitHeight: 32
    buttonRadius: Appearance.rounding.small
    toggled: root.expanded

    contentItem: RowLayout {
        anchors {
            fill: parent
            leftMargin: root.labelled ? 8 : 0
            rightMargin: root.labelled ? 6 : 0
        }
        spacing: 6

        MaterialSymbol {
            // Alone in the row the icon has to centre itself; the layout would
            // otherwise leave it against the left edge of a 32px button.
            Layout.fillWidth: !root.labelled
            horizontalAlignment: root.labelled ? Text.AlignLeft : Text.AlignHCenter
            iconSize: Appearance.font.pixelSize.larger * ClaudeCode.textScale
            color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
            text: "history"
        }

        StyledText {
            visible: root.labelled
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small * ClaudeCode.textScale
            color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
            text: root.label
        }

        MaterialSymbol {
            visible: root.labelled
            iconSize: Appearance.font.pixelSize.normal * ClaudeCode.textScale
            color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
            text: root.expanded ? "expand_less" : "expand_more"
        }
    }

    StyledToolTip {
        text: root.tooltipText
        extraVisibleCondition: root.tooltipText.length > 0
    }
}
