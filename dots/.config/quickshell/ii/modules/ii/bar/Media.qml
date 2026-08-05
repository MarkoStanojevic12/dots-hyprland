import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Hyprland

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string trackTitle: activePlayer?.trackTitle ?? ""
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")

    // True from the moment the YouTube Music launch script is fired until a track
    // actually shows up (or the failsafe timeout below gives up). Blocks repeat
    // clicks and swaps the icon for a spinner.
    property bool launching: false

    onTrackTitleChanged: if (root.trackTitle.length > 0) root.launching = false

    Timer { // Failsafe: the launch script itself waits up to ~21s for the MPRIS player
        id: launchTimeout
        interval: 30000
        running: root.launching
        onTriggered: root.launching = false
    }

    Layout.fillHeight: true
    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 2
    implicitHeight: Appearance.sizes.barHeight

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        onPressed: (event) => {
            if (event.button === Qt.MiddleButton) {
                activePlayer.togglePlaying();
            } else if (event.button === Qt.BackButton) {
                activePlayer.previous();
            } else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) {
                activePlayer.next();
            } else if (event.button === Qt.LeftButton) {
                // Chrome keeps an MPRIS player registered while running, so check for an
                // actual track title (the same signal the "No media" label uses) rather
                // than mere player existence.
                if (activePlayer?.trackTitle) {
                    GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
                } else if (!root.launching) {
                    // Nothing playing: open YouTube Music on workspace 10 and start playback
                    root.launching = true
                    Quickshell.execDetached(["bash", "-c", "$HOME/.config/hypr/custom/scripts/open-ytmusic.sh"])
                }
            }
        }
    }

    RowLayout { // Real content
        id: rowLayout

        spacing: 4
        anchors.fill: parent

        Item { // Icon slot: track progress normally, indeterminate spinner while launching
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 20
            implicitHeight: 20

            ClippedFilledCircularProgress {
                id: mediaCircProg
                anchors.fill: parent
                visible: !root.launching
                lineWidth: Appearance.rounding.unsharpen
                value: activePlayer?.position / activePlayer?.length
                implicitSize: 20
                colPrimary: Appearance.colors.colOnSecondaryContainer
                enableAnimation: false

                Item {
                    anchors.centerIn: parent
                    width: mediaCircProg.implicitSize
                    height: mediaCircProg.implicitSize

                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: 1
                        text: activePlayer?.isPlaying ? "pause" : "music_note"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }
                }
            }

            CircularProgress { // Material 3 indeterminate spinner: arc grows/shrinks while the whole ring rotates
                id: launchSpinner
                anchors.fill: parent
                visible: root.launching
                implicitSize: 20
                lineWidth: 2
                colPrimary: Appearance.colors.colOnSecondaryContainer
                enableAnimation: false

                SequentialAnimation on value {
                    running: root.launching
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.08; to: 0.75; duration: 700; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.75; to: 0.08; duration: 700; easing.type: Easing.InOutQuad }
                }
                RotationAnimation on rotation {
                    running: root.launching
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 1400
                    easing.type: Easing.Linear
                }
            }
        }

        StyledText {
            visible: Config.options.bar.verbose
            width: rowLayout.width - (CircularProgress.size + rowLayout.spacing * 2)
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true // Ensures the text takes up available space
            Layout.rightMargin: rowLayout.spacing
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight // Truncates the text on the right
            color: Appearance.colors.colOnLayer1
            text: root.launching ? Translation.tr("Opening music…")
                : `${cleanedTitle}${activePlayer?.trackArtist ? ' • ' + activePlayer.trackArtist : ''}`
        }

    }

}
