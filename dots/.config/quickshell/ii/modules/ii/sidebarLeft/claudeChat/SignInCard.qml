import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Shown when the CLI reports itself signed out.
 *
 * Nothing in the tab works until this is fixed, and the fix is a browser round
 * trip the sidebar cannot host — so this hands the job to a terminal and waits
 * to be told it is done.
 */
Rectangle {
    id: root

    implicitHeight: layout.implicitHeight + 20
    radius: Appearance.rounding.small
    color: Appearance.colors.colErrorContainer

    ColumnLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 10
        }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnErrorContainer
                text: "key_off"
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnErrorContainer
                text: Translation.tr("Your Claude session has expired")
            }
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnErrorContainer
            text: Translation.tr("Signing in opens a terminal and a browser. Come back here once it finishes.")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6

            RippleButton {
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                toggled: true
                onClicked: ClaudeCode.signIn()

                contentItem: StyledText {
                    anchors.centerIn: parent
                    leftPadding: 12
                    rightPadding: 12
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onPrimary
                    text: Translation.tr("Sign in")
                }
            }

            RippleButton {
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                enabled: !ClaudeCode.authChecking
                onClicked: ClaudeCode.checkAuth()

                contentItem: StyledText {
                    anchors.centerIn: parent
                    leftPadding: 12
                    rightPadding: 12
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnErrorContainer
                    text: ClaudeCode.authChecking
                        ? Translation.tr("Checking…")
                        : Translation.tr("I've signed in")
                }

                StyledToolTip {
                    text: Translation.tr("Ask the CLI whether the session is good again")
                }
            }

            Item { Layout.fillWidth: true }
        }
    }
}
