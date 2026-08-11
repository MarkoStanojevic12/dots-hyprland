pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    id: root

    property alias inhibit: idleInhibitor.enabled
    inhibit: false

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.isNewHyprlandInstance) {
                root.inhibit = Persistent.states.idle.inhibit;
            } else {
                Persistent.states.idle.inhibit = root.inhibit;
            }
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    // Hyprland only honours a Wayland idle inhibitor when it can tie it to a
    // real window, and everything the shell draws is a layer surface — so the
    // inhibitor below is created and then ignored (hyprwm/Hyprland#5878).
    // A logind inhibitor doesn't care who asked, and hypridle respects those
    // unless ignore_systemd_inhibit is turned on.
    //
    // The held command is `cat` rather than a sleep: systemd-inhibit passes the
    // lock's fd to its child, so a child that outlives the kill would keep the
    // lock forever. cat sees EOF the moment this pipe closes and exits with it.
    Process {
        id: logindInhibitor
        running: root.inhibit
        stdinEnabled: true
        command: ["systemd-inhibit", "--what=idle", "--who=Quickshell",
                  "--why=Keep awake", "--mode=block", "cat"]
    }

    IdleInhibitor {
        id: idleInhibitor
        window: PanelWindow {
            // Inhibitor requires a "visible" surface
            // Actually not lol
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            // Just in case...
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }
        }
    }
}
