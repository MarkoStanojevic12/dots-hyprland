import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button
    property string day
    property int isToday
    property bool bold
    // Up to CalendarEvents.maxDots colours, one per calendar with an event today.
    property var dotColors: []
    property bool selected: false
    property var clickAction

    readonly property bool showDots: dotColors.length > 0
    readonly property bool dimmed: isToday == -1

    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 38;
    implicitHeight: 38;

    toggled: (isToday == 1)
    buttonRadius: Appearance.rounding.small
    downAction: clickAction

    // Selection ring. Today already reads as selected via `toggled`, so it only
    // shows on other days.
    Rectangle {
        anchors.fill: parent
        visible: button.selected && button.isToday != 1
        radius: button.buttonRadius
        color: "transparent"
        border.width: 1
        border.color: Appearance.colors.colPrimary
    }

    contentItem: Item {
        StyledText {
            anchors.centerIn: parent
            // Shift up to make room for the dot row without growing the cell.
            anchors.verticalCenterOffset: button.showDots ? -3 : 0
            text: button.day
            horizontalAlignment: Text.AlignHCenter
            font.weight: button.bold ? Font.DemiBold : Font.Normal
            color: (button.isToday == 1) ? Appearance.m3colors.m3onPrimary :
                (button.isToday == 0) ? Appearance.colors.colOnLayer1 :
                Appearance.colors.colOutlineVariant

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            Behavior on anchors.verticalCenterOffset {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            spacing: 2
            visible: button.showDots
            opacity: button.dimmed ? 0.45 : 1

            Repeater {
                model: button.dotColors
                delegate: Rectangle {
                    width: 4
                    height: 4
                    radius: 2
                    color: modelData
                }
            }
        }
    }
}
