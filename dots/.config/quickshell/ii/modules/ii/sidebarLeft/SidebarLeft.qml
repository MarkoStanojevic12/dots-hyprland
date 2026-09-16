import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool detach: false
    property bool pin: false
    property Component contentComponent: SidebarLeftContent {}
    property Item sidebarContent

    function toggleDetach() {
        root.detach = !root.detach;
    }

    Process { // Dodge cursor away, pin, move cursor back
        id: pinWithFunnyHyprlandWorkaroundProc
        property var hook: null
        property int cursorX;
        property int cursorY;
        function doIt() {
            command = ["hyprctl", "cursorpos"]
            hook = (output) => {
                cursorX = parseInt(output.split(",")[0]);
                cursorY = parseInt(output.split(",")[1]);
                doIt2();
            }
            running = true;
        }
        function doIt2(output) {
            command = ["bash", "-c", "hyprctl dispatch 'hl.dsp.cursor.move({x=9999,y=9999})'"];
            hook = () => {
                doIt3();
            }
            running = true;
        }
        function doIt3(output) {
            root.pin = !root.pin;
            command = ["bash", "-c", `sleep 0.01; hyprctl dispatch 'hl.dsp.cursor.move({x=${cursorX},y=${cursorY}})'`];
            hook = null
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                pinWithFunnyHyprlandWorkaroundProc.hook(text);
            }
        }
    }

    function togglePin() {
        if (!root.pin) pinWithFunnyHyprlandWorkaroundProc.doIt()
        else root.pin = !root.pin;
    }

    // Persisted so the sidebar comes back locked across restarts
    readonly property bool lock: Config.options.sidebar.lockLeft

    function toggleLock() {
        Config.options.sidebar.lockLeft = !Config.options.sidebar.lockLeft;
    }

    Component.onCompleted: {
        root.sidebarContent = contentComponent.createObject(null, {
            "scopeRoot": root,
        });
        sidebarLoader.item.contentParent.children = [root.sidebarContent];
    }

    onDetachChanged: {
        if (root.detach) {
            GlobalFocusGrab.removeDismissable(sidebarLoader.item) // Remove sidebar from the focus grab system
            sidebarContent.parent = null; // Detach content from sidebar
            sidebarLoader.active = false; // Unload sidebar
            detachedSidebarLoader.active = true; // Load detached window
            detachedSidebarLoader.item.contentParent.children = [sidebarContent];
        } else {
            sidebarContent.parent = null; // Detach content from window
            detachedSidebarLoader.active = false; // Unload detached window
            sidebarLoader.active = true; // Load sidebar
            sidebarLoader.item.contentParent.children = [sidebarContent];
        }
    }

    Loader {
        id: sidebarLoader
        active: true
        
        sourceComponent: PanelWindow { // Window
            id: panelWindow
            // Hyprland draws a closing layer from a snapshot, and snapshots are
            // never blurred -- so letting it play its own slide-out dropped the
            // glass the instant the sidebar started to leave. The panel slides
            // out here instead, while the surface is still mapped and still
            // blurred, and the surface unmaps only once it is gone.
            // Deliberately not bound to GlobalStates: a binding re-evaluates
            // before the handler below runs, so the surface unmapped for an
            // instant and Hyprland took its unblurred snapshot anyway.
            visible: panelWindow.shown
            property bool shown: false
            property bool closing: false
            property real slideOffset: 0
            readonly property real hiddenOffset: -(sidebarLeftBackground.width + Appearance.sizes.hyprlandGapsOut * 2)

            Component.onCompleted: panelWindow.shown = GlobalStates.sidebarLeftOpen

            // Hyprland's layer animations are off for this namespace (see
            // hypr/hyprland/rules.lua). Its slide-out ran *after* this one, on
            // the snapshot it takes at unmap, which brought the panel back for
            // a moment before it finally went. Both directions live here now,
            // keeping Hyprland's old timings: 270ms emphasizedDecel in,
            // 240ms menu_accel out.
            NumberAnimation {
                id: openSlide
                target: panelWindow
                property: "slideOffset"
                to: 0
                duration: 270
                easing.type: Easing.Bezier
                easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1, 1]
            }

            NumberAnimation {
                id: closeSlide
                target: panelWindow
                property: "slideOffset"
                duration: 240
                easing.type: Easing.Bezier
                easing.bezierCurve: [0.52, 0.03, 0.72, 0.08, 1, 1]
                onFinished: {
                    panelWindow.closing = false;
                    panelWindow.shown = false;
                }
            }

            Connections {
                target: GlobalStates
                function onSidebarLeftOpenChanged() {
                    if (GlobalStates.sidebarLeftOpen) {
                        closeSlide.stop();
                        panelWindow.closing = false;
                        // Reopened mid-close it carries on from where it is;
                        // from a standing start it comes in from off screen.
                        if (!panelWindow.shown) {
                            panelWindow.slideOffset = panelWindow.hiddenOffset;
                            panelWindow.shown = true;
                        }
                        openSlide.restart();
                    } else if (panelWindow.shown) {
                        // The grab goes now, not when the surface finally
                        // unmaps, or the next click lands on a panel that is
                        // already on its way out.
                        openSlide.stop();
                        GlobalFocusGrab.removeDismissable(panelWindow);
                        closeSlide.to = panelWindow.hiddenOffset;
                        panelWindow.closing = true;
                        closeSlide.restart();
                    }
                }
            }

            property bool extend: false
            property bool resizing: false
            property real dragWidth: 0
            readonly property real configuredWidth: panelWindow.extend ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidthLeft
            // Follow the pointer while dragging, the saved value otherwise
            property real sidebarWidth: panelWindow.resizing ? panelWindow.dragWidth : panelWindow.configuredWidth
            property var contentParent: sidebarLeftBackground

            // Drag writes back to whichever width is currently on screen
            function commitWidth(w) {
                const rounded = Math.round(w);
                if (panelWindow.extend) Config.options.sidebar.widthLeftExtended = rounded;
                else Config.options.sidebar.widthLeft = rounded;
            }

            function hide() {
                GlobalStates.sidebarLeftOpen = false
            }

            exclusionMode: ExclusionMode.Normal
            // Dropped as soon as the slide-out starts, so pinned windows begin
            // reflowing at the same moment they did when the surface unmapped.
            exclusiveZone: (root.pin && !panelWindow.closing) ? sidebarWidth : 0
            implicitWidth: Appearance.sizes.sidebarLeftMaxWidth + Appearance.sizes.elevationMargin
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            // Hyprland 0.49: OnDemand is Exclusive, Exclusive just breaks click-outside-to-close
            // Which also means an open sidebar eats every keystroke, so anything
            // sending synthetic input elsewhere has to make it drop the keyboard
            // outright — focusing another window is not enough.
            // Focus is let go the moment it starts closing: a surface that is
            // only still mapped for its animation must not eat keystrokes.
            WlrLayershell.keyboardFocus: (GlobalStates.sidebarLeftYieldKeyboard || panelWindow.closing)
                ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                top: true
                left: true
                bottom: true
            }

            // While dragging, claim the whole window so pointer motion past the
            // panel edge still reaches the resize handle
            mask: Region {
                item: panelWindow.resizing ? null : sidebarLeftBackground
                width: panelWindow.resizing ? panelWindow.width : 0
                height: panelWindow.resizing ? panelWindow.height : 0
            }

            onVisibleChanged: {
                if (visible) {
                    GlobalFocusGrab.addDismissable(panelWindow);
                } else {
                    GlobalFocusGrab.removeDismissable(panelWindow);
                }
            }
            // A dismiss we ignored still dropped us from the grab list, so an
            // open sidebar has to re-register on unlock or click-outside stays dead
            Connections {
                target: root
                function onLockChanged() {
                    if (!root.lock && panelWindow.visible) {
                        GlobalFocusGrab.addDismissable(panelWindow);
                    }
                }
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    // Locked: stay put and close only on Esc or the toggle shortcut.
                    // The registration above is kept either way so the sidebar still
                    // takes keyboard focus when opened.
                    if (root.lock) return;
                    panelWindow.hide();
                }
            }

            // Content
            StyledRectangularShadow {
                target: sidebarLeftBackground
                radius: sidebarLeftBackground.radius
            }
            Rectangle {
                id: sidebarLeftBackground
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: Appearance.sizes.hyprlandGapsOut
                // The margin, not x: the shadow is anchored to this rectangle
                // and has to travel with it.
                anchors.leftMargin: Appearance.sizes.hyprlandGapsOut + panelWindow.slideOffset
                width: panelWindow.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                height: parent.height - Appearance.sizes.hyprlandGapsOut * 2
                // Only the layer-shell panel: the detached window is a normal
                // window, and Hyprland blurs no windows here, so letting it go
                // see-through would just show the raw desktop.
                // Built from the opaque base rather than colLayer0, so the slider
                // is the only thing deciding this panel's alpha even when the
                // shell-wide appearance.transparency is on.
                color: ColorUtils.transparentize(Appearance.colors.colLayer0Base, Config.options.sidebar.transparency)
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

                // Animating during a drag would lag behind the pointer
                Behavior on width {
                    enabled: !panelWindow.resizing
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_O) {
                            panelWindow.extend = !panelWindow.extend;
                        } else if (event.key === Qt.Key_D) {
                            root.toggleDetach();
                        } else if (event.key === Qt.Key_P) {
                            root.togglePin();
                        } else if (event.key === Qt.Key_L) {
                            root.toggleLock();
                        }
                        event.accepted = true;
                    }
                }
            }

            // Drag-to-resize grip. Sibling of the background rect on purpose:
            // anything parented to it gets wiped by `contentParent.children = [...]`
            MouseArea {
                id: resizeHandle
                anchors.right: sidebarLeftBackground.right
                anchors.top: sidebarLeftBackground.top
                anchors.bottom: sidebarLeftBackground.bottom
                width: Appearance.sizes.sidebarResizeHandleWidth
                z: 100

                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.SizeHorCursor
                acceptedButtons: Qt.LeftButton

                property real pressWindowX: 0
                property real startWidth: 0

                function windowX(mouse) {
                    return mapToItem(null, mouse.x, mouse.y).x;
                }

                onPressed: mouse => {
                    startWidth = panelWindow.sidebarWidth;
                    pressWindowX = windowX(mouse);
                    panelWindow.dragWidth = startWidth;
                    panelWindow.resizing = true;
                }

                onPositionChanged: mouse => {
                    if (!panelWindow.resizing) return;
                    const target = startWidth + (windowX(mouse) - pressWindowX);
                    panelWindow.dragWidth = Math.max(Appearance.sizes.sidebarLeftMinWidth, Math.min(Appearance.sizes.sidebarLeftMaxWidth, target));
                }

                onReleased: {
                    if (!panelWindow.resizing) return;
                    panelWindow.commitWidth(panelWindow.dragWidth);
                    panelWindow.resizing = false;
                }

                onCanceled: {
                    if (!panelWindow.resizing) return;
                    panelWindow.commitWidth(panelWindow.dragWidth);
                    panelWindow.resizing = false;
                }

                // Double click resets to the default width
                onDoubleClicked: {
                    panelWindow.resizing = false;
                    panelWindow.commitWidth(panelWindow.extend ? 750 : 460);
                }

                // Subtle grip, only visible when it matters
                Rectangle {
                    anchors.centerIn: parent
                    width: 3
                    height: 42
                    radius: width / 2
                    color: Appearance.colors.colOnLayer0
                    opacity: (resizeHandle.containsMouse || panelWindow.resizing) ? 0.45 : 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }

    Loader {
        id: detachedSidebarLoader
        active: false

        sourceComponent: FloatingWindow {
            id: detachedSidebarRoot
            property var contentParent: detachedSidebarBackground
            color: "transparent"

            visible: GlobalStates.sidebarLeftOpen
            onVisibleChanged: {
                if (!visible) GlobalStates.sidebarLeftOpen = false;
            }
            
            Rectangle {
                id: detachedSidebarBackground
                anchors.fill: parent
                color: Appearance.colors.colLayer0

                Keys.onPressed: (event) => {
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_D) {
                            root.toggleDetach();
                        }
                        event.accepted = true;
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
        }

        function close(): void {
            GlobalStates.sidebarLeftOpen = false
        }

        function open(): void {
            GlobalStates.sidebarLeftOpen = true
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = false;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Detach left sidebar into a window/Attach it back"

        onPressed: {
            root.detach = !root.detach;
        }
    }

}
