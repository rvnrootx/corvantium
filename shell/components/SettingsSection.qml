import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

ColumnLayout {
    property string title: ""
    property string icon: ""
    property var shellState: null
    default property alias content: container.data

    spacing: 8
    Layout.fillWidth: true

    RowLayout {
        spacing: 8
        Text {
            text: icon
            color: shellState.chartreuse
            font.family: "Iosevka Nerd Font"
            font.pixelSize: 14
        }
        Text {
            text: title
            color: shellState.text
            font.pixelSize: 10
            font.bold: true
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: shellState.edge
        opacity: 0.5
    }

    ColumnLayout {
        id: container
        Layout.fillWidth: true
        Layout.leftMargin: 20
        spacing: 5
    }
}
