pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import org.kde.syntaxhighlighting

ColumnLayout {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property var segmentContent: ({})
    property var segmentLang: "txt"
    property var messageData: {}
    property bool isCommandRequest: segmentLang === "command"
    property var displayLang: (isCommandRequest ? "bash" : segmentLang)

    // Find in chat, numbered message-wide like MessageTextBlock.
    property string searchQuery: ""
    property int searchOrdinalBase: 0
    property int searchCurrent: -1
    signal currentMatchAt(real y)

    // Whether the closing fence has arrived. html and qml only preview once
    // it has, so nothing is rendered off half a page.
    property bool completed: true

    // Markdown is a document, so its preview is how it will read. html is
    // rendered to a picture out of process (Quickshell can't host WebEngine)
    // and qml is loaded straight into the chat.
    readonly property string previewKind: {
        const lang = String(root.segmentLang ?? "").toLowerCase();
        if (lang === "markdown" || lang === "md") return "markdown";
        if (lang === "qml") return "qml";
        if (["html", "htm", "xhtml", "svg"].indexOf(lang) !== -1) return "html";
        return "";
    }
    readonly property bool previewable: root.previewKind.length > 0
    // html and qml open on the preview; markdown stays on its source.
    property bool showPreview: root.previewKind === "qml" || root.previewKind === "html"
    // Editing is always done against the source — a preview that silently ate
    // keystrokes would be worse than no preview.
    readonly property bool previewing: root.previewable && root.showPreview && !root.editing
        && (root.previewKind === "markdown" || root.completed)

    readonly property string renderHtmlScript: Quickshell.shellPath("scripts/claude/render-html.sh")
    readonly property string previewDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/claude-preview`
    // Keyed by content, so an unchanged block never renders twice.
    readonly property string htmlPreviewPath: root.previewKind === "html" && root.completed
        ? `${root.previewDir}/${Qt.md5(root.segmentContent)}.png` : ""
    property string htmlPreviewReady: ""
    property string htmlPreviewError: ""
    onPreviewingChanged: root.renderHtmlIfNeeded()
    onHtmlPreviewPathChanged: root.renderHtmlIfNeeded()
    onWidthChanged: if (root.htmlPreviewReady.length === 0) root.renderHtmlIfNeeded()
    function renderHtmlIfNeeded() {
        if (!root.previewing || root.previewKind !== "html" || root.htmlPreviewPath.length === 0) return;
        if (root.htmlPreviewReady === root.htmlPreviewPath || htmlRender.running || root.width <= 0) return;
        root.htmlPreviewError = "";
        htmlRender.running = true;
    }

    Process {
        id: htmlRender
        command: [root.renderHtmlScript, root.segmentContent, root.htmlPreviewPath, String(Math.max(200, Math.round(root.width - 20)))]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) root.htmlPreviewReady = root.htmlPreviewPath;
            else root.htmlPreviewError = Translation.tr("Rendering failed (exit %1)").arg(exitCode);
        }
    }

    // Shell dialects we can hand straight to a terminal. Anything else (python,
    // qml, a diff) would need us to guess an interpreter, so it gets no button
    // rather than a wrong one. A pending command request is excluded: it already
    // has its own Approve/Reject below.
    readonly property var runnableLangs: ["bash", "sh", "shell", "shell-session", "console", "zsh", "fish", "command"]
    readonly property bool runnable: root.runnableLangs.indexOf(String(root.segmentLang ?? "").toLowerCase()) !== -1
        && !(root.messageData?.functionPending ?? false)

    // Where the block runs. Left empty the terminal falls back to $HOME, which
    // is what the chats without a session directory of their own want.
    property string workingDirectory: ""
    property bool terminalOpen: false
    // Records the terminal so its output can be handed to Claude.
    property bool terminalLogged: false

    // A command the user changed before running it. Null while the block is
    // still Claude's own, so an edit that empties it isn't mistaken for that.
    property var editedContent: null
    readonly property string effectiveContent: root.editedContent ?? root.segmentContent
    property bool commandEditing: false
    // What Esc goes back to: the block as it was when this edit began.
    property var editOriginal: null
    readonly property var placeholders: root.runnable ? root.findPlaceholders(codeTextArea.text) : []

    onEditedContentChanged: {
        const edits = root.messageData?.codeEdits;
        if (!edits) return;
        if (root.editedContent === null) delete edits[root.segmentContent];
        else edits[root.segmentContent] = root.editedContent;
    }
    Component.onCompleted: root.editedContent = root.messageData?.codeEdits?.[root.segmentContent] ?? null

    // `<path>`-style holes Claude leaves to be filled in. A word has to follow
    // the `<` directly, which keeps redirections like `< in > out` out of it.
    function findPlaceholders(text) {
        const found = [];
        const pattern = /<[A-Za-z][\w.:\/-]*(?: [\w.:\/-]+)*>/g;
        let match;
        while ((match = pattern.exec(text)) !== null) found.push({ start: match.index, end: match.index + match[0].length });
        return found;
    }

    function selectPlaceholder(from, backwards) {
        const marks = root.placeholders;
        if (marks.length === 0) return false;
        const target = backwards
            ? (marks.filter(mark => mark.start < from).pop() ?? marks[marks.length - 1])
            : (marks.find(mark => mark.start >= from) ?? marks[0]);
        codeTextArea.select(target.start, target.end);
        return true;
    }

    function startEditing(toPlaceholder) {
        root.editOriginal = root.editedContent;
        root.commandEditing = true;
        codeTextArea.forceActiveFocus();
        if (toPlaceholder) root.selectPlaceholder(0, false);
        else codeTextArea.cursorPosition = codeTextArea.length;
    }

    function finishEditing(revert) {
        if (revert) root.editedContent = root.editOriginal;
        root.commandEditing = false;
    }

    function run() {
        // A run with holes in it can only fail, so the first press goes to
        // filling them in. Once editing, it runs as is — a false positive must
        // never make a block unrunnable.
        if (!root.commandEditing && root.placeholders.length > 0) {
            root.startEditing(true);
            return;
        }
        root.commandEditing = false;
        if (root.terminalOpen && inlineTerminal.item) {
            inlineTerminal.item.command = root.effectiveContent;
            inlineTerminal.item.restart();
        } else {
            root.terminalOpen = true;
        }
    }

    property real codeBlockBackgroundRounding: Appearance.rounding.small
    property real codeBlockHeaderPadding: 3
    property real codeBlockComponentSpacing: 2

    spacing: codeBlockComponentSpacing

    Rectangle { // Code background
        Layout.fillWidth: true
        topLeftRadius: codeBlockBackgroundRounding
        topRightRadius: codeBlockBackgroundRounding
        bottomLeftRadius: Appearance.rounding.unsharpen
        bottomRightRadius: Appearance.rounding.unsharpen
        color: Appearance.colors.colSurfaceContainerHighest
        implicitHeight: codeBlockTitleBarRowLayout.implicitHeight + codeBlockHeaderPadding * 2

        RowLayout { // Language and buttons
            id: codeBlockTitleBarRowLayout
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: codeBlockHeaderPadding
            anchors.rightMargin: codeBlockHeaderPadding
            spacing: 5

            StyledText {
                id: codeBlockLanguage
                Layout.alignment: Qt.AlignLeft
                Layout.fillWidth: false
                Layout.topMargin: 7
                Layout.bottomMargin: 7
                Layout.leftMargin: 10
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                text: root.displayLang ? Repository.definitionForName(root.displayLang).name : "plain"
            }

            ButtonGroup { // Source vs. how it will actually read
                visible: root.previewable
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 8
                spacing: 2

                GroupButton {
                    baseHeight: 24
                    horizontalPadding: 10
                    verticalPadding: 2
                    toggled: !root.showPreview
                    onClicked: root.showPreview = false

                    contentItem: StyledText {
                        text: Translation.tr("Source")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.showPreview ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnPrimary
                    }
                }
                GroupButton {
                    baseHeight: 24
                    horizontalPadding: 10
                    verticalPadding: 2
                    toggled: root.showPreview
                    onClicked: root.showPreview = true

                    contentItem: StyledText {
                        text: Translation.tr("Preview")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.showPreview ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
            }

            Item { Layout.fillWidth: true }

            ButtonGroup {
                AiMessageControlButton {
                    visible: root.runnable && root.editedContent !== null
                    buttonIcon: "undo"
                    onClicked: {
                        root.editedContent = null;
                        root.commandEditing = false;
                    }

                    StyledToolTip {
                        text: Translation.tr("Back to Claude's version")
                    }
                }
                AiMessageControlButton {
                    visible: root.runnable
                    buttonIcon: "edit"
                    activated: root.commandEditing
                    onClicked: root.commandEditing ? root.finishEditing(false) : root.startEditing(root.placeholders.length > 0)

                    StyledToolTip {
                        text: root.commandEditing ? Translation.tr("Done editing") : Translation.tr("Edit command")
                    }
                }
                AiMessageControlButton {
                    id: runCodeButton
                    visible: root.runnable
                    buttonIcon: "play_arrow"
                    activated: root.terminalOpen

                    // The sidebar keeps the keyboard grab while this runs — that
                    // is what makes the terminal typeable without any of the
                    // focus handover the old spawn-a-window path needed.
                    onClicked: root.run()

                    StyledToolTip {
                        text: !root.commandEditing && root.placeholders.length > 0 ? Translation.tr("Fill in the placeholders")
                            : root.terminalOpen ? Translation.tr("Run again")
                            : Translation.tr("Run here")
                    }
                }
                AiMessageControlButton {
                    id: copyCodeButton
                    buttonIcon: activated ? "inventory" : "content_copy"

                    onClicked: {
                        Quickshell.clipboardText = root.effectiveContent
                        copyCodeButton.activated = true
                        copyIconTimer.restart()
                    }

                    Timer {
                        id: copyIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            copyCodeButton.activated = false
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Copy code")
                    }
                }
                AiMessageControlButton {
                    id: saveCodeButton
                    buttonIcon: activated ? "check" : "save"

                    onClicked: {
                        const downloadPath = FileUtils.trimFileProtocol(Directories.downloads)
                        Quickshell.execDetached(["bash", "-c", 
                            `echo '${StringUtils.shellSingleQuoteEscape(root.effectiveContent)}' >'${downloadPath}/code.${segmentLang || "txt"}'`
                        ])
                        Quickshell.execDetached(["notify-send", 
                            Translation.tr("Code saved to file"), 
                            Translation.tr("Saved to %1").arg(`${downloadPath}/code.${segmentLang || "txt"}`),
                            "-a", "Shell"
                        ])
                        saveCodeButton.activated = true
                        saveIconTimer.restart()
                    }

                    Timer {
                        id: saveIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            saveCodeButton.activated = false
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Save to Downloads")
                    }
                }
            }
        }
    }

    RowLayout { // Line numbers and code
        spacing: codeBlockComponentSpacing
        visible: !root.previewing

        Rectangle { // Line numbers
            implicitWidth: 40
            implicitHeight: lineNumberColumnLayout.implicitHeight
            Layout.fillHeight: true
            Layout.fillWidth: false
            topLeftRadius: Appearance.rounding.unsharpen
            bottomLeftRadius: codeBlockBackgroundRounding
            topRightRadius: Appearance.rounding.unsharpen
            bottomRightRadius: Appearance.rounding.unsharpen
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: lineNumberColumnLayout
                anchors {
                    left: parent.left
                    right: parent.right
                    rightMargin: 5
                    top: parent.top
                    topMargin: 6
                }
                spacing: 0
                
                Repeater {
                    model: codeTextArea.text.split("\n").length
                    Text {
                        required property int index
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        horizontalAlignment: Text.AlignRight
                        text: index + 1
                    }
                }
            }
        }

        Rectangle { // Code background
            Layout.fillWidth: true
            topLeftRadius: Appearance.rounding.unsharpen
            bottomLeftRadius: Appearance.rounding.unsharpen
            topRightRadius: Appearance.rounding.unsharpen
            bottomRightRadius: codeBlockBackgroundRounding
            color: Appearance.colors.colLayer2
            border.width: root.commandEditing ? 1 : 0
            border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.4)
            implicitHeight: codeColumnLayout.implicitHeight

            ColumnLayout {
                id: codeColumnLayout
                anchors.fill: parent
                spacing: 0
                ScrollView {
                    id: codeScrollView
                    Layout.fillWidth: true
                    // Layout.fillHeight: true
                    implicitWidth: parent.width
                    implicitHeight: codeTextArea.implicitHeight + 1
                    contentWidth: codeTextArea.width - 1
                    // contentHeight: codeTextArea.contentHeight
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                    // A ScrollView accepts every wheel event, even ones it
                    // can't scroll by, so over a code block the chat stopped
                    // scrolling. Sideways scrolling is done by the MouseArea below.
                    wheelEnabled: false

                    ScrollBar.horizontal: ScrollBar {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        padding: 5
                        policy: ScrollBar.AsNeeded
                        opacity: visualSize == 1 ? 0 : 1
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        
                        contentItem: Rectangle {
                            implicitHeight: 6
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2Active
                        }
                    }

                    TextArea { // Code
                        id: codeTextArea
                        Layout.fillWidth: true
                        readOnly: !(editing || root.commandEditing)
                        selectByMouse: enableMouseSelection || editing || root.commandEditing
                        renderType: Text.NativeRendering
                        font.family: Appearance.font.family.monospace
                        font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
                        font.pixelSize: Appearance.font.pixelSize.small
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        // wrapMode: TextEdit.Wrap
                        color: messageData.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1

                        text: root.effectiveContent
                        onTextChanged: {
                            if (root.commandEditing) root.editedContent = text === root.segmentContent ? null : text
                            else if (editing) segmentContent = text
                        }

                        Keys.onPressed: (event) => {
                            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                            if (root.commandEditing && !ctrl && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
                                const backwards = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
                                if (root.selectPlaceholder(backwards ? codeTextArea.selectionStart : codeTextArea.selectionEnd, backwards)) {
                                    event.accepted = true;
                                    return;
                                }
                            }
                            if (root.commandEditing && ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                root.run();
                                event.accepted = true;
                            } else if (root.commandEditing && event.key === Qt.Key_Escape) {
                                root.finishEditing(true);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab && !ctrl) {
                                // Insert 4 spaces at cursor
                                const cursor = codeTextArea.cursorPosition;
                                codeTextArea.insert(cursor, "    ");
                                codeTextArea.cursorPosition = cursor + 4;
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_C) && event.modifiers == Qt.ControlModifier) {
                                codeTextArea.copy();
                                event.accepted = true;
                            }
                        }

                        SyntaxHighlighter {
                            id: highlighter
                            textEdit: codeTextArea
                            repository: Repository
                            definition: Repository.definitionForName(root.displayLang || "plaintext")
                            theme: Appearance.syntaxHighlightingTheme
                        }

                        SearchMatchOverlay {
                            textEdit: codeTextArea
                            query: root.searchQuery
                            ordinalBase: root.searchOrdinalBase
                            current: root.searchCurrent
                            onCurrentMatchAt: y => root.currentMatchAt(codeTextArea.mapToItem(root, 0, y).y)
                        }

                        Repeater { // The placeholders still to fill in
                            model: root.placeholders

                            Rectangle {
                                id: placeholderMark
                                required property var modelData
                                readonly property real layoutVersion: codeTextArea.contentWidth + codeTextArea.contentHeight
                                readonly property rect startRect: {
                                    const version = placeholderMark.layoutVersion;
                                    return codeTextArea.positionToRectangle(placeholderMark.modelData.start);
                                }
                                readonly property rect endRect: {
                                    const version = placeholderMark.layoutVersion;
                                    return codeTextArea.positionToRectangle(placeholderMark.modelData.end);
                                }
                                x: placeholderMark.startRect.x - 1
                                y: placeholderMark.startRect.y
                                width: placeholderMark.endRect.x - placeholderMark.startRect.x + 2
                                height: placeholderMark.startRect.height
                                radius: 3
                                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                                border.width: 1
                                border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.4)
                            }
                        }
                    }
                }
                RowLayout { // How to get around while the command is being edited
                    visible: root.commandEditing
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    Layout.bottomMargin: 6
                    spacing: 6

                    MaterialSymbol {
                        text: "edit"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: root.placeholders.length > 0
                            ? Translation.tr("Tab next placeholder · Ctrl+Enter run · Esc cancel")
                            : Translation.tr("Ctrl+Enter run · Esc cancel")
                    }
                }
                Loader {
                    active: root.isCommandRequest && root.messageData.functionPending
                    visible: active
                    Layout.fillWidth: true
                    Layout.margins: 6
                    Layout.topMargin: 0
                    sourceComponent: RowLayout {
                        Item { Layout.fillWidth: true }
                        ButtonGroup {
                            GroupButton {
                                contentItem: StyledText {
                                    text: Translation.tr("Reject")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer2
                                }
                                onClicked: Ai.rejectCommand(root.messageData)
                            }
                            GroupButton {
                                toggled: true
                                contentItem: StyledText {
                                    text: Translation.tr("Approve")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnPrimary
                                }
                                onClicked: Ai.approveCommand(root.messageData)
                            }
                        }
                    }
                }
            }

            MouseArea { // Sideways wheel or Shift+wheel scrolls long lines; the rest passes through
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    const flick = codeScrollView.contentItem;
                    const room = flick.contentWidth - flick.width;
                    const sideways = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y);
                    let delta = !sideways ? 0 : wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x * 1.5 : wheel.angleDelta.x / 2;
                    if (delta === 0 && (wheel.modifiers & Qt.ShiftModifier)) delta = wheel.angleDelta.y / 2;
                    if (delta === 0 || room <= 0) {
                        wheel.accepted = false;
                        return;
                    }
                    flick.contentX = Math.min(Math.max(flick.contentX - delta, 0), room);
                }
            }

            // MouseArea to block scrolling
            // MouseArea {
            //     id: codeBlockMouseArea
            //     anchors.fill: parent
            //     acceptedButtons: editing ? Qt.NoButton : Qt.LeftButton
            //     cursorShape: (enableMouseSelection || editing) ? Qt.IBeamCursor : Qt.ArrowCursor
            //     onWheel: (event) => {
            //         event.accepted = false
            //     }
            // }
        }
    }

    Loader {
        Layout.fillWidth: true
        active: root.previewing
        visible: active
        sourceComponent: root.previewKind === "markdown" ? markdownPreview
            : root.previewKind === "qml" ? qmlPreview
            : htmlPreview
    }

    Loader {
        id: inlineTerminal
        Layout.fillWidth: true
        Layout.topMargin: root.codeBlockComponentSpacing
        active: root.terminalOpen
        visible: active
        // Loaded by url rather than as a type: the terminal needs the
        // qmltermwidget plugin, and referencing it by type would take every
        // code block in the chat down with it when the plugin is missing.
        source: Qt.resolvedUrl("InlineTerminal.qml")

        onLoaded: {
            inlineTerminal.item.workingDirectory = root.workingDirectory;
            inlineTerminal.item.logged = root.terminalLogged;
            inlineTerminal.item.closeRequested.connect(() => root.terminalOpen = false);
            inlineTerminal.item.command = root.effectiveContent;
        }
        // Deferred: closing from inside the loader's own status change writes
        // straight back into the property `active` reads, which Qt reports as
        // a binding loop.
        onStatusChanged: if (inlineTerminal.status === Loader.Error) Qt.callLater(() => root.terminalOpen = false)
    }

    component PreviewBox: Rectangle {
        topLeftRadius: Appearance.rounding.unsharpen
        topRightRadius: Appearance.rounding.unsharpen
        bottomLeftRadius: root.codeBlockBackgroundRounding
        bottomRightRadius: root.codeBlockBackgroundRounding
        color: Appearance.colors.colLayer2
    }

    Component { // The same renderer the chat's own prose goes through
        id: markdownPreview

        PreviewBox {
            implicitHeight: previewColumnLayout.implicitHeight + 20

            ColumnLayout {
                id: previewColumnLayout
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: 10
                    rightMargin: 10
                    topMargin: 10
                }

                MessageTextBlock {
                    Layout.fillWidth: true
                    enableMouseSelection: root.enableMouseSelection
                    segmentContent: root.segmentContent
                    messageData: root.messageData
                    done: true
                    // The document is already whole by the time it can be
                    // previewed; the fade-in chunking is for streaming prose.
                    forceDisableChunkSplitting: true
                }
            }
        }
    }

    Component { // Loaded into the shell itself, so it is live but unsandboxed
        id: qmlPreview

        PreviewBox {
            id: qmlBox
            property string error: ""
            implicitHeight: (qmlBox.error.length > 0 ? qmlError.implicitHeight : qmlStage.implicitHeight) + 20

            Item {
                id: qmlStage
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 10
                }
                clip: true
                property Item content: null
                // A root that anchors to its parent would size itself from
                // the stage and the stage from it, so it gets a fixed stage.
                property bool anchored: false
                readonly property real contentWidth: qmlStage.content ? Math.max(qmlStage.content.width, qmlStage.content.implicitWidth) : 0
                readonly property real contentHeight: qmlStage.content ? Math.max(qmlStage.content.height, qmlStage.content.implicitHeight) : 0
                // Shrunk to fit the column; never enlarged.
                readonly property real factor: qmlStage.contentWidth > 0 ? Math.min(1, qmlStage.width / qmlStage.contentWidth) : 1
                implicitHeight: qmlStage.anchored ? 320 : Math.max(24, qmlStage.contentHeight * qmlStage.factor)

                Component.onCompleted: {
                    try {
                        const object = Qt.createQmlObject(root.segmentContent, qmlStage, `file://${root.previewDir}/block.qml`);
                        qmlStage.anchored = !!(object.anchors?.fill || object.anchors?.centerIn || object.anchors?.top || object.anchors?.left);
                        object.transformOrigin = Item.TopLeft;
                        object.scale = Qt.binding(() => qmlStage.factor);
                        qmlStage.content = object;
                    } catch (e) {
                        const errors = e.qmlErrors ?? [];
                        qmlBox.error = errors.length > 0
                            ? errors.map(err => `${err.lineNumber}:${err.columnNumber} ${err.message}`).join("\n")
                            : String(e);
                    }
                }
            }

            StyledText {
                id: qmlError
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 10
                }
                visible: qmlBox.error.length > 0
                wrapMode: Text.Wrap
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3error
                text: qmlBox.error
            }
        }
    }

    Component { // A picture of the page, rendered out of process
        id: htmlPreview

        PreviewBox {
            id: htmlBox
            readonly property bool ready: htmlImage.status === Image.Ready
            implicitHeight: (htmlBox.ready ? htmlImage.height : htmlStatus.implicitHeight) + 20

            Image {
                id: htmlImage
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 10
                }
                visible: htmlBox.ready
                source: root.htmlPreviewReady.length > 0 ? `file://${root.htmlPreviewReady}` : ""
                cache: false
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                height: htmlImage.sourceSize.width > 0 ? htmlImage.width * htmlImage.sourceSize.height / htmlImage.sourceSize.width : 0
            }

            RowLayout {
                id: htmlStatus
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 10
                }
                visible: !htmlBox.ready
                spacing: 8

                MaterialLoadingIndicator {
                    visible: root.htmlPreviewError.length === 0
                    implicitSize: 22
                    loading: true
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.htmlPreviewError.length > 0 ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                    text: root.htmlPreviewError.length > 0 ? root.htmlPreviewError : Translation.tr("Rendering the page…")
                }
            }
        }
    }
}