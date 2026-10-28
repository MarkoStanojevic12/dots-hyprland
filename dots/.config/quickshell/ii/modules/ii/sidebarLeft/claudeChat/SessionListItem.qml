import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One past conversation in the Claude tab's history list.
 */
RippleButton {
    id: root
    // { id, title, ticket, mtime, turns, category, prompt }
    required property var session
    property bool current: false
    // Off inside a category tab, where every row would carry the same icon.
    property bool showCategory: true

    readonly property var categoryStyle: ({
        "Tickets": { icon: "confirmation_number", color: Appearance.colors.colPrimary },
        "PR Reviews": { icon: "rate_review", color: Appearance.colors.colTertiary },
        "Coding": { icon: "code", color: Appearance.colors.colSecondary },
        "Hyprland": { icon: "desktop_windows", color: Appearance.colors.colOnLayer2 },
    })[root.session?.category ?? ""] ?? { icon: "chat_bubble", color: Appearance.colors.colSubtext }

    // Ticket titles are "KEY summary"; the key moves into a chip.
    readonly property string ticketKey: {
        const key = root.session?.ticket ?? "";
        return key.length > 0 && (root.session?.title ?? "").startsWith(key) ? key : "";
    }
    readonly property string summary: (root.session?.title ?? "").slice(root.ticketKey.length).trim()

    function shortAge(mtime) {
        const seconds = Date.now() / 1000 - mtime;
        if (seconds < 60) return Translation.tr("now");
        if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
        if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
        if (seconds < 7 * 86400) return `${Math.floor(seconds / 86400)}d`;
        return Qt.formatDate(new Date(mtime * 1000), "d MMM");
    }

    implicitHeight: Math.max(30, rowLayout.implicitHeight + 10)
    buttonRadius: Appearance.rounding.small
    toggled: root.current

    contentItem: RowLayout {
        id: rowLayout
        anchors {
            fill: parent
            leftMargin: 8
            rightMargin: 8
        }
        spacing: 8

        MaterialSymbol {
            visible: root.showCategory
            iconSize: Appearance.font.pixelSize.normal * ClaudeCode.textScale
            color: root.toggled ? Appearance.m3colors.m3onPrimary : root.categoryStyle.color
            text: root.categoryStyle.icon
        }

        Rectangle {
            visible: root.ticketKey.length > 0
            implicitWidth: keyText.implicitWidth + 10
            implicitHeight: keyText.implicitHeight + 2
            radius: Appearance.rounding.unsharpenmore
            color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSecondaryContainer

            StyledText {
                id: keyText
                anchors.centerIn: parent
                font.pixelSize: Appearance.font.pixelSize.smallest * ClaudeCode.textScale
                font.weight: Font.DemiBold
                color: root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
                text: root.ticketKey
            }
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small * ClaudeCode.textScale
            color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
            text: root.summary
        }

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smallest * ClaudeCode.textScale
            color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
            text: root.shortAge(root.session?.mtime ?? 0)
        }
    }
}
