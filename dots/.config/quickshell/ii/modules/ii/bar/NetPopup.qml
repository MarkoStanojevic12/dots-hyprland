import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Hover card for the bar Net widget: download + upload speeds drawn as two
// stacked flowing waves (like TempsPopup) whose amplitude scales with the
// current throughput, with the exact rate alongside. StyledPopup is a
// LazyLoader, so the card and its animation Timer only exist while hovered.
StyledPopup {
    id: root

    readonly property int pointCount: 56
    readonly property real maxVisualizerValue: 100
    property real phase: 0
    property list<real> downPoints: []
    property list<real> upPoints: []

    readonly property color downColor: "#66BB6A" // green
    readonly property color upColor: "#AB47BC"   // purple

    // Live connection details, refreshed only while the card is hovered.
    property string ipAddress: ""
    property real pingMs: -1

    function formatBytes(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let v = bytes, i = 0;
        while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
        return `${i === 0 ? Math.round(v) : v.toFixed(1)} ${units[i]}`;
    }

    function pingColor(ms) {
        if (ms < 0) return Appearance.colors.colOnSurfaceVariant;
        if (ms <= 50) return "#66BB6A";
        if (ms <= 120) return "#F0A02E";
        return Appearance.colors.colError;
    }

    // Log-scaled 0..1 fraction: gentle floor so slow transfers still ripple,
    // reaching full at the configured "full speed".
    function speedFrac(bytesPerSec, fullSpeed) {
        if (bytesPerSec <= 0) return 0;
        const floor = 32 * 1024;
        const f = Math.log(1 + bytesPerSec / floor)
                / Math.log(1 + Math.max(floor + 1, fullSpeed) / floor);
        return Math.max(0, Math.min(1, f));
    }

    function formatSpeed(bytesPerSec) {
        return `${(bytesPerSec / (1024 * 1024)).toFixed(2)} MB/s`;
    }

    // Build a brand-new points array each tick. WaveVisualizer ONLY repaints when
    // `points` is reassigned (never on in-place mutation), so we never push/splice.
    function buildWave(frac, seed) {
        const n = root.pointCount;
        const arr = new Array(n);
        const amp = (0.08 + 0.77 * frac) * root.maxVisualizerValue;
        for (let i = 0; i < n; i++) {
            const wobble = Math.sin(i * 0.28 + root.phase + seed)
                         + 0.5 * Math.sin(i * 0.11 - root.phase * 0.7 + seed);
            const env = 0.5 + 0.5 * (wobble / 1.5);
            arr[i] = amp * env;
        }
        return arr;
    }

    component SpeedCard: Rectangle {
        id: card
        property string sIcon
        property string sLabel
        property real speed
        property color accent
        property var wavePoints: []

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
                    text: root.formatSpeed(card.speed)
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
        }
    }

    component InfoRow: RowLayout {
        property string sIcon
        property string sLabel
        property string sValue
        property color valueColor: Appearance.colors.colOnLayer1
        Layout.fillWidth: true
        spacing: 8
        MaterialSymbol {
            fill: 1
            text: sIcon
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            text: sLabel
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.small
        }
        Item { Layout.fillWidth: true }
        StyledText {
            text: sValue
            color: valueColor
            font.weight: Font.DemiBold
            font.pixelSize: Appearance.font.pixelSize.small
            elide: Text.ElideRight
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8

        // Resolves the outbound source IP and pings the configured host. Only
        // runs while the card is hovered (poll Timer bound to root.active).
        Process {
            id: netInfoProc
            command: ["bash", "-c", `h='${Config.options.bar.resources.networkPingHost}'; ip=$(ip -4 route get "$h" 2>/dev/null | grep -oP 'src \\K[0-9.]+' | head -1); pg=$(ping -c1 -W1 "$h" 2>/dev/null | grep -oP 'time=\\K[0-9.]+'); printf '%s|%s' "$ip" "$pg"`]
            stdout: StdioCollector {
                onStreamFinished: {
                    const parts = text.trim().split("|");
                    root.ipAddress = parts[0] || "";
                    root.pingMs = parts[1] ? Math.round(Number(parts[1])) : -1;
                }
            }
        }

        Timer {
            running: root.active // LazyLoader.active -> only animates while hovered
            repeat: true
            interval: 33 // ~30 fps
            onTriggered: {
                root.phase += 0.16;
                root.downPoints = root.buildWave(
                    root.speedFrac(ResourceUsage.netDownSpeed, Config.options.bar.resources.networkDownFullSpeed), 0);
                root.upPoints = root.buildWave(
                    root.speedFrac(ResourceUsage.netUpSpeed, Config.options.bar.resources.networkUpFullSpeed), 1.7);
            }
        }

        Timer {
            running: root.active
            repeat: true
            interval: 2000
            triggeredOnStart: true
            onTriggered: if (!netInfoProc.running) netInfoProc.running = true
        }

        StyledPopupHeaderRow {
            icon: "swap_vert"
            label: Translation.tr("Network")
        }

        Rectangle {
            Layout.fillWidth: true
            implicitWidth: 300
            implicitHeight: infoCol.implicitHeight + 16
            radius: Appearance.rounding.small
            color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.35)
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            ColumnLayout {
                id: infoCol
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                InfoRow {
                    sIcon: Network.materialSymbol
                    sLabel: Translation.tr("Name")
                    sValue: Network.active?.ssid || Network.networkName || (Network.ethernet ? Translation.tr("Ethernet") : "—")
                }
                InfoRow {
                    sIcon: "lan"
                    sLabel: Translation.tr("IP")
                    sValue: root.ipAddress || "—"
                }
                InfoRow {
                    sIcon: "speed"
                    sLabel: Translation.tr("Ping")
                    sValue: root.pingMs >= 0 ? `${root.pingMs} ms` : "—"
                    valueColor: root.pingColor(root.pingMs)
                }
                InfoRow {
                    sIcon: "data_usage"
                    sLabel: Translation.tr("Today")
                    sValue: `↓ ${root.formatBytes(ResourceUsage.netDownTotal)}   ↑ ${root.formatBytes(ResourceUsage.netUpTotal)}`
                }
            }
        }

        SpeedCard {
            sIcon: "download"
            sLabel: Translation.tr("Download")
            speed: ResourceUsage.netDownSpeed
            accent: root.downColor
            wavePoints: root.downPoints
        }

        SpeedCard {
            sIcon: "upload"
            sLabel: Translation.tr("Upload")
            speed: ResourceUsage.netUpSpeed
            accent: root.upColor
            wavePoints: root.upPoints
        }
    }
}
