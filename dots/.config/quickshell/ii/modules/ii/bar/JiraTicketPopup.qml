pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Clickable (not hover) popup for the active Jira ticket. A layer surface
 * rather than a PopupWindow so the comment and assignee fields get keyboard
 * focus; dismissed through the shared focus grab like the sidebars.
 */
LazyLoader {
    id: root

    property Item anchorItem
    readonly property real contentWidth: 388

    component IconButton: RippleButton {
        id: iconButton
        property string symbol
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: iconButton.symbol
            iconSize: 20
            color: !iconButton.enabled ? Appearance.colors.colOnLayer2Disabled
                : iconButton.toggled ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnSurfaceVariant
        }
    }

    component ChipButton: RippleButton {
        id: chipButton
        property string label
        property string symbol
        property bool filled: false
        readonly property color foreground: !chipButton.enabled ? Appearance.colors.colOnLayer2Disabled
            : chipButton.filled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        implicitHeight: 30
        implicitWidth: chipRow.implicitWidth + 12 * 2
        buttonRadius: Appearance.rounding.full
        colBackground: chipButton.filled ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
        colBackgroundHover: chipButton.filled ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
        colRipple: chipButton.filled ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active
        contentItem: Item {
            RowLayout {
                id: chipRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    visible: chipButton.symbol !== ""
                    text: chipButton.symbol
                    iconSize: 17
                    color: chipButton.foreground
                }
                StyledText {
                    visible: chipButton.label !== ""
                    text: chipButton.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: chipButton.foreground
                }
            }
        }
    }

    component Avatar: Rectangle {
        id: avatar
        property string name
        property real size: 26
        implicitWidth: avatar.size
        implicitHeight: avatar.size
        radius: avatar.size / 2
        color: Appearance.colors.colSecondaryContainer
        StyledText {
            anchors.centerIn: parent
            text: avatar.name.split(" ").map(part => part[0] ?? "").slice(0, 2).join("").toUpperCase()
            font.pixelSize: Math.round(avatar.size * 0.4)
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    component MenuPanel: Rectangle {
        default property alias entries: menuColumn.data
        Layout.fillWidth: true
        implicitHeight: menuColumn.implicitHeight + 4 * 2
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1
        ColumnLayout {
            id: menuColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 4
            }
            spacing: 0
        }
    }

    component MenuEntry: RippleButton {
        id: menuEntry
        property string label
        property string symbol
        property string personName
        Layout.fillWidth: true
        implicitHeight: 34
        buttonRadius: Appearance.rounding.verysmall
        contentItem: Item {
            RowLayout {
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 10
                    rightMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8
                Avatar {
                    visible: menuEntry.personName !== ""
                    name: menuEntry.personName
                    size: 22
                }
                MaterialSymbol {
                    visible: menuEntry.symbol !== ""
                    text: menuEntry.symbol
                    iconSize: 18
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: menuEntry.label || menuEntry.personName
                    color: menuEntry.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer2Disabled
                }
            }
        }
    }

    component SectionLabel: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
        color: Appearance.colors.colSubtext
    }

    // TextEdit rather than Text so keys, SHAs and log lines can be copied.
    component SelectableText: TextEdit {
        id: selectable
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.PlainText
        renderType: Text.NativeRendering
        color: Appearance.colors.colOnLayer1
        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
        selectionColor: Appearance.colors.colSecondaryContainer
        font {
            hintingPreference: Font.PreferDefaultHinting
            family: Appearance.font.family.main
            pixelSize: Appearance.font.pixelSize.small
            variableAxes: Appearance.font.variableAxes.main
        }
        onLinkActivated: link => Qt.openUrlExternally(link)
        HoverHandler {
            cursorShape: selectable.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor
        }
    }

    // TextEdit has no linkColor, so links are coloured inline.
    component RichBody: SelectableText {
        property string html
        Layout.fillWidth: true
        textFormat: TextEdit.RichText
        wrapMode: TextEdit.Wrap
        text: html.replace(/<a /g, `<a style="color: ${Appearance.m3colors.m3primary}" `)
    }

    component: PanelWindow {
        id: popupWindow

        readonly property var issue: Jira.issue
        // "status", "assignee", "more" or "": at most one inline menu is open.
        property string menu: ""

        readonly property string statusCategory: popupWindow.issue?.statusCategory ?? ""
        readonly property color statusBackground: statusCategory === "done" ? Appearance.colors.colTertiaryContainer
            : statusCategory === "indeterminate" ? Appearance.colors.colPrimaryContainer
            : Appearance.colors.colLayer3
        readonly property color statusBackgroundHover: statusCategory === "done" ? Appearance.colors.colTertiaryContainerHover
            : statusCategory === "indeterminate" ? Appearance.colors.colPrimaryContainerHover
            : Appearance.colors.colLayer3Hover
        readonly property color statusRipple: statusCategory === "done" ? Appearance.colors.colTertiaryContainerActive
            : statusCategory === "indeterminate" ? Appearance.colors.colPrimaryContainerActive
            : Appearance.colors.colLayer3Active
        readonly property color statusForeground: statusCategory === "done" ? Appearance.colors.colOnTertiaryContainer
            : statusCategory === "indeterminate" ? Appearance.colors.colOnPrimaryContainer
            : Appearance.colors.colOnLayer3

        function toggleMenu(name) {
            popupWindow.menu = popupWindow.menu === name ? "" : name;
            if (popupWindow.menu === "assignee") {
                Jira.assignableUsers = [];
                assigneeField.text = "";
                assigneeField.forceActiveFocus();
            } else if (popupWindow.menu === "more") {
                pinField.forceActiveFocus();
            }
        }

        function sendComment() {
            const text = commentField.text.trim();
            if (text.length > 0 && Jira.pendingAction === "") Jira.comment(text);
        }

        screen: root.anchorItem.QsWindow.window?.screen ?? null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:jiraTicket"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        anchors.left: true
        anchors.top: !Config.options.bar.bottom
        anchors.bottom: Config.options.bar.bottom

        implicitWidth: background.implicitWidth + Appearance.sizes.elevationMargin * 2
        implicitHeight: background.implicitHeight + Appearance.sizes.elevationMargin * 2

        margins {
            left: {
                const centered = root.QsWindow?.mapFromItem(root.anchorItem,
                    (root.anchorItem.width - popupWindow.implicitWidth) / 2, 0).x ?? 0;
                const maxLeft = (popupWindow.screen?.width ?? 0) - popupWindow.implicitWidth;
                return Math.max(0, Math.min(centered, maxLeft));
            }
            top: Appearance.sizes.barHeight
            bottom: Appearance.sizes.barHeight
        }

        mask: Region {
            item: background
        }

        Component.onCompleted: GlobalFocusGrab.addDismissable(popupWindow)
        Component.onDestruction: GlobalFocusGrab.removeDismissable(popupWindow)
        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                Jira.popupOpen = false;
            }
        }
        Connections {
            target: Jira
            function onActiveKeyChanged() {
                popupWindow.menu = "";
            }
            function onActionFinished(action, ok) {
                if (action === "comment" && ok) commentField.text = "";
            }
        }

        StyledRectangularShadow {
            target: background
        }

        Rectangle {
            id: background
            anchors {
                fill: parent
                margins: Appearance.sizes.elevationMargin
            }
            implicitWidth: root.contentWidth + 16 * 2
            implicitHeight: content.implicitHeight + 16 * 2
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            focus: true
            Keys.onEscapePressed: Jira.popupOpen = false

            ColumnLayout {
                id: content
                anchors {
                    fill: parent
                    margins: 16
                }
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialSymbol {
                        text: {
                            const type = (popupWindow.issue?.type ?? "").toLowerCase();
                            if (type.includes("bug")) return "bug_report";
                            if (type.includes("story")) return "bookmark";
                            if (type.includes("epic")) return "bolt";
                            if (type.includes("sub")) return "subdirectory_arrow_right";
                            return "task_alt";
                        }
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        visible: !!popupWindow.issue?.parent
                        text: `${popupWindow.issue?.parent?.key ?? ""} /`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    SelectableText {
                        text: Jira.activeKey || Translation.tr("No active ticket")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        visible: Jira.source !== ""
                        implicitWidth: sourceText.implicitWidth + 8 * 2
                        implicitHeight: sourceText.implicitHeight + 3 * 2
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSecondaryContainer
                        StyledText {
                            id: sourceText
                            anchors.centerIn: parent
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSecondaryContainer
                            text: Jira.source === "pinned" ? Translation.tr("pinned")
                                : Jira.source === "claude" ? Translation.tr("from Claude")
                                : Translation.tr("from branch")
                        }
                    }
                    Item { Layout.fillWidth: true }
                    MaterialLoadingIndicator {
                        visible: Jira.loading || Jira.pendingAction !== ""
                        implicitSize: 20
                    }
                    IconButton {
                        symbol: "push_pin"
                        enabled: Jira.activeKey !== ""
                        toggled: Jira.source === "pinned"
                        releaseAction: () => Jira.source === "pinned" ? Jira.unpin() : Jira.pin(Jira.activeKey)
                    }
                    IconButton {
                        symbol: "open_in_new"
                        enabled: !!popupWindow.issue
                        releaseAction: () => {
                            Qt.openUrlExternally(popupWindow.issue.url);
                            Jira.popupOpen = false;
                        }
                    }
                    IconButton {
                        symbol: "more_vert"
                        toggled: popupWindow.menu === "more"
                        releaseAction: () => popupWindow.toggleMenu("more")
                    }
                }

                MenuPanel {
                    visible: popupWindow.menu === "more"
                    MenuEntry {
                        symbol: "refresh"
                        label: Translation.tr("Refresh")
                        enabled: Jira.activeKey !== ""
                        releaseAction: () => {
                            Jira.refresh();
                            popupWindow.menu = "";
                        }
                    }
                    ToolbarTextField {
                        id: pinField
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.margins: 4
                        implicitHeight: 34
                        colBackground: Appearance.colors.colLayer2
                        placeholderText: Translation.tr("Pin another ticket (%1-123)…").arg(Jira.project || "PROJ")
                        Keys.onEscapePressed: popupWindow.menu = ""
                        onAccepted: {
                            Jira.pin(pinField.text);
                            pinField.text = "";
                            popupWindow.menu = "";
                        }
                    }
                }

                SelectableText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: popupWindow.issue?.summary ?? ""
                    wrapMode: TextEdit.Wrap
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.larger
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !!popupWindow.issue
                    spacing: 8

                    RippleButton {
                        implicitHeight: 32
                        implicitWidth: statusRow.implicitWidth + 14 * 2
                        buttonRadius: Appearance.rounding.full
                        colBackground: popupWindow.statusBackground
                        colBackgroundHover: popupWindow.statusBackgroundHover
                        colRipple: popupWindow.statusRipple
                        releaseAction: () => popupWindow.toggleMenu("status")
                        contentItem: Item {
                            RowLayout {
                                id: statusRow
                                anchors.centerIn: parent
                                spacing: 2
                                StyledText {
                                    text: popupWindow.issue?.status ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: popupWindow.statusForeground
                                }
                                MaterialSymbol {
                                    text: popupWindow.menu === "status" ? "expand_less" : "expand_more"
                                    iconSize: 18
                                    color: popupWindow.statusForeground
                                }
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    RippleButton {
                        implicitHeight: 32
                        implicitWidth: assigneeRow.implicitWidth + 8 * 2
                        buttonRadius: Appearance.rounding.full
                        toggled: popupWindow.menu === "assignee"
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        releaseAction: () => popupWindow.toggleMenu("assignee")
                        contentItem: Item {
                            RowLayout {
                                id: assigneeRow
                                anchors.centerIn: parent
                                spacing: 6
                                Avatar {
                                    visible: !!popupWindow.issue?.assignee
                                    name: popupWindow.issue?.assignee?.name ?? ""
                                }
                                MaterialSymbol {
                                    visible: !popupWindow.issue?.assignee
                                    text: "person_off"
                                    iconSize: 20
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    text: popupWindow.issue?.assignee?.name ?? Translation.tr("Unassigned")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer1
                                }
                                MaterialSymbol {
                                    text: popupWindow.menu === "assignee" ? "expand_less" : "expand_more"
                                    iconSize: 18
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }

                MenuPanel {
                    visible: popupWindow.menu === "status" && !!popupWindow.issue
                    StyledText {
                        Layout.margins: 10
                        visible: Jira.transitions.length === 0
                        text: Translation.tr("Loading transitions…")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    Repeater {
                        model: Jira.transitions.filter(transition => transition.to !== popupWindow.issue?.status)
                        delegate: MenuEntry {
                            required property var modelData
                            symbol: "arrow_forward"
                            label: modelData.name === modelData.to ? modelData.name : `${modelData.name} → ${modelData.to}`
                            enabled: Jira.pendingAction === ""
                            releaseAction: () => {
                                if (Jira.transition(modelData.id)) popupWindow.menu = "";
                            }
                        }
                    }
                }

                MenuPanel {
                    visible: popupWindow.menu === "assignee" && !!popupWindow.issue
                    RowLayout {
                        Layout.margins: 4
                        spacing: 6
                        ChipButton {
                            symbol: "person"
                            label: Translation.tr("Assign to me")
                            enabled: Jira.pendingAction === ""
                            releaseAction: () => {
                                if (Jira.assign("me")) popupWindow.menu = "";
                            }
                        }
                        ChipButton {
                            symbol: "person_remove"
                            label: Translation.tr("Unassign")
                            enabled: Jira.pendingAction === "" && !!popupWindow.issue?.assignee
                            releaseAction: () => {
                                if (Jira.assign("none")) popupWindow.menu = "";
                            }
                        }
                    }
                    ToolbarTextField {
                        id: assigneeField
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.margins: 4
                        implicitHeight: 34
                        colBackground: Appearance.colors.colLayer2
                        placeholderText: Translation.tr("Search people…")
                        onTextChanged: userSearchDebounce.restart()
                        Keys.onEscapePressed: popupWindow.menu = ""
                        Timer {
                            id: userSearchDebounce
                            interval: 300
                            onTriggered: if (assigneeField.text.trim().length > 0) Jira.searchUsers(assigneeField.text.trim())
                        }
                    }
                    Repeater {
                        model: Jira.assignableUsers
                        delegate: MenuEntry {
                            required property var modelData
                            personName: modelData.name
                            enabled: Jira.pendingAction === ""
                            releaseAction: () => {
                                if (Jira.assign(modelData.id)) popupWindow.menu = "";
                            }
                        }
                    }
                }

                SecondaryTabBar {
                    id: tabBar
                    visible: !!popupWindow.issue
                    onCurrentIndexChanged: details.contentY = 0
                    SecondaryTabButton {
                        buttonText: Translation.tr("Details")
                        buttonIcon: "description"
                    }
                    SecondaryTabButton {
                        buttonText: Translation.tr("Comments %1").arg(popupWindow.issue?.commentCount ?? 0)
                        buttonIcon: "forum"
                    }
                    SecondaryTabButton {
                        buttonText: Translation.tr("Subtasks %1").arg(popupWindow.issue?.subtasks.length ?? 0)
                        buttonIcon: "checklist"
                    }
                }

                StyledFlickable {
                    id: details
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(detailsColumn.implicitHeight, 300)
                    visible: !!popupWindow.issue
                    clip: true
                    contentWidth: width
                    contentHeight: detailsColumn.implicitHeight

                    ColumnLayout {
                        id: detailsColumn
                        width: details.width - 8
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: tabBar.currentIndex === 0
                            spacing: 10

                            RichBody {
                                html: Jira.cleanHtml(popupWindow.issue?.description) || `<i>${Translation.tr("No description")}</i>`
                            }
                            GridLayout {
                                columns: 2
                                columnSpacing: 16
                                rowSpacing: 4
                                SectionLabel { text: Translation.tr("Priority") }
                                StyledText {
                                    text: popupWindow.issue?.priority ?? "—"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer1
                                }
                                SectionLabel { text: Translation.tr("Reporter") }
                                StyledText {
                                    text: popupWindow.issue?.reporter ?? "—"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer1
                                }
                                SectionLabel { text: Translation.tr("Updated") }
                                StyledText {
                                    text: Jira.formatDate(popupWindow.issue?.updated)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer1
                                }
                                SectionLabel {
                                    visible: !!popupWindow.issue?.parent
                                    text: Translation.tr("Parent")
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: !!popupWindow.issue?.parent
                                    elide: Text.ElideRight
                                    text: popupWindow.issue?.parent ? `${popupWindow.issue.parent.key} · ${popupWindow.issue.parent.summary}` : ""
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: tabBar.currentIndex === 1
                            spacing: 10

                            SectionLabel {
                                visible: (popupWindow.issue?.commentCount ?? 0) > (popupWindow.issue?.comments.length ?? 0)
                                text: Translation.tr("Last %1 of %2").arg(popupWindow.issue?.comments.length ?? 0).arg(popupWindow.issue?.commentCount ?? 0)
                            }
                            StyledText {
                                visible: (popupWindow.issue?.commentCount ?? 0) === 0
                                text: Translation.tr("No comments yet")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            Repeater {
                                model: popupWindow.issue?.comments ?? []
                                delegate: RowLayout {
                                    id: commentEntry
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Avatar {
                                        Layout.alignment: Qt.AlignTop
                                        name: commentEntry.modelData.author
                                        size: 24
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        StyledText {
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            text: `${commentEntry.modelData.author} · ${Jira.formatDate(commentEntry.modelData.created)}`
                                        }
                                        RichBody {
                                            html: Jira.cleanHtml(commentEntry.modelData.body)
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: tabBar.currentIndex === 2
                            spacing: 6

                            StyledText {
                                visible: (popupWindow.issue?.subtasks.length ?? 0) === 0
                                text: Translation.tr("No subtasks")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            Repeater {
                                model: popupWindow.issue?.subtasks ?? []
                                delegate: RowLayout {
                                    id: subtaskEntry
                                    required property var modelData
                                    readonly property bool done: /done|closed|resolved/i.test(modelData.status)
                                    Layout.fillWidth: true
                                    spacing: 6
                                    MaterialSymbol {
                                        text: subtaskEntry.done ? "check_circle" : "radio_button_unchecked"
                                        iconSize: 16
                                        color: subtaskEntry.done ? Appearance.colors.colTertiary : Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        text: subtaskEntry.modelData.key
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: subtaskEntry.modelData.summary
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        text: subtaskEntry.modelData.status
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !!popupWindow.issue
                    spacing: 6

                    ToolbarTextField {
                        id: commentField
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        implicitHeight: 40
                        colBackground: Appearance.colors.colLayer2
                        placeholderText: Translation.tr("Comment on %1…").arg(Jira.activeKey)
                        onAccepted: popupWindow.sendComment()
                        Keys.onEscapePressed: Jira.popupOpen = false
                    }
                    IconButton {
                        implicitWidth: 40
                        implicitHeight: 40
                        symbol: "send"
                        enabled: commentField.text.trim().length > 0 && Jira.pendingAction === ""
                        releaseAction: () => popupWindow.sendComment()
                    }
                    ChipButton {
                        implicitWidth: 40
                        implicitHeight: 40
                        filled: true
                        symbol: "smart_toy"
                        enabled: Jira.activeKey !== ""
                        releaseAction: () => {
                            ClaudeCode.insertIntoComposer(`${Jira.activeKey}: `);
                            GlobalStates.sidebarLeftOpen = true;
                            Jira.popupOpen = false;
                        }
                        StyledToolTip {
                            text: Translation.tr("Ask Claude about %1").arg(Jira.activeKey)
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Jira.error !== "" ? Appearance.colors.colError : Appearance.colors.colSubtext
                    text: Jira.error !== "" ? Jira.error
                        : Jira.activeKey === "" ? Translation.tr("No ticket from a branch, Claude or a pin. Pin one from the ⋮ menu.")
                        : ""
                }
            }
        }
    }
}
