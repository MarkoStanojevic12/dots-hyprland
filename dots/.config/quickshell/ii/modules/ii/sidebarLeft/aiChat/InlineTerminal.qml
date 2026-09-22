pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QMLTermWidget 2.0

/**
 * A real terminal, inside a code block. Runs the block and then hands the pty
 * over to an interactive shell, the way spawning a window used to.
 */
Rectangle {
    id: root
    property string command: ""
    property string workingDirectory: ""
    property bool expanded: false
    property bool exited: false
    signal closeRequested()

    readonly property int collapsedRows: 14
    readonly property int expandedRows: 30
    readonly property int shownRows: root.expanded ? root.expandedRows : root.collapsedRows

    // The plugin forces TERM=xterm on the whole shell process, so 256 colours
    // have to be put back from inside the pty.
    readonly property string script: `export TERM=xterm-256color COLORTERM=truecolor
${root.command}
printf '\\n─── exit %s ───\\n' "$?"
command -v fish >/dev/null 2>&1 && exec fish
exec "\${SHELL:-/bin/bash}"`

    function restart() {
        root.exited = false;
        termLoader.active = false;
        termLoader.active = Qt.binding(() => root.command.length > 0);
    }

    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.small
    implicitHeight: terminalColumn.implicitHeight + 8

    ColumnLayout {
        id: terminalColumn
        anchors {
            fill: parent
            margins: 4
        }
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: root.exited ? Translation.tr("terminal · exited") : Translation.tr("terminal")
            }

            AiMessageControlButton {
                buttonIcon: "refresh"
                onClicked: root.restart()
                StyledToolTip {
                    text: Translation.tr("Run again")
                }
            }
            AiMessageControlButton {
                buttonIcon: root.expanded ? "collapse_content" : "expand_content"
                onClicked: root.expanded = !root.expanded
                StyledToolTip {
                    text: root.expanded ? Translation.tr("Shrink") : Translation.tr("Grow")
                }
            }
            AiMessageControlButton {
                buttonIcon: "close"
                onClicked: root.closeRequested()
                StyledToolTip {
                    text: Translation.tr("Close terminal")
                }
            }
        }

        Loader {
            id: termLoader
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Layout.bottomMargin: 2
            // The command arrives after this file is instantiated, and the pty
            // is spawned on creation — so there is nothing to create until then.
            active: root.command.length > 0
            sourceComponent: terminalComponent
        }
    }

    Component {
        id: terminalComponent

        QMLTermWidget {
            id: terminal
            // fontMetrics is empty until the first font pass, and a zero height
            // would make the widget report zero lines and never draw.
            implicitHeight: Math.max(16, terminal.fontMetrics.height) * root.shownRows
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.small
            colorScheme: Appearance.m3colors.darkmode ? "Linux" : "BlackOnWhite"
            enableBold: true
            fullCursorHeight: true
            smooth: true

            session: QMLTermSession {
                id: termSession
                initialWorkingDirectory: root.workingDirectory.length > 0 ? root.workingDirectory : "$HOME"
                shellProgram: "/bin/bash"
                shellProgramArgs: ["-c", root.script]
                onFinished: root.exited = true
            }

            // The shell is handed a terminal sized from this widget, and the
            // widget has no width until the layout has run. Starting at
            // creation gives it a zero-column pty that swallows the whole first
            // run -- which is why hitting play a second time appeared to fix it.
            property bool started: false

            // The bundled schemes paint a pure black behind the text, which
            // reads as a hole punched in the card. Only these two are settable
            // from here -- the sixteen ANSI colours stay with the scheme -- and
            // setColorScheme resets them, so they are re-applied rather than
            // bound.
            readonly property color shellBackground: Appearance.colors.colLayer2
            readonly property color shellForeground: Appearance.colors.colOnLayer2

            function applyColors() {
                terminal.setBackgroundColor(terminal.shellBackground);
                terminal.setForegroundColor(terminal.shellForeground);
            }

            onShellBackgroundChanged: terminal.applyColors()
            onShellForegroundChanged: terminal.applyColors()
            onColorSchemeChanged: terminal.applyColors()

            function startWhenSized() {
                if (terminal.started || terminal.width <= 0 || terminal.height <= 0) return;
                terminal.started = true;
                terminal.applyColors();
                termSession.startShellProgram();
                terminal.forceActiveFocus();
            }

            // Polled rather than hung off a geometry signal: on "run again" the
            // replacement is built straight into the size the old one had, so
            // width and height never change and no such signal ever arrives.
            Timer {
                interval: 16
                repeat: true
                running: !terminal.started
                onTriggered: terminal.startWhenSized()
            }

            TapHandler {
                gesturePolicy: TapHandler.DragThreshold
                onTapped: terminal.forceActiveFocus()
            }

            QMLTermScrollbar {
                terminal: terminal
                width: 6

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Appearance.colors.colLayer2Active
                    opacity: 0.6
                }
            }
        }
    }
}
