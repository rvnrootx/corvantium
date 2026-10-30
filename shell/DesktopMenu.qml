import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "components"

FluidPanel {
    id: root
    implicitWidth: 200
    implicitHeight: 180

    property var shellState: null

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 5

        Text {
            text: "DESKTOP"
            color: shellState.chartreuse
            font.family: "Lexend"
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: shellState.edge }

        Repeater {
            model: [
                { title: "Change Wallpaper", action: "wallpaper", icon: "󰏘" },
                { title: "Add Clock", action: "calendar", icon: "󰥔" },
                { title: "Settings", action: "settings", icon: "󰒓" },
                { title: "Terminal", action: "terminal", icon: "󰆍" }
            ]
            delegate: ToolButton {
                Layout.fillWidth: true
                onClicked: {
                    shellState.overlayOpen = false; // Close menu
                    if (modelData.action === "settings" || modelData.action === "calendar") {
                        shellState.showPanel(modelData.action);
                    } else {
                        shellState.launchAction(modelData.action);
                    }
                }
                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? shellState.raised : "transparent"
                }
                contentItem: RowLayout {
                    spacing: 10
                    Text { text: modelData.icon; color: shellState.chartreuse; font.pixelSize: 14 }
                    Text { text: modelData.title; color: shellState.text; font.pixelSize: 11 }
                }
            }
        }
    }
}
