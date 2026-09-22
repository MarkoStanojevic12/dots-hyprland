import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * One icon in the Claude chat header.
 *
 * Every header layout draws the same set of buttons; only the arrangement
 * differs between them. Keeping the button itself here is what makes a layout
 * a layout rather than another copy of all five buttons.
 */
RippleButton {
    id: root

    // A Material symbol, or an asset name for the one icon that isn't one
    // (claude-symbolic, which has no Material equivalent). Not `icon`: Button
    // declares that one FINAL, and overriding it fails the whole config load.
    property string symbol: ""
    property string assetIcon: ""
    property string tooltipText: ""

    implicitWidth: 32
    implicitHeight: 32
    buttonRadius: Appearance.rounding.small

    contentItem: Item {
        anchors.fill: parent

        MaterialSymbol {
            visible: root.assetIcon.length === 0
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            iconSize: Appearance.font.pixelSize.larger * ClaudeCode.textScale
            color: root.toggled ? Appearance.m3colors.m3onPrimary
                : root.enabled ? Appearance.colors.colOnLayer1
                : Appearance.colors.colOnLayer1Inactive
            text: root.symbol
        }

        // Loaded rather than hidden: a CustomIcon with no source still asks
        // for the icon folder itself and warns that it cannot open it, once
        // per button, on every reload.
        Loader {
            active: root.assetIcon.length > 0
            anchors.centerIn: parent
            width: 18
            height: 18

            sourceComponent: CustomIcon {
                width: 18
                height: 18
                source: root.assetIcon
                colorize: true
                color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
            }
        }
    }

    StyledToolTip {
        text: root.tooltipText
        extraVisibleCondition: root.tooltipText.length > 0
    }
}
