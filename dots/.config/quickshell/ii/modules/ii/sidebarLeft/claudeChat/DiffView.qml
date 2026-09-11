import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import org.kde.syntaxhighlighting

/**
 * Line-level diff for an Edit or Write tool call.
 *
 * A plain longest-common-subsequence over lines: enough to see what actually
 * changed in a narrow column, without pulling in a diff library. Bounded in
 * both directions so a huge write can't stall the sidebar.
 *
 * The code is syntax-highlighted from the file's extension, the same way the
 * chat's code blocks are, with the added and removed rows tinted behind it.
 */
ColumnLayout {
    id: root
    property string oldText: ""
    property string newText: ""
    property string filePath: ""
    // Diffing is O(n*m); past this the file gets shown as a plain addition.
    readonly property int lineBudget: 400
    readonly property int shownLimit: 60

    // Invalid (no match for the extension) simply highlights nothing.
    readonly property var definition: Repository.definitionForFileName(root.filePath)
    readonly property string languageName: String(root.definition?.name ?? "")

    readonly property var lines: {
        const before = root.oldText.length > 0 ? root.oldText.split("\n") : [];
        const after = root.newText.length > 0 ? root.newText.split("\n") : [];
        if (before.length === 0) return after.map(text => ({ sign: "+", text: text }));
        if (before.length > root.lineBudget || after.length > root.lineBudget) {
            return after.map(text => ({ sign: " ", text: text }));
        }

        // Longest common subsequence table over lines.
        const table = [];
        for (let i = 0; i <= before.length; i++) table.push(new Array(after.length + 1).fill(0));
        for (let i = before.length - 1; i >= 0; i--) {
            for (let j = after.length - 1; j >= 0; j--) {
                table[i][j] = before[i] === after[j]
                    ? table[i + 1][j + 1] + 1
                    : Math.max(table[i + 1][j], table[i][j + 1]);
            }
        }

        const result = [];
        let i = 0;
        let j = 0;
        while (i < before.length && j < after.length) {
            if (before[i] === after[j]) {
                result.push({ sign: " ", text: before[i] });
                i++;
                j++;
            } else if (table[i + 1][j] >= table[i][j + 1]) {
                result.push({ sign: "-", text: before[i] });
                i++;
            } else {
                result.push({ sign: "+", text: after[j] });
                j++;
            }
        }
        while (i < before.length) result.push({ sign: "-", text: before[i++] });
        while (j < after.length) result.push({ sign: "+", text: after[j++] });
        return result;
    }

    readonly property var shownLines: root.lines.slice(0, root.shownLimit)
    readonly property int addedCount: root.lines.filter(line => line.sign === "+").length
    readonly property int removedCount: root.lines.filter(line => line.sign === "-").length

    function signColor(sign) {
        return sign === "+" ? Appearance.colors.colPrimary
            : sign === "-" ? Appearance.m3colors.m3error
            : Appearance.colors.colSubtext;
    }

    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 2
        spacing: 8

        StyledText {
            visible: root.addedCount > 0
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colPrimary
            text: `+${root.addedCount}`
        }
        StyledText {
            visible: root.removedCount > 0
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.m3colors.m3error
            text: `-${root.removedCount}`
        }
        Item { Layout.fillWidth: true }
        StyledText {
            visible: root.languageName.length > 0 && root.languageName !== "None"
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            text: root.languageName
        }
    }

    CopyableBox {
        Layout.fillWidth: true
        implicitHeight: diffColumn.implicitHeight + 8
        clip: true
        // The text as it will exist afterwards, not the +/- rendering — the
        // marked-up version is for reading, and pasting it anywhere would just
        // mean stripping the signs back off. Copies in full even when the view
        // above is cut off at shownLimit.
        copyText: root.newText
        hint: Translation.tr("Click to copy the new text")

        ColumnLayout {
            id: diffColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 4
            }
            spacing: 0

            Item { // One row per line: tint behind, sign in the gutter, code beside
                id: rows
                Layout.fillWidth: true
                implicitHeight: diffText.contentHeight + 2
                // Monospace at one size, unwrapped, so every row is the same height.
                readonly property real rowHeight: diffText.contentHeight / Math.max(1, diffText.lineCount)

                Repeater {
                    model: root.shownLines

                    Rectangle {
                        required property var modelData
                        required property int index
                        width: rows.width
                        y: index * rows.rowHeight + 1
                        height: rows.rowHeight
                        radius: Appearance.rounding.verysmall
                        color: modelData.sign === "+" ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
                            : modelData.sign === "-" ? ColorUtils.transparentize(Appearance.m3colors.m3error, 0.85)
                            : "transparent"
                    }
                }

                Column {
                    x: 4
                    y: 1

                    Repeater {
                        model: root.shownLines

                        StyledText {
                            required property var modelData
                            height: rows.rowHeight
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: root.signColor(modelData.sign)
                            text: modelData.sign
                        }
                    }
                }

                TextEdit {
                    id: diffText
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        leftMargin: 16
                        rightMargin: 4
                        topMargin: 1
                    }
                    readOnly: true
                    // Clicks belong to the copy box around it.
                    enabled: false
                    wrapMode: TextEdit.NoWrap
                    textFormat: TextEdit.PlainText
                    renderType: Text.NativeRendering
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    font.hintingPreference: Font.PreferNoHinting
                    color: Appearance.colors.colOnLayer1
                    text: root.shownLines.map(line => line.text).join("\n")

                    SyntaxHighlighter {
                        textEdit: diffText
                        repository: Repository
                        definition: root.definition
                        theme: Appearance.syntaxHighlightingTheme
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: root.lines.length > root.shownLimit
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: Translation.tr("…and %1 more lines").arg(root.lines.length - root.shownLimit)
            }
        }
    }
}
