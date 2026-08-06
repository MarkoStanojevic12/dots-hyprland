pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Reminders for upcoming calendar events: a sound a few minutes ahead, then a
 * popup shortly before the event starts.
 *
 * Firing is decided by wall clock against a (previousTick, now] window rather
 * than by "minutes remaining", so each alert fires exactly once and a shell
 * reload mid-day cannot replay a morning's worth of reminders.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.calendar?.alerts ?? null
    readonly property bool enableAlerts: opts?.enable ?? true
    readonly property int soundLeadMinutes: Math.max(0, opts?.soundLeadMinutes ?? 5)
    readonly property int popupLeadMinutes: Math.max(0, opts?.popupLeadMinutes ?? 1)
    readonly property string soundFile: opts?.soundFile ?? "/usr/share/sounds/freedesktop/stereo/bell.oga"
    readonly property string soundCommand: opts?.soundCommand ?? "paplay"
    // An all-day event "starts" at midnight, so a lead-time reminder for one
    // lands late the night before. Rarely what anyone wants.
    readonly property bool alertAllDay: opts?.alertAllDay ?? false
    // Drop a popup this long after the event began, so one missed reminder
    // doesn't sit on screen for the rest of the day.
    readonly property int dismissAfterMinutes: Math.max(1, opts?.dismissAfterMinutes ?? 15)

    // Events with a popup currently on screen.
    property var activeAlerts: []

    // Milliseconds. 0 until the first tick establishes a baseline.
    property double lastTick: 0

    readonly property int tickMs: 10000

    function eventKey(e) {
        return `${e.uid}|${e.start.getTime()}`;
    }

    function shouldAlertFor(e) {
        if (e.cancelled)
            return false;
        if (e.allDay && !root.alertAllDay)
            return false;
        // A multi-day event only "starts" on its first day.
        if (e.spansMultipleDays && e.isFirstDay === false)
            return false;
        return true;
    }

    function playSound() {
        if (root.soundFile.length === 0 || root.soundCommand.length === 0)
            return;
        Quickshell.execDetached([root.soundCommand, root.soundFile]);
    }

    function showPopup(e) {
        // Never stack duplicates of the same occurrence.
        const key = root.eventKey(e);
        for (let i = 0; i < root.activeAlerts.length; i++)
            if (root.eventKey(root.activeAlerts[i]) === key)
                return;
        root.activeAlerts = root.activeAlerts.concat([e]);
    }

    function dismiss(e) {
        const key = root.eventKey(e);
        root.activeAlerts = root.activeAlerts.filter(a => root.eventKey(a) !== key);
    }

    function dismissAll() {
        root.activeAlerts = [];
    }

    function joinAndDismiss(e) {
        CalendarEvents.openEventLink(e);
        root.dismiss(e);
    }

    function tick() {
        const now = Date.now();
        // First tick after start/reload: look back one interval only. Without
        // this, `prev` would be 0 and every reminder of the epoch-to-now range
        // would fire at once.
        const prev = root.lastTick === 0 ? now - root.tickMs : root.lastTick;
        root.lastTick = now;

        if (!root.enableAlerts)
            return;

        const events = CalendarEvents.events ?? [];
        for (let i = 0; i < events.length; i++) {
            const e = events[i];
            if (!root.shouldAlertFor(e))
                continue;
            const start = e.start.getTime();

            const soundAt = start - root.soundLeadMinutes * 60000;
            if (soundAt > prev && soundAt <= now)
                root.playSound();

            const popupAt = start - root.popupLeadMinutes * 60000;
            if (popupAt > prev && popupAt <= now)
                root.showPopup(e);
        }

        // Expire popups for events that began a while ago.
        if (root.activeAlerts.length > 0) {
            const cutoff = root.dismissAfterMinutes * 60000;
            const kept = root.activeAlerts.filter(a => (now - a.start.getTime()) < cutoff);
            if (kept.length !== root.activeAlerts.length)
                root.activeAlerts = kept;
        }
    }

    Timer {
        interval: root.tickMs
        repeat: true
        running: Config.ready && root.enableAlerts
        triggeredOnStart: true
        onTriggered: root.tick()
    }
}
