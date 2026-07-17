import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    // Helper function to format KB to GB
    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    // fillHeight on each column + a flexible spacer above each Sparkline keeps
    // the three sparklines aligned along a common bottom edge even though the
    // columns have different numbers of value rows.
    RowLayout {
        anchors.centerIn: parent
        spacing: 12

        ColumnLayout {
            Layout.fillHeight: true
            spacing: 8

            StyledPopupHeaderRow {
                icon: "memory"
                label: "RAM"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "clock_loader_60"
                    label: Translation.tr("Used:")
                    value: root.formatKB(ResourceUsage.memoryUsed)
                }
                StyledPopupValueRow {
                    icon: "check_circle"
                    label: Translation.tr("Free:")
                    value: root.formatKB(ResourceUsage.memoryFree)
                }
                StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatKB(ResourceUsage.memoryTotal)
                }
            }
            Item { Layout.fillHeight: true }
            Sparkline {
                Layout.fillWidth: true
                implicitWidth: 132
                implicitHeight: 34
                values: ResourceUsage.memoryUsageHistory
                color: Appearance.m3colors.m3primary
            }
        }

        ColumnLayout {
            visible: ResourceUsage.swapTotal > 0
            Layout.fillHeight: true
            spacing: 8

            StyledPopupHeaderRow {
                icon: "swap_horiz"
                label: "Swap"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "clock_loader_60"
                    label: Translation.tr("Used:")
                    value: root.formatKB(ResourceUsage.swapUsed)
                }
                StyledPopupValueRow {
                    icon: "check_circle"
                    label: Translation.tr("Free:")
                    value: root.formatKB(ResourceUsage.swapFree)
                }
                StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatKB(ResourceUsage.swapTotal)
                }
            }
            Item { Layout.fillHeight: true }
            Sparkline {
                Layout.fillWidth: true
                implicitWidth: 132
                implicitHeight: 34
                values: ResourceUsage.swapUsageHistory
                color: Appearance.m3colors.m3primary
            }
        }

        ColumnLayout {
            Layout.fillHeight: true
            spacing: 8

            StyledPopupHeaderRow {
                icon: "planner_review"
                label: "CPU"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "bolt"
                    label: Translation.tr("Load:")
                    value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
                }
            }
            Item { Layout.fillHeight: true }
            Sparkline {
                Layout.fillWidth: true
                implicitWidth: 132
                implicitHeight: 34
                values: ResourceUsage.cpuUsageHistory
                color: Appearance.m3colors.m3primary
            }
        }
    }
}
