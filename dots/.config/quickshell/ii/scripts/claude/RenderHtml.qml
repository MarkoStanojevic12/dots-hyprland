import QtQuick
import QtQuick.Window
import QtWebEngine

/**
 * Headless page-to-PNG for render-html.sh. Loads the file, grows to the
 * document's height, grabs the result and quits. Non-zero exit on failure.
 * Arguments after "--": <html file> <out.png> <width>
 */
Window {
    id: root
    readonly property var args: Qt.application.arguments
    readonly property int split: root.args.indexOf("--")
    readonly property string file: root.split >= 0 ? (root.args[root.split + 1] ?? "") : ""
    readonly property string out: root.split >= 0 ? (root.args[root.split + 2] ?? "") : ""
    readonly property int pageWidth: Math.max(200, parseInt(root.args[root.split + 3] ?? "460") || 460)

    width: root.pageWidth
    height: 600
    visible: true
    color: "white"

    function fail(reason) {
        console.warn("render-html:", reason);
        Qt.exit(2);
    }

    Timer {
        interval: 15000
        running: true
        onTriggered: root.fail("timed out")
    }

    // Lets late layout, fonts and first-frame scripts land before the grab.
    Timer {
        id: settle
        interval: 250
        onTriggered: view.grabToImage(result => {
            if (result.saveToFile(root.out)) Qt.quit();
            else root.fail("could not save " + root.out);
        })
    }

    WebEngineView {
        id: view
        width: root.pageWidth
        height: root.height
        url: root.file.length > 0 ? `file://${root.file}` : ""
        backgroundColor: "white"
        onLoadingChanged: info => {
            if (info.status === WebEngineView.LoadFailedStatus) root.fail("load failed: " + info.errorString);
            if (info.status !== WebEngineView.LoadSucceededStatus) return;
            view.runJavaScript("Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)", h => {
                const height = Math.min(2400, Math.max(80, Number(h) || 0));
                root.height = height;
                view.height = height;
                settle.start();
            });
        }
    }
}
