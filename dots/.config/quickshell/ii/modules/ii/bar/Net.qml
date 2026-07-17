import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// Network throughput indicator: download + upload speeds, with a wave-based
// hover (NetPopup) mirroring the Temps widget.
MouseArea {
    id: root
    property bool alwaysShowAllResources: false
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    visible: Config.options.bar.resources.showNetwork || root.alwaysShowAllResources

    function formatSpeed(bytesPerSec) {
        return `${(bytesPerSec / (1024 * 1024)).toFixed(1)}M`;
    }

    RowLayout {
        id: rowLayout
        spacing: 8
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        RowLayout {
            spacing: 2
            MaterialSymbol {
                fill: 1
                text: "download"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                text: root.formatSpeed(ResourceUsage.netDownSpeed)
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }

        RowLayout {
            spacing: 2
            MaterialSymbol {
                fill: 1
                text: "upload"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                text: root.formatSpeed(ResourceUsage.netUpSpeed)
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    NetPopup {
        hoverTarget: root
    }
}
