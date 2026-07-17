import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

// CPU + GPU temperature indicators, split out of Resources so they can carry
// their own wave-based hover (TempsPopup) while RAM/swap/CPU keep theirs.
MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool alwaysShowAllResources: false
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    visible: Config.options.bar.resources.showCpuTemperature
        || Config.options.bar.resources.showGpuTemperature
        || root.alwaysShowAllResources

    RowLayout {
        id: rowLayout

        spacing: 0
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        Resource {
            iconName: "device_thermostat"
            percentage: ResourceUsage.cpuTemperature / 100
            shown: Config.options.bar.resources.showCpuTemperature ||
                root.alwaysShowAllResources
            warningThreshold: Config.options.bar.resources.cpuTempWarningThreshold
            criticalThreshold: Config.options.bar.resources.cpuTempCriticalThreshold
        }

        Resource {
            iconName: "thermostat"
            percentage: ResourceUsage.gpuTemperature / 100
            shown: Config.options.bar.resources.showGpuTemperature ||
                root.alwaysShowAllResources
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: Config.options.bar.resources.gpuTempWarningThreshold
            criticalThreshold: Config.options.bar.resources.gpuTempCriticalThreshold
        }

    }

    TempsPopup {
        hoverTarget: root
    }
}
