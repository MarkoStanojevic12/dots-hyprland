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
    property bool effortPickerShown: false
    property bool historyShown: false
    property bool usefulFeaturesShown: false

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

    // Both pickers live in the same strip above the composer, so opening one
    // closes the other rather than stacking two panels over the input.
    function toggleEffortPicker() {
        root.effortPickerShown = !root.effortPickerShown;
        if (root.effortPickerShown) root.modelPickerShown = false;
    }

    // History and the feature list both drop out of the header, so opening one
    // closes the other rather than stacking two panels over the messages.
    function toggleHistory() {
        root.historyShown = !root.historyShown;
        if (root.historyShown) {
            root.usefulFeaturesShown = false;
            ClaudeCode.refreshSessions();
        }
    }

    function toggleUsefulFeatures() {
        root.usefulFeaturesShown = !root.usefulFeaturesShown;
        if (root.usefulFeaturesShown) root.historyShown = false;
    }

    function runFeature(feature) {
        root.usefulFeaturesShown = false;
        ClaudeCode.sendMessage(feature.prompt);
        messageListView.positionViewAtEnd();
    }

    UsefulFeatures {
        id: usefulFeatures
    }

    readonly property var availableFeatures: usefulFeatures.forDirectory(ClaudeCode.workingDirectory)

    // Moving somewhere with nothing on offer would otherwise leave an empty
    // panel hanging under a button that is no longer there.
    onAvailableFeaturesChanged: if (root.availableFeatures.length === 0) root.usefulFeaturesShown = false;

    function toggleDirectoryPicker() {
        root.directoryPickerShown = !root.directoryPickerShown;
        if (root.directoryPickerShown) {
            ClaudeCode.clearDirectoryError();
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

    // A second conversation alongside this one, rather than in place of it. It
    // starts in the same directory, since opening a tab is usually splitting
    // the work you are already doing rather than moving to another project.
    function openTab() {
        if (!ClaudeCode.canOpenTab) return;
        ClaudeCode.newTab(ClaudeCode.workingDirectory);
        root.historyShown = false;
        root.usefulFeaturesShown = false;
        messageInputField.forceActiveFocus();
    }

    function closeTab() {
        ClaudeCode.closeTab(ClaudeCode.activeIndex);
        messageInputField.forceActiveFocus();
    }

    onFocusChanged: focus => {
        if (focus) root.inputField.forceActiveFocus();
    }

    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            root.startNewConversation();
            event.accepted = true;
            return;
        }
        // Ctrl+PageUp/PageDown already moves between the sidebar's own tabs, so
        // conversations move on Ctrl+Tab instead.
        if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_T) {
                root.openTab();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_W) {
                root.closeTab();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                // Shift+Tab arrives as Backtab, and on some layouts with the
                // shift modifier still set, so either one means backwards.
                const backwards = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
                ClaudeCode.activateNextTab(backwards ? -1 : 1);
                event.accepted = true;
                return;
            }
        }
        // Typing anywhere in the tab lands in the composer, but only real
        // typing. Anything a focused field left unhandled — a bare modifier, an
        // arrow, Tab — has to stay put, or answering a question yanks the
        // cursor out of that question's own field.
        const character = event.text;
        if (character.length === 0 || character.charCodeAt(0) < 0x20 || character.charCodeAt(0) === 0x7f) return;
        messageInputField.forceActiveFocus();
    }

    function send() {
        const text = messageInputField.text;
        if (text.trim().length === 0 && ClaudeCode.pendingAttachments.length === 0) return;
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

            RippleButton { // Another conversation alongside this one
                id: newTabButton
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                enabled: ClaudeCode.canOpenTab
                onClicked: root.openTab()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    color: newTabButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer1Inactive
                    text: "add"
                }

                StyledToolTip {
                    text: ClaudeCode.canOpenTab
                        ? Translation.tr("New chat tab (Ctrl+T)\nRuns beside this one, in the same directory")
                        : Translation.tr("%1 chats at once is the limit — each one is a whole CLI").arg(ClaudeCode.maxTabs)
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

            RippleButton { // Saved prompts
                id: usefulFeaturesButton
                visible: root.availableFeatures.length > 0
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                toggled: root.usefulFeaturesShown
                onClicked: root.toggleUsefulFeatures()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    color: usefulFeaturesButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                    text: "bolt"
                }

                StyledToolTip {
                    text: Translation.tr("Useful features")
                }
            }
        }

        Revealer { // The other conversations, once there is more than one
            vertical: true
            // A single conversation keeps the vertical space it had before tabs
            // existed; the header's + is what says a second one is possible.
            reveal: ClaudeCode.tabs.length > 1

            ChatTabStrip {
                width: mainColumn.width
            }
        }

        Revealer { // Useful features
            vertical: true
            reveal: root.usefulFeaturesShown
            Layout.bottomMargin: root.usefulFeaturesShown ? 10 : 0

            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            Rectangle {
                width: mainColumn.width
                implicitHeight: featureColumn.implicitHeight + 8
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: featureColumn
                    anchors {
                        fill: parent
                        margins: 4
                    }
                    spacing: 2

                    Repeater {
                        model: root.availableFeatures

                        delegate: UsefulFeatureItem {
                            required property var modelData
                            Layout.fillWidth: true
                            feature: modelData
                            onClicked: root.runFeature(modelData)
                        }
                    }
                }
            }
        }

        Revealer { // History list
            vertical: true
            reveal: root.historyShown
            // Only while open -- the Revealer collapses to nothing when closed,
            // so an unconditional margin would leave a gap under the header.
            Layout.bottomMargin: root.historyShown ? 10 : 0

            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

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
            // Sits on top of mainColumn's spacing, so the chat keeps the same
            // distance from whatever is above it -- header or tab strip.
            Layout.topMargin: 8
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
                // The layer above only masks painting, so without this the
                // delegates scrolled past the top still swallow clicks meant
                // for the header buttons.
                clip: true
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

        Loader { // Signed out — nothing else in the tab will work until it isn't
            Layout.fillWidth: true
            active: ClaudeCode.signedOut
            visible: active
            sourceComponent: SignInCard {}
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
                            MaterialSymbol {
                                visible: (queuedItem.modelData.attachments ?? []).length > 0
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                                text: "image"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: queuedItem.modelData.text
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

                Revealer { // Effort picker
                    vertical: true
                    reveal: root.effortPickerShown

                    FlowButtonGroup {
                        width: inputColumn.width
                        spacing: 4

                        Repeater {
                            model: ClaudeCode.availableEfforts

                            SelectionGroupButton {
                                required property var modelData
                                leftmost: true
                                rightmost: true
                                verticalPadding: 5
                                buttonText: modelData.name
                                toggled: ClaudeCode.selectedEffort === modelData.alias
                                // The CLI has to restart to pick this up, so not
                                // in the middle of a turn.
                                enabled: !ClaudeCode.busy
                                onClicked: {
                                    ClaudeCode.setEffort(modelData.alias);
                                    root.effortPickerShown = false;
                                }

                                StyledToolTip {
                                    text: modelData.description
                                }
                            }
                        }
                    }
                }

                Flow { // Images pasted into this message, not sent yet
                    Layout.fillWidth: true
                    Layout.bottomMargin: ClaudeCode.pendingAttachments.length > 0 ? 4 : 0
                    spacing: 4

                    Repeater {
                        model: ScriptModel {
                            values: ClaudeCode.pendingAttachments
                        }

                        delegate: AttachmentThumbnail {
                            required property var modelData
                            required property int index
                            path: modelData.path
                            canRemove: true
                            onRemove: ClaudeCode.detachAttachment(index)
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
                                // Ctrl+Tab moves between conversations, so bare
                                // Tab is the only one that completes a command.
                                if (event.key === Qt.Key_Tab && event.modifiers === Qt.NoModifier && root.slashSuggestions.length > 0) {
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
                                } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                                    // Whether the clipboard holds an image is
                                    // only known once wl-paste has answered, so
                                    // the paste is taken over entirely and the
                                    // text case is put back from there.
                                    // Ctrl+Shift+V stays Qt's own plain paste.
                                    if (event.modifiers & Qt.ShiftModifier) messageInputField.paste();
                                    else ClaudeCode.pasteInto(messageInputField);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape && ClaudeCode.pendingAttachments.length > 0 && !ClaudeCode.busy) {
                                    ClaudeCode.clearAttachments();
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
                            || ClaudeCode.pendingAttachments.length > 0
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
                        onClicked: {
                            root.modelPickerShown = !root.modelPickerShown;
                            if (root.modelPickerShown) root.effortPickerShown = false;
                        }

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

                    RippleButton { // How hard it thinks
                        id: effortButton
                        implicitHeight: 28
                        implicitWidth: effortButtonRow.implicitWidth + 16
                        buttonRadius: Appearance.rounding.full
                        toggled: root.effortPickerShown
                        enabled: !ClaudeCode.busy
                        onClicked: root.toggleEffortPicker()

                        contentItem: RowLayout {
                            id: effortButtonRow
                            anchors.centerIn: parent
                            spacing: 2

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.normal
                                color: effortButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                                text: "psychology"
                            }
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: effortButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
                                text: ClaudeCode.selectedEffortName
                            }
                        }

                        StyledToolTip {
                            text: ClaudeCode.busy
                                ? Translation.tr("Can't change effort while Claude is working")
                                : Translation.tr("How hard Claude thinks. Changing it restarts the CLI\nand resumes this conversation on the next message.")
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

                    Row { // A turn in flight. The bubble has its own spinner, but
                          // that one is off-screen the moment you scroll up.
                        id: busyIndicator
                        property bool hovered: busyHover.hovered
                        visible: ClaudeCode.busy
                        spacing: 3

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                            text: "progress_activity"

                            RotationAnimation on rotation {
                                running: busyIndicator.visible
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 1600
                            }
                        }

                        HoverHandler {
                            id: busyHover
                        }

                        StyledToolTip {
                            text: Translation.tr("Claude is working — Esc to stop")
                        }
                    }

                    Row { // Work still running in the background
                        id: backgroundIndicator
                        property bool hovered: backgroundHover.hovered
                        readonly property int count: ClaudeCode.backgroundTasks.length
                        visible: backgroundIndicator.count > 0
                        spacing: 3

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                            text: "monitoring"

                            SequentialAnimation on opacity {
                                running: backgroundIndicator.visible
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutQuad }
                            }
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            text: backgroundIndicator.count
                        }

                        HoverHandler {
                            id: backgroundHover
                        }

                        StyledToolTip {
                            text: {
                                const running = ClaudeCode.backgroundTasks
                                    .map(task => `• ${task.description}`)
                                    .join("\n");
                                const heading = backgroundIndicator.count === 1
                                    ? Translation.tr("1 background task running")
                                    : Translation.tr("%1 background tasks running").arg(backgroundIndicator.count);
                                return running.length > 0 ? `${heading}\n${running}` : heading;
                            }
                        }
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

