import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A question Claude asked, and what was picked, left in the transcript.
 *
 * Deliberately not a plain tool chip: the answer is a decision the user made
 * and needs to stand out later, so it keeps the question card's own colour and
 * shows the choices as filled pills.
 */
Rectangle {
    id: root
    // { name, detail, status, answers, input }
    required property var toolCall

    readonly property var questions: root.toolCall?.input?.questions ?? []
    readonly property var answers: root.toolCall?.answers ?? null
    // Restored history keeps the summary line but not the full input.
    readonly property bool detailOnly: root.questions.length === 0
    readonly property bool answered: {
        if (root.detailOnly) return (root.toolCall?.detail ?? "").length > 0;
        if (!root.answers) return false;
        for (const question of root.questions) {
            if ((root.answers[question.question] ?? "").length > 0) return true;
        }
        return false;
    }

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + 16
    radius: Appearance.rounding.small
    color: Appearance.colors.colSecondaryContainer

    ColumnLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 8
        }
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.normal
                color: root.answered ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                text: root.answered ? "task_alt" : "cancel"
            }
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
                text: root.answered ? Translation.tr("YOU ANSWERED") : Translation.tr("NOT ANSWERED")
            }
        }

        StyledText { // Restored history: the summary is all that survived
            Layout.fillWidth: true
            visible: root.detailOnly
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: Appearance.m3colors.m3onSecondaryContainer
            text: root.toolCall?.detail ?? ""
        }

        Repeater {
            model: root.detailOnly ? [] : root.questions

            ColumnLayout {
                id: block
                required property var modelData
                readonly property string answer: root.answers?.[block.modelData.question] ?? ""
                // The chosen labels are kept as a list alongside the joined
                // string, so a label with a comma in it still shows as one pill.
                readonly property var picks: root.toolCall?.picks?.[block.modelData.question]
                    ?? (block.answer.length > 0 ? block.answer.split(", ").filter(part => part.length > 0) : [])

                Layout.fillWidth: true
                spacing: 3

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    text: block.modelData.question ?? ""
                }

                FlowButtonGroup {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: block.picks

                        Rectangle {
                            required property string modelData
                            implicitWidth: pickText.implicitWidth + 20
                            implicitHeight: pickText.implicitHeight + 8
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colPrimary

                            StyledText {
                                id: pickText
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: Appearance.m3colors.m3onPrimary
                                text: parent.modelData
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: block.picks.length === 0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Skipped")
                }
            }
        }
    }
}
