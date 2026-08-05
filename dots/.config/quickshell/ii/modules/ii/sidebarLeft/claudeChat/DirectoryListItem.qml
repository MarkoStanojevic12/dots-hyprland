import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One candidate working directory in the Claude tab's directory picker.
 */
RippleButton {
    id: root
    // { path, sessions, mtime }
    required property var directory
    property bool current: false

    readonly property string path: root.directory?.path ?? ""
    readonly property string home: Directories.home.replace(/^file:\/\//, "")
    // Home-relative paths are shorter and easier to scan in a narrow column.
    readonly property string shownPath: root.path === root.home ? "~"
        : root.path.startsWith(`${root.home}/`) ? `~${root.path.slice(root.home.length)}`
        : root.path

    implicitHeight: 34
    buttonRadius: Appearance.rounding.small
    toggled: root.current

    contentItem: RowLayout {
        anchors {
            fill: parent
            leftMargin: 8
            rightMargin: 8
        }
        spacing: 8

        MaterialSymbol {
            iconSize: Appearance.font.pixelSize.normal
            color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
            text: root.current ? "folder_open" : "folder"
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideLeft
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
            text: root.shownPath
        }

        StyledText {
            visible: (root.directory?.sessions ?? 0) > 0
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
            text: root.directory?.sessions ?? 0
        }
    }
}
