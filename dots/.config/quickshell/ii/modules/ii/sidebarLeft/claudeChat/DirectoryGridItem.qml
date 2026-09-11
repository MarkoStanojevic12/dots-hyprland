import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One cell of the working directory grid: the folder's name, where it lives,
 * and how many conversations have been had there.
 */
RippleButton {
    id: root
    // { path, sessions, mtime }
    required property var directory
    property bool current: false

    readonly property string path: root.directory?.path ?? ""
    readonly property string home: Directories.home.replace(/^file:\/\//, "")
    readonly property string shownPath: root.path === root.home ? "~"
        : root.path.startsWith(`${root.home}/`) ? `~${root.path.slice(root.home.length)}`
        : root.path
    readonly property string folderName: root.shownPath === "~" ? "~"
        : (root.path.split("/").filter(part => part.length > 0).pop() ?? root.path)
    readonly property string parentPath: {
        const cut = root.shownPath.lastIndexOf("/");
        if (cut < 0) return "";
        return cut === 0 ? "/" : root.shownPath.slice(0, cut);
    }
    readonly property int sessions: root.directory?.sessions ?? 0

    implicitHeight: 60
    buttonRadius: Appearance.rounding.small
    toggled: root.current

    contentItem: RowLayout {
        anchors {
            fill: parent
            leftMargin: 10
            rightMargin: 8
        }
        spacing: 8

        MaterialSymbol {
            iconSize: Appearance.font.pixelSize.larger
            color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
            text: root.current ? "folder_open" : "folder"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                text: root.folderName
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.parentPath.length > 0
                elide: Text.ElideLeft
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                text: root.parentPath
            }
        }

        Rectangle {
            visible: root.sessions > 0
            implicitWidth: sessionsText.implicitWidth + 10
            implicitHeight: sessionsText.implicitHeight + 4
            radius: Appearance.rounding.full
            color: root.toggled ? ColorUtils.transparentize(Appearance.m3colors.m3onPrimary, 0.8) : Appearance.colors.colLayer2

            StyledText {
                id: sessionsText
                anchors.centerIn: parent
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                text: root.sessions
            }
        }
    }

    StyledToolTip {
        text: root.shownPath
    }
}
