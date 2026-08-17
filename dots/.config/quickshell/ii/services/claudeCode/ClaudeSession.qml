pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * One Claude Code conversation: a CLI process, the messages it produced, and
 * everything that is true of that conversation alone.
 *
 * Several of these run side by side, so nothing account-wide or machine-wide
 * belongs here — the CLI path, the credentials, the rate limit and the tool
 * icons live on the ClaudeCode singleton. That singleton is handed in as
 * `manager` rather than imported, since it is the thing that creates us and
 * importing it back would make the two files circular.
 *
 * A Scope rather than an Item: a conversation has a process and some timers but
 * nothing to draw, and an Item created outside the scene graph warns about it
 * every time a tab is opened.
 */
Scope {
    id: root

    required property var manager

    property string workingDirectory: ""

    property bool busy: false // A turn is in flight
    // `busy` is what the UI trusts; this is what is actually true, and the gap
    // between the two is where a reload leaves a session stuck.
    readonly property bool processRunning: claudeProcess.running
    property string sessionId: ""
    property string modelName: ""

    // A turn that finished while some other tab was on screen, so the tab strip
    // can say there is something here to read.
    property bool unseen: false

    readonly property bool active: root.manager.active === root

    // ------------------------------------------------------------------
    // Model and effort
    // ------------------------------------------------------------------

    property string selectedModel: ""

    readonly property string selectedModelName: {
        const match = root.manager.availableModels.find(model => model.alias === root.selectedModel);
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
        root.rememberPreference("model", alias);
        // A fresh model may have a different window; let the fallback take
        // over until the next result event reports the real one.
        root.contextLimit = 0;
        if (claudeProcess.running) {
            // The CLI swaps models in place and keeps the conversation, so
            // there's nothing to restart or replay. Omitting `model` resets
            // it to the CLI default.
            root.sendControlRequest("set_model", alias.length > 0 ? { model: alias } : ({}));
        }
        root.manager.rememberTabs();
    }

    property string selectedEffort: ""

    readonly property string selectedEffortName: {
        const match = root.manager.availableEfforts.find(effort => effort.alias === root.selectedEffort);
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
        root.rememberPreference("effort", alias);
        if (claudeProcess.running) {
            root.resumeSessionId = root.sessionId;
            root.discardStream = true;
            claudeProcess.running = false;
        }
        root.manager.rememberTabs();
    }

    // A per-tab choice, but the last one made in the tab you were looking at is
    // also the best guess for the next tab you open, so it goes back to the
    // config the way it did when there was only one conversation.
    function rememberPreference(key, value) {
        if (!root.active || !root.manager.options) return;
        root.manager.options[key] = value;
    }

    // ------------------------------------------------------------------
    // Tool permissions
    // ------------------------------------------------------------------

    // With --permission-prompt-tool the CLI asks before each tool that isn't
    // already allowed, over the same control channel as set_model. The mode
    // decides whether it bothers: bypassPermissions never asks.
    property string permissionMode: "ask"
    readonly property bool askPermission: root.permissionMode !== "bypass"

    // { requestId, toolName, displayName, description, input, suggestions, toolUseId }
    property var pendingPermission: null

    // AskUserQuestion arrives down the same channel, but it isn't a permission
    // question — it's Claude asking something, and the answer travels back as
    // `answers` on the tool input. { requestId, questions, input }
    property var pendingQuestion: null

    readonly property bool needsInput: root.pendingPermission !== null || root.pendingQuestion !== null

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
        root.permissionMode = mode;
        root.rememberPreference("permissionMode", mode);
        if (claudeProcess.running) {
            root.sendControlRequest("set_permission_mode", {
                mode: mode === "bypass" ? "bypassPermissions" : "default"
            });
        }
        // A prompt already on screen belongs to the old mode.
        if (mode === "bypass" && root.pendingPermission) {
            root.answerPermission("allow", null);
        }
        root.manager.rememberTabs();
    }

    function handlePermissionRequest(event) {
        root.manager.playInputNeededSound();
        if (!root.active) root.unseen = true;
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

    // ------------------------------------------------------------------
    // Working directory
    // ------------------------------------------------------------------

    property string directoryError: ""

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
        root.workingDirectory = path;
        root.rememberPreference("workingDirectory", path);
        root.manager.rememberTabs();
    }

    Process {
        id: resolveDirProcess
        property string candidate: ""
        command: ["python3", root.manager.sessionsScript, "resolve", resolveDirProcess.candidate]
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

    // [{ id, title, mtime, turns }] for this tab's working directory, newest
    // first. Per tab rather than global, since each tab has its own directory.
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
        root.manager.rememberTabs();
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
                icon: root.manager.toolIcons[tool.name] ?? "build",
                detail: root.manager.toolDetail(tool.name, tool.input),
                // The chip expansions read from the input, so dropping it here
                // would leave every diff in a loaded conversation unopenable.
                input: tool.input ?? ({}),
                // Anything in a finished transcript has already run.
                status: "done"
            }));
        }
    }

    Process {
        id: listSessionsProcess
        command: ["python3", root.manager.sessionsScript, "list", root.workingDirectory]
        stdout: StdioCollector {
            id: listSessionsCollector
            onStreamFinished: {
                try {
                    root.sessions = JSON.parse(listSessionsCollector.text);
                } catch (e) {
                    root.sessions = [];
                    console.warn("[ClaudeSession] could not read session list:", e);
                }
                root.sessionsLoading = false;
            }
        }
        stderr: SplitParser {
            onRead: data => {
                if (data.trim().length > 0) console.warn("[ClaudeSession/sessions]", data);
            }
        }
    }

    Process {
        id: readSessionProcess
        property string targetId: ""
        command: ["python3", root.manager.sessionsScript, "read", root.workingDirectory, readSessionProcess.targetId]
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
                if (data.trim().length > 0) console.warn("[ClaudeSession/sessions]", data);
            }
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

    // ------------------------------------------------------------------
    // Messages
    // ------------------------------------------------------------------

    property var messageIDs: []
    property var messageByID: ({})

    property Component messageComponent: ClaudeMessageData {}

    signal messageAppended

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
        // Published as a fresh object rather than mutated in place: an in-place
        // key write emits no change signal, so a view binding that looked the
        // id up before it landed would stay undefined for the life of that
        // delegate — an empty bubble with nothing but the speaker's name.
        root.messageByID = Object.assign({}, root.messageByID, { [id]: message });
        root.messageIDs = [...root.messageIDs, id];
        root.messageAppended();
        return id;
    }

    function currentAssistant() {
        return root.messageByID[root.currentAssistantId] ?? null;
    }

    // A reload rebuilds the session mid-turn and leaves no open bubble, while
    // the reply keeps arriving. Without somewhere to put it the rest of the
    // answer is parsed and dropped, and the turn ends looking complete.
    function requireAssistant() {
        const existing = root.currentAssistant();
        if (existing) return existing;
        root.currentAssistantId = root.addMessage("assistant", "");
        const created = root.currentAssistant();
        // Outside a turn no result event will ever close this bubble, and text
        // in a closed bubble still renders -- a stuck spinner does worse.
        if (created && !root.busy) created.done = true;
        return created;
    }

    function appendAssistantText(text) {
        if (text.length === 0) return;
        const message = root.requireAssistant();
        if (!message) return;
        message.content += text;
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
        root.unseen = false;
        root.spawnPending = false;
        spawnWatchdog.stop();
        // Dropping the process drops the CLI-side conversation with it.
        root.discardStream = true;
        claudeProcess.running = false;
        root.manager.rememberTabs();
    }

    // ------------------------------------------------------------------
    // Sending
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
        // A reload can leave this looking mid-turn with no process behind it,
        // and every guard in sendMessage then reads as "already working".
        if (!claudeProcess.running) {
            root.busy = false;
            root.queuedMessages = [];
            root.spawnPending = false;
            spawnWatchdog.stop();
        }
        root.sendMessage("Continue where you left off.");
    }

    // Why a send went nowhere, for the IPC handler to report. Cheap enough to
    // keep: every one of these is a path that otherwise fails in silence.
    function sendBlockedReason() {
        if (!root.manager.available) return `no CLI at "${root.manager.cliPath}"`;
        if (root.busy && claudeProcess.running) return "busy with a live process — would queue";
        if (root.busy) return "busy with no process — stale, would self-heal";
        return "";
    }

    function sendMessage(text) {
        const trimmed = text.trim();
        if (trimmed.length === 0) return;
        if (!root.manager.available) {
            root.addMessage("interface", Translation.tr("Claude Code CLI not found. Set sidebar.claude.cliPath in the config."), true);
            return;
        }
        // Only a process that is up -- or one still on its way up -- can ever
        // drain the queue. Parking a message behind anything else loses it
        // silently, which is what a stuck `busy` after a reload did to the
        // offer to continue an interrupted turn.
        if (root.busy && (claudeProcess.running || root.spawnPending)) {
            root.queuedMessages = [...root.queuedMessages, trimmed];
            return;
        }
        // A process on its way out after an interrupt is a dead letterbox, and
        // a new one can't spawn until it's gone; park this for onExited.
        if (claudeProcess.running && root.discardStream) {
            root.queuedMessages = [...root.queuedMessages, trimmed];
            return;
        }
        // Falling through with a bubble still open would leave it spinning
        // forever once currentAssistantId moves on below.
        const stale = root.currentAssistant();
        if (stale && !stale.done) stale.done = true;

        root.addMessage("user", trimmed);
        root.busy = true;
        // The assistant bubble is created up front so the spinner has somewhere
        // to live while we wait for the first token.
        root.currentAssistantId = root.addMessage("assistant", "");

        if (!claudeProcess.running) {
            root.discardStream = false;
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
        root.discardStream = true;
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
        root.manager.rememberTabs();
    }

    // Closing the tab. The session stays resumable on disk, so this only has to
    // leave the CLI with nothing to wait on before the process goes.
    function shutDown() {
        if (root.pendingPermission) root.answerPermission("deny", null);
        if (root.pendingQuestion) root.dismissQuestion();
        root.spawnPending = false;
        spawnWatchdog.stop();
        checkpointTimer.stop();
        root.busy = false;
        root.discardStream = true;
        claudeProcess.running = false;
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
                assistant.content = Translation.tr("Claude Code failed to start — nothing runnable at `%1`. Looking the CLI up again; send that message once more.").arg(root.manager.cliPath);
            }
        }
        root.busy = false;
        root.currentAssistantId = "";
        // These were stacking up invisibly behind a turn that was never going
        // to finish; better to drop them than to replay them out of order.
        root.queuedMessages = [];
        root.manager.refreshCliPath();
    }

    Timer {
        id: spawnWatchdog
        interval: 10000 // Generous: a cold start still prints within a second.
        repeat: false
        onTriggered: root.failSpawn()
    }

    Timer { // Checkpoint mid-turn, since that is when a reload tends to hit
        id: checkpointTimer
        interval: 2000
        repeat: true
        running: root.busy
        onTriggered: root.manager.rememberTabs()
    }

    // ------------------------------------------------------------------
    // Tool call rendering
    // ------------------------------------------------------------------

    function addToolCall(id, name, input, contentOffset) {
        const message = root.currentAssistant();
        if (!message) return;
        // A thought that ran right up to this call belongs above it.
        root.flushThought();
        message.toolCalls = [...message.toolCalls, {
            id: id,
            name: name,
            icon: root.manager.toolIcons[name] ?? "build",
            detail: root.manager.toolDetail(name, input),
            // Kept so the chip can expand into a diff or a todo list.
            input: input ?? ({}),
            status: "running",
            // How far into the prose this happened, so the timeline can put the
            // chip back between the paragraphs it actually interrupted.
            contentOffset: contentOffset ?? message.content.length
        }];
    }

    function resolveToolCall(id, isError, output) {
        const message = root.currentAssistant();
        if (!message) return;
        const text = (output ?? "");
        message.toolCalls = message.toolCalls.map(call => call.id === id
            ? Object.assign({}, call, {
                status: isError ? "error" : "done",
                output: text.length > root.manager.maxOutputChars
                    ? text.substring(0, root.manager.maxOutputChars) + "\n…"
                    : text
            })
            : call);
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

    // ------------------------------------------------------------------
    // Stream handling
    // ------------------------------------------------------------------

    function handleEvent(event) {
        switch (event.type) {
        case "system":
            if (event.subtype === "init") {
                root.sessionId = event.session_id ?? root.sessionId;
                root.modelName = event.model ?? root.modelName;
                root.manager.rememberTabs();
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
                console.warn("[ClaudeSession] control request failed:", event.response.error);
            } else if (event.response?.response?.commands) {
                root.manager.slashCommands = event.response.response.commands;
            }
            break;

        case "rate_limit_event":
            // Account-wide, so every tab reports into the same place.
            root.manager.rateLimit = event.rate_limit_info ?? null;
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
        const assistant = root.requireAssistant();
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
                    root.manager.toolResultText(block.content));
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
        if (!event.is_error && event.subtype === "success") root.manager.signedOut = false;
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
                root.manager.checkAuth();
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
        if (!root.active) root.unseen = true;
        root.manager.rememberTabs();

        if (root.queuedMessages.length > 0) {
            const next = root.queuedMessages[0];
            root.queuedMessages = root.queuedMessages.slice(1);
            Qt.callLater(() => root.sendMessage(next));
        }
    }

    // ------------------------------------------------------------------
    // The process
    // ------------------------------------------------------------------

    // A killed process can take seconds to actually die, and until it does it
    // keeps streaming. Everything after the decision to kill it is output
    // nobody asked for -- rendering it makes the stop button look ignored.
    property bool discardStream: false

    Process {
        id: claudeProcess
        running: false
        workingDirectory: root.workingDirectory
        stdinEnabled: true
        command: [
            root.manager.cliPath,
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
            "--append-system-prompt", root.manager.options?.systemPrompt ?? "",
            ...(root.spawnModel.length > 0 ? ["--model", root.spawnModel] : []),
            ...(root.spawnEffort.length > 0 ? ["--effort", root.spawnEffort] : []),
            ...(root.spawnResumeId.length > 0 ? ["--resume", root.spawnResumeId] : [])
        ]

        stdout: SplitParser {
            onRead: data => {
                if (root.discardStream) return;
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
                if (data.trim().length > 0) console.warn("[ClaudeSession]", data);
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
            // Whatever ended this process, the transcript it leaves behind is
            // resumable; claim it so the next spawn continues the conversation.
            if (root.sessionId.length > 0) root.resumeSessionId = root.sessionId;
            root.sessionId = "";
            // A process that dies on its own is the other face of an expired
            // session: it never gets far enough to report a failed turn. A
            // deliberate kill exits nonzero too, and means nothing about auth.
            if (exitCode !== 0 && !root.discardStream) root.manager.checkAuth();
            root.discardStream = false;
            // Anything parked while the old process was dying can spawn now.
            if (!root.busy && root.queuedMessages.length > 0) {
                const next = root.queuedMessages[0];
                root.queuedMessages = root.queuedMessages.slice(1);
                Qt.callLater(() => root.sendMessage(next));
            }
        }
    }

    // ------------------------------------------------------------------
    // Surviving a shell reload
    // ------------------------------------------------------------------

    // Editing any QML file the shell has loaded makes Quickshell hot-reload,
    // which tears every tab down and kills its CLI with it — mid-turn, with no
    // result event and no error. Since the agent is regularly asked to edit
    // this very config, that is a routine event rather than an edge case.
    //
    // What is on screen is saved rather than the CLI's own transcript: the
    // transcript lags the stream by a beat, and a reload lands mid-turn, so
    // the transcript is missing precisely the reply that was interrupted.
    // A whole-file Write can outweigh the rest of the state file put together;
    // past this size the diff is not worth what every 2s checkpoint would pay.
    readonly property int maxStoredInputChars: 65536

    function serialize() {
        // After an interrupt the live id is gone but the session is still
        // resumable, so fall back to the id the next spawn will resume from.
        const id = root.sessionId.length > 0 ? root.sessionId : root.resumeSessionId;
        return {
            sessionId: id,
            workingDirectory: root.workingDirectory,
            model: root.selectedModel,
            effort: root.selectedEffort,
            permissionMode: root.permissionMode,
            unseen: root.unseen,
            contextTokens: root.contextTokens,
            contextLimit: root.contextLimit,
            messages: root.messageIDs.slice(-200).map(messageId => {
                const message = root.messageByID[messageId];
                return {
                    role: message.role,
                    content: message.content,
                    model: message.model,
                    done: message.done,
                    isError: message.isError,
                    interrupted: message.interrupted,
                    thinkingTokens: message.thinkingTokens,
                    // The expansions -- diffs, todo lists, command output --
                    // read straight from the input, so a chip stored without
                    // it can never open again. Only an outsized input is
                    // dropped, and only that one chip comes back inert.
                    toolCalls: message.toolCalls.map(call => {
                        const entry = {
                            id: call.id,
                            name: call.name,
                            icon: call.icon,
                            detail: call.detail,
                            status: call.status,
                            contentOffset: call.contentOffset ?? 0
                        };
                        if (JSON.stringify(call.input ?? ({})).length <= root.maxStoredInputChars) {
                            entry.input = call.input ?? ({});
                        }
                        if ((call.output ?? "").length > 0) entry.output = call.output;
                        return entry;
                    })
                };
            })
        };
    }

    function restore(entry) {
        // A rebuilt session is not mid-turn, whatever it was doing before. The
        // process that would have reported the turn finished died with the old
        // session, so nothing else is ever going to clear these.
        root.busy = false;
        root.currentAssistantId = "";
        root.queuedMessages = [];
        root.spawnPending = false;
        spawnWatchdog.stop();

        root.selectedModel = entry.model ?? "";
        root.selectedEffort = entry.effort ?? "";
        root.permissionMode = entry.permissionMode ?? "ask";
        root.unseen = entry.unseen ?? false;
        root.contextTokens = entry.contextTokens ?? 0;
        root.contextLimit = entry.contextLimit ?? 0;

        const id = entry.sessionId ?? "";
        if (id.length === 0) return;

        const stored = entry.messages ?? [];
        if (stored.length === 0) {
            // Nothing of our own saved, but the CLI's transcript may still
            // have the conversation.
            root.loadSession(id);
            return;
        }

        root.resumeSessionId = id;
        for (const item of stored) {
            const messageId = root.addMessage(item.role, item.content, item.isError);
            const message = root.messageByID[messageId];
            if (!message) continue;
            message.model = item.model ?? "";
            message.thinkingTokens = item.thinkingTokens ?? 0;
            message.toolCalls = (item.toolCalls ?? []).map(call =>
                call.status === "running" ? Object.assign({}, call, { status: "done" }) : call);
            message.done = true;
            // Survives a second reload, so the offer to resume doesn't vanish
            // just because the shell restarted again before it was taken up.
            message.interrupted = item.interrupted ?? false;
        }

        // A reply cut off by the reload should say so rather than just stop —
        // as a flag rather than appended prose, so the view can offer to resume
        // instead of leaving the user to retype the request.
        const last = root.messageByID[root.messageIDs[root.messageIDs.length - 1]];
        if (last && last.role === "assistant" && stored[stored.length - 1].done === false) {
            last.interrupted = true;
        }
    }
}
