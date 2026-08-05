import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * One past conversation in the Claude tab's history list.
 */
RippleButton {
    id: root
    // { id, title, mtime, turns }
    required property var session
    property bool current: false

    implicitHeight: 40
    buttonRadius: Appearance.rounding.small
    toggled: root.current

    contentItem: RowLayout {
        anchors {
            fill: parent
            leftMargin: 8
            rightMargin: 8
        }
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
                text: root.session?.title ?? ""
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                text: {
                    const turns = root.session?.turns ?? 0;
                    const when = NotificationUtils.getFriendlyNotifTimeString((root.session?.mtime ?? 0) * 1000);
                    return turns === 1
                        ? Translation.tr("%1 · 1 message").arg(when)
                        : Translation.tr("%1 · %2 messages").arg(when).arg(turns);
                }
            }
        }

        MaterialSymbol {
            visible: root.current
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.m3colors.m3onPrimary
            text: "check"
        }
    }
}
