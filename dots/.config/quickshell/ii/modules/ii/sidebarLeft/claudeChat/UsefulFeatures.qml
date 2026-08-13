import qs.modules.common
import QtQuick
import Quickshell.Io

/**
 * Saved prompts for the Claude tab, read from
 * ~/.config/illogical-impulse/useful-features.json — deliberately outside this
 * repo, since the prompts are work-specific and this config is public. No file,
 * no features, and the button that opens them stays hidden.
 *
 * [{ title, description, icon, directory, prompt }] — `directory` is optional.
 */
Item {
    id: root

    property var features: []

    // A prompt that only makes sense inside one project is offered only there.
    function forDirectory(directory) {
        return root.features.filter(feature => !feature.directory
            || directory === feature.directory
            || directory.startsWith(feature.directory + "/"));
    }

    FileView {
        id: featuresFile
        path: `${Directories.shellConfig}/useful-features.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(featuresFile.text());
                root.features = Array.isArray(parsed) ? parsed : [];
            } catch (e) {
                console.log("[UsefulFeatures] Could not parse", featuresFile.path, e);
                root.features = [];
            }
        }
        onLoadFailed: root.features = []
    }
}
