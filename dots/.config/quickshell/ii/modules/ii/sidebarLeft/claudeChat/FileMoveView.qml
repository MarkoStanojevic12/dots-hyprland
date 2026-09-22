import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * A file that was moved rather than edited.
 *
 * `mv` says nothing when it works, so the command's output is not what the
 * reader wants — the pair of paths is. The directories the two have in common
 * are dimmed, leaving what actually moved at full strength: a rename inside one
 * folder then reads as a changed name, not as two near-identical lines.
 */
ColumnLayout {
    id: root
    property string from: ""
    property string to: ""

    // `mv file dir/` keeps the name; spelling the result out beats making the
    // reader finish the command in their head.
    readonly property string destination: root.to.endsWith("/")
        ? root.to + (root.from.split("/").pop() ?? "")
        : root.to

    // Only whole directories count as shared — half of a file name is not a
    // path both sides have in common.
    readonly property string shared: {
        let same = 0;
        while (same < root.from.length && same < root.destination.length
            && root.from[same] === root.destination[same]) same++;
        const cut = root.from.slice(0, same).lastIndexOf("/");
        return cut === -1 ? "" : root.from.slice(0, cut + 1);
    }

    function escapeHtml(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function marked(path) {
        const dim = StringUtils.cssColor(Appearance.colors.colSubtext);
        return `<span style="color:${dim}">${root.escapeHtml(root.shared)}</span>`
            + root.escapeHtml(path.slice(root.shared.length));
    }

    spacing: 3

    RowLayout {
        Layout.leftMargin: 2
        spacing: 5

        MaterialSymbol {
            iconSize: Appearance.font.pixelSize.small * ClaudeCode.textScale
            color: Appearance.colors.colSubtext
            text: "drive_file_move"
        }
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smallest * ClaudeCode.textScale
            font.weight: Font.DemiBold
            color: Appearance.colors.colSubtext
            text: Translation.tr("Moved")
        }
    }

    PathRow {
        path: root.from
        arrow: false
    }
    PathRow {
        path: root.destination
        arrow: true
    }

    component PathRow: CopyableBox {
        id: pathRow
        required property string path
        required property bool arrow

        Layout.fillWidth: true
        implicitHeight: pathText.implicitHeight + 10
        copyText: pathRow.path
        hint: Translation.tr("Click to copy the path")

        RowLayout {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 6
                rightMargin: 6
            }
            spacing: 5

            StyledText { // Keeps both rows on one left edge, arrow or not
                Layout.alignment: Qt.AlignTop
                font.pixelSize: Appearance.font.pixelSize.smallest * ClaudeCode.textScale
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colPrimary
                text: pathRow.arrow ? "→" : " "
            }
            StyledText {
                id: pathText
                Layout.fillWidth: true
                wrapMode: Text.WrapAnywhere
                textFormat: Text.RichText
                font.pixelSize: Appearance.font.pixelSize.smallest * ClaudeCode.textScale
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colOnLayer2
                text: root.marked(pathRow.path)
            }
        }
    }
}
