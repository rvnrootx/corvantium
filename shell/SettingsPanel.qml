import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "components"

FluidPanel {
    id: root
    implicitWidth: 400
    implicitHeight: 500

    property var shellState: null
    property var barWindow: null

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        Text {
            text: "HYPRSETTINGS"
            color: shellState.chartreuse
            font.family: "Lexend"
            font.pixelSize: 12
            font.bold: true
            font.letterSpacing: 1.5
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 10

                // Performance Section
                SettingsSection {
                    title: "Performance"
                    icon: "󰓅"
                    shellState: root.shellState

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        Repeater {
                            model: [
                                { name: "Power Saver", profile: "power-saver", icon: "󰌪" },
                                { name: "Balanced", profile: "balanced", icon: "󰗑" },
                                { name: "Performance", profile: "performance", icon: "󰓅" }
                            ]
                            delegate: ToolButton {
                                Layout.fillWidth: true
                                text: modelData.name
                                onClicked: barWindow.perfAction("perf-set-" + modelData.profile)
                                background: Rectangle {
                                    radius: 8
                                    color: barWindow.perfProfile === modelData.profile ? shellState.raised : "transparent"
                                    border.color: barWindow.perfProfile === modelData.profile ? shellState.chartreuse : "transparent"
                                    border.width: 1
                                }
                                contentItem: RowLayout {
                                    spacing: 10
                                    Text { text: modelData.icon; color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 16 }
                                    Text { text: modelData.name; color: shellState.text; font.pixelSize: 11 }
                                }
                            }
                        }
                    }
                }

                // Appearance Section
                SettingsSection {
                    title: "Appearance"
                    icon: "󰏘"
                    shellState: root.shellState

                    Button {
                        Layout.fillWidth: true
                        text: "Change Wallpaper"
                        onClicked: shellState.launchAction("wallpaper")
                        background: Rectangle { radius: 8; color: shellState.raised }
                        contentItem: Text { text: parent.text; color: shellState.text; horizontalAlignment: Text.AlignHCenter }
                    }
                }

                // System Section
                SettingsSection {
                    title: "System"
                    icon: "󰘚"
                    shellState: root.shellState

                    Button {
                        Layout.fillWidth: true
                        text: "Keybindings"
                        onClicked: shellState.launchAction("keybinds")
                        background: Rectangle { radius: 8; color: shellState.raised }
                        contentItem: Text { text: parent.text; color: shellState.text; horizontalAlignment: Text.AlignHCenter }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: "Bluetooth Settings"
                        onClicked: shellState.launchAction("bluetooth-settings")
                        background: Rectangle { radius: 8; color: shellState.raised }
                        contentItem: Text { text: parent.text; color: shellState.text; horizontalAlignment: Text.AlignHCenter }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: "Log Out"
                        onClicked: shellState.launchAction("logout")
                        background: Rectangle { radius: 8; color: "#f7768e" }
                        contentItem: Text { text: parent.text; color: shellState.ink; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                    }
                }
            }
        }
    }
}
