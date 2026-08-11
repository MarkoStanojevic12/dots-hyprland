import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

/**
 * A content box that puts what it shows on the clipboard when clicked.
 *
 * The text inside these boxes is laid out as plain labels rather than an
 * editor, so there is nothing to drag-select; a click on the whole box is the
 * affordance instead. It is deliberately indistinguishable from the plain
 * Rectangle it replaces until the pointer is over it, so a transcript full of
 * them stays quiet to read.
 */
Rectangle {
    id: root
    property string copyText: ""
    property string hint: Translation.tr("Click to copy")
    readonly property bool copyable: root.copyText.length > 0

    // StyledToolTip reads `parent.hovered`, and treats it being undefined as
    // "always show" — so a plain Rectangle has to declare one.
    readonly property bool hovered: copyArea.containsMouse && root.copyable

    // The tooltip is already open under the cursor that just clicked, so it can
    // carry the confirmation without putting anything new on screen.
    property bool copied: false

    radius: Appearance.rounding.verysmall
    color: (copyArea.containsMouse && root.copyable)
        ? Appearance.colors.colLayer1Hover
        : Appearance.colors.colLayer1

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    MouseArea {
        id: copyArea
        anchors.fill: parent
        enabled: root.copyable
        hoverEnabled: true
        cursorShape: root.copyable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            Quickshell.clipboardText = root.copyText;
            root.copied = true;
            copiedTimer.restart();
        }
        onExited: root.copied = false
    }

    Timer {
        id: copiedTimer
        interval: 1500
        onTriggered: root.copied = false
    }

    StyledToolTip {
        text: root.copied ? Translation.tr("Copied") : root.hint
    }
}
