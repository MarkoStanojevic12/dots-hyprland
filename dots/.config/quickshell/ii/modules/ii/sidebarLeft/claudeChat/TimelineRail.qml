import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * The gutter that turns a run of timeline entries into a connected thread: a
 * dot for this step, and line segments reaching towards the neighbouring ones.
 *
 * The downward segment deliberately overruns the item's own bounds by `gap` so
 * it crosses the layout spacing and meets the next rail. Nothing clips here, so
 * the overrun draws; the line simply stops when the next entry isn't a step.
 */
Item {
    id: root

    // Whether the entries either side are steps too, and so worth reaching for
    property bool linkUp: false
    property bool linkDown: false
    // Layout spacing to bridge on the way down
    property real gap: 0

    property bool running: false
    property bool errored: false
    property bool muted: false

    // Sits on the first line of the row's text rather than the middle of it, so
    // the dots stay level with the labels no matter how tall an entry grows
    // once it expands into a diff or a command's output.
    readonly property real dotCenter: 16
    readonly property real dotSize: running ? 9 : 7
    readonly property real lineWidth: 2

    readonly property color lineColor: Appearance.colors.colOutlineVariant
    readonly property color dotColor: root.errored ? Appearance.colors.colError
        : root.running ? Appearance.colors.colPrimary
        : root.muted ? Appearance.colors.colOutlineVariant
        : Appearance.colors.colOutline

    implicitWidth: 14
    Layout.fillHeight: true

    Rectangle { // Reaching up to the previous step
        visible: root.linkUp
        x: (root.width - width) / 2
        y: 0
        width: root.lineWidth
        height: Math.max(0, root.dotCenter - root.dotSize / 2 - 2)
        color: root.lineColor
    }

    Rectangle { // This step
        x: (root.width - width) / 2
        y: root.dotCenter - height / 2
        width: root.dotSize
        height: root.dotSize
        radius: height / 2
        color: root.dotColor
        antialiasing: true

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        SequentialAnimation on opacity { // Alive while the step is
            running: root.running
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.3; to: 1; duration: 600; easing.type: Easing.InOutQuad }
        }
    }

    Rectangle { // Reaching down to the next one, across the layout spacing
        visible: root.linkDown
        x: (root.width - width) / 2
        y: root.dotCenter + root.dotSize / 2 + 2
        width: root.lineWidth
        height: Math.max(0, root.height + root.gap - y)
        color: root.lineColor
    }
}
