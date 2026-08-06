import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Claude asking the user something, with the options as buttons.
 *
 * Several questions can arrive in one call. They're shown one at a time behind
 * a tab per question rather than stacked, so a narrow column stays readable and
 * it's obvious how many are left. Any question can be answered with free text
 * instead of an option — that is what the CLI calls picking "Other".
 */
Rectangle {
    id: root
    // { requestId, questions, input }
    required property var request

    readonly property var questions: root.request?.questions ?? []
    readonly property bool tabbed: root.questions.length > 1
    property int currentIndex: 0

    // Both keyed by question index: chosen option labels, and typed text.
    property var selections: ({})
    property var customAnswers: ({})

    function chosenFor(index) {
        return root.selections[index] ?? [];
    }

    function isChosen(index, label) {
        return root.chosenFor(index).indexOf(label) >= 0;
    }

    function toggleOption(index, label, multiSelect) {
        const current = root.chosenFor(index).slice();
        const at = current.indexOf(label);
        let next;
        if (multiSelect) {
            if (at >= 0) current.splice(at, 1);
            else current.push(label);
            next = current;
        } else {
            // Tapping the chosen one again clears it.
            next = at >= 0 ? [] : [label];
        }
        const updated = Object.assign({}, root.selections);
        updated[index] = next;
        root.selections = updated;

        // Picking a single answer finishes that question, so move along.
        if (!multiSelect && next.length > 0) Qt.callLater(root.advance);
    }

    function setCustom(index, text) {
        const updated = Object.assign({}, root.customAnswers);
        updated[index] = text;
        root.customAnswers = updated;
    }

    // The CLI expects one string per question; several picks join with commas.
    function answerFor(index) {
        const custom = (root.customAnswers[index] ?? "").trim();
        const picked = root.chosenFor(index);
        return picked.concat(custom.length > 0 ? [custom] : []).join(", ");
    }

    readonly property int answeredCount: {
        let count = 0;
        for (let i = 0; i < root.questions.length; i++) {
            if (root.answerFor(i).length > 0) count++;
        }
        return count;
    }

    readonly property bool complete: root.questions.length > 0
        && root.answeredCount === root.questions.length

    function advance() {
        for (let i = root.currentIndex + 1; i < root.questions.length; i++) {
            if (root.answerFor(i).length === 0) {
                root.currentIndex = i;
                return;
            }
        }
    }

    function submit() {
        if (!root.complete) return;
        const answers = ({});
        const picks = ({});
        for (let i = 0; i < root.questions.length; i++) {
            const question = root.questions[i].question;
            answers[question] = root.answerFor(i);
            const custom = (root.customAnswers[i] ?? "").trim();
            picks[question] = root.chosenFor(i).concat(custom.length > 0 ? [custom] : []);
        }
        ClaudeCode.answerQuestion(answers, picks);
    }

    implicitHeight: layout.implicitHeight + 20
    radius: Appearance.rounding.small
    color: Appearance.colors.colSecondaryContainer
    clip: true

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    ColumnLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 10
        }
        spacing: 6

        SecondaryTabBar { // One tab per question
            id: tabBar
            Layout.fillWidth: true
            visible: root.tabbed
            currentIndex: root.currentIndex
            onCurrentIndexChanged: root.currentIndex = tabBar.currentIndex

            Repeater {
                model: root.questions

                SecondaryTabButton {
                    required property var modelData
                    required property int index
                    buttonText: (modelData.header ?? "").length > 0
                        ? modelData.header
                        : Translation.tr("Q%1").arg(index + 1)
                    // A tick marks the ones already dealt with.
                    buttonIcon: root.answerFor(index).length > 0 ? "check" : ""
                }
            }
        }

        Repeater {
            model: root.questions

            ColumnLayout {
                id: questionBlock
                required property var modelData
                required property int index
                readonly property bool multiSelect: questionBlock.modelData.multiSelect ?? false

                // Only the current question is on screen; ColumnLayout drops
                // hidden items, so the card shrinks to fit it.
                visible: questionBlock.index === root.currentIndex
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialSymbol {
                        visible: !root.tabbed
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.m3colors.m3onSecondaryContainer
                        text: "help"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSecondaryContainer
                        text: questionBlock.modelData.question ?? ""
                    }
                    StyledText {
                        visible: questionBlock.multiSelect
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("pick any")
                    }
                }

                Repeater {
                    model: questionBlock.modelData.options ?? []

                    RippleButton {
                        id: optionButton
                        required property var modelData
                        readonly property bool chosen: root.isChosen(questionBlock.index, optionButton.modelData.label)

                        Layout.fillWidth: true
                        implicitHeight: optionColumn.implicitHeight + 12
                        buttonRadius: Appearance.rounding.verysmall
                        toggled: optionButton.chosen
                        onClicked: root.toggleOption(questionBlock.index,
                            optionButton.modelData.label, questionBlock.multiSelect)

                        contentItem: RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 8
                                rightMargin: 8
                            }
                            spacing: 8

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.normal
                                color: optionButton.chosen ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                                text: questionBlock.multiSelect
                                    ? (optionButton.chosen ? "check_box" : "check_box_outline_blank")
                                    : (optionButton.chosen ? "radio_button_checked" : "radio_button_unchecked")
                            }

                            ColumnLayout {
                                id: optionColumn
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: optionButton.chosen ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
                                    text: optionButton.modelData.label ?? ""
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: optionButton.chosen ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                                    text: optionButton.modelData.description ?? ""
                                }
                            }
                        }
                    }
                }

                MaterialTextField { // "Other" — anything the options don't cover
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    placeholderText: Translation.tr("Something else…")
                    onTextChanged: root.setCustom(questionBlock.index, text)
                    onAccepted: root.complete ? root.submit() : root.advance()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6

            StyledText {
                visible: root.tabbed
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: Translation.tr("%1 of %2 answered").arg(root.answeredCount).arg(root.questions.length)
            }

            Item { Layout.fillWidth: true }

            RippleButton {
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                onClicked: ClaudeCode.dismissQuestion()

                contentItem: StyledText {
                    anchors.centerIn: parent
                    leftPadding: 12
                    rightPadding: 12
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Skip")
                }
            }

            RippleButton {
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                enabled: root.complete
                toggled: root.complete
                onClicked: root.submit()

                contentItem: StyledText {
                    anchors.centerIn: parent
                    leftPadding: 12
                    rightPadding: 12
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.complete ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                    text: Translation.tr("Answer")
                }
            }
        }
    }
}
