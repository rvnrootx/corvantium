import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Wayland
import "components"

ShellRoot {
    id: shellState

    property color ink: "#0b0912"
    property color panel: "#15121e"
    property color raised: "#201b2b"
    property color edge: "#3b3450"
    property color text: "#f3f0e9"
    property color muted: "#a59db5"
    property color chartreuse: "#d8f55a"
    property color violet: "#a88bfa"
    property var activePlayer: null
    property var weatherData: ({ ok: false, status: "loading", message: "Weather is loading or disabled." })
    property var lyricData: ({ status: "no-player", message: "Start a player that supports MPRIS.", lines: [] })
    property var lyricLines: []
    property string lyricSignature: ""
    property int lyricOffset: 0
    property string nowTime: ""
    property string keyboardLayout: "…"

    function refreshPlayer() {
        const players = Mpris.players.values;
        let selected = null;
        for (let i = 0; i < players.length; i++) {
            if (players[i].isPlaying) { selected = players[i]; break; }
        }
        if (!selected && players.length > 0) selected = players[0];
        activePlayer = selected;
        if (!selected) {
            lyricSignature = "";
            lyricData = ({ status: "no-player", message: "Start a player that supports MPRIS.", lines: [] });
            lyricLines = [];
            return;
        }
        const signature = [selected.dbusName, selected.trackTitle, selected.trackArtist, selected.trackAlbum, selected.length].join("\u0000");
        if (signature !== lyricSignature) {
            lyricSignature = signature;
            lyricOffset = 0;
            lyricProcess.exec([
                "python3", Quickshell.shellDir + "/services/lyrics.py",
                "--title", selected.trackTitle || "", "--artist", selected.trackArtist || "",
                "--album", selected.trackAlbum || "", "--duration", String(selected.length || 0)
            ]);
        }
    }

    function updateClock() {
        const now = new Date();
        nowTime = Qt.formatTime(now, weatherData.time_format === "12h" ? "h:mm AP" : "HH:mm");
    }

    Process {
        id: lyricProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    shellState.lyricData = JSON.parse(text);
                    shellState.lyricLines = shellState.lyricData.lines || [];
                } catch (error) {
                    shellState.lyricData = ({ status: "error", message: "Lyrics response could not be read.", lines: [] });
                    shellState.lyricLines = [];
                }
            }
        }
    }

    Process {
        id: weatherProcess
        command: ["python3", Quickshell.shellDir + "/services/weather.py", "--config", Quickshell.shellDir + "/settings.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { shellState.weatherData = JSON.parse(text); }
                catch (error) { shellState.weatherData = ({ ok: false, status: "error", message: "Weather response could not be read." }); }
            }
        }
    }
    Process {
        id: keyboardProcess
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const keyboards = data.keyboards || [];
                    const keyboard = keyboards.find(device => device.main) || keyboards[0];
                    if (!keyboard) shellState.keyboardLayout = "--";
                    else {
                        const layout = keyboard.active_keymap || "--";
                        const short = layout.match(/\(([^)]+)\)/);
                        shellState.keyboardLayout = short ? short[1].slice(0, 5).toUpperCase() : layout.slice(0, 5).toUpperCase();
                    }
                } catch (error) { shellState.keyboardLayout = "--"; }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: shellState.updateClock()
    }
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: shellState.refreshPlayer()
    }
    Timer {
        interval: 500
        running: shellState.activePlayer !== null && shellState.activePlayer.isPlaying
        repeat: true
        onTriggered: if (shellState.activePlayer) shellState.activePlayer.positionChanged()
    }
    Timer {
        interval: Math.max(5, shellState.weatherData.refresh_minutes || 30) * 60 * 1000
        running: true
        repeat: true
        onTriggered: weatherProcess.running = true
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: keyboardProcess.running = true
    }
    Component.onCompleted: {
        updateClock();
        refreshPlayer();
        weatherProcess.running = true;
        keyboardProcess.running = true;
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Background
            color: "transparent"
            Canvas {
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const glow = ctx.createRadialGradient(width * 0.68, height * 0.57, 4, width * 0.68, height * 0.57, Math.max(width, height) * 0.72);
                    glow.addColorStop(0, "rgba(57, 41, 87, 0.52)");
                    glow.addColorStop(1, "rgba(11, 9, 18, 0)");
                    ctx.fillStyle = glow;
                    ctx.fillRect(0, 0, width, height);
                    ctx.strokeStyle = "#675687";
                    ctx.lineWidth = 1;
                    ctx.globalAlpha = 0.08;
                    for (let x = 40; x < width; x += 88) {
                        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke();
                    }
                    for (let y = 48; y < height; y += 88) {
                        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
                    }
                    ctx.globalAlpha = 0.22;
                    ctx.setLineDash([3, 9]);
                    for (let orbit = 0; orbit < 4; orbit++) {
                        ctx.beginPath();
                        ctx.ellipse(width * 0.62, height * 0.56, width * (0.12 + orbit * 0.09), height * (0.08 + orbit * 0.07), -0.18, 0, Math.PI * 2);
                        ctx.stroke();
                    }
                    ctx.setLineDash([]);
                    ctx.globalAlpha = 0.85;
                    for (const point of [[0.22, 0.28], [0.46, 0.72], [0.81, 0.34], [0.69, 0.83]]) {
                        ctx.beginPath(); ctx.arc(width * point[0], height * point[1], 2.5, 0, Math.PI * 2); ctx.fillStyle = "#d8f55a"; ctx.fill();
                    }
                    ctx.globalAlpha = 1;
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: barWindow
            required property var modelData
            screen: modelData
            anchors { top: true; left: true; right: true }
            implicitHeight: 36
            exclusiveZone: 36
            color: "transparent"

            property string openPanel: ""
            property var settingsAnchor: null
            property string audioTab: "outputs"
            property int monthYear: new Date().getFullYear()
            property int monthIndex: new Date().getMonth()
            property var pickedDate: new Date()
            property string cameraStatus: "checking supported controls…"

            function togglePanel(name) { openPanel = openPanel === name ? "" : name; }
            function appCommand(action) {
                launchProcess.exec([Quickshell.shellDir + "/../scripts/corvantium-launch", action]);
            }
            function pad(value) { return value < 10 ? "0" + value : String(value); }
            function dateForCell(index) {
                const first = new Date(monthYear, monthIndex, 1);
                const mondayOffset = (first.getDay() + 6) % 7;
                return new Date(monthYear, monthIndex, index - mondayOffset + 1);
            }
            function changeMonth(delta) {
                const date = new Date(monthYear, monthIndex + delta, 1);
                monthYear = date.getFullYear(); monthIndex = date.getMonth();
            }
            function weatherText(code) {
                if (code === 0) return "Clear";
                if (code === 1 || code === 2) return "Partly cloudy";
                if (code === 3) return "Overcast";
                if (code === 45 || code === 48) return "Fog";
                if (code >= 51 && code <= 67) return "Drizzle / rain";
                if (code >= 71 && code <= 77) return "Snow";
                if (code >= 80 && code <= 82) return "Showers";
                if (code >= 95) return "Thunderstorm";
                return "Conditions unavailable";
            }
            function timeLabel(iso) { return iso ? iso.slice(11, 16) : "--:--"; }
            function formatDuration(value) {
                const seconds = Math.max(0, Math.floor(value || 0));
                return pad(Math.floor(seconds / 60)) + ":" + pad(seconds % 60);
            }

            Process { id: launchProcess }
            PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }
            Process {
                id: cameraStatusProcess
                command: [Quickshell.shellDir + "/../scripts/corvantium-hardware", "camera-status"]
                stdout: StdioCollector { onStreamFinished: barWindow.cameraStatus = text.trim() || "unsupported: no status returned" }
            }
            Process {
                id: cameraProcess
                command: [Quickshell.shellDir + "/../scripts/corvantium-hardware", "camera-toggle"]
                onExited: cameraStatusProcess.running = true
            }
            Component.onCompleted: {
                cameraStatusProcess.running = true;
                settingsAnchor = settingsButton;
            }

            Rectangle {
                anchors.fill: parent
                color: "#6815121e"
                border.color: "#55a88bfa"
                border.width: 1
                radius: 18
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 9

                RowLayout {
                    spacing: 8
                    Rectangle {
                        Layout.preferredWidth: 25; Layout.preferredHeight: 25
                        radius: 12; color: shellState.chartreuse
                        Text { anchors.centerIn: parent; text: "C/"; color: shellState.ink; font.family: "monospace"; font.bold: true; font.pixelSize: 10 }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text { text: "CORVANTIUM"; color: shellState.text; font.family: "monospace"; font.pixelSize: 10; font.bold: true; letterSpacing: 1.1 }
                        Text { text: "FIELD / 01"; color: shellState.violet; font.family: "monospace"; font.pixelSize: 7; letterSpacing: 1 }
                    }
                    Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 23; color: shellState.edge }
                    ToolButton {
                        id: clockButton
                        Layout.preferredWidth: 78; Layout.preferredHeight: 29
                        onClicked: barWindow.togglePanel("calendar")
                        background: Rectangle { color: "transparent"; border.color: shellState.edge; border.width: 1; radius: 12 }
                        contentItem: Column {
                            spacing: 0
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: shellState.nowTime; color: shellState.text; font.family: "monospace"; font.bold: true; font.pixelSize: 10 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDate(new Date(), "ddd dd MMM"); color: shellState.muted; font.family: "monospace"; font.pixelSize: 7 }
                        }
                    }
                    ToolButton {
                        id: weatherButton
                        visible: shellState.weatherData.show_weather !== false
                        Layout.preferredHeight: 29
                        onClicked: barWindow.togglePanel("calendar")
                        background: Rectangle { color: "transparent"; border.color: shellState.edge; border.width: 1; radius: 12 }
                        contentItem: RowLayout {
                            spacing: 5
                            Rectangle { Layout.preferredWidth: 2; Layout.preferredHeight: 17; color: shellState.chartreuse }
                            Text { text: shellState.weatherData.ok ? Math.round(shellState.weatherData.current.temperature) + shellState.weatherData.unit : "WX"; color: shellState.violet; font.family: "monospace"; font.pixelSize: 9; rightPadding: 5 }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                ToolButton {
                    id: mediaButton
                    Layout.preferredWidth: Math.min(280, Math.max(145, barWindow.screen.width * 0.2))
                    Layout.preferredHeight: 29
                    onClicked: barWindow.togglePanel("media")
                    background: Rectangle { color: "transparent"; border.color: shellState.edge; border.width: 1; radius: 12 }
                    contentItem: RowLayout {
                        spacing: 7
                        Rectangle {
                            Layout.preferredWidth: 20; Layout.preferredHeight: 20; radius: 12; color: shellState.raised
                            Image { anchors.fill: parent; source: shellState.activePlayer ? shellState.activePlayer.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                            Text { anchors.centerIn: parent; text: "∿"; color: shellState.chartreuse; font.pixelSize: 16; visible: !shellState.activePlayer || shellState.activePlayer.trackArtUrl === "" }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            Text { Layout.fillWidth: true; text: shellState.activePlayer ? (shellState.activePlayer.trackTitle || "Untitled") : "NO SIGNAL / MPRIS"; color: shellState.text; font.family: "monospace"; font.pixelSize: 9; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: shellState.activePlayer ? barWindow.formatDuration(shellState.activePlayer.position) + "  /  " + (shellState.activePlayer.trackArtist || shellState.activePlayer.identity) : "Open a media source"; color: shellState.muted; font.family: "monospace"; font.pixelSize: 8; elide: Text.ElideRight }
                        }
                        ToolButton {
                            text: shellState.activePlayer && shellState.activePlayer.isPlaying ? "Ⅱ" : "▶"
                            Layout.preferredWidth: 23; Layout.preferredHeight: 23
                            onClicked: if (shellState.activePlayer && shellState.activePlayer.canTogglePlaying) shellState.activePlayer.togglePlaying()
                            background: Rectangle { color: "transparent" }
                            contentItem: Text { text: parent.text; color: shellState.chartreuse; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: 4
                    Text { text: shellState.keyboardLayout; color: shellState.muted; font.family: "monospace"; font.pixelSize: 8; padding: 5 }
                    ToolButton {
                        id: networkButton
                        text: Networking.devices.values.some(d => d.connected) ? "N+" : "N–"
                        background: Rectangle { color: "transparent"; border.color: shellState.edge; border.width: 1; radius: 12 }
                        contentItem: Text { text: parent.text; color: parent.text === "N+" ? shellState.violet : shellState.muted; font.family: "monospace"; font.pixelSize: 8; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: { barWindow.settingsAnchor = networkButton; barWindow.togglePanel("settings"); }
                    }
                    ToolButton {
                        id: bluetoothButton
                        text: "B" + Bluetooth.devices.values.length
                        background: Rectangle { color: "transparent"; border.color: shellState.edge; border.width: 1; radius: 12 }
                        contentItem: Text { text: parent.text; color: Bluetooth.devices.values.length > 0 ? shellState.violet : shellState.muted; font.family: "monospace"; font.pixelSize: 8; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: { barWindow.settingsAnchor = bluetoothButton; barWindow.togglePanel("settings"); }
                    }
                    ToolButton {
                        id: micButton
                        text: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio ? (Pipewire.defaultAudioSource.audio.muted ? "MIC×" : "MIC+") : "MIC—"
                        onClicked: if (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio) Pipewire.defaultAudioSource.audio.muted = !Pipewire.defaultAudioSource.audio.muted
                        background: Rectangle { color: "transparent"; border.color: shellState.edge; border.width: 1; radius: 12 }
                        contentItem: Text { text: micButton.text; color: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio && Pipewire.defaultAudioSource.audio.muted ? shellState.chartreuse : shellState.muted; font.family: "monospace"; font.pixelSize: 7; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    ToolButton {
                        id: volumeButton
                        text: {
                            const sink = Pipewire.defaultAudioSink;
                            return sink && sink.audio ? (sink.audio.muted ? "VOL×" : Math.round(sink.audio.volume * 100) + "%") : "VOL—";
                        }
                        onClicked: barWindow.togglePanel("audio")
                        background: Rectangle { color: "transparent"; border.color: shellState.violet; border.width: 1; radius: 12 }
                        contentItem: Text { text: volumeButton.text; color: shellState.violet; font.family: "monospace"; font.pixelSize: 8; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; leftPadding: 5; rightPadding: 5 }
                    }
                    Text {
                        text: UPower.displayDevice && UPower.displayDevice.ready && UPower.onBattery ? "P " + Math.round(UPower.displayDevice.percentage) : (UPower.displayDevice && UPower.displayDevice.ready ? "P AC" : "P—")
                        color: shellState.muted; font.family: "monospace"; font.pixelSize: 8; padding: 4
                    }
                }

                RowLayout {
                    spacing: 1
                    Repeater {
                        model: 9
                        delegate: ToolButton {
                            required property int index
                            property int workspaceNumber: index + 1
                            readonly property bool isActive: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === workspaceNumber
                            text: barWindow.pad(workspaceNumber)
                            Layout.preferredWidth: barWindow.screen.width < 1100 ? 23 : 25
                            Layout.preferredHeight: 25
                            onClicked: Hyprland.dispatch("workspace " + workspaceNumber)
                            background: Rectangle {
                                color: "transparent"
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.isActive ? parent.width : 17
                                    height: 17; radius: 12
                                    color: parent.isActive ? shellState.chartreuse : shellState.raised
                                    border.color: parent.isActive ? shellState.chartreuse : shellState.edge
                                    border.width: 1
                                }
                            }
                            contentItem: Text { text: parent.text; color: parent.isActive ? shellState.ink : shellState.muted; font.family: "monospace"; font.pixelSize: 8; font.bold: parent.isActive; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        }
                    }
                }

                ToolButton {
                    id: settingsButton
                    text: "SET"
                    onClicked: { barWindow.settingsAnchor = settingsButton; barWindow.togglePanel("settings"); }
                    Layout.preferredWidth: 34; Layout.preferredHeight: 25
                    background: Rectangle { color: "transparent"; border.color: shellState.edge; border.width: 1; radius: 12 }
                    contentItem: Text { text: parent.text; color: shellState.muted; font.family: "monospace"; font.pixelSize: 7; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
                ToolButton {
                    id: searchButton
                    text: "FIND"
                    onClicked: barWindow.appCommand("search")
                    Layout.preferredWidth: 38; Layout.preferredHeight: 25
                    background: Rectangle { color: shellState.chartreuse; radius: 12 }
                    contentItem: Text { text: parent.text; color: shellState.ink; font.family: "monospace"; font.pixelSize: 7; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
            }

            PopupWindow {
                id: audioPopup
                anchor.item: volumeButton
                anchor.edges: Edges.Bottom | Edges.Right
                anchor.gravity: Edges.Bottom | Edges.Right
                anchor.margins.bottom: -5
                width: Math.min(390, Math.max(280, barWindow.screen.width - 18)); height: Math.min(530, barWindow.screen.height - 48)
                visible: barWindow.openPanel === "audio"
                focusable: true; grabFocus: true
                onVisibleChanged: if (!visible && barWindow.openPanel === "audio") barWindow.openPanel = ""
                FluidPanel {
                    anchors.fill: parent
                    attachmentX: width - 48
                    focus: true
                    Keys.onEscapePressed: { barWindow.openPanel = ""; event.accepted = true; }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 17; anchors.topMargin: 31; spacing: 12
                        RowLayout {
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Text { text: "SOUND ROUTING"; color: shellState.chartreuse; font.family: "monospace"; font.pixelSize: 10; font.bold: true; letterSpacing: 1 }
                                Text { text: Pipewire.defaultAudioSink ? (Pipewire.defaultAudioSink.description || Pipewire.defaultAudioSink.name) : "No output device"; color: shellState.text; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            Text {
                                text: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Math.round(Pipewire.defaultAudioSink.audio.volume * 100) + "%" : "—"
                                color: shellState.violet; font.family: "monospace"; font.pixelSize: 23; font.bold: true
                            }
                        }
                        RowLayout {
                            ToolButton {
                                text: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted ? "×" : "◖"
                                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                                onClicked: if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted
                                background: Rectangle { radius: 14; color: shellState.raised }
                                contentItem: Text { text: parent.text; color: shellState.violet; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                            Slider {
                                Layout.fillWidth: true; from: 0; to: 1.5
                                value: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Pipewire.defaultAudioSink.audio.volume : 0
                                enabled: !!(Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
                                onMoved: if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) Pipewire.defaultAudioSink.audio.volume = value
                            }
                        }
                        RowLayout {
                            spacing: 5
                            Repeater {
                                model: ["outputs", "inputs", "streams"]
                                delegate: ToolButton {
                                    required property string modelData
                                    text: modelData.toUpperCase()
                                    Layout.fillWidth: true; Layout.preferredHeight: 32
                                    onClicked: barWindow.audioTab = modelData
                                    background: Rectangle { radius: 12; color: barWindow.audioTab === parent.modelData ? shellState.chartreuse : shellState.raised }
                                    contentItem: Text { text: parent.text; color: barWindow.audioTab === parent.modelData ? shellState.ink : shellState.muted; font.family: "monospace"; font.pixelSize: 9; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                }
                            }
                        }
                        Text {
                            text: barWindow.audioTab === "outputs" ? "PLAYBACK DEVICES" : (barWindow.audioTab === "inputs" ? "RECORDING DEVICES" : "APPLICATION STREAMS")
                            color: shellState.muted; font.family: "monospace"; font.pixelSize: 9; letterSpacing: 1
                        }
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 7
                            model: ScriptModel {
                                values: Pipewire.nodes.values.filter(node => node.audio && (barWindow.audioTab === "outputs" ? (node.isSink && !node.isStream) : (barWindow.audioTab === "inputs" ? (!node.isSink && !node.isStream) : node.isStream)))
                            }
                            delegate: Rectangle {
                                required property var modelData
                                width: ListView.view.width; height: 98; radius: 14
                                color: (barWindow.audioTab === "outputs" && Pipewire.defaultAudioSink === modelData) || (barWindow.audioTab === "inputs" && Pipewire.defaultAudioSource === modelData) ? "#2d2640" : shellState.raised
                                border.color: shellState.edge; border.width: 1
                                PwObjectTracker { objects: [modelData] }
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 5
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: modelData.description || modelData.name || "Audio node"; color: shellState.text; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight }
                                        ToolButton {
                                            text: modelData.audio && modelData.audio.muted ? "×" : "◖"; Layout.preferredWidth: 28; Layout.preferredHeight: 26
                                            onClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                                            background: Rectangle { radius: 12; color: "transparent" }
                                            contentItem: Text { text: parent.text; color: shellState.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: barWindow.audioTab === "outputs" && Pipewire.defaultAudioSink === modelData ? "DEFAULT OUTPUT" : (barWindow.audioTab === "inputs" && Pipewire.defaultAudioSource === modelData ? "DEFAULT INPUT" : (modelData.isStream ? "APPLICATION" : "AVAILABLE"))
                                            color: shellState.violet; font.family: "monospace"; font.pixelSize: 8; Layout.preferredWidth: 85
                                        }
                                        Slider {
                                            Layout.fillWidth: true; from: 0; to: 1.5
                                            value: modelData.audio ? modelData.audio.volume : 0
                                            enabled: !!modelData.audio
                                            onMoved: if (modelData.audio) modelData.audio.volume = value
                                        }
                                        ToolButton {
                                            visible: !modelData.isStream
                                            text: (barWindow.audioTab === "outputs" && Pipewire.defaultAudioSink === modelData) || (barWindow.audioTab === "inputs" && Pipewire.defaultAudioSource === modelData) ? "✓" : "SET"
                                            onClicked: {
                                                if (barWindow.audioTab === "outputs") Pipewire.preferredDefaultAudioSink = modelData;
                                                else if (barWindow.audioTab === "inputs") Pipewire.preferredDefaultAudioSource = modelData;
                                            }
                                            contentItem: Text { text: parent.text; color: shellState.chartreuse; font.family: "monospace"; font.pixelSize: 8; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        }
                                    }
                                }
                            }
                            footer: Text {
                                visible: Pipewire.nodes.values.filter(node => node.audio && (barWindow.audioTab === "outputs" ? (node.isSink && !node.isStream) : (barWindow.audioTab === "inputs" ? (!node.isSink && !node.isStream) : node.isStream))).length === 0
                                text: "No matching PipeWire devices are available."; color: shellState.muted; font.pixelSize: 11; padding: 12
                            }
                        }
                        Text { text: "Live controls via Quickshell PipeWire · WirePlumber"; color: "#736b85"; font.family: "monospace"; font.pixelSize: 8 }
                    }
                }
            }

            PopupWindow {
                id: mediaPopup
                anchor.item: mediaButton
                anchor.edges: Edges.Bottom | Edges.Left
                anchor.gravity: Edges.Bottom | Edges.Left
                anchor.margins.bottom: -5
                width: Math.min(660, Math.max(320, barWindow.screen.width - 24)); height: Math.min(560, barWindow.screen.height - 48)
                visible: barWindow.openPanel === "media"
                focusable: true; grabFocus: true
                onVisibleChanged: if (!visible && barWindow.openPanel === "media") barWindow.openPanel = ""
                property string mediaTab: "lyrics"
                FluidPanel {
                    anchors.fill: parent
                    attachmentX: Math.min(width - 48, Math.max(48, mediaButton.width * 0.5))
                    focus: true
                    Keys.onEscapePressed: { barWindow.openPanel = ""; event.accepted = true; }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 18; anchors.topMargin: 31; spacing: 13
                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                Layout.preferredWidth: 182; Layout.preferredHeight: 182; radius: 14; color: "#201b2b"; clip: true
                                Image { id: cover; anchors.fill: parent; source: shellState.activePlayer ? shellState.activePlayer.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                                Rectangle { anchors.fill: parent; color: "#650b0912"; visible: cover.status === Image.Ready }
                                Text { anchors.centerIn: parent; text: "C"; color: shellState.chartreuse; font.family: "monospace"; font.pixelSize: 64; font.bold: true; visible: cover.status !== Image.Ready }
                                Canvas {
                                    anchors.fill: parent
                                    onPaint: {
                                        const ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        const levels = [0.28, 0.54, 0.76, 0.42, 0.91, 0.63, 0.35, 0.72, 0.48];
                                        const barWidth = 8;
                                        const gap = 7;
                                        const baseY = height * 0.86;
                                        ctx.fillStyle = "#d8f55a";
                                        ctx.globalAlpha = 0.92;
                                        for (let i = 0; i < levels.length; i++) {
                                            const barHeight = 12 + levels[i] * 34;
                                            ctx.fillRect(width * 0.08 + i * (barWidth + gap), baseY - barHeight, barWidth, barHeight);
                                        }
                                        ctx.globalAlpha = 1;
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: 9
                                Text { text: "NOW IN ROTATION"; color: shellState.chartreuse; font.family: "monospace"; font.pixelSize: 9; letterSpacing: 1.2 }
                                Text { Layout.fillWidth: true; text: shellState.activePlayer ? (shellState.activePlayer.trackTitle || "Untitled") : "No MPRIS player"; color: shellState.text; font.family: "monospace"; font.pixelSize: 19; font.bold: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                                Text { Layout.fillWidth: true; text: shellState.activePlayer ? (shellState.activePlayer.trackArtist || "Unknown artist") : "Start Spotify or another MPRIS player"; color: shellState.muted; font.pixelSize: 13; elide: Text.ElideRight }
                                RowLayout {
                                    Rectangle { radius: 12; color: shellState.raised; implicitWidth: sourceText.implicitWidth + 16; implicitHeight: 25
                                        Text { id: sourceText; anchors.centerIn: parent; text: shellState.activePlayer ? shellState.activePlayer.identity : "MPRIS"; color: shellState.violet; font.family: "monospace"; font.pixelSize: 9 }
                                    }
                                    Text { Layout.fillWidth: true; text: Pipewire.defaultAudioSink ? "↗ " + (Pipewire.defaultAudioSink.description || Pipewire.defaultAudioSink.name) : "Audio route unavailable"; color: shellState.muted; font.family: "monospace"; font.pixelSize: 9; elide: Text.ElideRight }
                                }
                            }
                        }
                        Slider {
                            id: seekSlider
                            Layout.fillWidth: true; from: 0; to: shellState.activePlayer && shellState.activePlayer.length > 0 ? shellState.activePlayer.length : 1
                            value: shellState.activePlayer && shellState.activePlayer.positionSupported ? shellState.activePlayer.position : 0
                            enabled: !!(shellState.activePlayer && shellState.activePlayer.canSeek)
                            onMoved: if (shellState.activePlayer && shellState.activePlayer.canSeek) shellState.activePlayer.position = value
                        }
                        RowLayout {
                            Text { text: shellState.activePlayer ? barWindow.formatDuration(shellState.activePlayer.position) : "00:00"; color: shellState.muted; font.family: "monospace"; font.pixelSize: 9 }
                            Item { Layout.fillWidth: true }
                            ToolButton { text: "|◀"; enabled: !!(shellState.activePlayer && shellState.activePlayer.canGoPrevious); onClicked: if (shellState.activePlayer) shellState.activePlayer.previous(); contentItem: Text { text: parent.text; color: shellState.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
                            ToolButton {
                                text: shellState.activePlayer && shellState.activePlayer.isPlaying ? "Ⅱ" : "▶"
                                enabled: !!(shellState.activePlayer && shellState.activePlayer.canTogglePlaying)
                                onClicked: if (shellState.activePlayer) shellState.activePlayer.togglePlaying()
                                background: Rectangle { radius: 14; color: shellState.chartreuse }
                                contentItem: Text { text: parent.text; color: shellState.ink; font.bold: true; font.pixelSize: 17; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                            ToolButton { text: "▶|"; enabled: !!(shellState.activePlayer && shellState.activePlayer.canGoNext); onClicked: if (shellState.activePlayer) shellState.activePlayer.next(); contentItem: Text { text: parent.text; color: shellState.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
                            Item { Layout.fillWidth: true }
                            Text { text: shellState.activePlayer ? barWindow.formatDuration(shellState.activePlayer.length) : "00:00"; color: shellState.muted; font.family: "monospace"; font.pixelSize: 9 }
                        }
                        RowLayout {
                            Repeater {
                                model: ["equalizer", "audio", "lyrics"]
                                delegate: ToolButton {
                                    required property string modelData
                                    text: modelData.toUpperCase()
                                    Layout.fillWidth: true; Layout.preferredHeight: 31
                                    onClicked: mediaPopup.mediaTab = modelData
                                    background: Rectangle { color: mediaPopup.mediaTab === parent.modelData ? shellState.chartreuse : shellState.raised; radius: 12 }
                                    contentItem: Text { text: parent.text; color: mediaPopup.mediaTab === parent.modelData ? shellState.ink : shellState.muted; font.family: "monospace"; font.pixelSize: 9; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                }
                            }
                        }
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: mediaPopup.mediaTab === "equalizer"
                            ColumnLayout {
                                anchors.centerIn: parent; width: parent.width * 0.9; spacing: 10
                                Text { text: "SYSTEM EFFECTS"; color: shellState.chartreuse; font.family: "monospace"; font.pixelSize: 10; font.bold: true }
                                Text { Layout.fillWidth: true; text: "Corvantium does not apply a pretend EQ. When EasyEffects is installed, open it here to control the active PipeWire effects chain."; color: shellState.text; font.pixelSize: 12; wrapMode: Text.Wrap }
                                Button {
                                    text: "Open EasyEffects"
                                    onClicked: { easyeffectsProcess.exec([Quickshell.shellDir + "/../scripts/corvantium-launch", "effects"]) }
                                    background: Rectangle { radius: 12; color: shellState.raised }
                                    contentItem: Text { text: parent.text; color: shellState.violet; padding: 8; horizontalAlignment: Text.AlignHCenter }
                                }
                            }
                        }
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: mediaPopup.mediaTab === "audio"
                            ColumnLayout {
                                anchors.fill: parent; spacing: 8
                                Text { text: "OUTPUT DEVICE"; color: shellState.chartreuse; font.family: "monospace"; font.pixelSize: 9 }
                                Repeater {
                                    model: ScriptModel { values: Pipewire.nodes.values.filter(node => node.audio && node.isSink && !node.isStream) }
                                    delegate: ToolButton {
                                        required property var modelData
                                        Layout.fillWidth: true; Layout.preferredHeight: 34
                                        text: (Pipewire.defaultAudioSink === modelData ? "✓  " : "   ") + (modelData.description || modelData.name)
                                        onClicked: Pipewire.preferredDefaultAudioSink = modelData
                                        background: Rectangle { radius: 12; color: Pipewire.defaultAudioSink === parent.modelData ? "#2d2640" : shellState.raised }
                                        contentItem: Text { text: parent.text; color: shellState.text; font.pixelSize: 10; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; leftPadding: 8 }
                                    }
                                }
                                Text { visible: !Pipewire.defaultAudioSink; text: "No PipeWire output is connected."; color: shellState.muted; font.pixelSize: 11 }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 6
                            visible: mediaPopup.mediaTab === "lyrics"
                            RowLayout {
                                Text { text: "LRCLIB · " + (shellState.lyricData.status || "waiting").toUpperCase(); color: shellState.chartreuse; font.family: "monospace"; font.pixelSize: 9 }
                                Item { Layout.fillWidth: true }
                                ToolButton { text: "−"; onClicked: shellState.lyricOffset -= 250; contentItem: Text { text: parent.text; color: shellState.muted; horizontalAlignment: Text.AlignHCenter } }
                                Text { text: (shellState.lyricOffset >= 0 ? "+" : "") + shellState.lyricOffset + " ms"; color: shellState.muted; font.family: "monospace"; font.pixelSize: 9 }
                                ToolButton { text: "+"; onClicked: shellState.lyricOffset += 250; contentItem: Text { text: parent.text; color: shellState.muted; horizontalAlignment: Text.AlignHCenter } }
                            }
                            ListView {
                                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 9
                                model: shellState.lyricLines
                                visible: shellState.lyricLines.length > 0
                                delegate: Text {
                                    required property var modelData
                                    width: ListView.view.width
                                    text: modelData.text
                                    color: shellState.activePlayer && shellState.activePlayer.position * 1000 + shellState.lyricOffset >= modelData.time * 1000 ? shellState.violet : shellState.muted
                                    font.family: "monospace"; font.pixelSize: shellState.activePlayer && shellState.activePlayer.position * 1000 + shellState.lyricOffset >= modelData.time * 1000 ? 14 : 12
                                    font.bold: shellState.activePlayer && shellState.activePlayer.position * 1000 + shellState.lyricOffset >= modelData.time * 1000
                                    wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                                }
                            }
                            Text {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                visible: shellState.lyricLines.length === 0 && !!shellState.lyricData.plain
                                text: shellState.lyricData.plain || ""
                                color: shellState.muted; font.family: "monospace"; font.pixelSize: 12; wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { Layout.fillWidth: true; text: shellState.lyricData.message || ""; color: shellState.muted; font.pixelSize: 9; elide: Text.ElideRight }
                                ToolButton {
                                    text: "SEARCH"
                                    visible: !!shellState.lyricData.search_url
                                    onClicked: launcherForLyrics.exec([Quickshell.shellDir + "/../scripts/corvantium-launch", "browser", shellState.lyricData.search_url])
                                    contentItem: Text { text: parent.text; color: shellState.chartreuse; font.family: "monospace"; font.pixelSize: 8 }
                                }
                            }
                        }
                    }
                }
            }
            Process { id: easyeffectsProcess }
            Process { id: launcherForLyrics }
            Process { id: launcherForWeather }

            PopupWindow {
                id: calendarPopup
                anchor.item: clockButton
                anchor.edges: Edges.Bottom | Edges.Right
                anchor.gravity: Edges.Bottom | Edges.Right
                anchor.margins.bottom: -5
                width: Math.min(960, Math.max(300, barWindow.screen.width - 24)); height: Math.min(500, barWindow.screen.height - 48)
                visible: barWindow.openPanel === "calendar"
                focusable: true; grabFocus: true
                onVisibleChanged: if (!visible && barWindow.openPanel === "calendar") barWindow.openPanel = ""
                FluidPanel {
                    anchors.fill: parent
                    attachmentX: width - clockButton.width * 0.5
                    focus: true
                    Keys.onEscapePressed: { barWindow.openPanel = ""; event.accepted = true; }
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 20; anchors.topMargin: 34; spacing: 16
                        ColumnLayout {
                            Layout.preferredWidth: Math.min(270, Math.max(150, (calendarPopup.width - 64) * 0.38)); Layout.fillHeight: true; spacing: 12
                            RowLayout {
                                ToolButton { text: "‹"; onClicked: barWindow.changeMonth(-1); contentItem: Text { text: parent.text; color: shellState.text; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter } }
                                Text { Layout.fillWidth: true; text: Qt.formatDate(new Date(barWindow.monthYear, barWindow.monthIndex, 1), "MMMM yyyy").toUpperCase(); color: shellState.text; font.family: "monospace"; font.pixelSize: 11; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                                ToolButton { text: "›"; onClicked: barWindow.changeMonth(1); contentItem: Text { text: parent.text; color: shellState.text; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter } }
                            }
                            GridLayout {
                                Layout.fillWidth: true; columns: 7; rowSpacing: 5; columnSpacing: 3
                                Repeater {
                                    model: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
                                    delegate: Text { required property string modelData; text: modelData; color: shellState.muted; font.family: "monospace"; font.pixelSize: 8; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                                }
                                Repeater {
                                    model: 42
                                    delegate: ToolButton {
                                        required property int index
                                        readonly property var cellDate: barWindow.dateForCell(index)
                                        Layout.fillWidth: true; Layout.preferredHeight: 31
                                        text: String(cellDate.getDate())
                                        onClicked: barWindow.pickedDate = cellDate
                                        background: Rectangle {
                                            radius: 12
                                            color: cellDate.toDateString() === barWindow.pickedDate.toDateString() ? shellState.chartreuse : "transparent"
                                            border.color: cellDate.toDateString() === new Date().toDateString() ? shellState.violet : "transparent"
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: parent.text
                                            color: cellDate.getMonth() === barWindow.monthIndex ? (cellDate.toDateString() === barWindow.pickedDate.toDateString() ? shellState.ink : shellState.text) : "#736b85"
                                            font.family: "monospace"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                            Item { Layout.fillHeight: true }
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 72; color: shellState.raised; radius: 14
                                Column {
                                    anchors.centerIn: parent; spacing: 3
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: shellState.nowTime; color: shellState.text; font.family: "monospace"; font.pixelSize: 24; font.bold: true }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDate(barWindow.pickedDate, "dddd · dd MMMM yyyy"); color: shellState.muted; font.family: "monospace"; font.pixelSize: 9 }
                                }
                            }
                        }
                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: shellState.edge }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 13
                            RowLayout {
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 4
                                    Text { text: "FORECAST / LOCAL TIME"; color: shellState.chartreuse; font.family: "monospace"; font.pixelSize: 9; letterSpacing: 1 }
                                    Text { text: shellState.nowTime; color: shellState.text; font.family: "monospace"; font.pixelSize: 35; font.bold: true }
                                    Text { text: Qt.formatDate(new Date(), "dddd, dd MMMM yyyy"); color: shellState.muted; font.pixelSize: 11 }
                                }
                                ColumnLayout {
                                    Layout.preferredWidth: 170; spacing: 3
                                    Text { text: shellState.weatherData.ok ? Math.round(shellState.weatherData.current.temperature) + shellState.weatherData.unit : "—"; color: shellState.violet; font.family: "monospace"; font.pixelSize: 32; font.bold: true; horizontalAlignment: Text.AlignRight; Layout.fillWidth: true }
                                    Text { text: shellState.weatherData.ok ? barWindow.weatherText(shellState.weatherData.current.weather_code) : "Weather unavailable"; color: shellState.text; font.pixelSize: 11; horizontalAlignment: Text.AlignRight; Layout.fillWidth: true }
                                    Text { text: shellState.weatherData.location || shellState.weatherData.message || "Set a city in settings"; color: shellState.muted; font.pixelSize: 9; horizontalAlignment: Text.AlignRight; Layout.fillWidth: true; elide: Text.ElideRight }
                                }
                            }
                            Text { text: "NEXT HOURS"; color: shellState.muted; font.family: "monospace"; font.pixelSize: 9; letterSpacing: 1 }
                            ListView {
                                Layout.fillWidth: true; Layout.preferredHeight: 112; orientation: ListView.Horizontal; spacing: 7; clip: true
                                model: shellState.weatherData.hourly || []
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 76; height: 96; radius: 14; color: shellState.raised; border.color: shellState.edge; border.width: 1
                                    Column {
                                        anchors.centerIn: parent; spacing: 7
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: barWindow.timeLabel(modelData.time); color: shellState.muted; font.family: "monospace"; font.pixelSize: 9 }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.temperature) + (shellState.weatherData.unit || "°"); color: shellState.text; font.family: "monospace"; font.pixelSize: 17; font.bold: true }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: (modelData.precipitation_probability || 0) + "% rain"; color: shellState.violet; font.family: "monospace"; font.pixelSize: 8 }
                                    }
                                }
                                footer: Text { visible: !shellState.weatherData.ok; text: shellState.weatherData.message || "No forecast data. Configure a city in shell/settings.json."; color: shellState.muted; font.pixelSize: 10; padding: 8 }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 7
                                Repeater {
                                    model: [
                                        { label: "WIND", value: shellState.weatherData.ok ? shellState.weatherData.current.wind_speed + " m/s" : "—" },
                                        { label: "HUMIDITY", value: shellState.weatherData.ok ? shellState.weatherData.current.humidity + "%" : "—" },
                                        { label: "FEELS LIKE", value: shellState.weatherData.ok ? Math.round(shellState.weatherData.current.feels_like) + shellState.weatherData.unit : "—" },
                                        { label: "RAIN", value: shellState.weatherData.ok ? shellState.weatherData.current.precipitation + " mm" : "—" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true; Layout.fillHeight: true; radius: 14; color: shellState.raised
                                        Column {
                                            anchors.centerIn: parent; spacing: 5
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: shellState.muted; font.family: "monospace"; font.pixelSize: 8 }
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.value; color: shellState.text; font.family: "monospace"; font.pixelSize: 14; font.bold: true }
                                        }
                                    }
                                }
                            }
                            Text {
                                text: shellState.weatherData.show_weather === false ? "Weather is disabled in Corvantium settings." : (shellState.weatherData.ok && shellState.weatherData.stale ? "Cached city forecast · " : "City opt-in · ") + "No GPS lookup · <a href='https://open-meteo.com/'>Open-Meteo data · CC BY 4.0</a>"
                                textFormat: Text.RichText
                                color: "#736b85"; linkColor: shellState.violet
                                font.family: "monospace"; font.pixelSize: 8
                                onLinkActivated: launcherForWeather.exec([Quickshell.shellDir + "/../scripts/corvantium-launch", "browser", link])
                            }
                        }
                    }
                }
            }

            PopupWindow {
                id: settingsPopup
                anchor.item: barWindow.settingsAnchor
                anchor.edges: Edges.Bottom | Edges.Right
                anchor.gravity: Edges.Bottom | Edges.Right
                anchor.margins.bottom: -5
                width: 340; height: 310
                visible: barWindow.openPanel === "settings"
                focusable: true; grabFocus: true
                onVisibleChanged: if (!visible && barWindow.openPanel === "settings") barWindow.openPanel = ""
                FluidPanel {
                    anchors.fill: parent
                    attachmentX: width - 48
                    focus: true
                    Keys.onEscapePressed: { barWindow.openPanel = ""; event.accepted = true; }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 17; anchors.topMargin: 31; spacing: 10
                        Text { text: "CORVANTIUM / SESSION"; color: shellState.chartreuse; font.family: "monospace"; font.pixelSize: 10; font.bold: true; letterSpacing: 1 }
                        Text { text: "An independent Hyprland profile"; color: shellState.text; font.pixelSize: 14; font.bold: true }
                        Text { Layout.fillWidth: true; text: "This session uses its own files under ~/.config/corvantium. The existing Hyprland and Serpantinum configuration trees remain separate."; color: shellState.muted; font.pixelSize: 10; wrapMode: Text.Wrap }
                        Rectangle { Layout.fillWidth: true; height: 1; color: shellState.edge }
                        Text { text: "CONNECTIONS"; color: shellState.chartreuse; font.family: "monospace"; font.pixelSize: 9; letterSpacing: 1 }
                        Text { text: Networking.devices.values.some(d => d.connected) ? "NetworkManager: connected" : "NetworkManager: disconnected / unavailable"; color: shellState.text; font.pixelSize: 10 }
                        Text { text: Bluetooth.defaultAdapter ? (Bluetooth.defaultAdapter.enabled ? "Bluetooth adapter: on · " + Bluetooth.devices.values.length + " connected" : "Bluetooth adapter: off") : "Bluetooth adapter: unavailable"; color: shellState.text; font.pixelSize: 10 }
                        Text { text: "CAMERA PRIVACY"; color: shellState.chartreuse; font.family: "monospace"; font.pixelSize: 9; letterSpacing: 1 }
                        Text { Layout.fillWidth: true; text: shellState.cameraStatus; color: shellState.text; font.family: "monospace"; font.pixelSize: 9; wrapMode: Text.Wrap }
                        Text { Layout.fillWidth: true; text: "Only a reported V4L2 physical privacy control can be toggled. Software app permission is not represented as a hardware shutter."; color: shellState.muted; font.pixelSize: 9; wrapMode: Text.Wrap }
                        Button {
                            text: "Toggle detected V4L2 control"
                            onClicked: { cameraProcess.running = true }
                            background: Rectangle { radius: 12; color: shellState.raised }
                            contentItem: Text { text: parent.text; color: shellState.violet; font.pixelSize: 10; padding: 6; horizontalAlignment: Text.AlignHCenter }
                        }
                        Item { Layout.fillHeight: true }
                        Text { text: Quickshell.shellDir; color: "#736b85"; font.family: "monospace"; font.pixelSize: 8; elide: Text.ElideMiddle; Layout.fillWidth: true }
                    }
                }
            }
        }
    }
}
