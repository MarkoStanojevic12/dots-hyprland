import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A ticket, PR, issue or crash link drawn as a card: key and state, title,
 * and what changed or how often it happens. The key shows straight away; the
 * rest fills in once the lookup comes back, and stays put when it fails.
 */
RippleButton {
    id: root
    // { url, text, label, rest, info }
    required property var link
    readonly property var info: root.link.info
    readonly property var meta: ChatLinks.meta[root.info.ref] ?? null
    readonly property real scale: ClaudeCode.textScale

    readonly property string key: root.info.kind === "crash" && root.meta?.shortId ? root.meta.shortId : root.info.key
    readonly property string linkText: (root.link.text ?? "").replace(/`|\*\*/g, "").trim()
    readonly property string title: root.meta?.title
        ?? (root.linkText.length > 0 && root.linkText !== root.key && root.linkText !== root.link.url ? root.linkText : "")
    readonly property string details: {
        const m = root.meta;
        if (!m) return "";
        if (root.info.kind === "crash") {
            const parts = [];
            if (m.events !== undefined) parts.push(Translation.tr("%1 events").arg(m.events));
            if (m.users !== undefined && m.users !== null) parts.push(Translation.tr("%1 users").arg(m.users));
            const seen = ChatLinks.ago(m.lastSeen);
            if (seen.length > 0) parts.push(Translation.tr("last seen %1").arg(seen));
            return parts.join(" · ");
        }
        if (root.info.kind === "ticket") return m.type ?? "";
        if (root.info.kind === "issue") return root.info.repo;
        return "";
    }

    implicitHeight: column.implicitHeight + 17
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    onClicked: {
        ClaudeCode.openFileReference(root.link.url);
        GlobalStates.sidebarLeftOpen = false;
    }
    Component.onCompleted: ChatLinks.want(root.info.ref)

    contentItem: ColumnLayout {
        id: column
        anchors {
            fill: parent
            leftMargin: 11
            rightMargin: 11
            topMargin: 8
            bottomMargin: 9
        }
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            LinkIcon {
                info: root.info
                size: 15 * root.scale
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smallie * root.scale
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
                textFormat: Text.PlainText
                text: root.key
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                visible: text.length > 0
                font.pixelSize: Appearance.font.pixelSize.smaller * root.scale
                color: Appearance.colors.colSubtext
                textFormat: Text.PlainText
                text: root.link.label ?? ""
            }
            Item {
                Layout.fillWidth: true
                visible: (root.link.label ?? "").length === 0
            }
            LinkStatusPill {
                status: root.meta?.status ?? root.meta?.state ?? ""
                category: root.meta?.statusCategory ?? ""
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: text.length > 0
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: root.info.kind === "crash" ? Appearance.font.family.monospace : Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smallie * root.scale
            color: root.info.kind === "crash" ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer2
            // A PR title can come from any public repo, and as rich text an <img>
            // in it would be fetched, telling its owner you looked.
            textFormat: Text.PlainText
            text: root.title
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 5
            visible: root.details.length > 0 || root.meta?.additions !== undefined

            StyledText {
                visible: root.meta?.additions !== undefined
                font.pixelSize: Appearance.font.pixelSize.smaller * root.scale
                color: Appearance.colors.colTertiary
                text: `+${root.meta?.additions ?? 0}`
            }
            StyledText {
                visible: root.meta?.deletions !== undefined
                font.pixelSize: Appearance.font.pixelSize.smaller * root.scale
                color: Appearance.colors.colError
                text: `−${root.meta?.deletions ?? 0}`
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller * root.scale
                color: Appearance.colors.colSubtext
                textFormat: Text.PlainText
                text: root.info.kind === "pr" ? `· ${root.info.repo}` : root.details
            }
        }
    }

    StyledToolTip {
        text: root.link.url
    }
}
