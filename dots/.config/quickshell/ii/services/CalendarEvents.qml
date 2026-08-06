pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Calendar events, sourced from khal reading vdirs that vdirsyncer pulls from
 * Google Calendar. See ~/.config/vdirsyncer/README-google.md for the setup.
 *
 * khal is used rather than parsing .ics directly because it expands RRULEs and
 * resolves timezones for us. Its date output format is pinned to ISO in
 * ~/.config/khal/config -- parseDateTime() below depends on that.
 *
 * Named CalendarEvents, not Calendar, to avoid ambiguity with QtQuick.Controls
 * types in files that import both.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.calendar?.events ?? null
    readonly property bool enableEvents: opts?.enable ?? true
    readonly property int refreshIntervalMs: Math.max(1, opts?.refreshInterval ?? 5) * 60 * 1000
    readonly property int maxDots: Math.max(1, opts?.maxDots ?? 3)
    // Days visible in the week view, counting today as the first.
    readonly property int daysShown: Math.max(1, opts?.daysShown ?? 7)

    property bool available: false
    property bool loading: false
    property string errorMessage: ""
    property bool syncing: false

    // Flat list, sorted by start time.
    property var events: []
    // "YYYY-MM-DD" -> [event], each day's list sorted (all-day first, then by time).
    property var eventsByDate: ({})
    // Distinct calendar names seen in the current window, with their colours.
    property var calendars: []

    // Month the grid is currently showing. Drives the fetch window.
    property date viewMonth: new Date()
    // Day the user clicked in the grid.
    property date selectedDate: new Date()
    // First day the week view shows. A rolling window anchored on today, not a
    // Monday-aligned calendar week -- days that have already passed are noise.
    property date rangeStart: new Date()

    Component.onCompleted: root.rangeStart = root.startOfDay(new Date())

    // ---------------------------------------------------------------- dates

    function pad2(n) {
        return n < 10 ? `0${n}` : `${n}`;
    }

    function dateKey(d) {
        return `${d.getFullYear()}-${root.pad2(d.getMonth() + 1)}-${root.pad2(d.getDate())}`;
    }

    function startOfDay(d) {
        return new Date(d.getFullYear(), d.getMonth(), d.getDate());
    }

    function addDays(d, n) {
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
    }

    // Round, not floor: DST transitions make some "days" 23 or 25 hours long.
    function daysBetween(a, b) {
        return Math.round((root.startOfDay(b).getTime() - root.startOfDay(a).getTime()) / 86400000);
    }

    // Monday on or before the given date.
    function mondayOf(d) {
        const s = root.startOfDay(d);
        return root.addDays(s, -((s.getDay() + 6) % 7));
    }

    // Monday on or before the 1st of the given month -- the grid's top-left cell.
    function gridStartFor(monthDate) {
        return root.mondayOf(new Date(monthDate.getFullYear(), monthDate.getMonth(), 1));
    }

    // khal is configured for ISO, so "2026-08-06 14:30" or "2026-08-06".
    function parseDateTime(s) {
        if (!s)
            return null;
        const m = String(s).match(/(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2}))?/);
        if (!m)
            return null;
        return new Date(+m[1], +m[2] - 1, +m[3], m[4] ? +m[4] : 0, m[5] ? +m[5] : 0);
    }

    function truthy(v) {
        if (typeof v === "boolean")
            return v;
        if (typeof v === "number")
            return v !== 0;
        if (typeof v === "string")
            return ["true", "yes", "1", "x", "✓"].includes(v.trim().toLowerCase());
        return false;
    }

    // --------------------------------------------------------------- colours

    readonly property var fallbackPalette: ["#E57373", "#F06292", "#BA68C8", "#9575CD", "#7986CB", "#64B5F6", "#4FC3F7", "#4DD0E1", "#4DB6AC", "#81C784", "#AED581", "#FFD54F", "#FFB74D", "#FF8A65"]

    // khal accepts names like "dark green"; Qt cannot parse those, so map the
    // ones khal actually emits and hash-fallback for anything else.
    readonly property var namedColors: ({
            "black": "#5C5C5C",
            "red": "#E57373",
            "green": "#81C784",
            "yellow": "#FFD54F",
            "blue": "#64B5F6",
            "magenta": "#BA68C8",
            "cyan": "#4DD0E1",
            "white": "#E0E0E0",
            "dark red": "#C62828",
            "dark green": "#2E7D32",
            "dark yellow": "#F9A825",
            "dark blue": "#1565C0",
            "dark magenta": "#6A1B9A",
            "dark cyan": "#00838F",
            "light red": "#EF9A9A",
            "light green": "#A5D6A7",
            "light yellow": "#FFF59D",
            "light blue": "#90CAF9",
            "light magenta": "#CE93D8",
            "light cyan": "#80DEEA",
            "light gray": "#BDBDBD",
            "dark gray": "#757575"
        })

    function hashColor(name) {
        let h = 0;
        const s = String(name ?? "");
        for (let i = 0; i < s.length; i++)
            h = (h * 31 + s.charCodeAt(i)) >>> 0;
        return root.fallbackPalette[h % root.fallbackPalette.length];
    }

    function normalizeColor(raw, name) {
        // khal may wrap the colour in ANSI escapes depending on tty detection.
        const s = String(raw ?? "").replace(/\u001b?\[[0-9;]*m/g, "").trim();
        // Google writes #RRGGBBAA. Qt reads 8-digit hex as #AARRGGBB, so passing
        // it straight through would rotate the channels; drop the alpha instead.
        if (/^#[0-9a-fA-F]{8}$/.test(s))
            return s.slice(0, 7);
        if (/^#[0-9a-fA-F]{6}$/.test(s) || /^#[0-9a-fA-F]{3}$/.test(s))
            return s;
        const named = root.namedColors[s.toLowerCase()];
        if (named)
            return named;
        return root.hashColor(name);
    }

    // ---------------------------------------------------------- fetch window

    // The window must cover everything on screen: the month grid, the week view,
    // and today (so "Today" styling is right even when browsing elsewhere).
    readonly property date windowStart: {
        const candidates = [root.startOfDay(new Date()), root.gridStartFor(root.viewMonth), root.startOfDay(root.rangeStart)];
        let earliest = candidates[0];
        for (let i = 1; i < candidates.length; i++)
            if (candidates[i].getTime() < earliest.getTime())
                earliest = candidates[i];
        return earliest;
    }

    readonly property int windowDays: {
        const today = root.startOfDay(new Date());
        const candidates = [root.addDays(today, root.daysShown), root.addDays(root.gridStartFor(root.viewMonth), 41), root.addDays(root.startOfDay(root.rangeStart), root.daysShown - 1)];
        let latest = candidates[0];
        for (let i = 1; i < candidates.length; i++)
            if (candidates[i].getTime() > latest.getTime())
                latest = candidates[i];
        // Cap so browsing far into the future can't make khal expand years of
        // recurrences in one go.
        return Math.min(400, Math.max(1, root.daysBetween(root.windowStart, latest) + 1));
    }

    onWindowStartChanged: refreshDebounce.restart()
    onWindowDaysChanged: refreshDebounce.restart()

    // Scrolling through months fires these fast; don't spawn a khal per frame.
    Timer {
        id: refreshDebounce
        interval: 180
        repeat: false
        onTriggered: root.refresh()
    }

    // ------------------------------------------------------------------ API

    function load() {}

    function refresh() {
        if (!root.available || !root.enableEvents)
            return;
        listProc.running = false;
        listProc.command = ["khal", "list", "--json", "all", root.dateKey(root.windowStart), `${root.windowDays}d`];
        root.loading = true;
        listProc.running = true;
    }

    // Kick vdirsyncer immediately instead of waiting for its 15-minute timer.
    function syncNow() {
        if (root.syncing)
            return;
        root.syncing = true;
        syncProc.running = true;
    }

    function eventsOn(date) {
        return root.eventsByDate[root.dateKey(date)] ?? [];
    }

    function countOn(date) {
        return root.eventsOn(date).length;
    }

    // Distinct colours for a day's dots, in display order, capped at maxDots.
    function dotColorsOn(date) {
        const dayEvents = root.eventsOn(date);
        const seen = [];
        for (let i = 0; i < dayEvents.length && seen.length < root.maxDots; i++) {
            const c = dayEvents[i].color;
            if (!seen.includes(c))
                seen.push(c);
        }
        // A day full of same-calendar events still deserves more than one dot.
        if (seen.length === 1 && dayEvents.length > 1)
            return seen.concat(seen.slice(0, Math.min(dayEvents.length, root.maxDots) - 1));
        return seen;
    }

    // ------------------------------------------------------------ week model

    // Clicking a day in the month grid makes that day the first row, rather
    // than jumping to its Monday and burying it mid-list.
    function goToDay(date) {
        root.rangeStart = root.startOfDay(date);
        root.selectedDate = root.startOfDay(date);
    }

    function shiftDays(n) {
        root.rangeStart = root.addDays(root.rangeStart, n * root.daysShown);
    }

    function goToToday() {
        root.rangeStart = root.startOfDay(new Date());
        root.selectedDate = root.startOfDay(new Date());
    }

    readonly property bool startsToday: root.dateKey(root.rangeStart) === root.dateKey(new Date())

    // Flattened [dayHeader, event, event, dayHeader, ...] for the whole week.
    // Every day gets a header, including empty ones -- this is a week view, not
    // a filtered agenda, so gaps have to be visible.
    function rangeModel(startDate) {
        const start = root.startOfDay(startDate);
        const todayKey = root.dateKey(new Date());
        const out = [];
        for (let i = 0; i < root.daysShown; i++) {
            const d = root.addDays(start, i);
            const key = root.dateKey(d);
            const dayEvents = root.eventsByDate[key] ?? [];
            out.push({
                rowType: "header",
                date: d,
                key: key,
                title: root.dayLabel(d),
                count: dayEvents.length,
                isToday: key === todayKey,
                isPast: root.daysBetween(new Date(), d) < 0
            });
            if (dayEvents.length === 0) {
                out.push({
                    rowType: "empty",
                    date: d,
                    key: `${key}-empty`
                });
                continue;
            }
            for (let j = 0; j < dayEvents.length; j++)
                out.push(Object.assign({
                    rowType: "event",
                    key: `${key}-${j}`
                }, dayEvents[j]));
        }
        return out;
    }

    // Keep the date on every row -- in a week view the relative word alone
    // ("Yesterday") costs you the orientation the date gives you.
    function dayLabel(d) {
        const locale = Qt.locale(Config.options?.calendar?.locale ?? "en-GB");
        const stamp = d.toLocaleDateString(locale, "ddd d MMM");
        return root.daysBetween(new Date(), d) === 0 ? `${Translation.tr("Today")} · ${stamp}` : stamp;
    }

    function rangeLabel(startDate) {
        const locale = Qt.locale(Config.options?.calendar?.locale ?? "en-GB");
        const start = root.startOfDay(startDate);
        const end = root.addDays(start, root.daysShown - 1);
        // Drop the repeated month when the week doesn't straddle one.
        const startFmt = start.getMonth() === end.getMonth() ? "d" : "d MMM";
        return `${start.toLocaleDateString(locale, startFmt)} – ${end.toLocaleDateString(locale, "d MMM")}`;
    }

    // --------------------------------------------------------- meeting links

    // Ordered by preference: a real conferencing link beats a doc someone
    // pasted into the description.
    readonly property var conferencingHosts: ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "meet.jit.si", "whereby.com", "webex.com", "chime.aws", "bluejeans.com", "gotomeeting.com", "discord.gg"]

    function extractUrls(text) {
        if (!text)
            return [];
        // Trailing punctuation is almost always sentence punctuation, not URL.
        const found = String(text).match(/https?:\/\/[^\s<>"'\)\]]+/g);
        if (!found)
            return [];
        return found.map(u => u.replace(/[.,;:]+$/, ""));
    }

    // Google puts the Meet link in the description ("Join with Google Meet: ..."),
    // not in the ICS URL property, so the description has to be scanned.
    // Boilerplate Google staples into auto-created events ("To see detailed
    // information ... https://g.co/calendar"). Offering those as the event's
    // link is pure noise -- they go nowhere useful.
    readonly property var ignoredLinkFragments: ["g.co/calendar", "mail.google.com", "support.google.com"]

    function isIgnoredLink(url) {
        const u = String(url ?? "").toLowerCase();
        for (let i = 0; i < root.ignoredLinkFragments.length; i++)
            if (u.includes(root.ignoredLinkFragments[i]))
                return true;
        return false;
    }

    function meetingUrlFor(e) {
        const candidates = root.extractUrls(e.location).concat(root.extractUrls(e.description)).concat(root.extractUrls(e.url));
        // A conferencing link wins wherever it appears, even past boilerplate.
        for (let h = 0; h < root.conferencingHosts.length; h++) {
            for (let i = 0; i < candidates.length; i++) {
                if (candidates[i].toLowerCase().includes(root.conferencingHosts[h]))
                    return candidates[i];
            }
        }
        for (let i = 0; i < candidates.length; i++) {
            if (!root.isIgnoredLink(candidates[i]))
                return candidates[i];
        }
        return "";
    }

    function isConferencingUrl(url) {
        if (!url)
            return false;
        const u = String(url).toLowerCase();
        for (let h = 0; h < root.conferencingHosts.length; h++)
            if (u.includes(root.conferencingHosts[h]))
                return true;
        return false;
    }

    function openUrl(url) {
        if (!url || String(url).length === 0)
            return;
        Quickshell.execDetached(["xdg-open", String(url)]);
    }

    // --------------------------------------------------------------- parsing

    /**
     * khal --json emits ONE ARRAY PER DAY in the range, newline separated:
     *
     *     []
     *     []
     *     [{...}, {...}]
     *
     * so the output as a whole is not valid JSON. Strings are properly escaped,
     * making a newline split safe; the accumulate-and-retry loop additionally
     * survives a pretty-printed array spanning several lines.
     */
    function parseJsonChunks(text) {
        // Fast path, in case a future khal emits a single document.
        try {
            const once = JSON.parse(text);
            if (Array.isArray(once))
                return once;
        } catch (e) {}

        const out = [];
        const lines = text.split("\n");
        let buffer = "";
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (line.length === 0)
                continue;
            buffer = buffer.length === 0 ? line : `${buffer}\n${line}`;
            let chunk;
            try {
                chunk = JSON.parse(buffer);
            } catch (e) {
                continue; // Not a complete document yet -- keep accumulating.
            }
            buffer = "";
            if (Array.isArray(chunk)) {
                for (let j = 0; j < chunk.length; j++)
                    out.push(chunk[j]);
            } else {
                out.push(chunk);
            }
        }
        if (buffer.length > 0)
            console.error("[CalendarEvents] Trailing unparseable khal output:", buffer.slice(0, 200));
        return out;
    }

    function parseKhalOutput(text) {
        const trimmed = (text ?? "").trim();
        if (trimmed.length === 0)
            return [];
        const raw = root.parseJsonChunks(trimmed);
        if (raw.length === 0)
            return [];

        // Reporting per day means a multi-day event comes back once for every
        // day it covers. Without this, indexByDate fans each copy back out over
        // the whole span -- a 7-day event turns into 49 rows.
        const seen = ({});
        const deduped = [];
        for (let i = 0; i < raw.length; i++) {
            const e = raw[i];
            // Recurrences share a uid, so the start must be part of the key.
            const key = `${e["uid"] ?? ""}|${e["start-full"] ?? e["start"] ?? ""}|${e["end-full"] ?? e["end"] ?? ""}`;
            if (seen[key])
                continue;
            seen[key] = true;
            deduped.push(e);
        }
        return root.buildEvents(deduped);
    }

    function buildEvents(raw) {
        const parsed = [];
        for (let i = 0; i < raw.length; i++) {
            const e = raw[i];
            const allDay = root.truthy(e["all-day"]);
            const start = root.parseDateTime(e["start-full"] ?? e["start-date"] ?? e["start"]);
            if (!start)
                continue;
            let end = root.parseDateTime(e["end-full"] ?? e["end-date"] ?? e["end"]) ?? start;
            if (end.getTime() < start.getTime())
                end = start;
            const calendarName = String(e["calendar"] ?? "");
            const event = {
                uid: String(e["uid"] ?? `${calendarName}:${i}`),
                title: String(e["title"] ?? Translation.tr("(untitled)")).trim(),
                start: start,
                end: end,
                allDay: allDay,
                calendar: calendarName,
                color: root.normalizeColor(e["calendar-color"], calendarName),
                location: String(e["location"] ?? "").trim(),
                description: String(e["description"] ?? "").trim(),
                url: String(e["url"] ?? "").trim(),
                repeating: String(e["repeat-symbol"] ?? "").trim().length > 0,
                cancelled: root.truthy(e["cancelled"]) || String(e["status"] ?? "").toUpperCase() === "CANCELLED"
            };
            // Resolve once here rather than per-frame in the delegate.
            event.meetingUrl = root.meetingUrlFor(event);
            event.isConference = root.isConferencingUrl(event.meetingUrl);
            parsed.push(event);
        }

        parsed.sort((a, b) => {
            if (a.allDay !== b.allDay)
                return a.allDay ? -1 : 1;
            return a.start.getTime() - b.start.getTime();
        });
        return parsed;
    }

    function indexByDate(list) {
        const map = ({});
        for (let i = 0; i < list.length; i++) {
            const e = list[i];
            let lastDay = root.startOfDay(e.end);
            // A timed event ending exactly at midnight belongs to the day before.
            if (!e.allDay && lastDay.getTime() > root.startOfDay(e.start).getTime() && e.end.getHours() === 0 && e.end.getMinutes() === 0)
                lastDay = root.addDays(lastDay, -1);
            const span = Math.max(0, root.daysBetween(e.start, lastDay));
            // Guard against a runaway multi-year event flooding the map.
            const cappedSpan = Math.min(span, 400);
            for (let d = 0; d <= cappedSpan; d++) {
                const key = root.dateKey(root.addDays(e.start, d));
                if (!map[key])
                    map[key] = [];
                map[key].push(Object.assign({}, e, {
                    spansMultipleDays: cappedSpan > 0,
                    isFirstDay: d === 0,
                    isLastDay: d === cappedSpan
                }));
            }
        }
        for (const key in map) {
            map[key].sort((a, b) => {
                if (a.allDay !== b.allDay)
                    return a.allDay ? -1 : 1;
                return a.start.getTime() - b.start.getTime();
            });
        }
        return map;
    }

    function collectCalendars(list) {
        const seen = ({});
        const out = [];
        for (let i = 0; i < list.length; i++) {
            const e = list[i];
            if (seen[e.calendar])
                continue;
            seen[e.calendar] = true;
            out.push({
                name: e.calendar,
                color: e.color
            });
        }
        out.sort((a, b) => a.name.localeCompare(b.name));
        return out;
    }

    // -------------------------------------------------------------- processes

    Process {
        id: availabilityProc
        running: Config.ready
        command: ["which", "khal"]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0);
            if (!root.available) {
                root.errorMessage = Translation.tr("khal is not installed");
                root.loading = false;
            } else {
                root.errorMessage = "";
                root.refresh();
            }
        }
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            id: listStdout
        }
        stderr: StdioCollector {
            id: listStderr
        }
        onExited: (exitCode, exitStatus) => {
            // 15 is SIGTERM: refresh() killed an in-flight khal to start a newer
            // one. Self-inflicted and immediately superseded, so not an error --
            // and `loading` stays true because the replacement run owns it now.
            if (exitCode === 15)
                return;
            root.loading = false;
            if (exitCode !== 0) {
                const err = (listStderr.text ?? "").trim();
                console.error("[CalendarEvents] khal exited", exitCode, err);
                // No configured calendars yet is the expected pre-setup state,
                // not something worth shouting about.
                root.errorMessage = err.length > 0 ? err.split("\n")[0] : Translation.tr("khal failed (exit %1)").arg(exitCode);
                root.events = [];
                root.eventsByDate = ({});
                root.calendars = [];
                return;
            }
            root.errorMessage = "";
            const parsed = root.parseKhalOutput(listStdout.text);
            root.events = parsed;
            root.eventsByDate = root.indexByDate(parsed);
            root.calendars = root.collectCalendars(parsed);
        }
    }

    Process {
        id: syncProc
        command: ["systemctl", "--user", "start", "vdirsyncer.service"]
        onExited: (exitCode, exitStatus) => {
            root.syncing = false;
            if (exitCode !== 0)
                console.error("[CalendarEvents] vdirsyncer.service failed with", exitCode);
            // Re-read either way: a partial sync still may have written events.
            root.refresh();
        }
    }

    Timer {
        interval: root.refreshIntervalMs
        repeat: true
        running: Config.ready && root.enableEvents && root.available
        onTriggered: root.refresh()
    }

    // Roll the window over at midnight so "Today" stays correct.
    Connections {
        target: DateTime
        function onDateChanged() {
            root.refresh();
        }
    }
}
