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
 * Shown side by side by default, old on the left and new on the right, with
 * filler rows keeping the two in step; a toggle flips it to a unified view.
 * The code is syntax-highlighted from the file's extension, the same way the
 * chat's code blocks are, with the added and removed rows tinted behind it.
 */
ColumnLayout {
    id: root
    property string oldText: ""
    property string newText: ""
    property string filePath: ""
    property bool split: true
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

    // The unified lines folded into rows of [old, new]. A run of removals
    // followed by additions is paired up line for line; whichever side is
    // shorter gets filler rows so the two columns stay aligned.
    readonly property var pairs: {
        const filler = { sign: "", text: "" };
        const rows = [];
        let removed = [];
        let added = [];
        const flush = () => {
            const count = Math.max(removed.length, added.length);
            for (let k = 0; k < count; k++) rows.push({ left: removed[k] ?? filler, right: added[k] ?? filler });
            removed = [];
            added = [];
        };
        for (const line of root.lines) {
            if (line.sign === "-") removed.push(line);
            else if (line.sign === "+") added.push(line);
            else {
                flush();
                rows.push({ left: line, right: line });
            }
        }
        flush();
        return rows;
    }

    readonly property var shownLines: root.lines.slice(0, root.shownLimit)
    readonly property var shownPairs: root.pairs.slice(0, root.shownLimit)
    readonly property int totalRows: root.split ? root.pairs.length : root.lines.length
    readonly property int addedCount: root.lines.filter(line => line.sign === "+").length
    readonly property int removedCount: root.lines.filter(line => line.sign === "-").length

    function signColor(sign) {
        return sign === "+" ? Appearance.colors.colPrimary
            : sign === "-" ? Appearance.m3colors.m3error
            : Appearance.colors.colSubtext;
    }

    function rowTint(sign) {
        return sign === "+" ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
            : sign === "-" ? ColorUtils.transparentize(Appearance.m3colors.m3error, 0.85)
            : sign === "" ? ColorUtils.transparentize(Appearance.colors.colSubtext, 0.92)
            : "transparent";
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

        RippleButton {
            implicitWidth: 22
            implicitHeight: 22
            buttonRadius: Appearance.rounding.verysmall
            onClicked: root.split = !root.split

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
                text: root.split ? "view_agenda" : "vertical_split"
            }

            StyledToolTip {
                text: root.split ? Translation.tr("Show as one column") : Translation.tr("Show side by side")
            }
        }
    }

    // One column of code with tinted rows behind it. Rows are all one height
    // (monospace at one size, unwrapped), so the tints are laid out by index.
    component DiffColumn: Item {
        id: column
        required property var rows
        property real textLeftMargin: 4
        implicitHeight: columnText.contentHeight + 2
        readonly property real rowHeight: columnText.contentHeight / Math.max(1, columnText.lineCount)
        clip: true

        Repeater {
            model: column.rows

            Rectangle {
                required property var modelData
                required property int index
                width: column.width
                y: index * column.rowHeight + 1
                height: column.rowHeight
                radius: Appearance.rounding.verysmall
                color: root.rowTint(modelData.sign)
            }
        }

        TextEdit {
            id: columnText
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: column.textLeftMargin
                rightMargin: 4
                topMargin: 1
            }
            readOnly: true
            // Clicks belong to the copy box around it.
            enabled: false
            wrapMode: TextEdit.NoWrap
            textFormat: TextEdit.PlainText
            renderType: Text.NativeRendering
            // Same size as the chat's code blocks, so both read alike.
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.monospace
            font.hintingPreference: Font.PreferNoHinting
            color: Appearance.colors.colOnLayer1
            text: column.rows.map(row => row.text).join("\n")

            SyntaxHighlighter {
                textEdit: columnText
                repository: Repository
                definition: root.definition
                theme: Appearance.syntaxHighlightingTheme
            }
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

            Loader {
                Layout.fillWidth: true
                sourceComponent: root.split ? splitView : unifiedView
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: root.totalRows > root.shownLimit
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: Translation.tr("…and %1 more lines").arg(root.totalRows - root.shownLimit)
            }
        }
    }

    Component { // Old on the left, new on the right, row for row
        id: splitView

        RowLayout {
            spacing: 0

            DiffColumn {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                rows: root.shownPairs.map(pair => pair.left)
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.leftMargin: 3
                Layout.rightMargin: 3
                implicitWidth: 1
                color: Appearance.colors.colOutlineVariant
            }

            DiffColumn {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                rows: root.shownPairs.map(pair => pair.right)
            }
        }
    }

    Component { // Every line in one column, signs in the gutter
        id: unifiedView

        Item {
            implicitHeight: unifiedColumn.implicitHeight

            DiffColumn {
                id: unifiedColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                textLeftMargin: 16
                rows: root.shownLines
            }

            Column {
                x: 4
                y: 1

                Repeater {
                    model: root.shownLines

                    StyledText {
                        required property var modelData
                        height: unifiedColumn.rowHeight
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.monospace
                        color: root.signColor(modelData.sign)
                        text: modelData.sign
                    }
                }
            }
        }
    }
}
