import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * Line-level diff for an Edit or Write tool call.
 *
 * A plain longest-common-subsequence over lines: enough to see what actually
 * changed in a narrow column, without pulling in a diff library. Bounded in
 * both directions so a huge write can't stall the sidebar.
 */
ColumnLayout {
    id: root
    property string oldText: ""
    property string newText: ""
    // Diffing is O(n*m); past this the file gets shown as a plain addition.
    readonly property int lineBudget: 400
    readonly property int shownLimit: 60

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

    readonly property int addedCount: root.lines.filter(line => line.sign === "+").length
    readonly property int removedCount: root.lines.filter(line => line.sign === "-").length

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

            Repeater {
                model: root.lines.slice(0, root.shownLimit)

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: lineText.implicitHeight + 2
                    radius: Appearance.rounding.verysmall
                    color: modelData.sign === "+" ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
                        : modelData.sign === "-" ? ColorUtils.transparentize(Appearance.m3colors.m3error, 0.85)
                        : "transparent"

                    StyledText {
                        id: lineText
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 4
                            rightMargin: 4
                        }
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        elide: Text.ElideRight
                        color: parent.modelData.sign === "+" ? Appearance.colors.colPrimary
                            : parent.modelData.sign === "-" ? Appearance.m3colors.m3error
                            : Appearance.colors.colSubtext
                        text: `${parent.modelData.sign} ${parent.modelData.text}`
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
