import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * The chat's scrollbar, carrying its links: a view box that drags like a
 * scrollbar thumb, and one marker per reply that posted links, where that
 * reply sits in the chat. Hovering a marker lists the reply's links, clicking
 * it scrolls to the reply.
 */
Item {
    id: root
    // [{ messageIndex, links: [{ url, name, info }], fraction }], fraction being
    // how far down the chat the reply starts.
    property var markers: []
    property real viewTop: 0
    property real viewHeight: 1
    property bool scrollable: false
    // How wide the link list may get; it opens to the left, over the chat.
    property real popupMaxWidth: 300
    readonly property bool dragging: scrubber.pressed
    signal jump(int messageIndex)
    // Where the view box should start, as a fraction of the chat.
    signal scrollTo(real top)
    signal wheelScrolled(real deltaY)

    readonly property real markerSize: 24
    readonly property real markerGap: 27
    readonly property real travel: Math.max(0, 1 - root.viewHeight)
    property int hoveredMarker: -1

    // Markers keep their order and a minimum gap; when a long chat has more
    // than fit, the whole column is squeezed rather than pushed off the end.
    readonly property var placed: {
        const room = Math.max(0, root.height - root.markerSize);
        const items = root.markers.map(marker => ({ marker: marker, y: Math.min(room, Math.max(0, marker.fraction * root.height)) }));
        items.sort((a, b) => a.y - b.y);
        for (let i = 1; i < items.length; i++) items[i].y = Math.max(items[i].y, items[i - 1].y + root.markerGap);
        const last = items.length > 0 ? items[items.length - 1].y : 0;
        if (last > room && last > 0) for (const item of items) item.y *= room / last;
        return items;
    }

    Rectangle { // Track
        visible: root.scrollable
        anchors {
            top: parent.top
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
        width: 2
        radius: 1
        color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.4)
    }

    Rectangle { // What the chat currently shows
        id: viewBox
        visible: root.scrollable
        x: 0
        width: parent.width
        height: Math.min(root.height, Math.max(20, root.viewHeight * root.height))
        // Over the room the box can move in rather than the whole height, so a
        // box held at its minimum size still reaches both ends.
        y: (root.travel > 0 ? Math.min(Math.max(root.viewTop / root.travel, 0), 1) : 0) * (root.height - height)
        radius: 9
        color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, scrubber.pressed ? 0.88 : scrubber.containsMouse ? 0.92 : 0.95)
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.88)
    }

    // Pressed off the box, the box first centres on the pointer.
    MouseArea {
        id: scrubber
        property real grab: 0
        anchors.fill: parent
        enabled: root.scrollable
        hoverEnabled: true

        function follow(mouseY) {
            const room = Math.max(1, root.height - viewBox.height);
            root.scrollTo(Math.min(Math.max((mouseY - scrubber.grab) / room, 0), 1) * root.travel);
        }
        onPressed: mouse => {
            const onBox = mouse.y >= viewBox.y && mouse.y <= viewBox.y + viewBox.height;
            scrubber.grab = onBox ? mouse.y - viewBox.y : viewBox.height / 2;
            scrubber.follow(mouse.y);
        }
        onPositionChanged: mouse => {
            if (scrubber.pressed) scrubber.follow(mouse.y);
        }
        onWheel: wheel => root.wheelScrolled(wheel.angleDelta.y)
    }

    Repeater {
        model: root.placed
        delegate: RippleButton {
            id: marker
            required property var modelData
            required property int index
            readonly property var links: marker.modelData.marker.links
            readonly property bool inView: marker.modelData.marker.fraction >= root.viewTop
                && marker.modelData.marker.fraction <= root.viewTop + root.viewHeight

            x: (root.width - width) / 2
            y: marker.modelData.y
            implicitWidth: root.markerSize
            implicitHeight: root.markerSize
            buttonRadius: Appearance.rounding.verysmall
            colBackground: marker.inView ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer3
            colBackgroundHover: Appearance.colors.colLayer3Hover
            onClicked: root.jump(marker.modelData.marker.messageIndex)

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) {
                        closeTimer.stop();
                        root.hoveredMarker = marker.index;
                    } else {
                        closeTimer.restart();
                    }
                }
            }

            contentItem: Item {
                LinkIcon {
                    anchors.centerIn: parent
                    info: marker.links[0].info
                    size: 14
                }
            }

            Rectangle { // How many links the reply posted
                visible: marker.links.length > 1
                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: -5
                    rightMargin: -4
                }
                width: Math.max(14, countText.implicitWidth + 6)
                height: 14
                radius: 7
                color: Appearance.colors.colTertiary
                StyledText {
                    id: countText
                    anchors.centerIn: parent
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnTertiary
                    text: marker.links.length
                }
            }
        }
    }

    // Leaving a marker for its list crosses a gap, so closing waits a moment.
    Timer {
        id: closeTimer
        interval: 250
        onTriggered: root.hoveredMarker = -1
    }

    Rectangle {
        id: popup
        readonly property var entry: root.placed[root.hoveredMarker] ?? null
        visible: popup.entry !== null
        anchors.right: parent.left
        anchors.rightMargin: 4
        width: Math.min(root.popupMaxWidth, 300)
        height: Math.min(popupColumn.implicitHeight + 10, root.height)
        y: popup.entry ? Math.min(Math.max(0, popup.entry.y - 4), Math.max(0, root.height - height)) : 0
        radius: 10
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        HoverHandler {
            onHoveredChanged: hovered ? closeTimer.stop() : closeTimer.restart()
        }

        Flickable {
            anchors {
                fill: parent
                margins: 5
            }
            clip: true
            contentHeight: popupColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: popupColumn
                width: parent.width
                spacing: 0

                Repeater {
                    model: popup.entry?.marker.links ?? []
                    delegate: RippleButton {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.verysmall
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        onClicked: {
                            root.hoveredMarker = -1;
                            ClaudeCode.openFileReference(row.modelData.url);
                            GlobalStates.sidebarLeftOpen = false;
                        }

                        contentItem: RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 7
                                rightMargin: 8
                            }
                            spacing: 7

                            LinkIcon {
                                info: row.modelData.info
                                size: 14
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: Appearance.colors.colOnLayer2
                                textFormat: Text.PlainText
                                text: row.modelData.name
                            }
                            StyledText {
                                Layout.maximumWidth: popupColumn.width * 0.4
                                elide: Text.ElideMiddle
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                textFormat: Text.PlainText
                                text: row.modelData.info.host
                            }
                        }
                    }
                }
            }
        }
    }
}
