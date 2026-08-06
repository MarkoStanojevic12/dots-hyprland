import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The next seven days starting with today, each with its events listed inline
 * and clickable. A rolling window, not a Monday-aligned calendar week: days that
 * have already passed are wasted rows.
 *
 * Replaces the month grid as the primary calendar surface, because 38px day
 * tiles can't show event detail.
 */
Item {
    id: root

    readonly property var rows: {
        // Explicit read so this re-evaluates when the service reloads.
        const events = CalendarEvents.eventsByDate;
        return events ? CalendarEvents.rangeModel(CalendarEvents.rangeStart) : [];
    }

    // No scroll-to-today machinery here by design: the range starts at today,
    // so today is the first row and there is nothing to scroll to.
    Component.onCompleted: CalendarEvents.refresh()

    // Reopening the sidebar should always land on today. Paging back to look at
    // something and finding that window still there hours later isn't useful
    // state to preserve -- but don't fight the user mid-session, so this fires
    // only on the closed -> open transition.
    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen && !CalendarEvents.startsToday)
                CalendarEvents.goToToday();
        }
    }

    Keys.onPressed: event => {
        if (event.modifiers !== Qt.NoModifier)
            return;
        if (event.key === Qt.Key_PageDown) {
            CalendarEvents.shiftDays(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageUp) {
            CalendarEvents.shiftDays(-1);
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.rightMargin: 10
        spacing: 6

        // Week header
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
                text: `${CalendarEvents.startsToday ? "" : "• "}${CalendarEvents.rangeLabel(CalendarEvents.rangeStart)}`
            }

            CalendarHeaderButton {
                forceCircle: true
                visible: !CalendarEvents.startsToday
                tooltipText: Translation.tr("Back to today")
                downAction: () => CalendarEvents.goToToday()
                contentItem: MaterialSymbol {
                    text: "today"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
            CalendarHeaderButton {
                forceCircle: true
                tooltipText: Translation.tr("Earlier")
                downAction: () => CalendarEvents.shiftDays(-1)
                contentItem: MaterialSymbol {
                    text: "chevron_left"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
            CalendarHeaderButton {
                forceCircle: true
                tooltipText: Translation.tr("Later")
                downAction: () => CalendarEvents.shiftDays(1)
                contentItem: MaterialSymbol {
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
            CalendarHeaderButton {
                forceCircle: true
                enabled: !CalendarEvents.syncing
                tooltipText: CalendarEvents.syncing ? Translation.tr("Syncing…") : Translation.tr("Sync with Google now")
                downAction: () => CalendarEvents.syncNow()
                contentItem: MaterialSymbol {
                    text: "sync"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1

                    RotationAnimator on rotation {
                        running: CalendarEvents.syncing || CalendarEvents.loading
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1200
                    }
                }
            }
        }

        // The week
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // A Flickable + Repeater rather than a ListView on purpose. A ListView
            // recycles delegates, and swapping a Loader's sourceComponent on a
            // recycled delegate left stale heights behind -- day headers rendered
            // on top of event rows. A week is ~20 rows; there is nothing to gain
            // from recycling and a correctness bug to lose.
            StyledFlickable {
                id: flick
                anchors.fill: parent
                clip: true
                visible: CalendarEvents.available
                contentWidth: width
                contentHeight: weekColumn.implicitHeight
                
                Column {
                    id: weekColumn
                    width: flick.width
                    spacing: 3

                    Repeater {
                        id: weekRepeater
                        model: root.rows

                        delegate: Loader {
                            required property var modelData
                            width: weekColumn.width
                            // Fixed for the delegate's whole life -- Repeater
                            // rebuilds rather than recycles, so this never swaps
                            // underneath a live item.
                            sourceComponent: modelData.rowType === "header" ? dayHeader : (modelData.rowType === "empty" ? emptyRow : eventRow)

                            Component {
                                id: dayHeader
                                Item {
                                    implicitHeight: headerLabel.implicitHeight + 14
                                    StyledText {
                                        id: headerLabel
                                        anchors.left: parent.left
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 3
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: modelData.isToday ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                        opacity: modelData.isPast && !modelData.isToday ? 0.6 : 1
                                        text: modelData.title.toUpperCase()
                                    }
                                    // Today gets a rule across the row so the
                                    // current day is findable without reading
                                    // every label.
                                    Rectangle {
                                        anchors.left: headerLabel.right
                                        anchors.right: parent.right
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: headerLabel.verticalCenter
                                        height: 1
                                        visible: modelData.isToday
                                        color: Appearance.colors.colPrimary
                                        opacity: 0.35
                                    }
                                }
                            }

                            Component {
                                id: emptyRow
                                Item {
                                    implicitHeight: emptyLabel.implicitHeight + 4
                                    StyledText {
                                        id: emptyLabel
                                        anchors.left: parent.left
                                        anchors.leftMargin: 11
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                        opacity: 0.5
                                        text: Translation.tr("Nothing scheduled")
                                    }
                                }
                            }

                            Component {
                                id: eventRow
                                EventItem {
                                    event: modelData
                                }
                            }
                        }
                    }
                }
            }

            // Not set up yet
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 20
                spacing: 5
                visible: !CalendarEvents.available || CalendarEvents.errorMessage.length > 0

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 55
                    color: Appearance.m3colors.m3outline
                    text: "event_busy"
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3outline
                    text: CalendarEvents.available ? CalendarEvents.errorMessage : Translation.tr("khal is not installed.\nRun ~/.config/vdirsyncer/setup-google.sh")
                }
            }
        }

        // Calendar legend
        Flow {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            visible: CalendarEvents.calendars.length > 1
            spacing: 10

            Repeater {
                model: CalendarEvents.calendars
                delegate: Row {
                    spacing: 4
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: modelData.color
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        text: modelData.name
                    }
                }
            }
        }
    }
}
