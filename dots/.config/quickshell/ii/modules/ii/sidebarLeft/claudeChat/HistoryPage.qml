import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Past conversations in the Claude tab, shown in place of the chat: one tab
 * per category over a newest-first list under day headings.
 */
Item {
    id: root

    signal closeRequested()
    property alias searchField: historySearch

    readonly property var tabLabels: ({
        "": Translation.tr("All"),
        "Tickets": Translation.tr("Tickets"),
        "PR Reviews": Translation.tr("Reviews"),
        "Coding": Translation.tr("Code"),
        "Hyprland": Translation.tr("Hyprland"),
        "Misc": Translation.tr("Misc"),
    })

    function open() {
        historySearch.clear();
        tabBar.currentIndex = 0;
        historyList.positionViewAtBeginning();
        historySearch.forceActiveFocus();
    }

    // Matched against the generated title, the opening prompt and the category,
    // so both "what it was about" and "what I typed" find a conversation.
    readonly property var matching: {
        const needle = historySearch.text.trim().toLowerCase();
        if (needle.length === 0) return ClaudeCode.sessions;
        return ClaudeCode.sessions.filter(session =>
            `${session.title} ${session.prompt} ${session.category}`.toLowerCase().includes(needle));
    }

    // Taken from every session rather than the matches, so tabs don't vanish
    // and shift under the cursor while a search is typed.
    readonly property var categories: {
        const found = [""];
        for (const session of ClaudeCode.sessions) {
            if (!found.includes(session.category)) found.push(session.category);
        }
        return found;
    }

    readonly property var counts: {
        const counts = { "": root.matching.length };
        for (const session of root.matching) counts[session.category] = (counts[session.category] ?? 0) + 1;
        return counts;
    }

    readonly property string category: root.categories[tabBar.currentIndex] ?? ""

    readonly property var shown: root.matching
        .filter(session => root.category === "" || session.category === root.category)
        .sort((a, b) => b.mtime - a.mtime)

    function bucket(mtime) {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const startOfToday = today.getTime() / 1000;
        if (mtime >= startOfToday) return Translation.tr("Today");
        if (mtime >= startOfToday - 86400) return Translation.tr("Yesterday");
        if (mtime >= startOfToday - 6 * 86400) return Translation.tr("Last 7 days");
        if (mtime >= startOfToday - 30 * 86400) return Translation.tr("Last 30 days");
        return Translation.tr("Older");
    }

    component Heading: StyledText {
        leftPadding: 8
        bottomPadding: 2
        font.pixelSize: Appearance.font.pixelSize.smallest * ClaudeCode.textScale
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.4
        color: Appearance.colors.colSubtext
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            HeaderIconButton {
                symbol: "arrow_back"
                tooltipText: Translation.tr("Back to the chat (Esc)")
                onClicked: root.closeRequested()
            }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.normal * ClaudeCode.textScale
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                text: Translation.tr("History")
            }

            MaterialTextField {
                id: historySearch
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller * ClaudeCode.textScale
                placeholderText: Translation.tr("Search conversations…")
                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Escape) return;
                    // Escape backs out of the search before it backs out
                    // of the page, so a typo does not cost the list.
                    if (historySearch.text.length > 0) historySearch.clear();
                    else root.closeRequested();
                    event.accepted = true;
                }
            }
        }

        SecondaryTabBar {
            id: tabBar
            Layout.fillWidth: true

            Repeater {
                model: root.categories

                delegate: SecondaryTabButton {
                    required property string modelData
                    buttonText: `${root.tabLabels[modelData] ?? modelData} ${root.counts[modelData] ?? 0}`
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            StyledListView {
                id: historyList
                anchors {
                    fill: parent
                    margins: 4
                }
                clip: true
                spacing: 2
                model: ScriptModel {
                    values: root.shown
                }
                delegate: Column {
                    id: historyEntry
                    required property var modelData
                    required property int index
                    readonly property string bucket: root.bucket(historyEntry.modelData?.mtime ?? 0)
                    // The list is newest first, so a heading is just the
                    // point where the day bucket changes.
                    readonly property bool opensBucket: historyEntry.index === 0
                        || root.bucket(root.shown[historyEntry.index - 1]?.mtime ?? 0) !== historyEntry.bucket

                    width: historyList.width
                    spacing: 2

                    Heading {
                        visible: historyEntry.opensBucket
                        topPadding: historyEntry.index === 0 ? 4 : 10
                        text: historyEntry.bucket
                    }

                    SessionListItem {
                        width: parent.width
                        session: historyEntry.modelData
                        showCategory: root.category === ""
                        current: ClaudeCode.resumeSessionId === historyEntry.modelData.id
                        onClicked: {
                            ClaudeCode.loadSession(historyEntry.modelData.id);
                            root.closeRequested();
                        }
                    }
                }
            }

            // The heading of whatever is at the top stays pinned there, so a
            // long scroll never loses which day it is in. The inline heading
            // slides under it and takes over as it arrives.
            Rectangle {
                readonly property int topIndex: historyList.indexAt(historyList.width / 2, historyList.contentY + 1)
                visible: !historyList.atYBeginning && topIndex >= 0
                anchors {
                    top: historyList.top
                    left: historyList.left
                    right: historyList.right
                }
                height: stickyHeading.implicitHeight
                color: parent.color

                Heading {
                    id: stickyHeading
                    topPadding: 4
                    text: root.bucket(root.shown[parent.topIndex]?.mtime ?? 0)
                }
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - 16
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: root.shown.length === 0
                font.pixelSize: Appearance.font.pixelSize.smaller * ClaudeCode.textScale
                color: Appearance.colors.colSubtext
                text: {
                    if (ClaudeCode.sessionsLoading) return Translation.tr("Looking for past conversations…");
                    if (historySearch.text.trim().length > 0) return Translation.tr("Nothing matches that search");
                    return Translation.tr("No past conversations here yet");
                }
            }
        }
    }
}
