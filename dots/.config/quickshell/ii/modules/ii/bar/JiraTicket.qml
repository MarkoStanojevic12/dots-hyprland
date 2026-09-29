import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

MouseArea {
    id: root

    readonly property string screenName: root.QsWindow.window?.screen?.name ?? ""
    readonly property color statusColor: {
        switch (Jira.issue?.statusCategory) {
        case "done": return Appearance.colors.colTertiary;
        case "indeterminate": return Appearance.colors.colPrimary;
        default: return Appearance.colors.colSubtext;
        }
    }

    implicitWidth: row.implicitWidth + 8 * 2
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    onPressed: event => {
        if (event.button === Qt.MiddleButton) {
            if (Jira.issue) Qt.openUrlExternally(Jira.issue.url);
        } else {
            Jira.togglePopup(root.screenName);
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        MaterialSymbol {
            text: Jira.source === "pinned" ? "push_pin" : "confirmation_number"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            text: Jira.activeKey || Translation.tr("No ticket")
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            visible: text !== ""
            text: Jira.issue?.status ?? (Jira.loading ? "…" : "")
            color: root.statusColor
        }
    }

    JiraTicketPopup {
        anchorItem: root
        active: Jira.popupOpen && Jira.popupScreen === root.screenName
    }
}
