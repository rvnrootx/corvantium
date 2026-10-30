import QtQuick

Item {
    id: root

    default property alias contentData: contentLayer.data

    property real attachmentX: width * 0.5
    property color fillColor: "#f20e1217"
    property color rimColor: "#657b8285"

    Rectangle {
        x: 0
        y: 8
        width: parent.width
        height: parent.height - 8
        radius: 14
        color: root.fillColor
        border.color: root.rimColor
        border.width: 1
    }

    Rectangle {
        x: Math.max(22, Math.min(root.width - 54, root.attachmentX - 18))
        y: 0
        width: 36
        height: 18
        radius: 9
        color: root.fillColor
        border.color: root.rimColor
        border.width: 1
    }

    Rectangle {
        x: Math.max(23, Math.min(root.width - 53, root.attachmentX - 17))
        y: 8
        width: 34
        height: 3
        color: root.fillColor
        border.width: 0
    }

    Item {
        id: contentLayer
        anchors.fill: parent
        clip: true
        z: 1
    }
}
