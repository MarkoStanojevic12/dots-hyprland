pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services.claudeCode
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Owns the Claude Code conversations the sidebar can show, and everything that
 * is true of all of them at once.
 *
 * Auth note: the CLI reuses the OAuth credentials from `claude login`
 * (~/.claude/.credentials.json), so this runs on the user's Claude
 * subscription — no API key involved, nothing billed per token.
 *
 * Each conversation is a ClaudeSession with its own long-lived process, so
 * several can run turns at the same time. The machine-wide and account-wide
 * parts stay here: where the CLI is, whether the credentials are good, what the
 * rate limit says, how a tool call is drawn. The chat view only ever renders
 * one conversation, so the properties it binds to are proxied through to
 * whichever tab is `active` — that is what keeps the view from having to know
 * tabs exist at all.
 */
Singleton {
    id: root

    readonly property var options: Config.options?.sidebar?.claude ?? null
    readonly property bool enabled: options?.enable ?? true

    // ------------------------------------------------------------------
    // Tabs
    // ------------------------------------------------------------------

    // Each tab is a whole CLI process — a Node runtime, a few hundred megabytes
    // — so this is a real ceiling rather than a tidy round number.
    readonly property int maxTabs: 6

    property var tabs: []
    property int activeIndex: 0

    readonly property ClaudeSession active: root.tabs[root.activeIndex] ?? null
    readonly property bool anyBusy: root.tabs.some(tab => tab.busy)
    readonly property bool canOpenTab: root.tabs.length < root.maxTabs

    property Component sessionComponent: ClaudeSession {}

    function newTab(workingDirectory) {
        if (!root.canOpenTab) return null;
        const requested = root.normalizePath(workingDirectory ?? "");
        const session = root.sessionComponent.createObject(root, {
            manager: root,
            workingDirectory: requested.length > 0 ? requested : root.defaultWorkingDirectory,
            selectedModel: root.options?.model ?? "",
            selectedEffort: root.options?.effort ?? "",
            permissionMode: root.options?.permissionMode ?? "ask"
        });
        if (!session) return null;
        root.tabs = [...root.tabs, session];
        root.activeIndex = root.tabs.length - 1;
        root.rememberTabs();
        return session;
    }

    // The view binds to `active` unconditionally, so there is a window between
    // startup and the first restore where there is no tab at all. Anything that
    // acts on a conversation goes through here rather than assuming one exists.
    function requireTab() {
        if (root.tabs.length === 0) return root.newTab("");
        return root.active;
    }

    function activateTab(index) {
        if (index < 0 || index >= root.tabs.length) return;
        root.activeIndex = index;
        root.tabs[index].unseen = false;
        root.rememberTabs();
    }

    function closeTab(index) {
        const session = root.tabs[index];
        if (!session) return;
        const directory = session.workingDirectory;
        session.shutDown();
        root.tabs = root.tabs.filter((_, i) => i !== index);
        // Land on the neighbour rather than jumping to the end of the strip.
        const shifted = root.activeIndex > index ? root.activeIndex - 1 : root.activeIndex;
        root.activeIndex = Math.max(0, Math.min(shifted, root.tabs.length - 1));
        // Closing the only tab means starting over, not ending up with nothing.
        if (root.tabs.length === 0) root.newTab(directory);
        root.rememberTabs();
        session.destroy();
    }

    function activateNextTab(step) {
        if (root.tabs.length < 2) return;
        const count = root.tabs.length;
        root.activateTab((root.activeIndex + step + count) % count);
    }

    // A tab is worth flagging in the strip when it is waiting on an answer, or
    // when it finished saying something while you were looking elsewhere.
    function tabNeedsAttention(session) {
        return !!session && (session.needsInput || session.unseen);
    }

    // ------------------------------------------------------------------
    // What the chat view binds to
    // ------------------------------------------------------------------

    readonly property bool busy: root.active?.busy ?? false
    readonly property bool processRunning: root.active?.processRunning ?? false
    readonly property var messageIDs: root.active?.messageIDs ?? []
    readonly property var messageByID: root.active?.messageByID ?? ({})
    readonly property string conversationTitle: root.active?.conversationTitle ?? ""
    readonly property string sessionId: root.active?.sessionId ?? ""
    readonly property string modelName: root.active?.modelName ?? ""
    readonly property string workingDirectory: root.active?.workingDirectory ?? root.defaultWorkingDirectory
    readonly property string selectedModel: root.active?.selectedModel ?? ""
    readonly property string selectedModelName: root.active?.selectedModelName ?? ""
    readonly property string selectedEffort: root.active?.selectedEffort ?? ""
    readonly property string selectedEffortName: root.active?.selectedEffortName ?? ""
    readonly property bool askPermission: root.active?.askPermission ?? true
    readonly property var pendingPermission: root.active?.pendingPermission ?? null
    readonly property var pendingQuestion: root.active?.pendingQuestion ?? null
    readonly property var queuedMessages: root.active?.queuedMessages ?? []
    readonly property var backgroundTasks: root.active?.backgroundTasks ?? []
    readonly property var sessions: root.active?.sessions ?? []
    readonly property bool sessionsLoading: root.active?.sessionsLoading ?? false
    readonly property string resumeSessionId: root.active?.resumeSessionId ?? ""
    readonly property string directoryError: root.active?.directoryError ?? ""
    readonly property int contextTokens: root.active?.contextTokens ?? 0
    readonly property int effectiveContextLimit: root.active?.effectiveContextLimit ?? 200000
    readonly property real contextFraction: root.active?.contextFraction ?? 0

    signal messageAppended

    Connections {
        target: root.active
        ignoreUnknownSignals: true
        function onMessageAppended() {
            root.messageAppended();
        }
    }

    function sendMessage(text) {
        const tab = root.requireTab();
        if (!tab) return;
        tab.sendMessage(text, root.pendingAttachments);
        root.pendingAttachments = [];
    }
    function interrupt() { root.active?.interrupt(); }
    function clearMessages() { root.requireTab()?.clearMessages(); }
    function setModel(alias) { root.requireTab()?.setModel(alias); }
    function setEffort(alias) { root.requireTab()?.setEffort(alias); }
    function setPermissionMode(mode) { root.requireTab()?.setPermissionMode(mode); }
    function setWorkingDirectory(path) { root.requireTab()?.setWorkingDirectory(path); }
    function clearDirectoryError() { if (root.active) root.active.directoryError = ""; }
    function refreshSessions() { root.requireTab()?.refreshSessions(); }
    function loadSession(id) { root.requireTab()?.loadSession(id); }
    function unqueueMessage(index) { root.active?.unqueueMessage(index); }
    function continueInterrupted(message) { root.active?.continueInterrupted(message); }
    function answerPermission(behavior, remember) { root.active?.answerPermission(behavior, remember); }
    function answerQuestion(answers, picks) { root.active?.answerQuestion(answers, picks); }
    function dismissQuestion() { root.active?.dismissQuestion(); }

    // ------------------------------------------------------------------
    // Images pasted into the composer
    // ------------------------------------------------------------------

    // What the next message carries besides its text: [{ path, mediaType, data }],
    // data already base64 so sending is a string build rather than another trip
    // to disk. Held here rather than per tab because the composer is one field
    // shared by all of them, the same as the text being typed into it.
    property var pendingAttachments: []

    // The MCP servers a session is allowed to load, as a path the CLI reads.
    // Empty unless the config names a file, which is what keeps the account's
    // connectors out of a sidebar that has no use for them.
    readonly property string mcpConfigPath: {
        const path = root.options?.mcpConfigPath ?? "";
        return path.length === 0 ? "" : root.normalizePath(path);
    }

    readonly property string clipboardScript: Quickshell.shellPath("scripts/claude/clipboard-paste.sh")

    function detachAttachment(index) {
        root.pendingAttachments = root.pendingAttachments.filter((_, i) => i !== index);
    }

    function clearAttachments() {
        root.pendingAttachments = [];
    }

    // Ctrl+V: an image on the clipboard becomes an attachment, anything else is
    // an ordinary text paste. Which one it is is only known once wl-paste has
    // answered, so the field comes along and is written to from there.
    function pasteInto(field) {
        if (pasteProcess.running) return;
        pasteProcess.field = field;
        pasteProcess.running = true;
    }

    Process {
        id: pasteProcess
        property var field: null
        command: ["bash", root.clipboardScript, Directories.claudeAttachments]

        stdout: StdioCollector {
            id: pasteCollector
            onStreamFinished: {
                const output = pasteCollector.text;
                const split = output.indexOf("\n");
                const header = (split === -1 ? output : output.slice(0, split)).split(" ");
                const body = split === -1 ? "" : output.slice(split + 1);

                if (header[0] === "image" && body.length > 0) {
                    root.pendingAttachments = [...root.pendingAttachments, {
                        path: header.slice(2).join(" "),
                        mediaType: header[1],
                        data: body.trim()
                    }];
                    return;
                }

                const target = pasteProcess.field;
                if (!target || body.length === 0) return;
                if (target.selectionStart !== target.selectionEnd) {
                    target.remove(target.selectionStart, target.selectionEnd);
                }
                target.insert(target.cursorPosition, body);
            }
        }
    }

    // ------------------------------------------------------------------
    // Where the CLI is
    // ------------------------------------------------------------------

    property string cliPath: ""
    // An explicitly configured path is the user's business and is never
    // overwritten by autodetection; a detected one is only a snapshot of where
    // the CLI happened to live at startup, so it may be re-resolved later.
    property bool cliPathConfigured: false

    readonly property bool available: cliPath.length > 0

    function normalizePath(path) {
        const home = Directories.home.replace(/^file:\/\//, "");
        return (path ?? "").trim().replace(/^file:\/\//, "").replace(/^~/, home);
    }

    readonly property string defaultWorkingDirectory: {
        const configured = root.normalizePath(options?.workingDirectory ?? "");
        return configured.length > 0 ? configured : root.normalizePath(Directories.home);
    }

    // The bundled path carries a version number, so it stops existing the
    // moment the extension updates — which it does on its own schedule, mid
    // session. Resolving once at startup is what leaves the sidebar pointing at
    // a binary that is no longer there.
    function refreshCliPath() {
        if (root.cliPathConfigured) return;
        findCliProcess.running = false;
        findCliProcess.running = true;
    }

    Process {
        id: findCliProcess
        running: true
        // The CLI may be a standalone install or the copy bundled with the
        // VS Code extension, whose path carries a version number.
        command: ["bash", "-c", "command -v claude || ls -1dt \"$HOME\"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude 2>/dev/null | head -1"]
        stdout: SplitParser {
            onRead: data => {
                const path = data.trim();
                if (path.length > 0 && !root.cliPathConfigured) {
                    root.cliPath = path;
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Authentication
    // ------------------------------------------------------------------

    // The CLI runs on whatever `claude auth login` left in
    // ~/.claude/.credentials.json, and those credentials expire. Error text is
    // not worth pattern-matching, so when a turn fails we just ask the CLI:
    // `auth status` is authoritative, offline and fast.
    property bool signedOut: false
    property bool authChecking: false
    property string authEmail: ""

    function checkAuth() {
        if (root.authChecking || root.cliPath.length === 0) return;
        root.authChecking = true;
        authStatusProcess.running = false;
        authStatusProcess.running = true;
    }

    // Signing in is a browser round trip the sidebar cannot host, so it goes to
    // a terminal — the configured one takes a trailing command, as kitty does.
    function signIn() {
        if (root.cliPath.length === 0) return;
        Quickshell.execDetached(["bash", "-c",
            `${Config.options.apps.terminal} ${root.cliPath} auth login`]);
    }

    Process {
        id: authStatusProcess
        command: [root.cliPath, "auth", "status"]
        stdout: StdioCollector {
            id: authStatusCollector
            onStreamFinished: {
                try {
                    const status = JSON.parse(authStatusCollector.text);
                    root.signedOut = status.loggedIn === false;
                    root.authEmail = status.email ?? "";
                } catch (e) {
                    // Unparsable output tells us nothing; leave the flag as it
                    // was rather than claiming a session is fine or broken.
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.authChecking = false;
        }
    }

    // ------------------------------------------------------------------
    // Model and effort choices
    // ------------------------------------------------------------------

    // Aliases the CLI accepts for --model and the set_model control request.
    // An empty alias means "whatever the CLI is configured to use".
    readonly property var availableModels: [
        { alias: "", name: Translation.tr("Default"), description: Translation.tr("Whatever `claude` is configured to use") },
        { alias: "opus", name: "Opus", description: Translation.tr("Most capable") },
        { alias: "opus[1m]", name: "Opus 1M", description: Translation.tr("Most capable, 1M context") },
        { alias: "sonnet", name: "Sonnet", description: Translation.tr("Balanced") },
        { alias: "sonnet[1m]", name: "Sonnet 1M", description: Translation.tr("Balanced, 1M context") },
        { alias: "haiku", name: "Haiku", description: Translation.tr("Fastest, cheapest on your limit") },
        { alias: "opusplan", name: "Opus plan", description: Translation.tr("Opus to plan, Sonnet to execute") },
        { alias: "fable", name: "Fable", description: Translation.tr("Writing-focused") }
    ]

    // What --effort accepts. Empty leaves it to ~/.claude/settings.json,
    // which is where the global default lives.
    readonly property var availableEfforts: [
        { alias: "", name: Translation.tr("Default"), description: Translation.tr("Whatever ~/.claude/settings.json sets") },
        { alias: "low", name: Translation.tr("Low"), description: Translation.tr("Quickest, least deliberation") },
        { alias: "medium", name: Translation.tr("Medium"), description: Translation.tr("Balanced") },
        { alias: "high", name: Translation.tr("High"), description: Translation.tr("Thinks longer before acting") },
        { alias: "xhigh", name: Translation.tr("Extra high"), description: Translation.tr("Slower still, for tangled problems") },
        { alias: "max", name: Translation.tr("Max"), description: Translation.tr("Everything it has, and the slowest") }
    ]

    // ------------------------------------------------------------------
    // Answering prompts
    // ------------------------------------------------------------------

    // Both branches park a turn until you answer, so the sound belongs here
    // rather than being duplicated into each. With several tabs running it is
    // also the only cue that a conversation you aren't looking at is waiting.
    function playInputNeededSound() {
        const command = root.options?.soundCommand ?? "";
        const file = root.options?.inputNeededSound ?? "";
        if (command.length === 0 || file.length === 0)
            return;
        Quickshell.execDetached([command, file]);
    }

    // The rule-based suggestion is the narrow one ("this exact command"), so
    // it is what "always" should mean; mode changes are a blunter fallback.
    function rememberableSuggestion(pending) {
        if (!pending) return null;
        const suggestions = pending.suggestions ?? [];
        return suggestions.find(s => s.type === "addRules")
            ?? suggestions.find(s => s.type === "setMode")
            ?? null;
    }

    // ------------------------------------------------------------------
    // Rate limits
    // ------------------------------------------------------------------

    // { status, resetsAt, rateLimitType, isUsingOverage } — the number that
    // actually means something on a subscription, unlike a dollar figure. One
    // limit covers the account, so parallel tabs eat it that much faster.
    property var rateLimit: null

    readonly property string rateLimitResetText: {
        const resetsAt = root.rateLimit?.resetsAt ?? 0;
        if (resetsAt <= 0) return "";
        const remaining = resetsAt * 1000 - Date.now();
        if (remaining <= 0) return "";
        const hours = Math.floor(remaining / 3600000);
        const minutes = Math.floor((remaining % 3600000) / 60000);
        return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
    }

    // ------------------------------------------------------------------
    // Slash commands
    // ------------------------------------------------------------------

    // [{ name, description, argumentHint }] — reported by the CLI in reply to
    // the initialize handshake. The same set whichever tab asked.
    property var slashCommands: []

    // ------------------------------------------------------------------
    // Directories Claude has been used in
    // ------------------------------------------------------------------

    // [{ path, sessions, mtime }]
    property var knownDirectories: []
    property bool directoriesLoading: false

    readonly property string sessionsScript: Quickshell.shellPath("scripts/claude/sessions.py")

    function refreshDirectories() {
        if (root.directoriesLoading) return;
        root.directoriesLoading = true;
        listDirsProcess.running = false;
        listDirsProcess.running = true;
    }

    Process {
        id: listDirsProcess
        command: ["python3", root.sessionsScript, "dirs"]
        stdout: StdioCollector {
            id: listDirsCollector
            onStreamFinished: {
                try {
                    root.knownDirectories = JSON.parse(listDirsCollector.text);
                } catch (e) {
                    root.knownDirectories = [];
                }
                root.directoriesLoading = false;
            }
        }
    }

    // ------------------------------------------------------------------
    // Tool call rendering
    // ------------------------------------------------------------------

    // Each tool gets the one input field that actually says what it's doing;
    // showing raw JSON in a narrow sidebar is unreadable.
    readonly property var toolDetailKeys: ({
        "Bash": "command",
        "Read": "file_path",
        "Write": "file_path",
        "Edit": "file_path",
        "NotebookEdit": "notebook_path",
        "Glob": "pattern",
        "Grep": "pattern",
        "WebFetch": "url",
        "WebSearch": "query",
        "Task": "description",
        "Skill": "skill"
    })

    readonly property var toolIcons: ({
        "Bash": "terminal",
        "Read": "description",
        "Write": "note_add",
        "Edit": "edit_document",
        "NotebookEdit": "edit_document",
        "Glob": "folder_open",
        "Grep": "search",
        "WebFetch": "public",
        "WebSearch": "travel_explore",
        "Task": "account_tree",
        "TodoWrite": "checklist",
        "AskUserQuestion": "quiz",
        "Skill": "extension"
    })

    // Results can run to megabytes for something like a whole-file read; the
    // chip only ever shows the head of it.
    readonly property int maxOutputChars: 8000

    function truncate(text) {
        const collapsed = (text ?? "").replace(/\s+/g, " ").trim();
        return collapsed.length > 120 ? collapsed.substring(0, 120) + "…" : collapsed;
    }

    function toolDetail(name, input) {
        if (!input) return "";
        if (name === "AskUserQuestion") {
            // Until it's answered, the question itself is the useful summary.
            const first = (input.questions ?? [])[0];
            return first ? root.truncate(first.question ?? "") : "";
        }
        const key = root.toolDetailKeys[name];
        let value = key ? input[key] : undefined;
        if (value === undefined) {
            // Unknown tool: fall back to the first string-ish field.
            for (const candidate in input) {
                if (typeof input[candidate] === "string") {
                    value = input[candidate];
                    break;
                }
            }
        }
        if (typeof value !== "string") return "";
        return root.truncate(value);
    }

    // Most tools answer with a plain string, but the block form is allowed
    // too — anything that isn't text (an image, say) has nothing to show here.
    function toolResultText(content) {
        if (typeof content === "string") return content;
        if (Array.isArray(content)) {
            return content
                .filter(block => block?.type === "text")
                .map(block => block.text ?? "")
                .join("\n");
        }
        return "";
    }

    function formatTokens(count) {
        if (count >= 1000000) return (count / 1000000).toFixed(count >= 10000000 ? 0 : 1) + "M";
        if (count >= 1000) return (count / 1000).toFixed(count >= 100000 ? 0 : 1) + "k";
        return String(count);
    }

    // ------------------------------------------------------------------
    // File references
    // ------------------------------------------------------------------

    // Claude writes paths as inline code spans rather than links, so they are
    // turned into links at render time. The raw message content is left alone:
    // the streaming reconciliation compares it against what the CLI sent.

    // Recognised suffixes, so a bare `Config.qml` is treated as a file while
    // `Object.assign` is not. Anything containing a slash is a path regardless.
    readonly property var fileExtensions: [
        "qml", "js", "mjs", "ts", "tsx", "jsx", "py", "sh", "bash", "fish", "zsh",
        "rs", "go", "c", "h", "cpp", "hpp", "java", "kt", "rb", "php", "cs", "swift",
        "lua", "vim", "json", "yaml", "yml", "toml", "ini", "conf", "cfg", "rc",
        "xml", "html", "css", "scss", "md", "txt", "log", "csv", "sql", "patch", "diff",
        "svg", "png", "jpg", "jpeg", "gif", "webp", "pdf", "desktop", "service"
    ]

    // Relative paths resolve against the tab they were written in, which is the
    // active one — messages are only ever rendered for the conversation on
    // screen.
    function resolvePath(path) {
        const home = Directories.home.replace(/^file:\/\//, "");
        if (path === "~") return home;
        if (path.startsWith("~/")) return home + path.slice(1);
        if (path.startsWith("/")) return path;
        return `${root.workingDirectory}/${path.replace(/^\.\//, "")}`;
    }

    function looksLikeFilePath(text) {
        if (text.length === 0 || text.length > 240) return false;
        if (/\s/.test(text)) return false;
        if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text)) return false; // A URL, not a path
        if (/^(~\/|\.{1,2}\/|\/)/.test(text)) return true;
        if (text.includes("/")) return true;
        if (!text.includes(".")) return false;
        return root.fileExtensions.includes(text.split(".").pop().toLowerCase());
    }

    function linkifyPaths(text) {
        if (!text || !text.includes("`")) return text ?? "";
        return text.replace(/(!?\[)?`([^`\n]+)`(\]\()?/g, (match, before, inner, after) => {
            // A code span that is already a link label stays as it is.
            if (before || after) return match;
            const trimmed = inner.trim();
            // Trailing :42 is a line number, not part of the name.
            const withLine = trimmed.match(/^(.*[^:]):(\d+)$/);
            const path = withLine ? withLine[1] : trimmed;
            if (!root.looksLikeFilePath(path)) return match;
            const target = `file://${encodeURI(root.resolvePath(path))}${withLine ? `#L${withLine[2]}` : ""}`;
            return `[\`${inner}\`](${target})`;
        });
    }

    // Whichever editor is around, in order of preference. The desktop's default
    // handler is a poor fallback for source files — it tends to route them to a
    // word processor or a browser — so it is only used when no editor turns up.
    property string editorPath: ""

    // Dolphin is the one that gets --select; the fallback below just opens the folder.
    property string fileManagerPath: ""

    // Editors disagree on how to say "this file, at this line", so the command
    // shape follows whichever one was found.
    function editorCommand(path, line) {
        const target = line.length > 0 ? `${path}:${line}` : path;
        // -client hands the file to the window that is already open instead of
        // starting a second Qt Creator every time a link is clicked.
        if (root.editorPath.endsWith("qtcreator")) return [root.editorPath, "-client", target];
        return [root.editorPath, "--goto", target];
    }

    function openFileReference(link) {
        const url = String(link);
        if (!url.startsWith("file://")) {
            Qt.openUrlExternally(url);
            return;
        }
        const hash = url.indexOf("#L");
        const line = hash >= 0 ? url.slice(hash + 2) : "";
        const path = decodeURI(url.slice("file://".length, hash >= 0 ? hash : undefined));
        if (root.editorPath.length > 0) {
            Quickshell.execDetached(root.editorCommand(path, line));
        } else {
            Qt.openUrlExternally(`file://${encodeURI(path)}`);
        }
    }

    // Ctrl+click on a file link: show it in the file manager instead of opening it. Dolphin's
    // --select highlights the file inside its folder, which is more useful than just opening the
    // folder; if it is not installed, fall back to handing the folder to the desktop's default.
    function revealFileReference(link) {
        const url = String(link);
        if (!url.startsWith("file://")) {
            Qt.openUrlExternally(url);
            return;
        }
        const hash = url.indexOf("#L");
        const path = decodeURI(url.slice("file://".length, hash >= 0 ? hash : undefined));
        if (root.fileManagerPath.length > 0) {
            Quickshell.execDetached([root.fileManagerPath, "--select", path]);
            return;
        }
        const slash = path.lastIndexOf("/");
        const dir = slash > 0 ? path.slice(0, slash) : "/";
        Qt.openUrlExternally(`file://${encodeURI(dir)}`);
    }

    Process {
        id: findFileManagerProcess
        running: true
        command: ["bash", "-c", "command -v dolphin || true"]
        stdout: SplitParser {
            onRead: data => {
                const path = data.trim();
                if (path.length > 0 && root.fileManagerPath.length === 0) {
                    root.fileManagerPath = path;
                }
            }
        }
    }

    Process {
        id: findEditorProcess
        running: true
        command: ["bash", "-c", "command -v qtcreator || command -v code || command -v codium || command -v code-insiders || true"]
        stdout: SplitParser {
            onRead: data => {
                const path = data.trim();
                if (path.length > 0 && root.editorPath.length === 0) {
                    root.editorPath = path;
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Surviving a shell reload
    // ------------------------------------------------------------------

    // Editing any QML file the shell has loaded makes Quickshell hot-reload,
    // which tears this singleton down and kills every CLI with it — mid-turn,
    // with no result event and no error. Since the agent is regularly asked to
    // edit this very config, that is a routine event rather than an edge case.
    // Every tab is remembered on disk so the whole strip comes back afterwards.
    readonly property string sessionStatePath: FileUtils.trimFileProtocol(`${Directories.state}/user/claudeSession.json`)

    // The reload kills the CLI along with the session, so the rest of the reply
    // is produced by a process nobody is reading any more -- no amount of care
    // on the receiving end can recover it. Holding the watcher off until the
    // turn is done is the only thing that keeps a reply whole, at the cost of
    // config edits landing a turn late while a tab is working.
    Binding {
        target: Quickshell
        property: "watchFiles"
        value: !root.anyBusy
    }

    // The gate above means edits made during a turn never fire the watcher --
    // Quickshell does not replay file events missed while watching was off, so
    // the shell keeps running stale code until something else changes a file.
    // Whoever edits shell files mid-turn schedules the reload here instead.
    property bool reloadPending: false

    // Queued messages are deliberately not saved across reloads, and a turn
    // hands its queue over only after `busy` has already gone false -- so
    // "safe to reload" has to mean the queues are empty too, not just idle.
    readonly property bool quiet: !root.anyBusy && !root.tabs.some(tab => tab.queuedMessages.length > 0)

    onQuietChanged: root.tryScheduledReload()

    function tryScheduledReload() {
        if (!root.reloadPending || !root.quiet) return;
        root.reloadPending = false;
        // Deferred so the shell isn't torn down inside the signal handler of
        // the turn that just finished.
        Qt.callLater(() => {
            // One event-loop tick is enough for a queued message to open a new
            // turn; re-arm for its end rather than killing it.
            if (!root.quiet) { root.reloadPending = true; return; }
            Quickshell.reload(false);
        });
    }

    // The reload paths above fail quietly by nature -- a torn-down session has
    // nowhere to report to. This is how to ask what state one is actually in
    // without reading the checkpoint file and guessing.
    IpcHandler {
        target: "claude"

        function state(): string {
            const session = root.active;
            if (!session) return "no active tab";
            const last = session.messageByID[session.messageIDs[session.messageIDs.length - 1]];
            return [
                `tab ${root.activeIndex + 1}/${root.tabs.length}  ${session.workingDirectory}`,
                `busy=${session.busy}  process=${session.processRunning}  queued=${session.queuedMessages.length}`,
                `sessionId=${session.sessionId || "(none)"}  resumeId=${session.resumeSessionId || "(none)"}`,
                `cli=${root.cliPath || "(not found)"}`,
                `lastMessage=${last ? `${last.role} done=${last.done} interrupted=${last.interrupted} len=${last.content.length}` : "(none)"}`,
                `sendBlocked=${session.sendBlockedReason() || "no"}`
            ].join("\n");
        }

        function continueLast(): string {
            const session = root.active;
            if (!session) return "no active tab";
            const before = session.messageIDs.length;
            const blocked = session.sendBlockedReason();
            const last = session.messageByID[session.messageIDs[session.messageIDs.length - 1]];
            session.continueInterrupted(last ?? null);
            const sent = session.messageIDs.length > before;
            return `blocked before=${blocked || "no"}  sent=${sent}  busy=${session.busy}  process=${session.processRunning}`;
        }

        function scheduleReload(): string {
            root.reloadPending = true;
            root.tryScheduledReload();
            return root.quiet ? "reloading now" : "reload scheduled for when every tab is idle";
        }
    }

    property bool restored: false
    property bool restoring: false
    property int restoreAttempts: 0

    function rememberTabs() {
        // Before the restore has run the tab list is not yet the truth, and
        // writing it would erase the conversations we are about to bring back.
        if (!root.restored || root.restoring) return;
        sessionState.activeIndex = root.activeIndex;
        sessionState.tabs = root.tabs.map(tab => tab.serialize());
        // The single-conversation shape this replaced, cleared once so a
        // downgrade doesn't resurrect a conversation from months ago.
        sessionState.sessionId = "";
        sessionState.workingDirectory = "";
        sessionState.messages = [];
        sessionStateFile.writeAdapter();
    }

    function restoreTabs() {
        if (root.restored) return;
        if (!Config.ready) {
            // The config lands asynchronously and holds the defaults a restored
            // tab falls back to.
            if (root.restoreAttempts++ < 20) restoreTimer.restart();
            return;
        }

        root.restored = true;
        root.restoring = true;

        // A tab already in use means something got in ahead of the restore;
        // what is on screen wins over what was on disk.
        if (root.tabs.length === 0) {
            for (const entry of root.storedTabs()) {
                const session = root.newTab(entry.workingDirectory ?? "");
                if (session) session.restore(entry);
            }
            root.activeIndex = Math.max(0, Math.min(sessionState.activeIndex, root.tabs.length - 1));
            // The tab that comes back on screen is one you are by definition
            // looking at, so its "finished while you were away" mark is spent.
            if (root.active) root.active.unseen = false;
        }

        root.restoring = false;
        if (root.tabs.length === 0) root.newTab("");
        root.rememberTabs();
    }

    // Reads either shape: the list of tabs, or the single conversation that was
    // all this file held before tabs existed.
    function storedTabs() {
        const stored = sessionState.tabs ?? [];
        if (stored.length > 0) return stored.slice(0, root.maxTabs);
        if ((sessionState.sessionId ?? "").length === 0) return [];
        return [{
            sessionId: sessionState.sessionId,
            workingDirectory: sessionState.workingDirectory,
            model: root.options?.model ?? "",
            effort: root.options?.effort ?? "",
            permissionMode: root.options?.permissionMode ?? "ask",
            messages: sessionState.messages ?? []
        }];
    }

    Timer {
        id: restoreTimer
        interval: 250
        onTriggered: root.restoreTabs()
    }

    FileView {
        id: sessionStateFile
        path: root.sessionStatePath
        watchChanges: false
        onLoaded: restoreTimer.restart()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.restored = true;
                root.newTab("");
                sessionStateFile.writeAdapter();
            }
        }

        JsonAdapter {
            id: sessionState
            property int activeIndex: 0
            property list<var> tabs: []

            // Pre-tabs shape, read once on upgrade and then left empty.
            property string sessionId: ""
            property string workingDirectory: ""
            property list<var> messages: []
        }
    }

    Component.onCompleted: {
        const configured = (options?.cliPath ?? "").trim();
        if (configured.length > 0) {
            root.cliPath = configured;
            root.cliPathConfigured = true;
        }
    }
}
