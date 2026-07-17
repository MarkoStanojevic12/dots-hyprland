import QtQuick
import qs.modules.common

// Crisp line + soft area-fill trend chart for a rolling history array (values
// assumed 0..maxValue). Repaints whenever `values` is reassigned.
Canvas {
    id: root
    property list<real> values: []
    property real maxValue: 1
    property color color: Appearance.m3colors.m3primary
    property real strokeWidth: 1.5

    implicitWidth: 132
    implicitHeight: 34

    onValuesChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        const vals = root.values;
        const n = vals.length;
        if (n < 2) return;
        const maxV = root.maxValue || 1;
        const w = width, h = height;
        const pad = root.strokeWidth;      // keep the stroke inside the canvas
        const usableH = h - pad * 2;

        function px(i) { return (i / (n - 1)) * w; }
        function py(i) {
            const frac = Math.max(0, Math.min(1, vals[i] / maxV));
            return pad + usableH - frac * usableH;
        }

        // Soft area fill under the curve.
        ctx.beginPath();
        ctx.moveTo(0, h);
        for (let i = 0; i < n; i++) ctx.lineTo(px(i), py(i));
        ctx.lineTo(w, h);
        ctx.closePath();
        ctx.fillStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.12);
        ctx.fill();

        // Crisp trend line.
        ctx.beginPath();
        for (let i = 0; i < n; i++) i === 0 ? ctx.moveTo(px(i), py(i)) : ctx.lineTo(px(i), py(i));
        ctx.strokeStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.9);
        ctx.lineWidth = root.strokeWidth;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.stroke();
    }
}
