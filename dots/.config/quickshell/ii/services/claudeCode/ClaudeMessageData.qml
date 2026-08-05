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

    // [{ id, name, icon, detail, input, status: "running" | "done" | "error" }]
    property var toolCalls: []

    // The thinking text never reaches the client, only an estimate of its size.
    property int thinkingTokens: 0

    property string model
}
