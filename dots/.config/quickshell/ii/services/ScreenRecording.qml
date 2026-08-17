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

    function toggle() {
        Quickshell.execDetached([Directories.recordScriptPath]);
        settleTimer.restart();
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
