pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services.claudeCode
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Drives the Claude Code CLI in headless streaming mode and exposes the
 * conversation as a message list the sidebar can render.
 *
 * Auth note: the CLI reuses the OAuth credentials from `claude login`
 * (~/.claude/.credentials.json), so this runs on the user's Claude
 * subscription — no API key involved, nothing billed per token.
 *
 * One long-lived process serves the whole conversation: we speak
 * `--input-format stream-json` on stdin and read `--output-format stream-json`
 * on stdout, so context is retained across turns without re-spawning or
 * replaying history.
 */
Singleton {
    id: root

    readonly property var options: Config.options?.sidebar?.claude ?? null
    readonly property bool enabled: options?.enable ?? true

    property string cliPath: ""
    // An explicitly configured path is the user's business and is never
    // overwritten by autodetection; a detected one is only a snapshot of where
    // the CLI happened to live at startup, so it may be re-resolved later.
    property bool cliPathConfigured: false
    readonly property string workingDirectory: {
        const configured = (options?.workingDirectory ?? "").trim();
        const path = configured.length > 0 ? configured : Directories.home;
        return path.replace(/^file:\/\//, "").replace(/^~/, Directories.home.replace(/^file:\/\//, ""));
    }

    readonly property bool available: cliPath.length > 0
    property bool busy: false // A turn is in flight
    property string sessionId: ""
    property string modelName: ""

    // ------------------------------------------------------------------
    // Model selection
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

    property string selectedModel: ""

    readonly property string selectedModelName: {
        const match = root.availableModels.find(model => model.alias === root.selectedModel);
        return match ? match.name : root.selectedModel;
    }

    // The model the running process was spawned with. Kept separate from
    // `selectedModel` so switching mid-conversation doesn't re-evaluate the
    // command of a process that is already up — that switch goes over the
    // control channel instead.
    property string spawnModel: ""

    function setModel(alias) {
        if (alias === root.selectedModel) return;
        root.selectedModel = alias;
        if (root.options) root.options.model = alias;
        // A fresh model may have a different window; let the fallback take
        // over until the next result event reports the real one.
        root.contextLimit = 0;
        if (claudeProcess.running) {
            // The CLI swaps models in place and keeps the conversation, so
            // there's nothing to restart or replay. Omitting `model` resets
            // it to the CLI default.
            root.sendControlRequest("set_model", alias.length > 0 ? { model: alias } : ({}));
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

    // ------------------------------------------------------------------
    // Reasoning effort
    // ------------------------------------------------------------------

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

    property string selectedEffort: ""

    readonly property string selectedEffortName: {
        const match = root.availableEfforts.find(effort => effort.alias === root.selectedEffort);
        return match ? match.name : root.selectedEffort;
    }

    // The effort the running process was spawned with; see spawnModel.
    property string spawnEffort: ""

    // Unlike the model, effort has no control-request equivalent — the CLI only
    // takes it as a spawn flag — so switching means bringing the process back
    // up. Pointing the next spawn at the session it was already on keeps the
    // conversation; the restart itself is deferred to the next message, so
    // changing this between turns costs nothing.
    function setEffort(alias) {
        if (alias === root.selectedEffort) return;
        root.selectedEffort = alias;
        if (root.options) root.options.effort = alias;
        if (claudeProcess.running) {
            root.resumeSessionId = root.sessionId;
            claudeProcess.running = false;
        }
    }

    // ------------------------------------------------------------------
    // Tool permissions
    // ------------------------------------------------------------------

    // With --permission-prompt-tool the CLI asks before each tool that isn't
    // already allowed, over the same control channel as set_model. The mode
    // decides whether it bothers: bypassPermissions never asks.
    readonly property string permissionMode: options?.permissionMode ?? "ask"
    readonly property bool askPermission: root.permissionMode !== "bypass"

    // { requestId, toolName, displayName, description, input, suggestions, toolUseId }
    property var pendingPermission: null

    // AskUserQuestion arrives down the same channel, but it isn't a permission
    // question — it's Claude asking something, and the answer travels back as
    // `answers` on the tool input. { requestId, questions, input }
    property var pendingQuestion: null

    // The card disappears once answered, so the choice is written back onto
    // the tool call that asked — otherwise the transcript never records what
    // was picked.
    // `picks` keeps the chosen labels as a list per question. The CLI only
    // takes them comma-joined, but splitting that back apart would mangle any
    // label containing a comma, so the list is carried through for display.
    function recordQuestionAnswers(pending, answers, picks) {
        const message = root.currentAssistant();
        if (!message || !pending) return;
        const summary = (pending.questions ?? []).map(question => {
            const value = answers?.[question.question] ?? "";
            if (value.length === 0) return "";
            const header = (question.header ?? "").trim();
            return header.length > 0 ? `${header}: ${value}` : value;
        }).filter(part => part.length > 0).join(" · ");

        message.toolCalls = message.toolCalls.map(call => call.id === pending.toolUseId
            ? Object.assign({}, call, {
                answers: answers ?? ({}),
                picks: picks ?? ({}),
                // Survives into saved history, where the full input doesn't.
                detail: summary.length > 0 ? summary : Translation.tr("no answer")
            })
            : call);
    }

    function answerQuestion(answers, picks) {
        const pending = root.pendingQuestion;
        if (!pending) return;
        root.recordQuestionAnswers(pending, answers, picks);
        root.pendingQuestion = null;
        claudeProcess.write(JSON.stringify({
            type: "control_response",
            response: {
                subtype: "success",
                request_id: pending.requestId,
                response: {
                    behavior: "allow",
                    // Keyed by the question text; multi-select answers are
                    // joined with commas.
                    updatedInput: Object.assign({}, pending.input, { answers: answers })
                }
            }
        }) + "\n");
    }

    // Allowing the tool without answers is how "I'd rather not say" is
    // expressed: Claude is told nothing was chosen and carries on.
    function dismissQuestion() {
        const pending = root.pendingQuestion;
        if (!pending) return;
        root.recordQuestionAnswers(pending, null, null);
        root.pendingQuestion = null;
        claudeProcess.write(JSON.stringify({
            type: "control_response",
            response: {
                subtype: "success",
                request_id: pending.requestId,
                response: { behavior: "allow", updatedInput: pending.input }
            }
        }) + "\n");
    }

    function setPermissionMode(mode) {
        if (root.options) root.options.permissionMode = mode;
        if (claudeProcess.running) {
            root.sendControlRequest("set_permission_mode", {
                mode: mode === "bypass" ? "bypassPermissions" : "default"
            });
        }
        // A prompt already on screen belongs to the old mode.
        if (mode === "bypass" && root.pendingPermission) {
            root.answerPermission("allow", null);
        }
    }

    // Both branches below park the turn until you answer, so the sound belongs
    // here rather than being duplicated into each.
    function playInputNeededSound() {
        const command = Config.options?.sidebar?.claude?.soundCommand ?? "";
        const file = Config.options?.sidebar?.claude?.inputNeededSound ?? "";
        if (command.length === 0 || file.length === 0)
            return;
        Quickshell.execDetached([command, file]);
    }

    function handlePermissionRequest(event) {
        root.playInputNeededSound();
        const request = event.request;
        if (request.tool_name === "AskUserQuestion") {
            root.pendingQuestion = {
                requestId: event.request_id,
                questions: request.input?.questions ?? [],
                input: request.input ?? ({}),
                toolUseId: request.tool_use_id ?? ""
            };
            return;
        }
        root.pendingPermission = {
            requestId: event.request_id,
            toolName: request.tool_name ?? "",
            displayName: request.display_name ?? request.tool_name ?? "",
            description: request.description ?? "",
            input: request.input ?? ({}),
            suggestions: request.permission_suggestions ?? [],
            toolUseId: request.tool_use_id ?? ""
        };
    }

    // `remember` is one of the CLI's own permission_suggestions, or null for
    // a one-off answer.
    function answerPermission(behavior, remember) {
        const pending = root.pendingPermission;
        if (!pending) return;
        root.pendingPermission = null;

        const response = behavior === "allow"
            ? { behavior: "allow", updatedInput: pending.input }
            : { behavior: "deny", message: Translation.tr("Declined in the sidebar.") };
        if (behavior === "allow" && remember) response.updatedPermissions = [remember];

        claudeProcess.write(JSON.stringify({
            type: "control_response",
            response: {
                subtype: "success",
                request_id: pending.requestId,
                response: response
            }
        }) + "\n");
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
    // actually means something on a subscription, unlike a dollar figure.
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
    // the initialize handshake.
    property var slashCommands: []

    // ------------------------------------------------------------------
    // Surviving a shell reload
    // ------------------------------------------------------------------

    // Editing any QML file the shell has loaded makes Quickshell hot-reload,
    // which tears this singleton down and kills the CLI with it — mid-turn,
    // with no result event and no error. Since the agent is regularly asked to
    // edit this very config, that is a routine event rather than an edge case.
    // The conversation is remembered on disk so it comes back afterwards.
    readonly property string sessionStatePath: FileUtils.trimFileProtocol(`${Directories.state}/user/claudeSession.json`)
    property int restoreAttempts: 0

    // What is on screen is saved rather than the CLI's own transcript: the
    // transcript lags the stream by a beat, and a reload lands mid-turn, so
    // the transcript is missing precisely the reply that was interrupted.
    function rememberSession() {
        // After an interrupt the live id is gone but the session is still
        // resumable, so fall back to the id the next spawn will resume from.
        const id = root.sessionId.length > 0 ? root.sessionId : root.resumeSessionId;
        if (id.length === 0) return;
        sessionState.sessionId = id;
        sessionState.workingDirectory = root.workingDirectory;
        sessionState.messages = root.messageIDs.slice(-200).map(id => {
            const message = root.messageByID[id];
            return {
                role: message.role,
                content: message.content,
                model: message.model,
                done: message.done,
                isError: message.isError,
                interrupted: message.interrupted,
                thinkingTokens: message.thinkingTokens,
                // Inputs can carry whole file contents; the chip detail is
                // enough to redraw the history.
                toolCalls: message.toolCalls.map(call => ({
                    id: call.id,
                    name: call.name,
                    icon: call.icon,
                    detail: call.detail,
                    status: call.status,
                    contentOffset: call.contentOffset ?? 0
                }))
            };
        });
        sessionStateFile.writeAdapter();
    }

    function forgetSession() {
        sessionState.sessionId = "";
        sessionState.workingDirectory = "";
        sessionState.messages = [];
        sessionStateFile.writeAdapter();
    }

    function restoreLastSession() {
        if (root.messageIDs.length > 0 || root.busy) return;
        if (!Config.ready) {
            // The config lands asynchronously and decides the working
            // directory, which is what makes a stored session ours or not.
            if (root.restoreAttempts++ < 20) restoreTimer.restart();
            return;
        }
        if (sessionState.sessionId.length === 0) return;
        if (sessionState.workingDirectory !== root.workingDirectory) return;

        const stored = sessionState.messages ?? [];
        if (stored.length === 0) {
            // Nothing of our own saved, but the CLI's transcript may still
            // have the conversation.
            root.loadSession(sessionState.sessionId);
            return;
        }

        root.resumeSessionId = sessionState.sessionId;
        for (const entry of stored) {
            const id = root.addMessage(entry.role, entry.content, entry.isError);
            const message = root.messageByID[id];
            if (!message) continue;
            message.model = entry.model ?? "";
            message.toolCalls = (entry.toolCalls ?? []).map(call =>
                call.status === "running" ? Object.assign({}, call, { status: "done" }) : call);
            message.done = true;
            // Survives a second reload, so the offer to resume doesn't vanish
            // just because the shell restarted again before it was taken up.
            message.interrupted = entry.interrupted ?? false;
        }

        // A reply cut off by the reload should say so rather than just stop —
        // as a flag rather than appended prose, so the view can offer to resume
        // instead of leaving the user to retype the request.
        const last = root.messageByID[root.messageIDs[root.messageIDs.length - 1]];
        if (last && last.role === "assistant" && stored[stored.length - 1].done === false) {
            last.interrupted = true;
        }
    }

    Timer {
        id: restoreTimer
        interval: 250
        onTriggered: root.restoreLastSession()
    }

    Timer { // Checkpoint mid-turn, since that is when a reload tends to hit
        id: checkpointTimer
        interval: 2000
        repeat: true
        running: root.busy
        onTriggered: root.rememberSession()
    }

    FileView {
        id: sessionStateFile
        path: root.sessionStatePath
        watchChanges: false
        onLoaded: restoreTimer.restart()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) sessionStateFile.writeAdapter();
        }

        JsonAdapter {
            id: sessionState
            property string sessionId: ""
            property string workingDirectory: ""
            property list<var> messages: []
        }
    }

    // ------------------------------------------------------------------
    // Working directory
    // ------------------------------------------------------------------

    // [{ path, sessions, mtime }] — directories Claude has been used in.
    property var knownDirectories: []
    property bool directoriesLoading: false
    property string directoryError: ""

    function refreshDirectories() {
        if (root.directoriesLoading) return;
        root.directoriesLoading = true;
        listDirsProcess.running = false;
        listDirsProcess.running = true;
    }

    function setWorkingDirectory(path) {
        const trimmed = (path ?? "").trim();
        if (trimmed.length === 0 || root.busy) return;
        root.directoryError = "";
        resolveDirProcess.candidate = trimmed;
        resolveDirProcess.running = false;
        resolveDirProcess.running = true;
    }

    function applyWorkingDirectory(path) {
        if (path === root.workingDirectory) return;
        // The conversation and its history both belong to the old directory,
        // so moving means starting over rather than carrying them across.
        root.clearMessages();
        root.sessions = [];
        if (root.options) root.options.workingDirectory = path;
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

    Process {
        id: resolveDirProcess
        property string candidate: ""
        command: ["python3", root.sessionsScript, "resolve", resolveDirProcess.candidate]
        stdout: StdioCollector {
            id: resolveDirCollector
            onStreamFinished: {
                let resolved;
                try {
                    resolved = JSON.parse(resolveDirCollector.text);
                } catch (e) {
                    root.directoryError = Translation.tr("Could not read that path.");
                    return;
                }
                if (resolved.exists) {
                    root.applyWorkingDirectory(resolved.path);
                } else {
                    root.directoryError = Translation.tr("No such directory: %1").arg(resolved.path);
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Conversation history
    // ------------------------------------------------------------------

    // The CLI keeps a JSONL transcript per conversation. The helper script
    // turns those into something renderable; resuming one is just --resume.
    readonly property string sessionsScript: Quickshell.shellPath("scripts/claude/sessions.py")

    // [{ id, title, mtime, turns }] for the working directory, newest first.
    property var sessions: []
    property bool sessionsLoading: false

    // Set when a past conversation is opened, so the next spawn continues it.
    property string resumeSessionId: ""
    property string spawnResumeId: ""

    readonly property string conversationTitle: {
        for (const id of root.messageIDs) {
            const message = root.messageByID[id];
            if (message?.role === "user" && message.content.length > 0) {
                return message.content.split("\n")[0].substring(0, 90);
            }
        }
        return "";
    }

    function refreshSessions() {
        if (root.sessionsLoading) return;
        root.sessionsLoading = true;
        listSessionsProcess.running = false;
        listSessionsProcess.running = true;
    }

    function loadSession(id) {
        if (root.busy || id.length === 0) return;
        root.clearMessages();
        root.resumeSessionId = id;
        root.sessionId = id;
        root.rememberSession();
        readSessionProcess.targetId = id;
        readSessionProcess.running = false;
        readSessionProcess.running = true;
    }

    function applyTranscript(transcript) {
        for (const entry of transcript) {
            const id = root.addMessage(entry.role, entry.text);
            const message = root.messageByID[id];
            if (!message) continue;
            message.done = true;
            message.model = entry.model ?? "";
            message.toolCalls = (entry.tools ?? []).map(tool => ({
                id: tool.id,
                name: tool.name,
                icon: root.toolIcons[tool.name] ?? "build",
                detail: root.toolDetail(tool.name, tool.input),
                // Anything in a finished transcript has already run.
                status: "done"
            }));
        }
    }

    Process {
        id: listSessionsProcess
        command: ["python3", root.sessionsScript, "list", root.workingDirectory]
        stdout: StdioCollector {
            id: listSessionsCollector
            onStreamFinished: {
                try {
                    root.sessions = JSON.parse(listSessionsCollector.text);
                } catch (e) {
                    root.sessions = [];
                    console.warn("[ClaudeCode] could not read session list:", e);
                }
                root.sessionsLoading = false;
            }
        }
        stderr: SplitParser {
            onRead: data => {
                if (data.trim().length > 0) console.warn("[ClaudeCode/sessions]", data);
            }
        }
    }

    Process {
        id: readSessionProcess
        property string targetId: ""
        command: ["python3", root.sessionsScript, "read", root.workingDirectory, readSessionProcess.targetId]
        stdout: StdioCollector {
            id: readSessionCollector
            onStreamFinished: {
                try {
                    root.applyTranscript(JSON.parse(readSessionCollector.text));
                } catch (e) {
                    root.addMessage("interface", Translation.tr("Could not read that conversation."), true);
                }
            }
        }
        stderr: SplitParser {
            onRead: data => {
                if (data.trim().length > 0) console.warn("[ClaudeCode/sessions]", data);
            }
        }
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

    // ------------------------------------------------------------------
    // Context window usage
    // ------------------------------------------------------------------

    // Everything the last request carried: fresh input, freshly cached, and
    // cache hits, plus what came back — i.e. what the next turn starts from.
    property int contextTokens: 0
    // Reported per model in the result event; 0 until the first turn lands.
    property int contextLimit: 0

    readonly property int effectiveContextLimit: {
        if (root.contextLimit > 0) return root.contextLimit;
        if (root.modelName.includes("[1m]")) return 1000000;
        return 200000;
    }
    readonly property real contextFraction: root.effectiveContextLimit > 0
        ? Math.min(1, root.contextTokens / root.effectiveContextLimit)
        : 0

    function formatTokens(count) {
        if (count >= 1000000) return (count / 1000000).toFixed(count >= 10000000 ? 0 : 1) + "M";
        if (count >= 1000) return (count / 1000).toFixed(count >= 100000 ? 0 : 1) + "k";
        return String(count);
    }

    property var messageIDs: []
    property var messageByID: ({})

    property Component messageComponent: ClaudeMessageData {}

    signal messageAppended

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    // Anything typed while a turn is running, sent in order once it finishes.
    property var queuedMessages: []

    function unqueueMessage(index) {
        root.queuedMessages = root.queuedMessages.filter((_, i) => i !== index);
    }

    // Picking a cut-off turn back up. The CLI session is still resumable, so
    // this is an ordinary message — the flag only decides whether the offer is
    // on screen, and it clears whether or not the send goes through, since a
    // second press would only queue the same request twice.
    function continueInterrupted(message) {
        if (message) message.interrupted = false;
        root.sendMessage(Translation.tr("Continue where you left off."));
    }

    function sendMessage(text) {
        const trimmed = text.trim();
        if (trimmed.length === 0) return;
        if (!root.available) {
            root.addMessage("interface", Translation.tr("Claude Code CLI not found. Set sidebar.claude.cliPath in the config."), true);
            return;
        }
        if (root.busy) {
            root.queuedMessages = [...root.queuedMessages, trimmed];
            return;
        }

        root.addMessage("user", trimmed);
        root.busy = true;
        // The assistant bubble is created up front so the spinner has somewhere
        // to live while we wait for the first token.
        root.currentAssistantId = root.addMessage("assistant", "");

        if (!claudeProcess.running) {
            root.spawnModel = root.selectedModel;
            root.spawnEffort = root.selectedEffort;
            root.spawnResumeId = root.resumeSessionId;
            claudeProcess.running = true;
            // A process that never starts emits no `exited`, so nothing below
            // would ever clear `busy` and the turn would spin forever. Watch
            // for the first sign of life instead.
            root.spawnPending = true;
            spawnWatchdog.restart();
            // The reply to this carries the slash command list.
            root.sendControlRequest("initialize", { hooks: ({}) });
        }
        claudeProcess.write(JSON.stringify({
            type: "user",
            message: {
                role: "user",
                content: [{ type: "text", text: trimmed }]
            }
        }) + "\n");
    }

    // ------------------------------------------------------------------
    // Spawn failures
    // ------------------------------------------------------------------

    // Qt reports a binary that cannot be started through `errorOccurred`, not
    // `exited`, so `onExited` below never runs and the turn it belongs to is
    // never failed. The usual cause is the detected CLI moving out from under
    // us: the copy bundled with the VS Code extension lives in a versioned
    // directory that disappears on every extension update.
    property bool spawnPending: false

    // Anything at all on stdout means the process is up and the turn is now the
    // stream's problem, not the watchdog's.
    function noteProcessAlive() {
        if (!root.spawnPending) return;
        root.spawnPending = false;
        spawnWatchdog.stop();
    }

    function failSpawn() {
        if (!root.spawnPending) return;
        root.spawnPending = false;
        // A slow starter that came up without saying anything yet is not a
        // failure; leave it to the stream and to onExited.
        if (claudeProcess.running) return;

        const assistant = root.currentAssistant();
        if (assistant) {
            assistant.done = true;
            assistant.isError = true;
            if (assistant.content.length === 0) {
                assistant.content = Translation.tr("Claude Code failed to start — nothing runnable at `%1`. Looking the CLI up again; send that message once more.").arg(root.cliPath);
            }
        }
        root.busy = false;
        root.currentAssistantId = "";
        // These were stacking up invisibly behind a turn that was never going
        // to finish; better to drop them than to replay them out of order.
        root.queuedMessages = [];
        root.refreshCliPath();
    }

    Timer {
        id: spawnWatchdog
        interval: 10000 // Generous: a cold start still prints within a second.
        repeat: false
        onTriggered: root.failSpawn()
    }

    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = ({});
        root.currentAssistantId = "";
        root.thinkingStartedAt = 0;
        root.sessionId = "";
        root.busy = false;
        root.contextTokens = 0;
        root.pendingPermission = null;
        root.pendingQuestion = null;
        root.queuedMessages = [];
        root.resumeSessionId = "";
        root.forgetSession();
        root.spawnPending = false;
        spawnWatchdog.stop();
        // Dropping the process drops the CLI-side conversation with it.
        claudeProcess.running = false;
    }

    // Out-of-band commands to a running process (model switches and the like).
    property int controlRequestCounter: 0

    function sendControlRequest(subtype, extra) {
        if (!claudeProcess.running) return;
        root.controlRequestCounter += 1;
        claudeProcess.write(JSON.stringify({
            type: "control_request",
            request_id: `qs_${root.controlRequestCounter}`,
            request: Object.assign({ subtype: subtype }, extra ?? ({}))
        }) + "\n");
    }

    function interrupt() {
        if (!root.busy) return;
        root.flushThought();
        // Answering first keeps the CLI from blocking on a prompt nobody
        // will ever click once the process is gone.
        if (root.pendingPermission) root.answerPermission("deny", null);
        if (root.pendingQuestion) root.dismissQuestion();
        // The CLI records the interrupt in its transcript and the session stays
        // resumable, so claim the id before onExited clears it. Without this the
        // next message spawns a blank session and the conversation on screen is
        // one the agent has never seen.
        if (root.sessionId.length > 0) root.resumeSessionId = root.sessionId;
        root.spawnPending = false;
        spawnWatchdog.stop();
        claudeProcess.running = false;
        root.busy = false;
        root.queuedMessages = [];
        const current = root.messageByID[root.currentAssistantId];
        if (current) {
            current.done = true;
            if (current.content.length === 0) {
                current.content = Translation.tr("_Interrupted_");
            }
        }
        root.currentAssistantId = "";
        // busy just went false, so the checkpoint timer has stopped; this is the
        // last chance to persist the interrupted turn for a later reload.
        root.rememberSession();
    }

    // ------------------------------------------------------------------
    // Message bookkeeping
    // ------------------------------------------------------------------

    property string currentAssistantId: ""

    function newMessageId() {
        return Date.now().toString(36) + Math.random().toString(36).substring(2, 8);
    }

    function addMessage(role, content, isError) {
        const id = root.newMessageId();
        const message = root.messageComponent.createObject(root, {
            role: role,
            content: content ?? "",
            done: role !== "assistant",
            isError: isError ?? false,
            model: root.modelName
        });
        root.messageByID[id] = message;
        root.messageIDs = [...root.messageIDs, id];
        root.messageAppended();
        return id;
    }

    function currentAssistant() {
        return root.messageByID[root.currentAssistantId] ?? null;
    }

    function appendAssistantText(text) {
        const message = root.currentAssistant();
        if (!message || text.length === 0) return;
        message.content += text;
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

    function addToolCall(id, name, input, contentOffset) {
        const message = root.currentAssistant();
        if (!message) return;
        // A thought that ran right up to this call belongs above it.
        root.flushThought();
        message.toolCalls = [...message.toolCalls, {
            id: id,
            name: name,
            icon: root.toolIcons[name] ?? "build",
            detail: root.toolDetail(name, input),
            // Kept so the chip can expand into a diff or a todo list.
            input: input ?? ({}),
            status: "running",
            // How far into the prose this happened, so the timeline can put the
            // chip back between the paragraphs it actually interrupted.
            contentOffset: contentOffset ?? message.content.length
        }];
    }

    // Thinking arrives as size estimates with no text attached, so the only
    // thing there is to report is how long it went on for. Timed here and
    // folded into the same list as the tool calls, which makes it one entry in
    // the timeline rather than a second thing the view has to interleave.
    property double thinkingStartedAt: 0
    property int thoughtCounter: 0
    readonly property int minReportedThinkingMs: 1000

    function noteThinking() {
        if (root.thinkingStartedAt === 0) root.thinkingStartedAt = Date.now();
    }

    function flushThought() {
        if (root.thinkingStartedAt === 0) return;
        const elapsed = Date.now() - root.thinkingStartedAt;
        root.thinkingStartedAt = 0;
        // A sub-second pause is noise, not a step worth a row of its own.
        if (elapsed < root.minReportedThinkingMs) return;
        const message = root.currentAssistant();
        if (!message) return;
        root.thoughtCounter += 1;
        message.toolCalls = [...message.toolCalls, {
            id: `thought_${root.thoughtCounter}`,
            name: "__thought",
            icon: "neurology",
            detail: Translation.tr("Thought for %1s").arg(Math.round(elapsed / 1000)),
            status: "done",
            contentOffset: message.content.length
        }];
    }

    // Results can run to megabytes for something like a whole-file read; the
    // chip only ever shows the head of it.
    readonly property int maxOutputChars: 8000

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

    function resolveToolCall(id, isError, output) {
        const message = root.currentAssistant();
        if (!message) return;
        const text = (output ?? "");
        message.toolCalls = message.toolCalls.map(call => call.id === id
            ? Object.assign({}, call, {
                status: isError ? "error" : "done",
                output: text.length > root.maxOutputChars
                    ? text.substring(0, root.maxOutputChars) + "\n…"
                    : text
            })
            : call);
    }

    // ------------------------------------------------------------------
    // Stream handling
    // ------------------------------------------------------------------

    function handleEvent(event) {
        switch (event.type) {
        case "system":
            if (event.subtype === "init") {
                root.sessionId = event.session_id ?? root.sessionId;
                root.modelName = event.model ?? root.modelName;
                root.rememberSession();
            }
            break;

        case "stream_event":
            root.handleStreamEvent(event.event);
            break;

        case "assistant":
            root.handleAssistantMessage(event.message);
            break;

        case "user":
            // Tool results come back as synthetic user messages.
            root.handleToolResults(event.message);
            break;

        case "result":
            root.finishTurn(event);
            break;

        case "control_request":
            if (event.request?.subtype === "can_use_tool") {
                root.handlePermissionRequest(event);
            }
            break;

        case "control_response":
            if (event.response?.subtype === "error") {
                console.warn("[ClaudeCode] control request failed:", event.response.error);
            } else if (event.response?.response?.commands) {
                root.slashCommands = event.response.response.commands;
            }
            break;

        case "rate_limit_event":
            root.rateLimit = event.rate_limit_info ?? null;
            break;
        }
    }

    // Live token deltas. The `assistant` event that follows is authoritative,
    // so anything accumulated here is a preview that gets reconciled below.
    property string streamedText: ""

    function handleStreamEvent(event) {
        if (!event) return;
        if (event.type === "content_block_start" && event.content_block?.type === "text") {
            root.streamedText = "";
        } else if (event.type === "content_block_delta" && event.delta?.type === "text_delta") {
            const chunk = event.delta.text ?? "";
            // Prose starting is what ends a thought, and it has to close before
            // the chunk lands so the entry sits above the text and not after it.
            root.flushThought();
            root.streamedText += chunk;
            root.appendAssistantText(chunk);
        } else if (event.type === "content_block_delta" && event.delta?.type === "thinking_delta") {
            // The thinking text itself never arrives — only a running estimate
            // of how much of it there is — so that count is what we show.
            root.noteThinking();
            const message = root.currentAssistant();
            if (message) {
                message.thinkingTokens = Math.max(message.thinkingTokens, event.delta.estimated_tokens ?? 0);
            }
        }
    }

    function handleAssistantMessage(message) {
        if (!message) return;
        const assistant = root.currentAssistant();
        if (!assistant) return;

        if (message.model) assistant.model = message.model;
        root.updateContextTokens(message.usage);

        root.flushThought();

        // Reconcile the streamed preview against the authoritative text. Tool
        // calls are collected rather than registered inside the loop: a tool_use
        // block comes after the text of the same message, so where it belongs is
        // only known once that text has been placed.
        let finalText = "";
        const toolBlocks = [];
        for (const block of (message.content ?? [])) {
            if (block.type === "text") {
                finalText += block.text ?? "";
            } else if (block.type === "tool_use") {
                toolBlocks.push({ block: block, offset: finalText.length });
            }
        }

        let textStart = assistant.content.length;
        if (finalText.length > 0) {
            if (root.streamedText.length > 0 && assistant.content.endsWith(root.streamedText)) {
                // Swap the preview for the final text rather than duplicating it.
                textStart = assistant.content.length - root.streamedText.length;
                assistant.content = assistant.content.slice(0, textStart) + finalText;
            } else if (!assistant.content.endsWith(finalText)) {
                const separator = assistant.content.length > 0 ? "\n\n" : "";
                textStart = assistant.content.length + separator.length;
                assistant.content += separator + finalText;
            } else {
                textStart = assistant.content.length - finalText.length;
            }
        }
        for (const pending of toolBlocks) {
            root.addToolCall(pending.block.id, pending.block.name, pending.block.input, textStart + pending.offset);
        }
        root.streamedText = "";
    }

    // Each assistant message reports the size of the prompt that produced it,
    // so the newest one is the best read on how full the window is.
    function updateContextTokens(usage) {
        if (!usage) return;
        root.contextTokens = (usage.input_tokens ?? 0)
            + (usage.cache_creation_input_tokens ?? 0)
            + (usage.cache_read_input_tokens ?? 0)
            + (usage.output_tokens ?? 0);
    }

    function updateContextLimit(modelUsage) {
        if (!modelUsage) return;
        const keys = Object.keys(modelUsage);
        if (keys.length === 0) return;
        // Keyed by the full model string; opusplan runs two, so prefer the one
        // the session reports and fall back to whichever came last.
        const entry = modelUsage[root.modelName] ?? modelUsage[keys[keys.length - 1]];
        if ((entry?.contextWindow ?? 0) > 0) root.contextLimit = entry.contextWindow;
    }

    function handleToolResults(message) {
        for (const block of (message?.content ?? [])) {
            if (block.type === "tool_result") {
                root.resolveToolCall(block.tool_use_id, block.is_error ?? false,
                    root.toolResultText(block.content));
            }
        }
    }

    function finishTurn(event) {
        // A turn that thought and then stopped without saying anything still
        // spent the time, so close the thought before the message goes final.
        root.flushThought();
        root.updateContextLimit(event.modelUsage);
        // A turn that came back at all proves the credentials are good, which
        // also clears the card after a sign-in the sidebar never saw happen.
        if (!event.is_error && event.subtype === "success") root.signedOut = false;
        const assistant = root.currentAssistant();
        if (assistant) {
            assistant.done = true;
            if (event.is_error || event.subtype !== "success") {
                assistant.isError = true;
                if (assistant.content.length === 0) {
                    assistant.content = event.result ?? Translation.tr("The request failed.");
                }
                // Expired credentials look like any other failed turn from
                // here, so let the CLI say whether that is what this was.
                root.checkAuth();
            } else if (assistant.content.length === 0 && (event.result ?? "").length > 0) {
                assistant.content = event.result;
            }
            // Tools still marked running at this point never reported back.
            assistant.toolCalls = assistant.toolCalls.map(call =>
                call.status === "running" ? Object.assign({}, call, { status: "done" }) : call);
        }
        root.currentAssistantId = "";
        root.streamedText = "";
        root.busy = false;
        root.pendingPermission = null;
        root.pendingQuestion = null;
        root.rememberSession();

        if (root.queuedMessages.length > 0) {
            const next = root.queuedMessages[0];
            root.queuedMessages = root.queuedMessages.slice(1);
            Qt.callLater(() => root.sendMessage(next));
        }
    }

    // ------------------------------------------------------------------
    // Processes
    // ------------------------------------------------------------------

    Process {
        id: claudeProcess
        running: false
        workingDirectory: root.workingDirectory
        stdinEnabled: true
        command: [
            root.cliPath,
            "--print",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            // Route permission questions to us over the control channel. The
            // mode below decides whether the CLI bothers asking at all, so
            // this stays on and the toggle stays live.
            "--permission-prompt-tool", "stdio",
            "--permission-mode", root.askPermission ? "default" : "bypassPermissions",
            // Skip the user's MCP servers: they add seconds of startup and a
            // lot of tool-schema tokens that a desktop sidebar has no use for.
            "--strict-mcp-config",
            "--append-system-prompt", root.options?.systemPrompt ?? "",
            ...(root.spawnModel.length > 0 ? ["--model", root.spawnModel] : []),
            ...(root.spawnEffort.length > 0 ? ["--effort", root.spawnEffort] : []),
            ...(root.spawnResumeId.length > 0 ? ["--resume", root.spawnResumeId] : [])
        ]

        stdout: SplitParser {
            onRead: data => {
                root.noteProcessAlive();
                const line = data.trim();
                if (line.length === 0) return;
                let event;
                try {
                    event = JSON.parse(line);
                } catch (e) {
                    return; // Non-JSON noise on stdout is not ours to handle.
                }
                root.handleEvent(event);
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (data.trim().length > 0) console.warn("[ClaudeCode]", data);
            }
        }

        onExited: (exitCode, exitStatus) => {
            // It started, so whatever happens next is an exit, not a spawn
            // failure.
            root.spawnPending = false;
            spawnWatchdog.stop();
            if (root.busy) {
                const assistant = root.currentAssistant();
                if (assistant) {
                    assistant.done = true;
                    assistant.isError = true;
                    if (assistant.content.length === 0) {
                        assistant.content = Translation.tr("Claude Code exited unexpectedly (code %1).").arg(exitCode);
                    }
                }
                root.busy = false;
                root.currentAssistantId = "";
            }
            root.sessionId = "";
            // A process that dies on its own is the other face of an expired
            // session: it never gets far enough to report a failed turn.
            if (exitCode !== 0) root.checkAuth();
        }
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

    Component.onCompleted: {
        const configured = (options?.cliPath ?? "").trim();
        if (configured.length > 0) {
            root.cliPath = configured;
            root.cliPathConfigured = true;
        }
        root.selectedModel = options?.model ?? "";
        root.selectedEffort = options?.effort ?? "";
    }
}
