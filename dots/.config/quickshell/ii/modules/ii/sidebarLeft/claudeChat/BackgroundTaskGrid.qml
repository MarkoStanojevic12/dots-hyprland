pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

/**
 * Work the conversation left running in the background, as a two-column grid
 * of cards above the composer. Clicking a card opens its details above the
 * grid. The CLI sends no estimate for any task, so every clock counts up.
 */
Column {
    id: root
    spacing: 4
    // Hidden, the content never lays out and its height would stay 0, so it
    // shows as soon as there are tasks and hides only once collapsed.
    visible: ClaudeCode.backgroundTaskIds.length > 0 || listArea.height > 0

    readonly property real textScale: ClaudeCode.textScale
    property string openTaskId: ""
    readonly property var openTask: ClaudeCode.backgroundTaskInfo[root.openTaskId] ?? null
    // Kept after the task goes away, so the card collapses with its content.
    property var shownTask: root.emptyTask
    readonly property int runningCount: ClaudeCode.backgroundTaskIds
        .filter(id => ClaudeCode.backgroundTaskInfo[id]?.status === "running").length
    property real now: Date.now()

    readonly property var emptyTask: ({
        taskId: "", type: "", description: "", subagent: "", toolUseId: "", command: "",
        outputFile: "", startedAt: 0, toolUses: 0, tokens: 0, lastTool: "", summary: "",
        status: "running", endedAt: 0
    })

    onOpenTaskChanged: {
        if (root.openTask) root.shownTask = root.openTask;
        else Qt.callLater(() => { if (!root.openTask) root.openTaskId = ""; });
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.visible
        onTriggered: root.now = Date.now()
    }

    function kindOf(task) {
        const type = task.type ?? "";
        if (type.includes("bash")) return "shell";
        if (type.includes("agent")) return "agent";
        if (type.includes("workflow")) return "workflow";
        return "other";
    }

    function kindIcon(kind) {
        switch (kind) {
        case "shell": return "terminal";
        case "agent": return "smart_toy";
        case "workflow": return "account_tree";
        }
        return "pending";
    }

    function kindLabel(task) {
        const named = task.subagent.length > 0 ? ` · ${task.subagent}` : "";
        switch (root.kindOf(task)) {
        case "shell": return Translation.tr("Background shell");
        case "agent": return Translation.tr("Subagent") + named;
        case "workflow": return Translation.tr("Workflow") + named;
        }
        return task.type;
    }

    function accentColor(task) {
        if (task.status === "failed") return Appearance.colors.colError;
        if (task.status === "stopped") return Appearance.colors.colSubtext;
        switch (root.kindOf(task)) {
        case "agent": return Appearance.colors.colTertiary;
        case "workflow": return Appearance.colors.colSecondary;
        }
        return Appearance.colors.colPrimary;
    }

    function containerColor(kind) {
        switch (kind) {
        case "agent": return Appearance.colors.colTertiaryContainer;
        case "workflow": return Appearance.colors.colSecondaryContainer;
        }
        return Appearance.colors.colPrimaryContainer;
    }

    function inkOnContainer(kind) {
        switch (kind) {
        case "agent": return Appearance.colors.colOnTertiaryContainer;
        case "workflow": return Appearance.colors.colOnSecondaryContainer;
        }
        return Appearance.colors.colOnPrimaryContainer;
    }

    function statusIcon(task) {
        switch (task.status) {
        case "completed": return "check";
        case "failed": return "close";
        case "stopped": return "stop";
        }
        return root.kindIcon(root.kindOf(task));
    }

    function statusText(status) {
        switch (status) {
        case "completed": return Translation.tr("Done");
        case "failed": return Translation.tr("Failed");
        case "stopped": return Translation.tr("Stopped");
        }
        return Translation.tr("Running");
    }

    function elapsed(task) {
        return (task.endedAt > 0 ? task.endedAt : root.now) - task.startedAt;
    }

    function formatDuration(ms) {
        const seconds = Math.max(0, Math.floor(ms / 1000));
        const minutes = Math.floor(seconds / 60);
        const hours = Math.floor(minutes / 60);
        if (hours > 0) return `${hours}:${String(minutes % 60).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
        return minutes > 0 ? `${minutes}:${String(seconds % 60).padStart(2, "0")}` : `${seconds}s`;
    }

    function formatTokens(count) {
        return count >= 1000 ? `${(count / 1000).toFixed(1)}k` : String(count);
    }

    function metaLine(task) {
        const took = root.formatDuration(root.elapsed(task));
        switch (task.status) {
        case "completed": return Translation.tr("done in %1").arg(took);
        case "failed": return Translation.tr("failed after %1").arg(took);
        case "stopped": return Translation.tr("stopped after %1").arg(took);
        }
        const parts = [took];
        if (root.kindOf(task) !== "shell" && (task.toolUses > 0 || task.tokens > 0)) {
            parts.push(Translation.tr("%1 tools").arg(task.toolUses));
            parts.push(Translation.tr("%1 tok").arg(root.formatTokens(task.tokens)));
        }
        return parts.join(" · ");
    }

    function tint(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    component ActivityLine: Item {
        id: line
        property bool running: true
        property color color: Appearance.colors.colPrimary
        implicitHeight: 2
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Appearance.colors.colLayer3
        }
        Rectangle {
            anchors.fill: parent
            visible: !line.running
            radius: height / 2
            color: line.color
        }
        Rectangle {
            id: segment
            visible: line.running
            width: line.width * 0.35
            height: line.height
            radius: height / 2
            color: line.color

            NumberAnimation on x {
                running: line.running && line.visible
                loops: Animation.Infinite
                from: -segment.width
                to: line.width
                duration: 1300
                easing.type: Easing.InOutCubic
            }
        }
    }

    component StatusChip: Rectangle {
        id: chip
        property string status: "running"
        implicitHeight: 20 * root.textScale
        implicitWidth: chipRow.implicitWidth + 14
        radius: height / 2
        color: chip.status === "running" ? Appearance.colors.colPrimaryContainer
            : chip.status === "failed" ? Appearance.m3colors.m3errorContainer
            : Appearance.colors.colLayer3

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.status === "running"
                width: 6
                height: 6
                radius: 3
                color: Appearance.colors.colPrimary

                SequentialAnimation on opacity {
                    running: chip.status === "running" && chip.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 650; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutQuad }
                }
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: Appearance.font.pixelSize.smallest * root.textScale
                color: chip.status === "running" ? Appearance.colors.colOnPrimaryContainer
                    : chip.status === "failed" ? Appearance.m3colors.m3onErrorContainer
                    : Appearance.colors.colOnLayer2
                text: root.statusText(chip.status)
            }
        }
    }

    component Stat: Column {
        id: stat
        property string label
        property string value
        spacing: 1

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smallest * root.textScale
            color: Appearance.colors.colSubtext
            text: stat.label
        }
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smallie * root.textScale
            color: Appearance.colors.colOnLayer2
            text: stat.value
        }
    }

    component DetailButton: Rectangle {
        id: button
        property string icon
        property string label
        property color foreground: Appearance.colors.colOnLayer2
        signal clicked
        implicitHeight: 24 * root.textScale
        implicitWidth: buttonRow.implicitWidth + 16
        radius: height / 2
        color: buttonMouse.containsMouse ? Appearance.colors.colLayer3Hover : "transparent"
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        Row {
            id: buttonRow
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                iconSize: Appearance.font.pixelSize.small * root.textScale
                color: button.foreground
                text: button.icon
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: Appearance.font.pixelSize.smallest * root.textScale
                color: button.foreground
                text: button.label
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    component TaskCard: Item {
        id: card
        required property string modelData
        readonly property var task: ClaudeCode.backgroundTaskInfo[card.modelData] ?? root.emptyTask
        readonly property string kind: root.kindOf(card.task)
        readonly property bool running: card.task.status === "running"
        readonly property color accent: root.accentColor(card.task)
        readonly property bool open: root.openTaskId === card.modelData
        // The session drops a finished task after backgroundLingerMs; this
        // starts the exit a little before, so the card is gone when it does.
        property bool leaving: false

        implicitHeight: Math.max(52, textColumn.implicitHeight + 24)

        onRunningChanged: if (!card.running) doneBurst.restart()

        Timer {
            interval: 2300
            running: !card.running
            onTriggered: card.leaving = true
        }

        Rectangle {
            id: body
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: card.open || cardMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
            border.width: 1
            border.color: card.open || cardMouse.containsMouse ? card.accent : Appearance.colors.colOutlineVariant
            clip: true
            scale: card.leaving ? 0.6 : 1
            opacity: card.leaving ? 0 : 1

            Behavior on scale {
                NumberAnimation { duration: 380; easing.type: Easing.InBack }
            }
            Behavior on opacity {
                NumberAnimation { duration: 380 }
            }

            Rectangle { // Shimmer: the card is alive, not just listed
                id: shimmer
                visible: card.running
                width: body.width * 0.7
                height: body.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: root.tint(card.accent, 0) }
                    GradientStop { position: 0.5; color: root.tint(card.accent, 0.09) }
                    GradientStop { position: 1; color: root.tint(card.accent, 0) }
                }

                NumberAnimation on x {
                    running: card.running && card.visible
                    loops: Animation.Infinite
                    from: -shimmer.width
                    to: body.width + shimmer.width
                    duration: 2400
                }
            }

            Rectangle {
                id: burst
                anchors.centerIn: badge
                width: badge.width
                height: badge.height
                radius: width / 2
                color: card.accent
                opacity: 0
            }

            ParallelAnimation {
                id: doneBurst
                NumberAnimation { target: burst; property: "scale"; from: 0.8; to: 2.4; duration: 650; easing.type: Easing.OutCubic }
                NumberAnimation { target: burst; property: "opacity"; from: 0.5; to: 0; duration: 650 }
            }

            Rectangle {
                id: badge
                x: 9
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -2
                width: 32
                height: 32
                radius: 16
                color: card.running ? root.containerColor(card.kind) : root.tint(card.accent, 0.2)

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: Appearance.font.pixelSize.large * root.textScale
                    fill: card.running ? 0 : 1
                    color: card.running ? root.inkOnContainer(card.kind) : card.accent
                    text: root.statusIcon(card.task)
                }

                Rectangle { // Live dot
                    anchors {
                        right: parent.right
                        top: parent.top
                    }
                    visible: card.running
                    width: 8
                    height: 8
                    radius: 4
                    color: card.accent
                    border.width: 1.5
                    border.color: body.color

                    SequentialAnimation on opacity {
                        running: card.running && card.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 650; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutQuad }
                    }
                }
            }

            Column {
                id: textColumn
                anchors {
                    left: badge.right
                    leftMargin: 8
                    right: parent.right
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: -2
                }
                spacing: 1

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallie * root.textScale
                    color: Appearance.colors.colOnLayer2
                    text: card.task.description
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallest * root.textScale
                    color: Appearance.colors.colSubtext
                    text: root.metaLine(card.task)
                }
            }

            ActivityLine {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    leftMargin: 12
                    rightMargin: 12
                    bottomMargin: 6
                }
                running: card.running
                color: card.accent
            }

            Rectangle { // Lands with a flash, then settles
                anchors.fill: parent
                radius: parent.radius
                color: root.tint(card.accent, 0.22)
                border.width: 2
                border.color: card.accent

                SequentialAnimation on opacity {
                    NumberAnimation { from: 0; to: 1; duration: 90 }
                    PauseAnimation { duration: 260 }
                    NumberAnimation { to: 0; duration: 800; easing.type: Easing.OutCubic }
                }
            }
        }

        MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openTaskId = card.open ? "" : card.modelData
        }
    }

    Rectangle { // Details of the open card
        id: detailCard
        readonly property var task: root.shownTask
        readonly property string kind: root.kindOf(detailCard.task)
        readonly property bool running: detailCard.task.status === "running"
        readonly property bool hasOutput: detailCard.task.outputFile.length > 0
        readonly property string commandText: detailCard.kind === "shell"
            ? (detailCard.task.command.length > 0 ? `$ ${detailCard.task.command}` : "")
            : detailCard.task.summary

        width: root.width
        height: root.openTask !== null ? details.implicitHeight + 20 : 0
        visible: height > 0
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        clip: true

        Behavior on height {
            enabled: !ClaudeCode.zooming
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Column {
            id: details
            x: 10
            y: 10
            width: parent.width - 20
            spacing: 8

            Item {
                width: parent.width
                height: 32

                Rectangle {
                    id: detailBadge
                    width: 32
                    height: 32
                    radius: 16
                    color: root.containerColor(detailCard.kind)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: Appearance.font.pixelSize.large * root.textScale
                        color: root.inkOnContainer(detailCard.kind)
                        text: root.kindIcon(detailCard.kind)
                    }
                }

                Column {
                    anchors {
                        left: detailBadge.right
                        leftMargin: 10
                        right: detailChip.left
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 1

                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small * root.textScale
                        color: Appearance.colors.colOnLayer2
                        text: detailCard.task.description
                    }
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest * root.textScale
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("%1 · started %2")
                            .arg(root.kindLabel(detailCard.task))
                            .arg(Qt.formatTime(new Date(detailCard.task.startedAt), "hh:mm"))
                    }
                }

                StatusChip {
                    id: detailChip
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    status: detailCard.task.status
                }
            }

            Rectangle { // The command, or an agent's own one-line status
                visible: detailCard.commandText.length > 0
                width: parent.width
                height: commandLabel.implicitHeight + 10
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer1

                StyledText {
                    id: commandLabel
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 8
                        rightMargin: 8
                    }
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller * root.textScale
                    color: Appearance.colors.colOnLayer2
                    text: detailCard.commandText
                }
            }

            Flow {
                width: parent.width
                spacing: 18

                Stat {
                    label: Translation.tr("Elapsed")
                    value: root.formatDuration(root.elapsed(detailCard.task))
                }
                Stat {
                    visible: detailCard.kind !== "shell"
                    label: Translation.tr("Tool calls")
                    value: String(detailCard.task.toolUses)
                }
                Stat {
                    visible: detailCard.kind !== "shell"
                    label: Translation.tr("Tokens")
                    value: root.formatTokens(detailCard.task.tokens)
                }
                Stat {
                    visible: detailCard.kind !== "shell"
                    label: Translation.tr("Last tool")
                    value: detailCard.task.lastTool.length > 0 ? detailCard.task.lastTool : "—"
                }
            }

            ActivityLine {
                width: parent.width
                height: 3
                running: detailCard.running
                color: root.accentColor(detailCard.task)
            }

            Row {
                anchors.right: parent.right
                spacing: 6
                visible: detailCard.hasOutput || detailCard.running

                DetailButton {
                    visible: detailCard.hasOutput
                    icon: "description"
                    label: Translation.tr("Output")
                    onClicked: ClaudeCode.openFileReference(`file://${encodeURI(detailCard.task.outputFile)}`)
                }
                DetailButton {
                    visible: detailCard.running
                    icon: "stop"
                    label: Translation.tr("Stop")
                    foreground: Appearance.colors.colError
                    onClicked: ClaudeCode.stopBackgroundTask(detailCard.task.taskId)
                }
            }
        }
    }

    // Eases the space it takes in and out, so the chat above slides instead of
    // jumping a whole row in one frame.
    Item {
        id: listArea
        width: root.width
        height: ClaudeCode.backgroundTaskIds.length > 0 ? listContent.implicitHeight : 0
        clip: listArea.height < listContent.implicitHeight

        Behavior on height {
            enabled: !ClaudeCode.zooming
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Column {
            id: listContent
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: 4

            Item {
                width: parent.width
                height: headerLabel.implicitHeight

                StyledText {
                    id: headerLabel
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    font.pixelSize: Appearance.font.pixelSize.smallest * root.textScale
                    font.letterSpacing: 0.8
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("IN THE BACKGROUND")
                }
                StyledText {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    font.pixelSize: Appearance.font.pixelSize.smallest * root.textScale
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("%1 running").arg(root.runningCount)
                }
            }

            Flow {
                id: grid
                width: parent.width
                spacing: 4

                add: Transition {
                    NumberAnimation { property: "scale"; from: 0.5; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 }
                }
                move: Transition {
                    NumberAnimation { properties: "x,y"; duration: 380; easing.type: Easing.OutCubic }
                }

                Repeater {
                    model: ScriptModel {
                        values: ClaudeCode.backgroundTaskIds
                    }
                    delegate: TaskCard {
                        width: (grid.width - grid.spacing) / 2
                    }
                }
            }
        }
    }
}
