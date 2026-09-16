import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth

    PanelWindow {
        id: panelWindow
        // Hyprland draws a closing layer from a snapshot, and snapshots are
        // never blurred -- so its own slide-out dropped the glass the instant
        // the sidebar started to leave. The panel slides out here instead,
        // while the surface is still mapped, and unmaps only once it is gone.
        // Deliberately not bound to GlobalStates: a binding re-evaluates before
        // the handler below runs, so the surface unmapped for an instant and
        // Hyprland took its unblurred snapshot anyway.
        visible: panelWindow.shown
        property bool shown: false
        property bool closing: false
        property real slideOffset: 0
        readonly property real hiddenOffset: panelWindow.width

        Component.onCompleted: panelWindow.shown = GlobalStates.sidebarRightOpen

        function hide() {
            GlobalStates.sidebarRightOpen = false;
        }

        // Hyprland's layer animations are off for this namespace (see
        // hypr/hyprland/rules.lua). Its slide-out ran *after* this one, on the
        // snapshot it takes at unmap, which brought the panel back for a moment
        // before it finally went. Both directions live here now, keeping
        // Hyprland's old timings: 270ms emphasizedDecel in, 240ms menu_accel out.
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
            function onSidebarRightOpenChanged() {
                if (GlobalStates.sidebarRightOpen) {
                    closeSlide.stop();
                    panelWindow.closing = false;
                    // Reopened mid-close it carries on from where it is; from a
                    // standing start it comes in from off screen.
                    if (!panelWindow.shown) {
                        panelWindow.slideOffset = panelWindow.hiddenOffset;
                        panelWindow.shown = true;
                    }
                    openSlide.restart();
                } else if (panelWindow.shown) {
                    openSlide.stop();
                    GlobalFocusGrab.removeDismissable(panelWindow);
                    closeSlide.to = panelWindow.hiddenOffset;
                    panelWindow.closing = true;
                    closeSlide.restart();
                }
            }
        }

        exclusiveZone: 0
        implicitWidth: sidebarWidth
        WlrLayershell.namespace: "quickshell:sidebarRight"
        WlrLayershell.keyboardFocus: (GlobalStates.sidebarRightOpen && !panelWindow.closing)
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            right: true
            bottom: true
        }

        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(panelWindow);
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }
        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                panelWindow.hide();
            }
        }

        Loader {
            id: sidebarContentLoader
            active: GlobalStates.sidebarRightOpen || panelWindow.closing
                || Config?.options.sidebar.keepRightSidebarLoaded
            // A translation rather than a margin: anchors.fill means a margin
            // would squeeze the content instead of moving it.
            transform: Translate { x: panelWindow.slideOffset }
            anchors {
                fill: parent
                margins: Appearance.sizes.hyprlandGapsOut
                leftMargin: Appearance.sizes.elevationMargin
            }
            width: sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
            height: parent.height - Appearance.sizes.hyprlandGapsOut * 2

            focus: GlobalStates.sidebarRightOpen
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    panelWindow.hide();
                }
            }

            sourceComponent: SidebarRightContent {}
        }
    }

    IpcHandler {
        target: "sidebarRight"

        function toggle(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }

        function close(): void {
            GlobalStates.sidebarRightOpen = false;
        }

        function open(): void {
            GlobalStates.sidebarRightOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = true;
        }
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = false;
        }
    }
}
