import qs.modules.common
import qs.modules.common.functions
import QtQuick

/**
 * Find-in-chat highlights for one TextEdit. Drawn over the rendered text so
 * the markdown underneath stays untouched.
 *
 * Matches are numbered from `ordinalBase` so a message with several text
 * blocks can tell which of its matches is the one navigated to.
 */
Item {
    id: root
    required property Item textEdit
    property string query: ""
    property int ordinalBase: 0
    property int current: -1
    readonly property int matchCount: root.matches.length
    signal currentMatchAt(real y)

    anchors.fill: parent

    readonly property var matches: {
        const query = root.query.toLowerCase();
        if (query.length === 0) return [];
        // Read for the dependency only; the document is what's searched.
        const rendered = root.textEdit.text;
        const haystack = root.textEdit.getText(0, root.textEdit.length).toLowerCase();
        const found = [];
        let at = haystack.indexOf(query);
        while (at !== -1) {
            found.push({ start: at, end: at + query.length });
            at = haystack.indexOf(query, at + query.length);
        }
        return found;
    }

    // Rewrapping moves every match, and nothing else here observes the layout.
    readonly property real layoutVersion: root.textEdit.width + root.textEdit.contentHeight

    Repeater {
        model: root.matches

        Rectangle {
            id: mark
            required property var modelData
            required property int index
            readonly property bool isCurrent: root.ordinalBase + index === root.current
            readonly property rect startRect: {
                const version = root.layoutVersion;
                return root.textEdit.positionToRectangle(mark.modelData.start);
            }
            readonly property rect endRect: {
                const version = root.layoutVersion;
                return root.textEdit.positionToRectangle(mark.modelData.end);
            }
            readonly property bool oneLine: Math.abs(mark.endRect.y - mark.startRect.y) < 1

            x: mark.startRect.x
            y: mark.startRect.y
            width: mark.oneLine ? Math.max(mark.endRect.x - mark.startRect.x, 4) : root.textEdit.width - mark.startRect.x
            height: mark.startRect.height
            radius: 3
            color: ColorUtils.transparentize(Appearance.colors.colTertiary, mark.isCurrent ? 0.55 : 0.8)
            border.width: mark.isCurrent ? 1 : 0
            border.color: Appearance.colors.colTertiary

            onIsCurrentChanged: if (mark.isCurrent) root.currentMatchAt(mark.y)
            onYChanged: if (mark.isCurrent) root.currentMatchAt(mark.y)
            Component.onCompleted: if (mark.isCurrent) root.currentMatchAt(mark.y)
        }
    }
}
