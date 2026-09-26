pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Screen recording state. The record script detaches wf-recorder, so the only
 * way to know whether a recording is running is to look for the process.
 */
Singleton {
    id: root

    property bool recording: false
    readonly property string savePath: Config.options.screenRecord.savePath.length > 0 ?
        Config.options.screenRecord.savePath : FileUtils.trimFileProtocol(Directories.videos)

    // The record script reads these from the config itself, so every entry point
    // (bar button, keybinds, region selector) picks up the same setting.
    readonly property bool desktopAudio: Config.options.screenRecord.desktopAudio
    readonly property bool microphone: Config.options.screenRecord.microphone

    function toggle() {
        Quickshell.execDetached([Directories.recordScriptPath]);
        settleTimer.restart();
    }

    function toggleDesktopAudio() {
        Config.options.screenRecord.desktopAudio = !Config.options.screenRecord.desktopAudio;
    }

    function toggleMicrophone() {
        Config.options.screenRecord.microphone = !Config.options.screenRecord.microphone;
    }

    function openFolder() {
        Quickshell.execDetached(["dolphin", root.savePath]);
    }

    function refresh() {
        if (!checkProcess.running)
            checkProcess.running = true;
    }

    Process {
        id: checkProcess
        command: ["pidof", "wf-recorder"]
        onExited: (exitCode, exitStatus) => root.recording = (exitCode === 0)
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: settleTimer
        interval: 300
        onTriggered: root.refresh()
    }
}
