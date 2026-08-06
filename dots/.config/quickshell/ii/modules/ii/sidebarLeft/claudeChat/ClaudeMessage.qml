import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.aiChat
import QtQuick
import QtQuick.Layouts
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

    implicitHeight: contentColumn.implicitHeight
    width: parent?.width ?? implicitWidth

    ColumnLayout {
        id: contentColumn
        anchors {
            left: parent.left
            right: parent.right
        }
        spacing: 4

        RowLayout { // Who's talking
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 8

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                color: root.messageData?.isError ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSecondaryContainer
                text: root.isUser ? "person" : root.isInterface ? "settings" : "neurology"
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3onSecondaryContainer
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

        ColumnLayout { // Tool calls, above the prose so a running tool stays visible
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 3
            visible: repeater.count > 0

            Repeater {
                id: repeater
                model: ScriptModel {
                    values: root.messageData?.toolCalls ?? []
                }
                delegate: DelegateChooser {
                    role: "name"

                    DelegateChoice { // A decision the user made, not a tool run
                        roleValue: "AskUserQuestion"
                        AnsweredQuestionCard {
                            required property var modelData
                            toolCall: modelData
                        }
                    }
                    DelegateChoice {
                        ToolCallChip {
                            required property var modelData
                            toolCall: modelData
                        }
                    }
                }
            }
        }

        Item { // Spinner until the first token lands
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
                shown: root.messageBlocks.length < 1 && !(root.messageData?.done ?? true)
                sourceComponent: RowLayout {
                    spacing: 8

                    MaterialLoadingIndicator {
                        implicitSize: 28
                        loading: true
                    }
                    StyledText {
                        // The thinking text itself is never sent to clients,
                        // so its size is the only thing there is to report.
                        visible: (root.messageData?.thinkingTokens ?? 0) > 0
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Thinking… ~%1 tokens").arg(root.messageData?.thinkingTokens ?? 0)
                    }
                }
            }
        }

        Repeater { // Message body
            model: ScriptModel {
                values: root.messageBlocks
            }
            delegate: DelegateChooser {
                role: "type"

                DelegateChoice {
                    roleValue: "code"
                    MessageCodeBlock {
                        segmentContent: modelData.content
                        segmentLang: modelData.lang
                        messageData: root.messageData
                    }
                }
                DelegateChoice {
                    roleValue: "think"
                    MessageThinkBlock {
                        segmentContent: modelData.content
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        completed: modelData.completed ?? false
                    }
                }
                DelegateChoice {
                    roleValue: "text"
                    MessageTextBlock {
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
    }
}
