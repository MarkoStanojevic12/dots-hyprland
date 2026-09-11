import QtQuick
import QtQuick.Window
import QtWebEngine

/**
 * Preview window for a code block from the Claude sidebar, run by the Qt 6
 * qml runtime (Quickshell itself can't host WebEngine).
 * Arguments after "--": <html|qml> <file>
 */
Window {
    id: root
    readonly property var args: Qt.application.arguments
    readonly property int split: root.args.indexOf("--")
    readonly property string kind: root.split >= 0 ? (root.args[root.split + 1] ?? "") : ""
    readonly property string file: root.split >= 0 ? (root.args[root.split + 2] ?? "") : ""

    title: "Claude preview"
    width: 960
    height: 720
    visible: true
    color: "white"

    Shortcut {
        sequences: ["Escape", "Ctrl+W", "Ctrl+Q"]
        onActivated: Qt.quit()
    }

    WebEngineView {
        anchors.fill: parent
        visible: root.kind === "html"
        url: root.kind === "html" ? `file://${root.file}` : ""
    }

    Loader {
        id: qmlLoader
        anchors.fill: parent
        active: root.kind === "qml"
        source: root.kind === "qml" ? `file://${root.file}` : ""
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - 40
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        color: "#b3261e"
        visible: qmlLoader.status === Loader.Error || (root.kind !== "html" && root.kind !== "qml")
        text: root.kind === "qml"
            ? "The QML failed to load. Run it from a terminal to see the error:\n" + `qml6 ${root.file}`
            : `Nothing to preview for "${root.kind}"`
    }
}
