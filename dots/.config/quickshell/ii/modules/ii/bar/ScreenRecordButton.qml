import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import Quickshell

CircleUtilButton {
    id: root

    readonly property color recordingColor: "#F44336"

    onClicked: ScreenRecording.toggle()
    altAction: () => {
        if (menuLoader.active)
            menuLoader.item?.close();
        else
            menuLoader.active = true;
    }

    MaterialSymbol {
        id: icon
        property color blinkColor: root.recordingColor

        horizontalAlignment: Qt.AlignHCenter
        fill: 1
        text: "videocam"
        iconSize: Appearance.font.pixelSize.large
        color: ScreenRecording.recording ? icon.blinkColor : Appearance.colors.colOnLayer2

        SequentialAnimation on blinkColor {
            running: ScreenRecording.recording
            loops: Animation.Infinite

            ColorAnimation {
                from: root.recordingColor
                to: ColorUtils.transparentize(root.recordingColor, 0.65)
                duration: 700
                easing.type: Easing.InOutQuad
            }
            ColorAnimation {
                to: root.recordingColor
                duration: 700
                easing.type: Easing.InOutQuad
            }
        }

        Loader {
            id: menuLoader
            active: false
            sourceComponent: RecorderMenu {
                anchorHovered: root.hovered
                anchor {
                    window: root.QsWindow.window
                    item: root
                    gravity: Config.options.bar.bottom ? Edges.Top : Edges.Bottom
                    edges: Config.options.bar.bottom ? Edges.Top : Edges.Bottom
                }
                Component.onCompleted: visible = true
                onMenuClosed: menuLoader.active = false
            }
        }
    }
}
