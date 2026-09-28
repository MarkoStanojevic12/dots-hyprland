pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Hand-written color themes from ~/.config/illogical-impulse/themes.
 * The index file is written by applytheme.sh --list.
 */
Singleton {
    id: root

    property list<var> list: []
    readonly property string active: Config.options.appearance.palette.customTheme ?? ""

    function refresh() {
        indexProc.running = true;
    }

    function apply(file: string) {
        Quickshell.execDetached([Directories.themeApplyScriptPath, "--apply", file]);
    }

    function clear() {
        Quickshell.execDetached([Directories.themeApplyScriptPath, "--clear"]);
    }

    function exportCurrent(name: string) {
        Quickshell.execDetached([Directories.themeApplyScriptPath, "--export", name]);
    }

    Process {
        id: indexProc
        command: [Directories.themeApplyScriptPath, "--list"]
        onExited: indexFileView.reload()
    }

    FileView {
        id: indexFileView
        path: Qt.resolvedUrl(Directories.generatedThemeIndexPath)
        watchChanges: true
        onFileChanged: reload()
        onLoadedChanged: {
            try {
                root.list = JSON.parse(indexFileView.text());
            } catch (e) {
                root.list = [];
            }
        }
    }

    Component.onCompleted: root.refresh()
}
