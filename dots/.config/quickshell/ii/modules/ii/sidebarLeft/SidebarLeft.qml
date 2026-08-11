import qs
import qs.services
import qs.modules.common
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
            visible: GlobalStates.sidebarLeftOpen
            
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
            exclusiveZone: root.pin ? sidebarWidth : 0
            implicitWidth: Appearance.sizes.sidebarLeftMaxWidth + Appearance.sizes.elevationMargin
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            // Hyprland 0.49: OnDemand is Exclusive, Exclusive just breaks click-outside-to-close
            // Which also means an open sidebar eats every keystroke, so anything
            // sending synthetic input elsewhere has to make it drop the keyboard
            // outright — focusing another window is not enough.
            WlrLayershell.keyboardFocus: GlobalStates.sidebarLeftYieldKeyboard
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
                anchors.leftMargin: Appearance.sizes.hyprlandGapsOut
                width: panelWindow.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                height: parent.height - Appearance.sizes.hyprlandGapsOut * 2
                color: Appearance.colors.colLayer0
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
