import QtQuick

/**
 * One message in a Claude Code conversation.
 *
 * Deliberately kept close to services/ai/AiMessageData.qml so the rendering
 * code can stay familiar, with the agent-specific bits (tool calls, cost)
 * added on top.
 */
QtObject {
    property string role // "user" | "assistant" | "interface"
    property string content: ""
    property bool done: false
    property bool isError: false

    // [{ id, name, detail, status: "running" | "done" | "error" }]
    property var toolCalls: []

    property string model
}
