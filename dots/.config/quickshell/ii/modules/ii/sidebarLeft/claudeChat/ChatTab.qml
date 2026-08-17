import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One conversation in the Claude tab strip.
 *
 * The chip is labelled with the conversation title, same as the history list;
 * tabs on the same project would otherwise all read alike. The directory falls
 * back in only while the conversation hasn't started, and stays in the tooltip.
 */
RippleButton {
    id: root

    required property var session
    required property int tabIndex

    readonly property bool current: root.session === ClaudeCode.active
    readonly property bool needsInput: root.session?.needsInput ?? false
    readonly property bool busy: root.session?.busy ?? false
    readonly property bool unseen: root.session?.unseen ?? false

    readonly property string label: {
        const title = (root.session?.conversationTitle ?? "").trim();
        const parts = (root.session?.workingDirectory ?? "").split("/").filter(part => part.length > 0);
        const text = title.length > 0 ? title
            : parts.length > 0 ? parts[parts.length - 1]
            : Translation.tr("Home");
        // Titles are first messages, and first messages start lowercase.
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    implicitHeight: 28
    buttonRadius: Appearance.rounding.verysmall
    toggled: root.current
    // RippleButton leaves an untoggled button transparent, which puts an
    // inactive tab straight on the sidebar with nothing to mark its edges.
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    onClicked: ClaudeCode.activateTab(root.tabIndex)
    // Closing without switching to the tab first, the way a browser does it.
    middleClickAction: () => ClaudeCode.closeTab(root.tabIndex)

    contentItem: RowLayout {
        anchors {
            fill: parent
            leftMargin: 8
            // The close button sits over the right edge, so the label has to
            // stop eliding before it reaches it.
            rightMargin: closeButton.visible ? 22 : 8
        }
        spacing: 5

        Rectangle { // What this tab wants, if anything
            id: statusDot
            visible: root.needsInput || root.busy || root.unseen
            implicitWidth: 6
            implicitHeight: 6
            radius: width / 2
            color: root.needsInput ? Appearance.m3colors.m3error
                : root.busy ? (root.current ? Appearance.m3colors.m3onPrimary : Appearance.colors.colPrimary)
                : Appearance.m3colors.m3tertiary

            // A tab that is waiting on an answer is the one thing here that
            // shouldn't be possible to miss out of the corner of an eye. The
            // sequence ends on full opacity, so stopping leaves a plain dot.
            SequentialAnimation on opacity {
                running: root.needsInput || root.busy
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutQuad }
            }
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: root.current ? Font.Medium : Font.Normal
            color: root.current ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
            text: root.label
        }
    }

    // A child of the button rather than of its contentItem: the button's own
    // mouse area covers the content, so anything clickable has to sit above it.
    Item {
        id: closeButton
        // Hover alone would flicker — the close area takes the pointer off the
        // button underneath it — so its own hover keeps it on screen.
        visible: root.current || root.hovered || closeArea.containsMouse
        anchors {
            right: parent.right
            rightMargin: 5
            verticalCenter: parent.verticalCenter
        }
        implicitWidth: 16
        implicitHeight: 16

        MaterialSymbol {
            anchors.centerIn: parent
            iconSize: 14
            color: root.current
                ? Appearance.m3colors.m3onPrimary
                : (closeArea.containsMouse ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext)
            text: "close"
        }

        MouseArea {
            id: closeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ClaudeCode.closeTab(root.tabIndex)
        }
    }

    StyledToolTip {
        text: {
            const directory = root.session?.workingDirectory ?? "";
            const title = root.session?.conversationTitle ?? "";
            const state = root.needsInput ? Translation.tr("Waiting for you")
                : root.busy ? Translation.tr("Working…")
                : root.unseen ? Translation.tr("Finished while you were elsewhere")
                : "";
            return [directory, title, state].filter(part => part.length > 0).join("\n");
        }
    }
}
