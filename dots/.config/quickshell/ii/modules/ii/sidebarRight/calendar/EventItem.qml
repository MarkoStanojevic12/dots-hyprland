import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One event row in the week view. Clicking opens its meeting link (Google Meet,
 * Zoom, Teams, ...) when the event has one.
 */
RippleButton {
    id: root
    required property var event

    readonly property string link: root.event.meetingUrl ?? ""
    readonly property bool hasLink: root.link.length > 0
    readonly property bool isConference: root.event.isConference ?? false
    readonly property bool dimmed: root.event.cancelled ?? false

    implicitHeight: contentRow.implicitHeight + 12
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    pointingHandCursor: root.hasLink
    rippleEnabled: root.hasLink
    background.anchors.fill: root
    opacity: root.dimmed ? 0.55 : 1

    downAction: () => {
        if (root.hasLink)
            CalendarEvents.openUrl(root.link);
    }

    contentItem: RowLayout {
        id: contentRow
        spacing: 8

        // Calendar colour stripe
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 3
            Layout.preferredHeight: Math.max(20, textColumn.implicitHeight)
            radius: 2
            color: root.event.color ?? Appearance.colors.colPrimary
        }

        // Time column. Fixed width so titles line up down the whole day.
        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1
            Layout.preferredWidth: 46
            Layout.minimumWidth: 46
            Layout.maximumWidth: 46
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignLeft
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                text: root.startLabel()
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                horizontalAlignment: Text.AlignLeft
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: root.endLabel()
            }
        }

        // Title + location
        ColumnLayout {
            id: textColumn
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.strikeout: root.dimmed
                color: Appearance.colors.colOnLayer2
                text: root.event.title ?? ""
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: root.placeLabel()
            }
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 2
            visible: root.hasLink
            text: root.isConference ? "videocam" : "open_in_new"
            iconSize: Appearance.font.pixelSize.small
            color: root.isConference ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 2
            visible: (root.event.repeating ?? false) && !root.hasLink
            text: "repeat"
            iconSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }

    StyledToolTip {
        text: root.tooltipText()
        extraVisibleCondition: root.hovered && text.length > 0
    }

    function timeString(d) {
        return d.toLocaleTimeString(Qt.locale(), Config.options?.time?.format ?? "hh:mm");
    }

    function startLabel() {
        const e = root.event;
        if (e.allDay)
            return Translation.tr("All day");
        // A day in the middle of a multi-day event has no meaningful start here.
        if (e.spansMultipleDays && !e.isFirstDay)
            return "↓";
        return root.timeString(e.start);
    }

    function endLabel() {
        const e = root.event;
        if (e.allDay)
            return "";
        if (e.spansMultipleDays && !e.isLastDay)
            return "→";
        return root.timeString(e.end);
    }

    function placeLabel() {
        const e = root.event;
        // A bare conferencing URL in the location field is already conveyed by
        // the camera icon; showing the raw link just adds noise.
        if (e.location && e.location.length > 0 && !/^https?:\/\//.test(e.location))
            return e.location;
        if (root.isConference)
            return Translation.tr("Click to join");
        return e.calendar ?? "";
    }

    function tooltipText() {
        const e = root.event;
        const parts = [e.title];
        if (e.allDay)
            parts.push(Translation.tr("All day"));
        else
            parts.push(`${root.timeString(e.start)} – ${root.timeString(e.end)}`);
        if (e.location && e.location.length > 0)
            parts.push(e.location);
        if (e.calendar && e.calendar.length > 0)
            parts.push(e.calendar);
        if (root.hasLink)
            parts.push(root.isConference ? Translation.tr("Click to join: %1").arg(root.link) : Translation.tr("Click to open: %1").arg(root.link));
        return parts.join("\n");
    }
}
