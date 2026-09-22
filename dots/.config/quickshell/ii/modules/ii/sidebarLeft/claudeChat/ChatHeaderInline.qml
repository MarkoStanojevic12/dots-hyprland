import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Header design 3 — one row, and that row is the tabs.
 *
 * The strip is the header: the current tab is the title, so there is no pill
 * repeating it, and the buttons sit in the space kept free at the right end of
 * the tabs. It gives the messages a whole row back, which in a sidebar chat is
 * about two lines of reply.
 *
 * What it costs is room for tabs — the cluster eats into the strip, so the
 * labels elide sooner. With one or two conversations open that is free; with
 * six it is the trade.
 */
Item {
    id: root

    property bool historyShown: false
    property bool usefulFeaturesShown: false
    property var availableFeatures: []

    signal toggleHistory
    signal openTab
    signal startNewConversation
    signal openClaudeWeb
    signal toggleUsefulFeatures

    property bool overflowShown: false

    implicitHeight: strip.implicitHeight

    ChatTabStrip {
        id: strip
        anchors.fill: parent
        // Whatever the cluster currently measures, overflow open or shut, plus
        // a gap so a tab's label never runs into the first button.
        trailingReserve: cluster.width + 4
    }

    Row {
        id: cluster
        anchors {
            right: parent.right
            rightMargin: 4
            verticalCenter: parent.verticalCenter
            // Centre on the tab row rather than the strip: the baseline below
            // the tabs is the strip's floor, not part of the row.
            verticalCenterOffset: -strip.baselineHeight / 2
        }
        spacing: 2

        Rectangle { // Keeps the buttons off the tabs
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 16
            color: Appearance.colors.colOutlineVariant
        }

        Item { // More air than the row's spacing gives, on the side that needs it
            width: 4
            height: 1
        }

        Revealer {
            reveal: root.overflowShown
            anchors.verticalCenter: parent.verticalCenter

            Row {
                spacing: 2

                HeaderIconButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    symbol: "add_comment"
                    enabled: ClaudeCode.messageIDs.length > 0 && !ClaudeCode.busy
                    tooltipText: Translation.tr("New conversation (Ctrl+Shift+O)")
                    onClicked: root.startNewConversation()
                }

                HeaderIconButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    assetIcon: "claude-symbolic"
                    tooltipText: Translation.tr("Open claude.ai")
                    onClicked: root.openClaudeWeb()
                }

                HeaderIconButton {
                    visible: root.availableFeatures.length > 0
                    implicitWidth: 28
                    implicitHeight: 28
                    symbol: "bolt"
                    toggled: root.usefulFeaturesShown
                    tooltipText: Translation.tr("Useful features")
                    onClicked: root.toggleUsefulFeatures()
                }
            }
        }

        HeaderHistoryButton {
            implicitWidth: 28
            implicitHeight: 28
            expanded: root.historyShown
            tooltipText: Translation.tr("Past conversations in %1").arg(ClaudeCode.workingDirectory)
            onClicked: root.toggleHistory()
        }

        HeaderIconButton {
            implicitWidth: 28
            implicitHeight: 28
            symbol: "add"
            enabled: ClaudeCode.canOpenTab
            tooltipText: ClaudeCode.canOpenTab
                ? Translation.tr("New chat tab (Ctrl+T)\nRuns beside this one, in the same directory")
                : Translation.tr("%1 chats at once is the limit — each one is a whole CLI").arg(ClaudeCode.maxTabs)
            onClicked: root.openTab()
        }

        HeaderIconButton {
            implicitWidth: 28
            implicitHeight: 28
            symbol: "more_horiz"
            toggled: root.overflowShown
            tooltipText: root.overflowShown ? Translation.tr("Fewer buttons") : Translation.tr("More")
            onClicked: root.overflowShown = !root.overflowShown
        }
    }
}
