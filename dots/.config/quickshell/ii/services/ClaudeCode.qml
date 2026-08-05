pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
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

    function sendMessage(text) {
        const trimmed = text.trim();
        if (trimmed.length === 0) return;
        if (!root.available) {
            root.addMessage("interface", Translation.tr("Claude Code CLI not found. Set sidebar.claude.cliPath in the config."), true);
            return;
        }
        if (root.busy) return;

        root.addMessage("user", trimmed);
        root.busy = true;
        // The assistant bubble is created up front so the spinner has somewhere
        // to live while we wait for the first token.
        root.currentAssistantId = root.addMessage("assistant", "");

        if (!claudeProcess.running) {
            root.spawnModel = root.selectedModel;
            claudeProcess.running = true;
        }
        claudeProcess.write(JSON.stringify({
            type: "user",
            message: {
                role: "user",
                content: [{ type: "text", text: trimmed }]
            }
        }) + "\n");
    }

    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = ({});
        root.currentAssistantId = "";
        root.sessionId = "";
        root.busy = false;
        root.contextTokens = 0;
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
        claudeProcess.running = false;
        root.busy = false;
        const current = root.messageByID[root.currentAssistantId];
        if (current) {
            current.done = true;
            if (current.content.length === 0) {
                current.content = Translation.tr("_Interrupted_");
            }
        }
        root.currentAssistantId = "";
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
        "Skill": "extension"
    })

    function toolDetail(name, input) {
        if (!input) return "";
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
        const collapsed = value.replace(/\s+/g, " ").trim();
        return collapsed.length > 120 ? collapsed.substring(0, 120) + "…" : collapsed;
    }

    function addToolCall(id, name, input) {
        const message = root.currentAssistant();
        if (!message) return;
        message.toolCalls = [...message.toolCalls, {
            id: id,
            name: name,
            icon: root.toolIcons[name] ?? "build",
            detail: root.toolDetail(name, input),
            status: "running"
        }];
    }

    function resolveToolCall(id, isError) {
        const message = root.currentAssistant();
        if (!message) return;
        message.toolCalls = message.toolCalls.map(call =>
            call.id === id ? Object.assign({}, call, { status: isError ? "error" : "done" }) : call);
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

        case "control_response":
            if (event.response?.subtype === "error") {
                console.warn("[ClaudeCode] control request failed:", event.response.error);
            }
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
            root.streamedText += chunk;
            root.appendAssistantText(chunk);
        }
    }

    function handleAssistantMessage(message) {
        if (!message) return;
        const assistant = root.currentAssistant();
        if (!assistant) return;

        if (message.model) assistant.model = message.model;
        root.updateContextTokens(message.usage);

        // Reconcile the streamed preview against the authoritative text.
        let finalText = "";
        for (const block of (message.content ?? [])) {
            if (block.type === "text") {
                finalText += block.text ?? "";
            } else if (block.type === "tool_use") {
                root.addToolCall(block.id, block.name, block.input);
            }
        }

        if (finalText.length > 0) {
            if (root.streamedText.length > 0 && assistant.content.endsWith(root.streamedText)) {
                // Swap the preview for the final text rather than duplicating it.
                assistant.content = assistant.content.slice(0, assistant.content.length - root.streamedText.length) + finalText;
            } else if (!assistant.content.endsWith(finalText)) {
                assistant.content += (assistant.content.length > 0 ? "\n\n" : "") + finalText;
            }
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
                root.resolveToolCall(block.tool_use_id, block.is_error ?? false);
            }
        }
    }

    function finishTurn(event) {
        root.updateContextLimit(event.modelUsage);
        const assistant = root.currentAssistant();
        if (assistant) {
            assistant.done = true;
            if (event.is_error || event.subtype !== "success") {
                assistant.isError = true;
                if (assistant.content.length === 0) {
                    assistant.content = event.result ?? Translation.tr("The request failed.");
                }
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
            // The sidebar has no UI for approving individual tool calls, and
            // the user opted into an agent that just gets on with it.
            "--permission-mode", "bypassPermissions",
            // Skip the user's MCP servers: they add seconds of startup and a
            // lot of tool-schema tokens that a desktop sidebar has no use for.
            "--strict-mcp-config",
            "--append-system-prompt", root.options?.systemPrompt ?? "",
            ...(root.spawnModel.length > 0 ? ["--model", root.spawnModel] : [])
        ]

        stdout: SplitParser {
            onRead: data => {
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
        }
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
                if (path.length > 0 && root.cliPath.length === 0) {
                    root.cliPath = path;
                }
            }
        }
    }

    Component.onCompleted: {
        const configured = (options?.cliPath ?? "").trim();
        if (configured.length > 0) root.cliPath = configured;
        root.selectedModel = options?.model ?? "";
    }
}
