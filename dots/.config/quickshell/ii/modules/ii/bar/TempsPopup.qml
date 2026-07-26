import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

// Hover card for the bar Temps widget: CPU + GPU temperatures drawn as two
// stacked flowing waves (à la the music WaveVisualizer) whose amplitude scales
// with temperature, tinted along a cool -> hot gradient, with the exact °C
// readout alongside. StyledPopup is a LazyLoader, so this whole card — and the
// animation Timer below — only exists/runs while the widget is hovered.
StyledPopup {
    id: root

    // ---- wave animation state ----
    readonly property int pointCount: 56
    readonly property real maxVisualizerValue: 100
    property real phase: 0
    property list<real> cpuPoints: []
    property list<real> gpuPoints: []

    // Map a temperature (°C) to a 0..1 "heat" fraction between an idle floor and
    // the sensor's own critical threshold (so each sensor is scaled fairly).
    function heatFrac(temp, critical) {
        const lo = 30;
        const hi = Math.max(lo + 1, critical); // critical °C == full heat
        return Math.max(0, Math.min(1, (temp - lo) / (hi - lo)));
    }

    // Cool -> warm -> hot gradient. ColorUtils.mix(c1, c2, p) weights c1 by p.
    readonly property color coolColor: "#4FC3F7" // calm blue
    readonly property color warmColor: "#F0A02E" // amber (matches Resource.qml warn tint)
    readonly property color hotColor: Appearance.colors.colError
    function heatColor(frac) {
        return frac < 0.5
            ? ColorUtils.mix(warmColor, coolColor, frac * 2)         // blue -> amber
            : ColorUtils.mix(hotColor, warmColor, (frac - 0.5) * 2); // amber -> red
    }

    // Build a brand-new points array each tick. WaveVisualizer ONLY repaints when
    // `points` is reassigned (never on in-place mutation), so we never push/splice.
    function buildWave(frac, seed) {
        const n = root.pointCount;
        const arr = new Array(n);
        // Floor of 0.08 keeps a gentle ripple even when idle; peak lands at ~0.85
        // of maxVisualizerValue so the wave never clips the (unclamped) top edge.
        const amp = (0.08 + 0.77 * frac) * root.maxVisualizerValue;
        for (let i = 0; i < n; i++) {
            const wobble = Math.sin(i * 0.28 + root.phase + seed)
                         + 0.5 * Math.sin(i * 0.11 - root.phase * 0.7 + seed);
            const env = 0.5 + 0.5 * (wobble / 1.5); // 0..1 envelope, fills like cava bars
            arr[i] = amp * env;
        }
        return arr;
    }

    // One temperature card: header (icon + label + °C) above its wave.
    component TempCard: Rectangle {
        id: card
        property string sIcon
        property string sLabel
        property real temp
        property int criticalThreshold
        property var wavePoints: []
        property string topProcess: ""
        property real topValue: 0
        readonly property real frac: root.heatFrac(temp, criticalThreshold)
        readonly property color accent: root.heatColor(frac)

        Layout.fillWidth: true
        implicitWidth: 300
        implicitHeight: cardCol.implicitHeight + 16
        radius: Appearance.rounding.small
        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.35)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: cardCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialSymbol {
                    fill: 1
                    text: card.sIcon
                    iconSize: Appearance.font.pixelSize.large
                    color: card.accent
                }
                StyledText {
                    text: card.sLabel
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurfaceVariant
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: `${Math.round(card.temp)}°C`
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: card.accent
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 54
                clip: true
                WaveVisualizer {
                    anchors.fill: parent
                    live: true
                    points: card.wavePoints
                    maxVisualizerValue: root.maxVisualizerValue
                    smoothing: 3
                    color: card.accent
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: card.topProcess !== ""
                MaterialSymbol {
                    fill: 1
                    text: "trending_up"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: card.topProcess
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    text: `${Math.round(card.topValue)}%`
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: card.accent
                }
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8

        // Non-visual: drives the wave point arrays. Lives inside the contentItem
        // (StyledPopup's single default Item child) and only ticks while hovered.
        Timer {
            running: root.active // LazyLoader.active -> only animates while hovered
            repeat: true
            interval: 33 // ~30 fps
            onTriggered: {
                root.phase += 0.16;
                root.cpuPoints = root.buildWave(
                    root.heatFrac(ResourceUsage.cpuTemperature, Config.options.bar.resources.cpuTempCriticalThreshold), 0);
                root.gpuPoints = root.buildWave(
                    root.heatFrac(ResourceUsage.gpuTemperature, Config.options.bar.resources.gpuTempCriticalThreshold), 1.7);
            }
        }

        Binding {
            target: ResourceUsage
            property: "topProcessPolling"
            value: root.active
        }

        StyledPopupHeaderRow {
            icon: "thermostat"
            label: Translation.tr("Temperatures")
        }

        TempCard {
            sIcon: "device_thermostat"
            sLabel: Translation.tr("CPU")
            temp: ResourceUsage.cpuTemperature
            criticalThreshold: Config.options.bar.resources.cpuTempCriticalThreshold
            wavePoints: root.cpuPoints
            topProcess: ResourceUsage.topCpuProcess
            topValue: ResourceUsage.topCpuPercentage
            visible: Config.options.bar.resources.showCpuTemperature
        }

        TempCard {
            sIcon: "thermostat"
            sLabel: Translation.tr("GPU")
            temp: ResourceUsage.gpuTemperature
            criticalThreshold: Config.options.bar.resources.gpuTempCriticalThreshold
            wavePoints: root.gpuPoints
            topProcess: ResourceUsage.topGpuProcess
            topValue: ResourceUsage.topGpuUtilization
            // nvidia-smi only; hide when there's no NVIDIA reading (stays 0).
            visible: Config.options.bar.resources.showGpuTemperature && ResourceUsage.gpuTemperature > 0
        }
    }
}
