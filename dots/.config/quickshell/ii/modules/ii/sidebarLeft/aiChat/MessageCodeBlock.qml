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

    // A markdown block is the one case where the snippet is a document rather
    // than something to run: what matters is how it will read once it lands
    // wherever it's going, so it gets the compose-box treatment.
    readonly property bool previewable: ["markdown", "md"].indexOf(String(root.segmentLang ?? "").toLowerCase()) !== -1
    property bool showPreview: false
    // Editing is always done against the source — a preview that silently ate
    // keystrokes would be worse than no preview.
    readonly property bool previewing: root.previewable && root.showPreview && !root.editing

    // Shell dialects we can hand straight to a terminal. Anything else (python,
    // qml, a diff) would need us to guess an interpreter, so it gets no button
    // rather than a wrong one. A pending command request is excluded: it already
    // has its own Approve/Reject below.
    readonly property string runInTerminalScript: Quickshell.shellPath("scripts/hyprland/runInTerminal.sh")
    readonly property var runnableLangs: ["bash", "sh", "shell", "shell-session", "console", "zsh", "fish", "command"]
    readonly property bool runnable: root.runnableLangs.indexOf(String(root.segmentLang ?? "").toLowerCase()) !== -1
        && !(root.messageData?.functionPending ?? false)

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
                    id: runCodeButton
                    visible: root.runnable
                    buttonIcon: activated ? "check" : "play_arrow"

                    onClicked: {
                        // Hyprland gives the open sidebar exclusive keyboard focus,
                        // so synthetic keystrokes land in the chat box no matter
                        // which window is focused. Releasing the grab is not enough
                        // — the layer surface has to stop asking for the keyboard,
                        // and the script cannot be launched until it has, since the
                        // window focus it checks is already correct and tells it
                        // nothing about where the keys are actually going.
                        GlobalFocusGrab.dismiss();
                        GlobalStates.sidebarLeftYieldKeyboard = true;
                        keyboardYieldTimer.restart();
                        launchTimer.restart();
                        runCodeButton.activated = true;
                        runIconTimer.restart();
                    }

                    Timer { // Lets the compositor take the keyboard back first
                        id: launchTimer
                        interval: 250
                        repeat: false
                        onTriggered: {
                            const terminal = (Config.options.apps.terminal ?? "").split(/\s+/).filter(part => part.length > 0);
                            // The script reuses a terminal already on this workspace
                            // and only spawns one when there is nothing to reuse; the
                            // terminal argv is a fallback, since it picks the same one
                            // the Super+T keybind does. Passed as argv rather than a
                            // shell string, so the snippet reaches it verbatim and no
                            // quoting of ours can mangle it.
                            Quickshell.execDetached([root.runInTerminalScript, root.segmentContent, ...terminal]);
                        }
                    }

                    Timer {
                        id: runIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            runCodeButton.activated = false
                        }
                    }

                    Timer { // Long enough to cover the script's focus wait and typing
                        id: keyboardYieldTimer
                        interval: 5000
                        repeat: false
                        onTriggered: {
                            GlobalStates.sidebarLeftYieldKeyboard = false
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Run in a terminal")
                    }
                }
                AiMessageControlButton {
                    id: copyCodeButton
                    buttonIcon: activated ? "inventory" : "content_copy"

                    onClicked: {
                        Quickshell.clipboardText = segmentContent
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
                            `echo '${StringUtils.shellSingleQuoteEscape(segmentContent)}' > '${downloadPath}/code.${segmentLang || "txt"}'`
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
                        readOnly: !editing
                        selectByMouse: enableMouseSelection || editing
                        renderType: Text.NativeRendering
                        font.family: Appearance.font.family.monospace
                        font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
                        font.pixelSize: Appearance.font.pixelSize.small
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        // wrapMode: TextEdit.Wrap
                        color: messageData.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1

                        text: segmentContent
                        onTextChanged: {
                            segmentContent = text
                        }

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Tab) {
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

    Loader { // The same renderer the chat's own prose goes through
        Layout.fillWidth: true
        active: root.previewing
        visible: active

        sourceComponent: Rectangle {
            implicitHeight: previewColumnLayout.implicitHeight + 20
            topLeftRadius: Appearance.rounding.unsharpen
            topRightRadius: Appearance.rounding.unsharpen
            bottomLeftRadius: root.codeBlockBackgroundRounding
            bottomRightRadius: root.codeBlockBackgroundRounding
            color: Appearance.colors.colLayer2

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
}