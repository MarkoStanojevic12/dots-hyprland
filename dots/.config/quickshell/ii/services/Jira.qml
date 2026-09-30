pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * The Jira ticket being worked on, for the bar's ticket chip.
 *
 * Which ticket: one pinned by hand wins; otherwise the newer of the ticket
 * Claude last touched (a Claude Code PostToolUse hook runs
 * `qs -c ii ipc call jira touched KEY`) and the key in the most recently
 * checked-out branch of the configured repos.
 *
 * Site, account and repos come from ~/.config/illogical-impulse/jira.json and
 * the API token from the keyring -- see scripts/jira/jira.sh. No file, no chip.
 *
 * Also polls for other people's activity that concerns me and sends it as
 * desktop notifications. Jira Cloud webhooks need a public endpoint, hence
 * the polling.
 */
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/jira/jira.sh")

    property bool configured: false
    property string site: ""
    property string project: ""

    property string branchKey: ""
    property real branchTime: 0

    readonly property string pinnedKey: persisted.pinnedKey
    readonly property bool touchedIsNewer: persisted.touchedKey !== "" && persisted.touchedAt / 1000 >= root.branchTime
    readonly property string activeKey: root.pinnedKey || (root.touchedIsNewer ? persisted.touchedKey : root.branchKey) || persisted.touchedKey
    readonly property string source: root.pinnedKey ? "pinned"
        : root.activeKey === "" ? ""
        : root.activeKey === persisted.touchedKey && (root.touchedIsNewer || root.branchKey === "") ? "claude"
        : "branch"

    property var issue: null
    property var transitions: []
    property var assignableUsers: []
    property var mentionableUsers: []
    property bool loading: false
    property string pendingAction: ""
    property string error: ""

    signal actionFinished(string action, bool ok)

    property bool popupOpen: false
    property string popupScreen: ""

    onActiveKeyChanged: {
        if (root.issue?.key !== root.activeKey) {
            root.issue = null;
            root.transitions = [];
            root.assignableUsers = [];
        }
        root.error = "";
        root.refresh();
    }

    function isKey(key) {
        const match = /^[A-Z][A-Z0-9]+-\d+$/.test(key);
        return match && (root.project === "" || key.startsWith(root.project + "-"));
    }

    function openPopup(screenName) {
        root.popupScreen = screenName;
        root.popupOpen = true;
        root.refresh();
    }

    // focusedMonitor stays null until Hyprland sends its first focus event.
    function focusedScreenName() {
        return Hyprland.focusedMonitor?.name || Quickshell.screens[0]?.name || "";
    }

    function togglePopup(screenName) {
        if (root.popupOpen && root.popupScreen === screenName) root.popupOpen = false;
        else root.openPopup(screenName);
    }

    function touch(key) {
        if (!root.isKey(key)) return;
        persisted.touchedKey = key;
        persisted.touchedAt = Date.now();
        if (key === root.activeKey) root.refresh();
    }

    function pin(key) {
        key = key.trim().toUpperCase();
        if (!root.isKey(key)) {
            root.error = `Not a ${root.project || "Jira"} key: ${key}`;
            return;
        }
        persisted.pinnedKey = key;
    }

    function unpin() { persisted.pinnedKey = ""; }

    function refresh() {
        if (!root.configured || root.activeKey === "") return;
        if (issueProcess.running) {
            issueProcess.again = true;
            return;
        }
        root.loading = true;
        issueProcess.command = [root.script, "issue", root.activeKey];
        issueProcess.running = true;
        if (root.popupOpen) root.loadTransitions();
    }

    function loadTransitions() {
        if (transitionsProcess.running || root.activeKey === "") return;
        transitionsProcess.command = [root.script, "transitions", root.activeKey];
        transitionsProcess.running = true;
    }

    function searchUsers(query) {
        if (usersProcess.running) {
            usersProcess.queued = query;
            return;
        }
        usersProcess.queued = null;
        usersProcess.command = [root.script, "users", root.activeKey, query];
        usersProcess.running = true;
    }

    function searchMentionable(query) {
        if (mentionProcess.running) {
            mentionProcess.queued = query;
            return;
        }
        mentionProcess.queued = null;
        mentionProcess.command = [root.script, "mentionable", root.activeKey, query];
        mentionProcess.running = true;
    }

    function run(action, args) {
        if (actionProcess.running || root.activeKey === "") return false;
        root.pendingAction = action;
        root.error = "";
        actionProcess.command = [root.script, action, root.activeKey, ...args];
        actionProcess.running = true;
        return true;
    }

    function transition(id) { return root.run("transition", [id]); }
    // mentions maps "Display Name" -> accountId for the @names in text.
    function comment(text, mentions) { return root.run("comment", [text, JSON.stringify(mentions ?? {})]); }
    function assign(accountId) { return root.run("assign", [accountId]); }

    // Polls overlap by a minute because Jira's search index lags behind
    // writes; seenEvents drops the repeats. After a long gap only the last
    // half hour is reported, not a backlog.
    function pollEvents() {
        if (!root.configured || eventsProcess.running) return;
        const now = Date.now();
        const since = Math.max(persisted.eventsSince || now, now - 30 * 60 * 1000) - 60 * 1000;
        eventsProcess.command = [root.script, "events", String(Math.floor(since))];
        eventsProcess.running = true;
    }

    function notifyEvent(event) {
        const title = event.type === "assigned" ? `${event.author} assigned you ${event.key}`
            : event.type === "mention" ? `${event.author} mentioned you in ${event.key}`
            : `${event.author} commented on ${event.key}`;
        const body = [event.summary, event.text].filter(part => part).join("\n")
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        Quickshell.execDetached([root.script, "notify", event.key, event.url, title, body]);
    }

    function parse(text) {
        try {
            return JSON.parse(text);
        } catch (e) {
            return { error: text.trim().length > 0 ? text.trim() : "no response from jira.sh" };
        }
    }

    // Jira's rendered HTML points images and links at the site root, and the
    // images need auth the Text element can't send.
    function cleanHtml(html) {
        return (html ?? "")
            .replace(/<img[^>]*>/g, "")
            .replace(/href="\//g, `href="${root.site}/`);
    }

    // Jira writes offsets as +0200, which the JS engine won't parse.
    function formatDate(iso) {
        if (!iso) return "";
        const date = new Date(iso.replace(/([+-]\d\d)(\d\d)$/, "$1:$2"));
        return isNaN(date) ? iso : Qt.formatDateTime(date, "d MMM, HH:mm");
    }

    FileView {
        path: `${Directories.shellConfig}/jira.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const config = root.parse(text());
            root.site = (config.site ?? "").replace(/\/$/, "");
            root.project = config.project ?? "";
            root.configured = root.site !== "" && !config.error;
            branchProcess.running = true;
            root.refresh();
        }
        onLoadFailed: root.configured = false
    }

    FileView {
        path: FileUtils.trimFileProtocol(`${Directories.state}/user/jira-ticket.json`)
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) writeAdapter();
        }

        JsonAdapter {
            id: persisted
            property string pinnedKey: ""
            property string touchedKey: ""
            property real touchedAt: 0
            property real eventsSince: 0
            property list<string> seenEvents: []
        }
    }

    Timer {
        running: root.configured
        interval: 30 * 1000
        repeat: true
        onTriggered: if (!branchProcess.running) branchProcess.running = true
    }

    Timer {
        running: root.configured && root.activeKey !== ""
        interval: 5 * 60 * 1000
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        running: root.configured
        interval: 5 * 60 * 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollEvents()
    }

    Process {
        id: eventsProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parse(text);
                if (result.error || !Array.isArray(result.events)) return;
                const seen = new Set(persisted.seenEvents);
                const fresh = result.events.filter(event => !seen.has(event.id));
                fresh.forEach(root.notifyEvent);
                persisted.seenEvents = [...persisted.seenEvents, ...fresh.map(event => event.id)].slice(-200);
                persisted.eventsSince = result.now;
                if (fresh.some(event => event.key === root.activeKey)) root.refresh();
            }
        }
    }

    Process {
        id: branchProcess
        command: [root.script, "branch"]
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parse(text);
                if (result.error) return;
                root.branchKey = result.key ?? "";
                root.branchTime = result.time ?? 0;
            }
        }
    }

    Process {
        id: issueProcess
        property bool again: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                const result = root.parse(text);
                if (result.error) root.error = result.error;
                else if (result.key === root.activeKey) {
                    root.issue = result;
                    root.error = "";
                }
                if (issueProcess.again) {
                    issueProcess.again = false;
                    Qt.callLater(root.refresh);
                }
            }
        }
    }

    Process {
        id: transitionsProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parse(text);
                root.transitions = Array.isArray(result) ? result : [];
            }
        }
    }

    Process {
        id: usersProcess
        property var queued: null
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parse(text);
                root.assignableUsers = Array.isArray(result) ? result : [];
                if (usersProcess.queued !== null) {
                    const query = usersProcess.queued;
                    Qt.callLater(() => root.searchUsers(query));
                }
            }
        }
    }

    Process {
        id: mentionProcess
        property var queued: null
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parse(text);
                root.mentionableUsers = Array.isArray(result) ? result : [];
                if (mentionProcess.queued !== null) {
                    const query = mentionProcess.queued;
                    Qt.callLater(() => root.searchMentionable(query));
                }
            }
        }
    }

    Process {
        id: actionProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parse(text);
                const action = root.pendingAction;
                root.pendingAction = "";
                if (result.error) root.error = result.error;
                else root.refresh();
                root.actionFinished(action, !result.error);
            }
        }
    }

    IpcHandler {
        target: "jira"

        function touched(key: string): void { root.touch(key); }
        function refresh(): void { root.refresh(); }
        function toggle(): void { root.togglePopup(root.focusedScreenName()); }
        function pin(key: string): void { root.pin(key); }
        function unpin(): void { root.unpin(); }
        function poll(): void { root.pollEvents(); }

        function state(): string {
            return [
                `configured=${root.configured}  active=${root.activeKey || "(none)"}  source=${root.source || "-"}`,
                `pinned=${root.pinnedKey || "-"}  touched=${persisted.touchedKey || "-"}  branch=${root.branchKey || "-"}`,
                `issue=${root.issue ? `${root.issue.key} [${root.issue.status}]` : "(none)"}  loading=${root.loading}  popup=${root.popupOpen ? root.popupScreen : "closed"}`,
                `error=${root.error || "none"}`
            ].join("\n");
        }
    }

    GlobalShortcut {
        name: "jiraTicketToggle"
        description: "Toggles the active Jira ticket popup"
        onPressed: root.togglePopup(root.focusedScreenName())
    }
}
