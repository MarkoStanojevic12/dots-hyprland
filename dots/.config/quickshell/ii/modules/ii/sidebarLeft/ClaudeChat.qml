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
    property bool historyShown: false

    property bool directoryPickerShown: false

    // Projects, project knowledge and claude.ai chat history have no public API
    // and are not reachable from the CLI this tab drives, so the way to them is
    // simply to open the web app.
    readonly property string claudeWebUrl: "https://claude.ai/cowork/projects"

    // Slash commands are offered only while the whole message is still just
    // the command being typed, so a "/" mid-sentence doesn't trigger them.
    readonly property var slashSuggestions: {
        const text = messageInputField.text;
        if (!text.startsWith("/") || text.includes("\n") || text.includes(" ")) return [];
        const query = text.slice(1).toLowerCase();
        return (ClaudeCode.slashCommands ?? [])
            .filter(command => command.name.toLowerCase().includes(query))
            .slice(0, 40);
    }

    function applySlashCommand(command) {
        messageInputField.text = `/${command.name} `;
        messageInputField.cursorPosition = messageInputField.text.length;
        messageInputField.forceActiveFocus();
    }

    function toggleHistory() {
        root.historyShown = !root.historyShown;
        if (root.historyShown) ClaudeCode.refreshSessions();
    }

    function toggleDirectoryPicker() {
        root.directoryPickerShown = !root.directoryPickerShown;
        if (root.directoryPickerShown) {
            ClaudeCode.directoryError = "";
            ClaudeCode.refreshDirectories();
            directoryInput.text = ClaudeCode.workingDirectory;
            directoryInput.forceActiveFocus();
        }
    }

    // Clearing leaves the composer empty and ready, so drop focus straight back
    // into it — otherwise the click leaves focus on the button.
    function startNewConversation() {
        ClaudeCode.clearMessages();
        root.historyShown = false;
        messageInputField.forceActiveFocus();
    }

    onFocusChanged: focus => {
        if (focus) root.inputField.forceActiveFocus();
    }

    Keys.onPressed: event => {
        messageInputField.forceActiveFocus();
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            root.startNewConversation();
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
        id: mainColumn
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        RowLayout { // Header
            Layout.fillWidth: true
            spacing: root.padding

            RippleButton { // Which conversation this is, and the way into the rest
                id: historyButton
                Layout.fillWidth: true
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                toggled: root.historyShown
                onClicked: root.toggleHistory()

                contentItem: RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 8
                        rightMargin: 6
                    }
                    spacing: 6

                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.larger
                        color: historyButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                        text: "history"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: historyButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                        text: ClaudeCode.conversationTitle.length > 0
                            ? ClaudeCode.conversationTitle
                            : Translation.tr("New conversation")
                    }
                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.normal
                        color: historyButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                        text: root.historyShown ? "expand_less" : "expand_more"
                    }
                }

                StyledToolTip {
                    text: Translation.tr("Past conversations in %1").arg(ClaudeCode.workingDirectory)
                }
            }

            RippleButton { // Start over
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                enabled: ClaudeCode.messageIDs.length > 0 && !ClaudeCode.busy
                onClicked: root.startNewConversation()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    color: parent.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer1Inactive
                    text: "add_comment"
                }

                StyledToolTip {
                    text: Translation.tr("New conversation (Ctrl+Shift+O)")
                }
            }

            RippleButton { // claude.ai, for what the CLI has no access to
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                onClicked: Quickshell.execDetached(["xdg-open", root.claudeWebUrl])

                contentItem: CustomIcon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    source: "claude-symbolic"
                    colorize: true
                    color: Appearance.colors.colOnLayer1
                }

                StyledToolTip {
                    text: Translation.tr("Open claude.ai")
                }
            }
        }

        Revealer { // History list
            vertical: true
            reveal: root.historyShown

            Rectangle {
                width: mainColumn.width
                implicitHeight: Math.min(
                    Math.max(historyList.contentHeight, emptyHistoryLabel.implicitHeight) + 8,
                    root.height * 0.5)
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                StyledListView {
                    id: historyList
                    anchors {
                        fill: parent
                        margins: 4
                    }
                    clip: true
                    spacing: 2
                    model: ScriptModel {
                        values: ClaudeCode.sessions
                    }
                    delegate: SessionListItem {
                        required property var modelData
                        width: historyList.width
                        session: modelData
                        current: ClaudeCode.resumeSessionId === modelData.id
                        onClicked: {
                            ClaudeCode.loadSession(modelData.id);
                            root.historyShown = false;
                        }
                    }
                }

                StyledText {
                    id: emptyHistoryLabel
                    anchors.centerIn: parent
                    visible: ClaudeCode.sessions.length === 0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: ClaudeCode.sessionsLoading
                        ? Translation.tr("Looking for past conversations…")
                        : Translation.tr("No past conversations here yet")
                }
            }
        }

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

        Loader { // Claude asking something, answered by clicking
            Layout.fillWidth: true
            active: ClaudeCode.pendingQuestion !== null
            visible: active
            sourceComponent: QuestionCard {
                request: ClaudeCode.pendingQuestion
            }
        }

        Loader { // Permission request, right above the input where the answer goes
            Layout.fillWidth: true
            active: ClaudeCode.pendingPermission !== null
            visible: active
            sourceComponent: PermissionRequestCard {
                request: ClaudeCode.pendingPermission
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

                Repeater { // Messages waiting for the current turn to finish
                    model: ScriptModel {
                        values: ClaudeCode.queuedMessages
                    }

                    delegate: Rectangle {
                        id: queuedItem
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.bottomMargin: 2
                        implicitHeight: queuedRow.implicitHeight + 10
                        radius: Appearance.rounding.verysmall
                        color: Appearance.colors.colLayer1

                        RowLayout {
                            id: queuedRow
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 8
                                rightMargin: 4
                            }
                            spacing: 6

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                                text: "schedule_send"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: queuedItem.modelData
                            }
                            RippleButton {
                                implicitWidth: 22
                                implicitHeight: 22
                                buttonRadius: Appearance.rounding.full
                                onClicked: ClaudeCode.unqueueMessage(queuedItem.index)

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
                                    text: "close"
                                }
                            }
                        }
                    }
                }

                Revealer { // Slash commands
                    vertical: true
                    reveal: root.slashSuggestions.length > 0

                    Rectangle {
                        width: inputColumn.width
                        implicitHeight: Math.min(slashList.contentHeight + 8, root.height * 0.35)
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1

                        StyledListView {
                            id: slashList
                            anchors {
                                fill: parent
                                margins: 4
                            }
                            clip: true
                            spacing: 1
                            model: ScriptModel {
                                values: root.slashSuggestions
                            }
                            delegate: SlashCommandItem {
                                required property var modelData
                                width: slashList.width
                                command: modelData
                                onClicked: root.applySlashCommand(modelData)
                            }
                        }
                    }
                }

                Revealer { // Working directory picker
                    vertical: true
                    reveal: root.directoryPickerShown

                    ColumnLayout {
                        width: inputColumn.width
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            MaterialTextField {
                                id: directoryInput
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                placeholderText: Translation.tr("Path to a directory…")
                                onAccepted: ClaudeCode.setWorkingDirectory(directoryInput.text)
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape) {
                                        root.directoryPickerShown = false;
                                        event.accepted = true;
                                    }
                                }
                            }

                            RippleButton {
                                implicitWidth: 32
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.small
                                enabled: directoryInput.text.trim().length > 0 && !ClaudeCode.busy
                                onClicked: ClaudeCode.setWorkingDirectory(directoryInput.text)

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: parent.enabled ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnLayer2Disabled
                                    text: "subdirectory_arrow_left"
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            visible: ClaudeCode.directoryError.length > 0
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.m3colors.m3error
                            text: ClaudeCode.directoryError
                        }

                        Rectangle { // Somewhere Claude has already been used
                            Layout.fillWidth: true
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer1
                            implicitHeight: Math.min(directoryList.contentHeight + 8, root.height * 0.3)
                            visible: ClaudeCode.knownDirectories.length > 0

                            StyledListView {
                                id: directoryList
                                anchors {
                                    fill: parent
                                    margins: 4
                                }
                                clip: true
                                spacing: 2
                                model: ScriptModel {
                                    values: ClaudeCode.knownDirectories
                                }
                                delegate: DirectoryListItem {
                                    required property var modelData
                                    width: directoryList.width
                                    directory: modelData
                                    current: ClaudeCode.workingDirectory === modelData.path
                                    onClicked: {
                                        ClaudeCode.setWorkingDirectory(modelData.path);
                                        root.directoryPickerShown = false;
                                    }
                                }
                            }
                        }
                    }
                }

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
                        // Without this the flickable's content is only as wide as
                        // the text itself, so an empty field is click-to-focus
                        // over the placeholder alone.
                        contentWidth: availableWidth
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                        StyledTextArea {
                            id: messageInputField
                            anchors.fill: parent
                            wrapMode: TextArea.Wrap
                            padding: 8
                            background: null
                            color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                            placeholderText: ClaudeCode.busy
                                ? Translation.tr("Claude is working — type to queue")
                                : Translation.tr("Ask Claude…  /  for commands")

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Tab && root.slashSuggestions.length > 0) {
                                    root.applySlashCommand(root.slashSuggestions[0]);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                                    if (event.modifiers & Qt.ShiftModifier) {
                                        messageInputField.insert(messageInputField.cursorPosition, "\n");
                                    } else if (root.slashSuggestions.length === 1) {
                                        // Exactly one match: complete it rather
                                        // than sending a half-typed command.
                                        root.applySlashCommand(root.slashSuggestions[0]);
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
                        readonly property bool hasText: messageInputField.text.trim().length > 0
                        enabled: ClaudeCode.busy || (sendButton.hasText && ClaudeCode.available)
                        toggled: enabled

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                // Typing during a turn queues it; the stop
                                // button is only what's left when there's
                                // nothing waiting to be sent.
                                if (sendButton.hasText) root.send();
                                else if (ClaudeCode.busy) ClaudeCode.interrupt();
                            }
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: 22
                            fill: (ClaudeCode.busy && !sendButton.hasText) ? 1 : 0
                            color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                            text: (ClaudeCode.busy && sendButton.hasText) ? "schedule_send"
                                : ClaudeCode.busy ? "stop_circle"
                                : "arrow_upward"
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

                    RippleButton { // Working directory
                        id: directoryButton
                        Layout.fillWidth: true
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.full
                        toggled: root.directoryPickerShown
                        enabled: !ClaudeCode.busy
                        onClicked: root.toggleDirectoryPicker()

                        contentItem: RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 8
                                rightMargin: 8
                            }
                            spacing: 4

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.normal
                                color: directoryButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                                text: "folder"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideLeft
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: directoryButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                                text: ClaudeCode.workingDirectory
                            }
                        }

                        StyledToolTip {
                            text: ClaudeCode.busy
                                ? Translation.tr("Can't move while Claude is working")
                                : Translation.tr("Working directory — click to change.\nMoving starts a new conversation.")
                        }
                    }

                    RippleButton { // Ask before each tool, or let it run
                        id: permissionButton
                        implicitWidth: 28
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.full
                        toggled: ClaudeCode.askPermission
                        onClicked: ClaudeCode.setPermissionMode(ClaudeCode.askPermission ? "bypass" : "ask")

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.large
                            color: permissionButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3error
                            text: ClaudeCode.askPermission ? "encrypted" : "no_encryption"
                        }

                        StyledToolTip {
                            text: ClaudeCode.askPermission
                                ? Translation.tr("Asking before each tool")
                                : Translation.tr("Running unattended — no confirmations")
                        }
                    }

                    StyledText { // How long until the usage limit resets
                        visible: ClaudeCode.rateLimitResetText.length > 0
                            && ClaudeCode.rateLimit?.status !== "allowed"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.m3colors.m3error
                        text: Translation.tr("limit resets in %1").arg(ClaudeCode.rateLimitResetText)
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

                }
            }
        }
    }
}

