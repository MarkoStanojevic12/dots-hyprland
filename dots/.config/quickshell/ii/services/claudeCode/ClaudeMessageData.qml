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

    // [{ id, name, icon, detail, input, status: "running" | "done" | "error",
    //    contentOffset }]
    // contentOffset is how far into `content` the entry happened, which is what
    // lets the view lay tool calls and prose out as one chronological timeline.
    // A name of "__thought" marks a thinking pause rather than a real tool.
    property var toolCalls: []

    // Local paths of the images pasted into the composer with this message.
    property var attachments: []

    // The thinking text never reaches the client, only an estimate of its size.
    property int thinkingTokens: 0

    // A turn the shell reload cut off mid-flight. The session is still resumable,
    // so the view offers to pick it up rather than just saying it stopped.
    property bool interrupted: false

    property string model
}
