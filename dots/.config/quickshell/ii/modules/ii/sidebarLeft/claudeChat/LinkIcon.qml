import qs.services
import QtQuick

/**
 * The site icon of one link, as ChatLinks classified it.
 */
Image {
    id: root
    required property var info
    property real size: 16

    sourceSize: Qt.size(Math.ceil(root.size), Math.ceil(root.size))
    fillMode: Image.PreserveAspectFit
    source: ChatLinks.iconUri(root.info)
}
