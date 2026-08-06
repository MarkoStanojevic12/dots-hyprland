import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Popup shown shortly before an event starts. The card adapts to the event:
 * a conferencing event gets a prominent Join button, an event with some other
 * link gets Open, and a plain event just states what is about to happen.
 */
Scope {
    id: scope

    PanelWindow {
        id: root
        visible: CalendarAlerts.activeAlerts.length > 0 && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

        WlrLayershell.namespace: "quickshell:calendarAlert"
        WlrLayershell.layer: WlrLayer.Overlay
        // Never take keyboard focus -- this appears while you are working.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusiveZone: 0

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        // Only the cards are clickable; the rest of the screen stays usable.
        mask: Region {
            item: alertColumn
        }

        color: "transparent"

        ColumnLayout {
            id: alertColumn
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: Appearance.sizes.hyprlandGapsOut + 8
            width: 420
            spacing: 8

            Repeater {
                model: CalendarAlerts.activeAlerts

                delegate: Rectangle {
                    id: card
                    required property var modelData

                    readonly property string link: modelData.meetingUrl ?? ""
                    readonly property bool hasLink: link.length > 0
                    readonly property bool isConference: modelData.isConference ?? false

                    Layout.fillWidth: true
                    implicitHeight: cardContent.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    StyledRectangularShadow {
                        target: card
                    }

                    // Calendar colour down the leading edge.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 4
                        radius: card.radius
                        color: card.modelData.color ?? Appearance.colors.colPrimary
                    }

                    RowLayout {
                        id: cardContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 18
                        anchors.rightMargin: 14
                        spacing: 12

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: card.isConference ? "videocam" : "event_upcoming"
                            iconSize: 28
                            color: card.isConference ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer0
                                text: card.modelData.title ?? ""
                            }
                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: scope.subtitleFor(card.modelData, clockTick.now)
                            }
                        }

                        DialogButton {
                            Layout.alignment: Qt.AlignVCenter
                            visible: card.hasLink
                            buttonText: card.isConference ? Translation.tr("Join") : Translation.tr("Open")
                            onClicked: CalendarAlerts.joinAndDismiss(card.modelData)
                        }

                        DialogButton {
                            Layout.alignment: Qt.AlignVCenter
                            buttonText: Translation.tr("Dismiss")
                            onClicked: CalendarAlerts.dismiss(card.modelData)
                        }
                    }
                }
            }
        }
    }

    // Drives the "in 2 minutes" / "starting now" text.
    Timer {
        id: clockTick
        property double now: Date.now()
        interval: 15000
        repeat: true
        running: CalendarAlerts.activeAlerts.length > 0
        triggeredOnStart: true
        onTriggered: clockTick.now = Date.now()
    }

    function subtitleFor(e, now) {
        const mins = Math.round((e.start.getTime() - now) / 60000);
        let when;
        if (mins > 1)
            when = Translation.tr("in %1 minutes").arg(mins);
        else if (mins === 1)
            when = Translation.tr("in 1 minute");
        else if (mins === 0)
            when = Translation.tr("starting now");
        else if (mins === -1)
            when = Translation.tr("started 1 minute ago");
        else
            when = Translation.tr("started %1 minutes ago").arg(-mins);

        const time = e.start.toLocaleTimeString(Qt.locale(), Config.options?.time?.format ?? "hh:mm");
        const where = (e.location && e.location.length > 0 && !/^https?:\/\//.test(e.location)) ? `  ·  ${e.location}` : "";
        return `${time}  ·  ${when}${where}`;
    }
}
