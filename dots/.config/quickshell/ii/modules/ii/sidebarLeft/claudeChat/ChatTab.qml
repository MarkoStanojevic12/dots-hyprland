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
 * Shaped like a browser tab: the current one is an accent surface with a
 * rounded top and bottom corners that flare outwards into the strip's baseline
 * bar. The bar is the same colour, so tab and bar are one shape and the current
 * conversation runs straight into the chat below it rather than sitting on top
 * of it. The others carry no fill at all until hovered.
 */
RippleButton {
    id: root

    required property var session
    required property int tabIndex
    // The strip's hovered tab, so the hairline can be dropped on both sides of
    // it; a tab cannot see its neighbour's hover state on its own.
    property int stripHoveredIndex: -1

    signal hoverRequested(int hoveredTab, bool entered)

    readonly property bool current: root.session === ClaudeCode.active
    readonly property bool previousCurrent: root.tabIndex > 0
        && ClaudeCode.tabs[root.tabIndex - 1] === ClaudeCode.active
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
    // The tab shape below is the whole of this button's fill; RippleButton's own
    // background stays out of the way so it cannot square off the flared corners.
    colBackground: "transparent"
    colBackgroundHover: "transparent"
    colBackgroundToggled: "transparent"
    colBackgroundToggledHover: "transparent"
    colRipple: Appearance.colors.colLayer1Active
    colRippleToggled: Appearance.colors.colPrimaryContainerActive
    onClicked: ClaudeCode.activateTab(root.tabIndex)
    // Closing without switching to the tab first, the way a browser does it.
    middleClickAction: () => ClaudeCode.closeTab(root.tabIndex)
    onHoveredChanged: root.hoverRequested(root.tabIndex, root.hovered)

    Item { // The tab shape
        id: tabShape
        z: -1
        anchors.fill: parent

        // How far the bottom corners flare out to either side. The strip leaves
        // this much margin so the first and last tab's flares are not cut off.
        readonly property int flare: Appearance.rounding.unsharpenmore

        // Not readonly: a Behavior needs to be able to write the property it
        // animates, binding or no binding.
        // The accent container rather than a layer colour: layer 1 is an alpha
        // overlay, so with the sidebar transparency up it left the current tab
        // barely distinguishable from the rest. This one is opaque.
        // Hover is a neutral wash, never the accent: an accent-tinted hover
        // reads as "this tab is selected" while the pointer crosses the strip.
        // The accent belongs to the active conversation and nothing else.
        property color surface: root.current
            ? Appearance.colors.colPrimaryContainer
            : root.hovered ? ColorUtils.transparentize(Appearance.colors.colLayer1, 0.45)
            : ColorUtils.transparentize(Appearance.colors.colLayer1, 1)

        // A little of the accent proper at the top, so the current tab is not a
        // flat slab. The bottom stays exactly the baseline's colour -- that is
        // the edge the two have to meet at without a seam.
        property color surfaceTop: root.current
            ? ColorUtils.mix(Appearance.colors.colPrimary, tabShape.surface, 0.32)
            : tabShape.surface

        Behavior on surface {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on surfaceTop {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Rectangle {
            anchors.fill: parent
            topLeftRadius: Appearance.rounding.verysmall
            topRightRadius: Appearance.rounding.verysmall
            gradient: Gradient {
                GradientStop { position: 0; color: tabShape.surfaceTop }
                GradientStop { position: 1; color: tabShape.surface }
            }
        }

        RoundCorner {
            anchors {
                right: parent.left
                bottom: parent.bottom
            }
            implicitSize: tabShape.flare
            corner: RoundCorner.CornerEnum.BottomRight
            color: tabShape.surface
        }

        RoundCorner {
            anchors {
                left: parent.right
                bottom: parent.bottom
            }
            implicitSize: tabShape.flare
            corner: RoundCorner.CornerEnum.BottomLeft
            color: tabShape.surface
        }
    }

    Rectangle { // Hairline to the tab on the left
        // Neither of the tabs it sits between may be filled: a line running into
        // the side of a surface is the one thing the browsers all avoid.
        visible: root.tabIndex > 0 && !root.current && !root.previousCurrent
            && root.stripHoveredIndex !== root.tabIndex
            && root.stripHoveredIndex !== root.tabIndex - 1
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        width: 1
        height: 16
        color: Appearance.colors.colOutlineVariant
    }

    contentItem: RowLayout {
        anchors {
            fill: parent
            leftMargin: 10
            // The close button sits over the right edge, so the label has to
            // stop eliding before it reaches it.
            rightMargin: closeButton.visible ? 22 : 10
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
            color: root.current ? Appearance.colors.colOnPrimaryContainer
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
            rightMargin: 6
            verticalCenter: parent.verticalCenter
        }
        implicitWidth: 16
        implicitHeight: 16

        MaterialSymbol {
            anchors.centerIn: parent
            iconSize: 14
            opacity: (root.current || closeArea.containsMouse) ? 1 : 0.6
            color: root.current ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
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
