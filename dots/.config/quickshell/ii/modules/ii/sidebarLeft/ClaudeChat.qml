import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.claudeChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

/**
 * Claude tab: a chat surface over the Claude Code CLI running on the user's
 * subscription. Sits alongside the existing Intelligence/Translator tabs
 * rather than replacing any of them.
 */
Item {
    id: root
    property real padding: 4
    property var inputField: messageInputField
    property bool modelPickerShown: false

    onFocusChanged: focus => {
        if (focus) root.inputField.forceActiveFocus();
    }

    Keys.onPressed: event => {
        messageInputField.forceActiveFocus();
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            ClaudeCode.clearMessages();
            event.accepted = true;
        }
    }

    function send() {
        const text = messageInputField.text;
        if (text.trim().length === 0) return;
        messageInputField.clear();
        ClaudeCode.sendMessage(text);
        messageListView.positionViewAtEnd();
    }

    Connections {
        target: ClaudeCode
        function onMessageAppended() {
            Qt.callLater(messageListView.positionViewAtEnd);
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        Item { // Messages
            Layout.fillWidth: true
            Layout.fillHeight: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: root.width
                    height: root.height
                    radius: Appearance.rounding.small
                }
            }

            StyledListView {
                id: messageListView
                anchors.fill: parent
                spacing: 14
                popin: false
                add: null // Function calls during streaming make this janky

                touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                // Follow the response only while the user is already at the
                // bottom, so scrolling back to read doesn't yank them forward.
                property bool following: true
                onContentYChanged: following = atYEnd
                Connections {
                    target: ClaudeCode
                    function onBusyChanged() {
                        if (ClaudeCode.busy) messageListView.following = true;
                    }
                }
                onContentHeightChanged: if (following) Qt.callLater(positionViewAtEnd)

                model: ScriptModel {
                    values: ClaudeCode.messageIDs
                }
                delegate: ClaudeMessage {
                    required property var modelData
                    messageData: ClaudeCode.messageByID[modelData]
                }
            }

            PagePlaceholder {
                shown: ClaudeCode.messageIDs.length === 0
                icon: ClaudeCode.available ? "neurology" : "sync_problem"
                title: ClaudeCode.available ? "Claude" : Translation.tr("Claude Code not found")
                description: ClaudeCode.available
                    ? Translation.tr("Runs on your Claude subscription\nWorking directory: %1\nCtrl+Shift+O to clear").arg(ClaudeCode.workingDirectory)
                    : Translation.tr("Install the Claude Code CLI, or set\nsidebar.claude.cliPath in the config")
                shape: MaterialShape.Shape.Cookie9Sided
            }

            ScrollToBottomButton {
                target: messageListView
            }
        }

        Rectangle { // Input area
            id: inputWrapper
            Layout.fillWidth: true
            radius: Appearance.rounding.normal - root.padding
            color: Appearance.colors.colLayer2
            implicitHeight: inputColumn.implicitHeight + 5 * 2
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            ColumnLayout {
                id: inputColumn
                anchors {
                    fill: parent
                    margins: 5
                }
                spacing: 2

                Revealer { // Model picker
                    vertical: true
                    reveal: root.modelPickerShown

                    FlowButtonGroup {
                        width: inputColumn.width
                        spacing: 4

                        Repeater {
                            model: ClaudeCode.availableModels

                            SelectionGroupButton {
                                required property var modelData
                                leftmost: true
                                rightmost: true
                                verticalPadding: 5
                                buttonText: modelData.name
                                toggled: ClaudeCode.selectedModel === modelData.alias
                                // Switching mid-turn would land halfway through
                                // a response; wait for it to finish.
                                enabled: !ClaudeCode.busy
                                onClicked: {
                                    ClaudeCode.setModel(modelData.alias);
                                    root.modelPickerShown = false;
                                }

                                StyledToolTip {
                                    text: modelData.description
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(root.height * 2 / 5, messageInputField.height)
                        clip: true
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                        StyledTextArea {
                            id: messageInputField
                            anchors.fill: parent
                            wrapMode: TextArea.Wrap
                            padding: 8
                            background: null
                            color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                            placeholderText: ClaudeCode.busy ? Translation.tr("Claude is working…") : Translation.tr("Ask Claude…")

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                                    if (event.modifiers & Qt.ShiftModifier) {
                                        messageInputField.insert(messageInputField.cursorPosition, "\n");
                                    } else {
                                        root.send();
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape && ClaudeCode.busy) {
                                    ClaudeCode.interrupt();
                                    event.accepted = true;
                                }
                            }
                        }
                    }

                    RippleButton { // Send, or stop while a turn is running
                        id: sendButton
                        Layout.alignment: Qt.AlignBottom
                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.small
                        enabled: ClaudeCode.busy || (messageInputField.text.trim().length > 0 && ClaudeCode.available)
                        toggled: enabled

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (ClaudeCode.busy) ClaudeCode.interrupt();
                                else root.send();
                            }
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: 22
                            fill: ClaudeCode.busy ? 1 : 0
                            color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                            text: ClaudeCode.busy ? "stop_circle" : "arrow_upward"
                        }
                    }
                }

                RowLayout { // Session status
                    Layout.fillWidth: true
                    spacing: 4

                    RippleButton { // Model
                        id: modelButton
                        implicitHeight: 28
                        implicitWidth: modelButtonRow.implicitWidth + 16
                        buttonRadius: Appearance.rounding.full
                        toggled: root.modelPickerShown
                        onClicked: root.modelPickerShown = !root.modelPickerShown

                        contentItem: RowLayout {
                            id: modelButtonRow
                            anchors.centerIn: parent
                            spacing: 2

                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: modelButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
                                text: ClaudeCode.selectedModelName
                            }
                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.normal
                                color: modelButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                                text: root.modelPickerShown ? "expand_less" : "expand_more"
                            }
                        }

                        StyledToolTip {
                            text: ClaudeCode.modelName.length > 0
                                ? Translation.tr("Model: %1").arg(ClaudeCode.modelName)
                                : Translation.tr("Choose a model")
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideLeft
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: ClaudeCode.workingDirectory
                    }

                    Item { // Context window usage
                        id: contextIndicator
                        property bool hovered: contextMouseArea.containsMouse
                        implicitWidth: 24
                        implicitHeight: 24
                        opacity: ClaudeCode.contextTokens > 0 ? 1 : 0

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        CircularProgress {
                            anchors.centerIn: parent
                            implicitSize: 20
                            lineWidth: 3
                            value: ClaudeCode.contextFraction
                            // Turn warm once the window is nearly full, since
                            // that is when compaction starts eating the history.
                            colPrimary: ClaudeCode.contextFraction > 0.85
                                ? Appearance.m3colors.m3error
                                : Appearance.colors.colOnLayer2
                            colSecondary: Appearance.colors.colLayer2Hover
                        }

                        MouseArea {
                            id: contextMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        StyledToolTip {
                            text: Translation.tr("Context: %1 / %2 (%3%)")
                                .arg(ClaudeCode.formatTokens(ClaudeCode.contextTokens))
                                .arg(ClaudeCode.formatTokens(ClaudeCode.effectiveContextLimit))
                                .arg(Math.round(ClaudeCode.contextFraction * 100))
                        }
                    }

                    RippleButton {
                        implicitWidth: 28
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.full
                        enabled: ClaudeCode.messageIDs.length > 0 && !ClaudeCode.busy
                        onClicked: ClaudeCode.clearMessages()

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.large
                            color: parent.enabled ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnLayer2Disabled
                            text: "delete_sweep"
                        }

                        StyledToolTip {
                            text: Translation.tr("New conversation (Ctrl+Shift+O)")
                        }
                    }
                }
            }
        }
    }
}
