import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The agent's task list, as a checklist rather than an opaque tool call.
 *
 * Each TodoWrite call replaces the whole list, so the newest chip is the
 * current state of the plan.
 */
ColumnLayout {
    id: root
    // [{ content, status: "pending" | "in_progress" | "completed", activeForm }]
    property var todos: []

    spacing: 1

    Repeater {
        model: root.todos

        RowLayout {
            id: todoRow
            required property var modelData
            readonly property bool completed: modelData.status === "completed"
            readonly property bool active: modelData.status === "in_progress"

            Layout.fillWidth: true
            Layout.leftMargin: 2
            spacing: 6

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.normal
                color: todoRow.completed ? Appearance.colors.colPrimary
                    : todoRow.active ? Appearance.m3colors.m3onSecondaryContainer
                    : Appearance.colors.colSubtext
                text: todoRow.completed ? "check_circle"
                    : todoRow.active ? "radio_button_checked"
                    : "radio_button_unchecked"
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: todoRow.active ? Font.Medium : Font.Normal
                // Finished items stay visible but stop asking for attention.
                font.strikeout: todoRow.completed
                color: todoRow.completed ? Appearance.colors.colSubtext
                    : todoRow.active ? Appearance.colors.colOnLayer2
                    : Appearance.colors.colSubtext
                text: (todoRow.active ? todoRow.modelData.activeForm : todoRow.modelData.content) ?? ""
            }
        }
    }
}
