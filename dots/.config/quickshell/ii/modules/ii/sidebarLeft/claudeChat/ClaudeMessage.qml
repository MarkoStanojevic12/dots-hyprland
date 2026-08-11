import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.aiChat
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell

/**
 * One turn in the Claude tab.
 *
 * Markdown/code/think rendering is delegated to the same block components the
 * Intelligence tab uses, so both tabs look like one product.
 */
Item {
    id: root
    required property var messageData

    readonly property bool isUser: root.messageData?.role === "user"
    readonly property bool isInterface: root.messageData?.role === "interface"
    property list<var> messageBlocks: StringUtils.splitMarkdownBlocks(root.messageData?.content ?? "")

    // The turn as one chronological list — prose blocks and the tool calls and
    // thinking pauses that happened between them, in the order they happened.
    // Every entry carries where in the prose it landed, so the content is sliced
    // at those points and the markdown split per slice.
    //
    // A restored transcript has no offsets to work from; those entries default
    // to 0 and stack at the top, which is where they used to sit anyway.
    readonly property var timeline: {
        const content = root.messageData?.content ?? "";
        const entries = root.messageData?.toolCalls ?? [];
        const items = [];
        let cursor = 0;

        const pushProse = (text) => {
            if (text.length === 0) return;
            for (const block of StringUtils.splitMarkdownBlocks(text)) items.push(block);
        };

        for (const entry of entries) {
            // Offsets only ever move forward: a stale one from a mid-turn
            // rewrite must not drag a later chip above an earlier one.
            const at = Math.max(cursor, Math.min(entry.contentOffset ?? 0, content.length));
            pushProse(content.slice(cursor, at));
            cursor = at;
            items.push({
                type: entry.name === "__thought" ? "thought"
                    : entry.name === "AskUserQuestion" ? "question"
                    : "tool",
                call: entry
            });
        }
        pushProse(content.slice(cursor));

        // Steps that sit next to each other get their rails joined up; prose in
        // between breaks the thread, which is the honest picture of what ran.
        const isStep = (item) => item !== undefined
            && (item.type === "tool" || item.type === "thought" || item.type === "question");
        for (let i = 0; i < items.length; i++) {
            if (!isStep(items[i])) continue;
            items[i].linkUp = isStep(items[i - 1]);
            items[i].linkDown = isStep(items[i + 1]);
        }
        return items;
    }

    // Air between timeline entries, and what the rail has to span to reach the
    // next one. One number so the two can't drift apart.
    readonly property real timelineSpacing: 9

    // Each speaker gets one of the palette's own accents rather than plain
    // white, so the two sides of the conversation are told apart at a glance
    // and the colours re-derive themselves whenever the theme changes.
    readonly property color speakerColor: root.messageData?.isError ? Appearance.colors.colError
        : root.isUser ? Appearance.colors.colPrimary
        : root.isInterface ? Appearance.colors.colSubtext
        : Appearance.colors.colTertiary

    // Dropped in by the user; without it the generic glyph simply stays.
    readonly property string avatarPath: `file://${Directories.shellConfig}/avatar.jpg`

    implicitHeight: contentColumn.implicitHeight
    width: parent?.width ?? implicitWidth

    ColumnLayout {
        id: contentColumn
        anchors {
            left: parent.left
            right: parent.right
        }
        spacing: root.timelineSpacing

        RowLayout { // Who's talking
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 8

            Item {
                id: speaker
                readonly property bool photoShown: root.isUser && avatar.status === Image.Ready
                implicitWidth: 22
                implicitHeight: 22

                StyledImage {
                    id: avatar
                    anchors.fill: parent
                    source: root.isUser ? root.avatarPath : ""
                    fillMode: Image.PreserveAspectCrop
                    visible: false // Only ever seen through the mask below
                }

                MultiEffect {
                    anchors.fill: avatar
                    source: avatar
                    visible: speaker.photoShown
                    maskEnabled: true
                    maskSource: avatarMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                    maskSpreadAtMax: 1
                }

                Rectangle {
                    id: avatarMask
                    width: avatar.width
                    height: avatar.height
                    radius: width / 2
                    color: "black"
                    antialiasing: true
                    layer.enabled: true
                    visible: false
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !speaker.photoShown
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.speakerColor
                    text: root.isUser ? "person" : root.isInterface ? "settings" : "neurology"
                }
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                // System usernames are typically lowercase; a speaker label
                // reads better capitalised.
                font.capitalization: Font.Capitalize
                color: root.speakerColor
                text: root.isUser ? (SystemInfo.username || Translation.tr("You"))
                    : root.isInterface ? Translation.tr("Interface")
                    : "Claude"
            }

            StyledText { // Model, once the turn has actually started
                visible: !root.isUser && !root.isInterface && (root.messageData?.model ?? "").length > 0
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: root.messageData?.model ?? ""
            }
        }

        Repeater { // The turn as it happened: prose, tool calls and thinking
            model: ScriptModel {
                values: root.timeline
            }
            delegate: DelegateChooser {
                role: "type"

                DelegateChoice {
                    roleValue: "thought"
                    RowLayout {
                        id: thoughtRow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        spacing: 6

                        TimelineRail {
                            linkUp: thoughtRow.modelData.linkUp ?? false
                            linkDown: thoughtRow.modelData.linkDown ?? false
                            gap: root.timelineSpacing
                            muted: true
                        }
                        ThoughtChip {
                            Layout.fillWidth: true
                            toolCall: thoughtRow.modelData.call
                        }
                    }
                }
                DelegateChoice { // A decision the user made, not a tool run
                    roleValue: "question"
                    RowLayout {
                        id: questionRow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        spacing: 6

                        TimelineRail {
                            linkUp: questionRow.modelData.linkUp ?? false
                            linkDown: questionRow.modelData.linkDown ?? false
                            gap: root.timelineSpacing
                        }
                        AnsweredQuestionCard {
                            Layout.fillWidth: true
                            toolCall: questionRow.modelData.call
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "tool"
                    RowLayout {
                        id: toolRow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        spacing: 6

                        TimelineRail {
                            linkUp: toolRow.modelData.linkUp ?? false
                            linkDown: toolRow.modelData.linkDown ?? false
                            gap: root.timelineSpacing
                            running: toolRow.modelData.call?.status === "running"
                            errored: toolRow.modelData.call?.status === "error"
                        }
                        ToolCallChip {
                            Layout.fillWidth: true
                            toolCall: toolRow.modelData.call
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "code"
                    MessageCodeBlock {
                        enableMouseSelection: true
                        segmentContent: modelData.content
                        segmentLang: modelData.lang
                        messageData: root.messageData
                    }
                }
                DelegateChoice {
                    roleValue: "think"
                    MessageThinkBlock {
                        enableMouseSelection: true
                        segmentContent: modelData.content
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        completed: modelData.completed ?? false
                    }
                }
                DelegateChoice {
                    roleValue: "text"
                    MessageTextBlock {
                        enableMouseSelection: true
                        bodyFontSize: Config.options.sidebar.claude.fontSize
                        // Paths Claude mentions become links to the file itself.
                        segmentContent: ClaudeCode.linkifyPaths(modelData.content)
                        linkColor: Appearance.colors.colPrimary
                        linkHandler: link => {
                            ClaudeCode.openFileReference(link);
                            GlobalStates.sidebarLeftOpen = false;
                        }
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        forceDisableChunkSplitting: root.messageData?.content.includes("```") ?? true
                    }
                }
            }
        }

        RowLayout { // A turn the reload cut off, and the offer to pick it up
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 8
            visible: root.messageData?.interrupted ?? false

            MaterialSymbol {
                text: "link_off"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Interrupted — the shell reloaded.")
            }

            RippleButton {
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                toggled: true
                // Nothing can be sent mid-turn anyway, and a queued duplicate is
                // the one outcome this button should never produce.
                enabled: !ClaudeCode.busy
                onClicked: ClaudeCode.continueInterrupted(root.messageData)

                contentItem: StyledText {
                    anchors.centerIn: parent
                    leftPadding: 12
                    rightPadding: 12
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onPrimary
                    text: Translation.tr("Continue")
                }
            }
        }

        Item { // Trails the output for the whole turn — a long tool run in the
               // middle of a reply should never look like it already finished.
            Layout.fillWidth: true
            implicitHeight: loadingIndicatorLoader.shown ? loadingIndicatorLoader.implicitHeight : 0
            visible: implicitHeight > 0

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            FadeLoader {
                id: loadingIndicatorLoader
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                shown: !(root.messageData?.done ?? true)
                sourceComponent: RowLayout {
                    spacing: 8

                    MaterialLoadingIndicator {
                        implicitSize: 28
                        loading: true
                    }
                    StyledText {
                        // The thinking text itself is never sent to clients, so
                        // its size is the only thing there is to report — and it
                        // is only worth saying while thinking is all that has
                        // happened. Once there is prose, the spinner says enough.
                        visible: root.messageBlocks.length < 1 && (root.messageData?.thinkingTokens ?? 0) > 0
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Thinking… ~%1 tokens").arg(root.messageData?.thinkingTokens ?? 0)
                    }
                }
            }
        }
    }
}
