import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import org.kde.syntaxhighlighting

/**
 * Line-level diff for an Edit or Write tool call.
 *
 * A plain longest-common-subsequence over lines: enough to see what actually
 * changed in a narrow column, without pulling in a diff library. Bounded in
 * both directions so a huge write can't stall the sidebar.
 *
 * The file itself is read from disk to place the snippet: that is where the
 * line numbers and the greyed context lines around the change come from.
 * Shown side by side by default, old on the left and new on the right, with
 * filler rows keeping the two in step and the changed words marked; a toggle
 * flips it to a unified view. The code is syntax-highlighted from the file's
 * extension, the same way the chat's code blocks are.
 */
ColumnLayout {
    id: root
    property string oldText: ""
    property string newText: ""
    property string filePath: ""
    // The tool call's status; the file is read again once the edit has landed.
    property string status: "done"
    property bool split: true
    // Diffing is O(n*m); past this the file gets shown as a plain addition.
    readonly property int lineBudget: 400
    readonly property int shownLimit: 120
    property int contextAbove: 3
    property int contextBelow: 3
    readonly property int contextStep: 10

    // Invalid (no match for the extension) simply highlights nothing.
    readonly property var definition: Repository.definitionForFileName(root.filePath)
    readonly property string languageName: String(root.definition?.name ?? "")
    readonly property string fileName: root.filePath.split("/").filter(part => part.length > 0).pop() ?? ""

    // ------------------------------------------------------------------
    // The file on disk
    // ------------------------------------------------------------------

    property string fileText: ""

    FileView {
        id: file
        path: root.filePath
        printErrors: false
        onLoaded: root.fileText = file.text()
        onLoadFailed: root.fileText = ""
    }
    onStatusChanged: if (root.status === "done" && root.filePath.length > 0) file.reload()

    // Where the snippet sits: its first line, 1-based, and the file's lines
    // above and below it. The new text is looked for first (the edit has
    // landed), then the old (it hasn't yet). A Write is the whole file.
    readonly property var anchor: {
        const text = root.fileText;
        if (text.length === 0) return null;
        const fileLines = text.split("\n");
        if (root.oldText.length === 0) return { startLine: 1, above: [], below: [] };
        for (const snippet of [root.newText, root.oldText]) {
            if (snippet.length === 0) continue;
            const at = text.indexOf(snippet);
            if (at === -1) continue;
            const startLine = text.slice(0, at).split("\n").length;
            const endLine = startLine + snippet.replace(/\n$/, "").split("\n").length - 1;
            return { startLine, above: fileLines.slice(0, startLine - 1), below: fileLines.slice(endLine) };
        }
        return null;
    }
    readonly property bool numbered: root.anchor !== null
    readonly property var contextBefore: root.anchor ? root.anchor.above.slice(Math.max(0, root.anchor.above.length - root.contextAbove)) : []
    readonly property var contextAfter: root.anchor ? root.anchor.below.slice(0, root.contextBelow) : []
    readonly property int hiddenAbove: root.anchor ? root.anchor.above.length - root.contextBefore.length : 0
    readonly property int hiddenBelow: root.anchor ? root.anchor.below.length - root.contextAfter.length : 0

    // ------------------------------------------------------------------
    // The diff
    // ------------------------------------------------------------------

    readonly property var diffLines: {
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

    // Context, diff, context — each row numbered on the old and new side.
    readonly property var lines: {
        const rows = [];
        const firstLine = (root.anchor?.startLine ?? 1) - root.contextBefore.length;
        let oldNumber = firstLine;
        let newNumber = firstLine;
        const push = (sign, text, context) => {
            rows.push({
                sign, text, context,
                oldNumber: root.numbered && sign !== "+" ? oldNumber : null,
                newNumber: root.numbered && sign !== "-" ? newNumber : null
            });
            if (sign !== "+") oldNumber++;
            if (sign !== "-") newNumber++;
        };
        for (const text of root.contextBefore) push(" ", text, true);
        for (const line of root.diffLines) push(line.sign, line.text, false);
        for (const text of root.contextAfter) push(" ", text, true);
        return rows;
    }

    // Which parts of two paired lines actually differ, as character ranges on
    // each side: a longest-common-subsequence over word, space and punctuation
    // tokens, with the tokens left out of it marked. Lines with nothing in
    // common get no ranges; the row tint already says all of it changed.
    function tokenize(text) {
        return text.match(/\w+|\s+|[^\w\s]/g) ?? [];
    }

    function changedSpans(before, after) {
        const a = root.tokenize(before);
        const b = root.tokenize(after);
        if (a.length === 0 || b.length === 0 || a.length * b.length > 40000) return [[], []];

        const table = [];
        for (let i = 0; i <= a.length; i++) table.push(new Array(b.length + 1).fill(0));
        for (let i = a.length - 1; i >= 0; i--) {
            for (let j = b.length - 1; j >= 0; j--) {
                table[i][j] = a[i] === b[j] ? table[i + 1][j + 1] + 1 : Math.max(table[i + 1][j], table[i][j + 1]);
            }
        }
        const keptA = new Array(a.length).fill(false);
        const keptB = new Array(b.length).fill(false);
        let kept = 0;
        let i = 0;
        let j = 0;
        while (i < a.length && j < b.length) {
            if (a[i] === b[j]) {
                keptA[i] = keptB[j] = true;
                if (a[i].trim().length > 0) kept++;
                i++;
                j++;
            } else if (table[i + 1][j] >= table[i][j + 1]) i++;
            else j++;
        }
        if (kept === 0) return [[], []];

        const spansOf = (tokens, keptFlags) => {
            const spans = [];
            let offset = 0;
            for (let k = 0; k < tokens.length; k++) {
                const end = offset + tokens[k].length;
                if (!keptFlags[k]) {
                    const last = spans[spans.length - 1];
                    if (last && last.end === offset) last.end = end;
                    else spans.push({ start: offset, end: end });
                }
                offset = end;
            }
            return spans;
        };
        return [spansOf(a, keptA), spansOf(b, keptB)];
    }

    // The unified lines folded into rows of [old, new]. A run of removals
    // followed by additions is paired up line for line; whichever side is
    // shorter gets filler rows so the two columns stay aligned.
    readonly property var pairs: {
        const filler = { sign: "", text: "", context: false, oldNumber: null, newNumber: null };
        const rows = [];
        let removed = [];
        let added = [];
        const flush = () => {
            const count = Math.max(removed.length, added.length);
            for (let k = 0; k < count; k++) {
                let left = removed[k] ?? filler;
                let right = added[k] ?? filler;
                if (removed[k] && added[k]) {
                    const [leftSpans, rightSpans] = root.changedSpans(left.text, right.text);
                    left = Object.assign({}, left, { spans: leftSpans });
                    right = Object.assign({}, right, { spans: rightSpans });
                }
                rows.push({ left, right });
            }
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
    readonly property int addedCount: root.diffLines.filter(line => line.sign === "+").length
    readonly property int removedCount: root.diffLines.filter(line => line.sign === "-").length
    readonly property int numberDigits: String(Math.max(1, root.lines.reduce((most, line) => Math.max(most, line.oldNumber ?? 0, line.newNumber ?? 0), 0))).length

    // ------------------------------------------------------------------
    // Presentation
    // ------------------------------------------------------------------

    // Long lines scroll sideways, both columns together, rather than wrapping
    // and putting the two sides out of step.
    property real scrollX: 0
    readonly property real maxScrollX: diffLoader.item?.overflow ?? 0
    onMaxScrollXChanged: root.scrollX = Math.min(root.scrollX, root.maxScrollX)

    TextMetrics {
        id: metrics
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.small
        text: "0"
    }

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
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideLeft
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            text: root.fileName
        }
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

    // A row that reveals more of the file above or below the change.
    component ContextButton: RippleButton {
        id: contextButton
        property int hidden: 0
        property string icon: "expand_less"
        Layout.fillWidth: true
        visible: contextButton.hidden > 0
        implicitHeight: 20
        buttonRadius: Appearance.rounding.verysmall

        contentItem: RowLayout {
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: contextButton.icon
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: Translation.tr("%1 more lines").arg(Math.min(root.contextStep, contextButton.hidden))
            }
        }
    }

    // One column of code: line numbers (and signs) in a fixed gutter, the
    // text beside it scrolling sideways, tinted rows behind and the changed
    // words marked. Rows are all one height (monospace at one size,
    // unwrapped), so everything is laid out by index.
    component DiffColumn: Item {
        id: column
        required property var rows
        property var numberKeys: ["oldNumber"]
        property bool showSigns: false
        readonly property real numberWidth: root.numbered ? root.numberDigits * metrics.advanceWidth : 0
        readonly property real gutterWidth: 4
            + (root.numbered ? column.numberKeys.length * (column.numberWidth + 6) : 0)
            + (column.showSigns ? metrics.advanceWidth + 6 : 0)
        readonly property real overflow: Math.max(0, columnText.contentWidth + 8 - viewport.width)
        implicitHeight: columnText.contentHeight + 2
        readonly property real rowHeight: columnText.contentHeight / Math.max(1, columnText.lineCount)

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

        Row { // Gutter
            x: 4
            y: 1
            spacing: 6

            Repeater {
                model: root.numbered ? column.numberKeys : []

                Column {
                    id: numberColumn
                    required property var modelData

                    Repeater {
                        model: column.rows

                        StyledText {
                            required property var modelData
                            width: column.numberWidth
                            height: column.rowHeight
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                            text: modelData[numberColumn.modelData] ?? ""
                        }
                    }
                }
            }

            Column {
                visible: column.showSigns

                Repeater {
                    model: column.rows

                    StyledText {
                        required property var modelData
                        width: metrics.advanceWidth
                        height: column.rowHeight
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.monospace
                        color: root.signColor(modelData.sign)
                        text: modelData.sign
                    }
                }
            }
        }

        Item { // The code, scrolling sideways under the gutter
            id: viewport
            x: column.gutterWidth
            width: column.width - column.gutterWidth
            height: column.height
            clip: true

            Item {
                id: scroller
                x: -root.scrollX
                width: columnText.contentWidth + 8
                height: parent.height

                // The changed parts within a row, as document positions, so
                // they can be placed with the text's own layout.
                readonly property var changed: {
                    const marks = [];
                    let offset = 0;
                    for (const row of column.rows) {
                        for (const span of (row.spans ?? [])) {
                            marks.push({ sign: row.sign, start: offset + span.start, end: offset + span.end });
                        }
                        offset += row.text.length + 1;
                    }
                    return marks;
                }

                Repeater {
                    model: scroller.changed

                    Rectangle {
                        id: mark
                        required property var modelData
                        readonly property rect startRect: {
                            const layout = columnText.contentWidth + columnText.contentHeight;
                            return columnText.positionToRectangle(mark.modelData.start);
                        }
                        readonly property rect endRect: {
                            const layout = columnText.contentWidth + columnText.contentHeight;
                            return columnText.positionToRectangle(mark.modelData.end);
                        }
                        x: columnText.x + mark.startRect.x
                        y: columnText.y + mark.startRect.y
                        width: Math.max(2, mark.endRect.x - mark.startRect.x)
                        height: mark.startRect.height
                        radius: 2
                        color: mark.modelData.sign === "+"
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
                            : ColorUtils.transparentize(Appearance.m3colors.m3error, 0.6)
                    }
                }

                TextEdit {
                    id: columnText
                    x: 4
                    y: 1
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
        }

        Repeater { // Context rows sit back, so the change itself stands out
            model: column.rows

            Rectangle {
                required property var modelData
                required property int index
                visible: modelData.context === true
                width: column.width
                y: index * column.rowHeight + 1
                height: column.rowHeight
                color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.5)
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

            RowLayout { // Column headers
                Layout.fillWidth: true
                Layout.bottomMargin: 2
                visible: root.split
                spacing: 7

                Repeater {
                    model: [Translation.tr("Before"), Translation.tr("After")]

                    StyledText {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.leftMargin: 4
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                        text: modelData
                    }
                }
            }

            ContextButton {
                hidden: root.hiddenAbove
                icon: "expand_less"
                onClicked: root.contextAbove += root.contextStep
            }

            Loader {
                id: diffLoader
                Layout.fillWidth: true
                sourceComponent: root.split ? splitView : unifiedView
            }

            ContextButton {
                hidden: root.hiddenBelow
                icon: "expand_more"
                onClicked: root.contextBelow += root.contextStep
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

        MouseArea { // Sideways wheel or Shift+wheel scrolls the code; the rest passes through
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                let delta = wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x * 1.5 : wheel.angleDelta.x / 2;
                if (delta === 0 && (wheel.modifiers & Qt.ShiftModifier)) delta = wheel.angleDelta.y / 2;
                if (delta === 0 || root.maxScrollX <= 0) {
                    wheel.accepted = false;
                    return;
                }
                root.scrollX = Math.min(Math.max(root.scrollX - delta, 0), root.maxScrollX);
            }
        }
    }

    Component { // Old on the left, new on the right, row for row
        id: splitView

        RowLayout {
            readonly property real overflow: Math.max(leftColumn.overflow, rightColumn.overflow)
            spacing: 0

            DiffColumn {
                id: leftColumn
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                numberKeys: ["oldNumber"]
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
                id: rightColumn
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                numberKeys: ["newNumber"]
                rows: root.shownPairs.map(pair => pair.right)
            }
        }
    }

    Component { // Every line in one column, both numbers and the sign in the gutter
        id: unifiedView

        Item {
            readonly property real overflow: unifiedColumn.overflow
            implicitHeight: unifiedColumn.implicitHeight

            DiffColumn {
                id: unifiedColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                numberKeys: ["oldNumber", "newNumber"]
                showSigns: true
                rows: root.shownLines
            }
        }
    }
}
