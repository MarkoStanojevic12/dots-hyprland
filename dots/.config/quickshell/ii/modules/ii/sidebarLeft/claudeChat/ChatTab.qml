import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * One conversation in the Claude tab strip.
 *
 * The chip is labelled with the conversation title, same as the history list;
 * tabs on the same project would otherwise all read alike. The directory falls
 * back in only while the conversation hasn't started, and stays in the tooltip.
 *
 * Nothing here is filled. The current conversation is accent-coloured text over
 * a 2px rule at the foot of the tab, the rest are plain labels on the sidebar
 * background. A filled tab has to be opaque enough to read as a surface, which
 * with the sidebar transparency up means painting over the wallpaper; a rule
 * costs two pixels and says the same thing.
 *
 * Hover is a faint neutral wash, never the accent: the accent means "this is
 * the conversation you are in" and nothing else may borrow it.
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

    implicitHeight: 30
    buttonRadius: Appearance.rounding.verysmall
    toggled: root.current
    // The current tab gets no fill of its own: hover looks the same whichever
    // tab the pointer is over, which is what makes the rule below the only
    // thing that marks the current one.
    colBackground: "transparent"
    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.45)
    colBackgroundToggled: "transparent"
    colBackgroundToggledHover: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.45)
    colRipple: Appearance.colors.colLayer1Active
    colRippleToggled: Appearance.colors.colLayer1Active
    onClicked: ClaudeCode.activateTab(root.tabIndex)
    // Closing without switching to the tab first, the way a browser does it.
    middleClickAction: () => ClaudeCode.closeTab(root.tabIndex)

    Rectangle { // The rule under the current conversation
        // A child of the button rather than of its background, so the hover
        // wash cannot tint it.
        visible: root.current
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 2
        radius: height / 2
        color: Appearance.colors.colPrimary
    }

    contentItem: RowLayout {
        anchors {
            fill: parent
            leftMargin: 8
            // The close button sits over the right edge, so the label has to
            // stop eliding before it reaches it.
            rightMargin: closeButton.visible ? 22 : 8
            // Clear of the rule: text sitting on it reads as underlined text.
            bottomMargin: 2
        }
        spacing: 5

        Rectangle { // What this tab wants, if anything
            id: statusDot
            visible: root.needsInput || root.busy || root.unseen
            implicitWidth: 6
            implicitHeight: 6
            radius: width / 2
            color: root.needsInput ? Appearance.m3colors.m3error
                : root.busy ? Appearance.colors.colPrimary
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
            font.pixelSize: Appearance.font.pixelSize.small * ClaudeCode.textScale
            font.weight: root.current ? Font.DemiBold : Font.Normal
            color: root.current ? Appearance.colors.colPrimary
                : root.hovered ? Appearance.colors.colOnLayer1
                : Appearance.colors.colSubtext
            text: root.label

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
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
            rightMargin: 4
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: -1
        }
        implicitWidth: 16
        implicitHeight: 16

        MaterialSymbol {
            anchors.centerIn: parent
            iconSize: 14
            opacity: (root.current || closeArea.containsMouse) ? 1 : 0.6
            color: root.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
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
