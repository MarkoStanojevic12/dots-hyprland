import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One agent tool invocation: a compact row saying what it ran, which expands
 * into the detail worth seeing — a diff for edits, the list for TodoWrite.
 */
Rectangle {
    id: root
    required property var toolCall

    readonly property bool running: root.toolCall?.status === "running"
    readonly property bool errored: root.toolCall?.status === "error"
    readonly property var input: root.toolCall?.input ?? null
    readonly property string toolName: root.toolCall?.name ?? ""

    // An input can still be missing -- oversized ones are dropped from the
    // checkpoint -- and a chip without one has nothing to open.
    readonly property bool expandable: root.isEdit || root.isWrite || root.isBash
    readonly property bool isEdit: root.toolName === "Edit" && (root.input?.old_string !== undefined)
    readonly property bool isWrite: root.toolName === "Write" && (root.input?.content !== undefined)
    readonly property bool isTodo: root.toolName === "TodoWrite" && Array.isArray(root.input?.todos)
    readonly property bool isBash: root.toolName === "Bash" && (root.input?.command !== undefined)

    // Edits open on their own — the diff is the point of the chip. Bash stays
    // shut until asked. Clicking breaks the binding, so a manual toggle sticks.
    property bool expanded: root.isEdit || root.isWrite

    // The find-in-chat match navigated to is inside this chip.
    property bool searchHit: false

    Layout.fillWidth: true
    implicitHeight: contentColumn.implicitHeight + 8 * 2
    radius: Appearance.rounding.small
    color: root.errored ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2
    border.width: root.searchHit ? 1 : 0
    border.color: Appearance.colors.colTertiary
    clip: true

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.expandable
        cursorShape: root.expandable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.expanded = !root.expanded
    }

    ColumnLayout {
        id: contentColumn
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 8
            rightMargin: 8
            topMargin: 8
        }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: root.errored ? "error" : (root.toolCall?.icon ?? "build")
                iconSize: Appearance.font.pixelSize.large
                color: root.errored ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colSubtext
            }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: root.errored ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnLayer2
                text: root.toolName
            }

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                visible: text.length > 0
                text: root.toolCall?.detail ?? ""
            }

            MaterialSymbol {
                visible: root.expandable
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
                text: root.expanded ? "expand_less" : "expand_more"
            }

            // A quiet pulse while the tool is running; nothing once it's done,
            // so finished calls fade into the background instead of competing.
            Rectangle {
                implicitWidth: 6
                implicitHeight: 6
                radius: 3
                visible: root.running
                color: Appearance.colors.colPrimary

                SequentialAnimation on opacity {
                    running: root.running
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.25; duration: 600; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.25; to: 1; duration: 600; easing.type: Easing.InOutQuad }
                }
            }
        }

        Loader { // Todo list — always open, since that is the whole point of it
            Layout.fillWidth: true
            active: root.isTodo
            visible: active
            sourceComponent: TodoListView {
                todos: root.input?.todos ?? []
            }
        }

        Loader { // What the command was and what it printed
            Layout.fillWidth: true
            active: root.expanded && root.isBash
            visible: active
            sourceComponent: CommandOutputView {
                command: root.input?.command ?? ""
                output: root.toolCall?.output ?? ""
                errored: root.errored
                running: root.running
            }
        }

        Loader { // Diff for edits
            Layout.fillWidth: true
            active: root.expanded && (root.isEdit || root.isWrite)
            visible: active
            sourceComponent: DiffView {
                filePath: root.input?.file_path ?? ""
                oldText: root.isEdit ? (root.input?.old_string ?? "") : ""
                newText: root.isEdit ? (root.input?.new_string ?? "") : (root.input?.content ?? "")
            }
        }
    }
}
