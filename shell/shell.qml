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
    property bool overlayOpen: false
    property bool barVisible: true
    property string requestedPanel: ""
    property string networkSpeedText: "↓ — ↑ —"
    property string networkInterface: ""
    property int previousRxBytes: -1
    property int previousTxBytes: -1

    IpcHandler {
        target: "corvantium"
        function toggleOverlay(): void { shellState.overlayOpen = !shellState.overlayOpen; }
        function closeOverlay(): void { shellState.overlayOpen = false; }
        function toggleBar(): void { shellState.barVisible = !shellState.barVisible; }
        function toggleMedia(): void { shellState.requestedPanel = shellState.requestedPanel === "media" ? "" : "media"; }
        function showPanel(panel: string): void { shellState.requestedPanel = panel; }
    }

    Process { id: overlayActionProcess }

    function launchAction(action) {
        overlayActionProcess.exec([Quickshell.shellDir + "/../scripts/corvantium-launch", action]);
    }

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
            lyricData = ({ status: "loading", message: "Finding synchronized lyrics…", lines: [] });
            lyricLines = [];
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

    function compactRate(bytesPerSecond) {
        if (bytesPerSecond < 1000) return Math.round(bytesPerSecond) + "B/s";
        if (bytesPerSecond < 1000000) return (bytesPerSecond / 1000).toFixed(1) + "K/s";
        if (bytesPerSecond < 1000000000) return (bytesPerSecond / 1000000).toFixed(1) + "M/s";
        return (bytesPerSecond / 1000000000).toFixed(1) + "G/s";
    }

    function activeNetworkInterface() {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].type !== DeviceType.Wifi || devices[i].name === "lo") continue;
            const networks = devices[i].networks.values;
            for (let n = 0; n < networks.length; n++) {
                if (networks[n].connected) return devices[i].name;
            }
        }
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].connected && devices[i].name !== "lo") return devices[i].name;
        }
        return "";
    }

    function pollNetworkSpeed() {
        networkSpeedProcess.exec([
            "python3", Quickshell.shellDir + "/services/network_speed.py", activeNetworkInterface()
        ]);
    }

    function currentLyricIndex() {
        if (!activePlayer || lyricLines.length === 0) return -1;
        const position = (activePlayer.position || 0) * 1000 + lyricOffset;
        let current = -1;
        for (let i = 0; i < lyricLines.length; i++) {
            if (lyricLines[i].time * 1000 > position) break;
            current = i;
        }
        return current;
    }

    function currentLyricLine() {
        const index = currentLyricIndex();
        if (index >= 0) return lyricLines[index].text;
        const plain = (lyricData.plain || "").split(/\r?\n/).map(line => line.trim()).filter(line => line.length > 0);
        return plain.length > 0 ? plain[0] : "";
    }

    function barLyricText() {
        const line = currentLyricLine();
        if (line) return line;
        if (!activePlayer) return "PLAY TO SYNC LYRICS";
        if (lyricData.status === "loading") return "FINDING LYRICS…";
        if (lyricData.status === "offline") return "LYRICS SERVICE OFFLINE";
        if (lyricData.status === "no-match") return "NO LYRICS FOUND FOR THIS TRACK";
        return "LYRICS WILL APPEAR HERE";
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
    Process {
        id: networkSpeedProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const sample = JSON.parse(text);
                    if (!sample.interface || sample.interface !== shellState.networkInterface || shellState.previousRxBytes < 0) {
                        shellState.networkSpeedText = "↓ — ↑ —";
                    } else {
                        const rxRate = Math.max(0, (sample.rx - shellState.previousRxBytes) / 2);
                        const txRate = Math.max(0, (sample.tx - shellState.previousTxBytes) / 2);
                        shellState.networkSpeedText = "↓ " + shellState.compactRate(rxRate) + " ↑ " + shellState.compactRate(txRate);
                    }
                    shellState.networkInterface = sample.interface || "";
                    shellState.previousRxBytes = sample.rx;
                    shellState.previousTxBytes = sample.tx;
                } catch (error) {
                    shellState.networkSpeedText = "↓ — ↑ —";
                    shellState.networkInterface = "";
                    shellState.previousRxBytes = -1;
                    shellState.previousTxBytes = -1;
                }
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
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: shellState.pollNetworkSpeed()
    }
    Component.onCompleted: {
        updateClock();
        refreshPlayer();
        weatherProcess.running = true;
        keyboardProcess.running = true;
        pollNetworkSpeed();
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
            visible: shellState.barVisible
            anchors { top: true; left: true; right: true }
            implicitHeight: 44
            exclusiveZone: 44
            color: "transparent"

            property string openPanel: ""
            property var settingsAnchor: null
            property var calendarAnchor: null
            property string audioTab: "outputs"
            property int monthYear: new Date().getFullYear()
            property int monthIndex: new Date().getMonth()
            property var pickedDate: new Date()
            property string cameraStatus: "checking supported controls…"
            property var selectedWifiNetwork: null
            property string wifiPassword: ""

            function togglePanel(name) {
                openPanel = openPanel === name ? "" : name;
                shellState.requestedPanel = openPanel;
            }
            function closePanel(name) {
                if (openPanel === name) {
                    openPanel = "";
                    shellState.requestedPanel = "";
                }
            }
            function scanWifi() {
                if (!Networking.wifiEnabled) return;
                const devices = Networking.devices.values;
                for (let i = 0; i < devices.length; i++) {
                    if (devices[i].type === DeviceType.Wifi) devices[i].scannerEnabled = true;
                }
            }
            function wifiDevice() {
                const devices = Networking.devices.values;
                for (let i = 0; i < devices.length; i++) {
                    if (devices[i].type === DeviceType.Wifi) return devices[i];
                }
                return null;
            }
            function availableWifiNetworks() {
                const device = wifiDevice();
                if (!device) return [];
                const networks = device.networks.values.slice();
                networks.sort((a, b) => a.connected !== b.connected ? (b.connected - a.connected) : b.signalStrength - a.signalStrength);
                return networks;
            }
            function currentWifiNetwork() {
                const networks = availableWifiNetworks();
                for (let i = 0; i < networks.length; i++) {
                    if (networks[i].connected) return networks[i];
                }
                return null;
            }
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
                calendarAnchor = clockButton;
                openPanel = shellState.requestedPanel;
            }
            Connections {
                target: shellState
                function onRequestedPanelChanged() {
                    barWindow.openPanel = shellState.requestedPanel;
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "#a80b0912"
                border.width: 0
                radius: 0
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 1; opacity: 0.42
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: shellState.chartreuse }
                        GradientStop { position: 0.48; color: shellState.violet }
                        GradientStop { position: 1.0; color: "#9ad9e2" }
                    }
                }
            }
            RowLayout {
                id: barLayout
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                spacing: 6

                RowLayout {
                    spacing: 5
                    ToolButton {
                        id: launcherButton
                        text: "🐧"
                        onClicked: barWindow.appCommand("search")
                        Layout.preferredWidth: 32; Layout.preferredHeight: 32
                        background: Rectangle { color: parent.hovered ? shellState.raised : "transparent"; radius: 10; }
                        contentItem: Text { text: parent.text; font.pixelSize: 17; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    ToolButton {
                        id: mediaButton
                        Layout.preferredWidth: Math.min(650, Math.max(500, barWindow.screen.width * 0.42))
                        Layout.preferredHeight: 42
                        onClicked: barWindow.togglePanel("media")
                        background: Rectangle {
                            color: barWindow.openPanel === "media" ? "#603b3450" : (parent.hovered ? "#3015121e" : "transparent")
                            radius: 12
                            border.color: barWindow.openPanel === "media" ? "#647dcd78" : "transparent"
                            border.width: 1
                        }
                        contentItem: RowLayout {
                            spacing: 5
                            Rectangle {
                                Layout.preferredWidth: 23; Layout.preferredHeight: 23; radius: 7
                                color: shellState.raised; clip: true
                                Image {
                                    anchors.fill: parent
                                    source: shellState.activePlayer ? shellState.activePlayer.trackArtUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: status === Image.Ready
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "∿"; color: shellState.chartreuse; font.pixelSize: 15
                                    visible: !shellState.activePlayer || shellState.activePlayer.trackArtUrl === ""
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: shellState.activePlayer ? (shellState.activePlayer.trackTitle || "Untitled") : "No player"
                                    color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: shellState.activePlayer ? (shellState.activePlayer.trackArtist || shellState.activePlayer.identity) : "Open a media source"
                                    color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 8
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: shellState.barLyricText()
                                    color: shellState.currentLyricLine().length > 0 ? "#a7e8d4" : shellState.violet
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: 8; font.bold: true
                                    elide: Text.ElideNone; clip: true; visible: text.length > 0
                                }
                            }
                            ToolButton {
                                text: "‹"; enabled: shellState.activePlayer && shellState.activePlayer.canGoPrevious
                                Layout.preferredWidth: 18; Layout.preferredHeight: 23
                                onClicked: if (shellState.activePlayer && shellState.activePlayer.canGoPrevious) shellState.activePlayer.previous()
                                background: Rectangle { color: parent.hovered ? shellState.raised : "transparent"; radius: 8; }
                                contentItem: Text { text: parent.text; color: shellState.muted; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                            ToolButton {
                                text: shellState.activePlayer && shellState.activePlayer.isPlaying ? "Ⅱ" : "▶"
                                enabled: shellState.activePlayer && shellState.activePlayer.canTogglePlaying
                                Layout.preferredWidth: 20; Layout.preferredHeight: 23
                                onClicked: if (shellState.activePlayer && shellState.activePlayer.canTogglePlaying) shellState.activePlayer.togglePlaying()
                                background: Rectangle { color: parent.hovered ? shellState.raised : "transparent"; radius: 8; }
                                contentItem: Text { text: parent.text; color: shellState.chartreuse; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                            ToolButton {
                                text: "›"; enabled: shellState.activePlayer && shellState.activePlayer.canGoNext
                                Layout.preferredWidth: 18; Layout.preferredHeight: 23
                                onClicked: if (shellState.activePlayer && shellState.activePlayer.canGoNext) shellState.activePlayer.next()
                                background: Rectangle { color: parent.hovered ? shellState.raised : "transparent"; radius: 8; }
                                contentItem: Text { text: parent.text; color: shellState.muted; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: 4
                    ToolButton {
                        text: shellState.keyboardLayout
                        Layout.preferredWidth: 30; Layout.preferredHeight: 24
                        background: Rectangle { color: "transparent" }
                        contentItem: Text { text: parent.text; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    ToolButton {
                        id: networkButton
                        text: {
                            const connected = barWindow.currentWifiNetwork();
                            return "⌁ " + (connected ? connected.name : (Networking.wifiEnabled ? "Wi-Fi" : "Off"));
                        }
                        Layout.preferredWidth: Math.min(112, Math.max(72, barWindow.screen.width * 0.075)); Layout.preferredHeight: 25
                        background: Rectangle { color: barWindow.openPanel === "wifi" || parent.hovered ? shellState.raised : "transparent"; radius: 10; }
                        contentItem: Text { text: parent.text; color: Networking.wifiEnabled ? "#9ad9e2" : shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; leftPadding: 3; rightPadding: 3 }
                        onClicked: barWindow.togglePanel("wifi")
                    }
                    Text {
                        text: shellState.networkSpeedText
                        color: shellState.muted
                        font.family: "Iosevka Nerd Font"; font.pixelSize: 7
                        Layout.preferredWidth: 88
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    ToolButton {
                        id: bluetoothButton
                        text: "ᛒ"
                        Layout.preferredWidth: 20; Layout.preferredHeight: 24
                        background: Rectangle { color: barWindow.openPanel === "bluetooth" || parent.hovered ? shellState.raised : "transparent"; radius: 9 }
                        contentItem: Text { text: parent.text; color: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? shellState.violet : shellState.muted; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: barWindow.togglePanel("bluetooth")
                    }
                    ToolButton {
                        id: micButton
                        text: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio && Pipewire.defaultAudioSource.audio.muted ? "×" : "◖"
                        Layout.preferredWidth: 20; Layout.preferredHeight: 24
                        onClicked: if (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio) Pipewire.defaultAudioSource.audio.muted = !Pipewire.defaultAudioSource.audio.muted
                        background: Rectangle { color: parent.hovered ? shellState.raised : "transparent"; radius: 9; }
                        contentItem: Text { text: micButton.text; color: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio && Pipewire.defaultAudioSource.audio.muted ? shellState.chartreuse : shellState.muted; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    ToolButton {
                        id: volumeButton
                        text: {
                            const sink = Pipewire.defaultAudioSink;
                            return sink && sink.audio ? (sink.audio.muted ? "×" : "◖ " + Math.round(sink.audio.volume * 100) + "%") : "◖";
                        }
                        Layout.preferredWidth: 49; Layout.preferredHeight: 24
                        onClicked: barWindow.togglePanel("audio")
                        background: Rectangle { color: barWindow.openPanel === "audio" || parent.hovered ? shellState.raised : "transparent"; radius: 9; }
                        contentItem: Text { text: volumeButton.text; color: shellState.violet; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    Text {
                        text: UPower.displayDevice && UPower.displayDevice.ready
                            ? ((UPower.displayDevice.onBattery ? "▰ " : "ϟ ") + Math.round(UPower.displayDevice.percentage <= 1 ? UPower.displayDevice.percentage * 100 : Math.min(100, UPower.displayDevice.percentage)) + "%")
                            : "—"
                        color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; padding: 3
                    }
                }
            }

            RowLayout {
                id: centeredControls
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                ToolButton {
                    id: clockButton
                    Layout.preferredWidth: 100; Layout.preferredHeight: 30
                    onClicked: { barWindow.calendarAnchor = clockButton; barWindow.togglePanel("calendar"); }
                    background: Rectangle { color: barWindow.openPanel === "calendar" || parent.hovered ? shellState.raised : "transparent"; radius: 10; }
                    contentItem: Column {
                        spacing: 0
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: shellState.nowTime; color: shellState.text; font.family: "Iosevka Nerd Font"; font.bold: true; font.pixelSize: 9 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDate(new Date(), "dddd, dd MMMM"); color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 7 }
                    }
                }
                ToolButton {
                    id: weatherButton
                    visible: shellState.weatherData.show_weather !== false
                    Layout.preferredHeight: 28
                    onClicked: { barWindow.calendarAnchor = weatherButton; barWindow.togglePanel("calendar"); }
                    background: Rectangle { color: barWindow.openPanel === "calendar" || parent.hovered ? shellState.raised : "transparent"; radius: 10; }
                    contentItem: RowLayout {
                        spacing: 4
                        Text { text: "☁"; color: "#9ad9e2"; font.pixelSize: 12 }
                        Text { text: shellState.weatherData.ok ? Math.round(shellState.weatherData.current.temperature) + shellState.weatherData.unit : ""; color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 8 }
                    }
                }
            }

            RowLayout {
                id: workspaceTrack
                anchors.left: centeredControls.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                visible: barWindow.screen.width >= 1100
                Text {
                    text: "FIELD"
                    color: shellState.muted
                    font.family: "Iosevka Nerd Font"; font.pixelSize: 6; font.letterSpacing: 0.7
                    Layout.alignment: Qt.AlignVCenter
                }
                Repeater {
                    model: 10
                    delegate: ToolButton {
                        id: workspaceButton
                        required property int index
                        property int workspaceNumber: index + 1
                        readonly property bool isActive: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === workspaceNumber
                        readonly property bool hasWindows: Hyprland.workspaces.values.some(workspace => workspace.id === workspaceNumber)
                        property int fieldWidth: isActive ? 24 : 8
                        Layout.preferredWidth: fieldWidth
                        Layout.preferredHeight: 24
                        onClicked: Hyprland.dispatch(
                            Hyprland.usingLua
                                ? "hl.dsp.focus({ workspace = \"" + workspaceNumber + "\" })"
                                : "workspace " + workspaceNumber
                        )
                        background: Rectangle {
                            radius: workspaceButton.isActive ? 7 : 5
                            color: workspaceButton.isActive ? shellState.chartreuse : (parent.hovered ? shellState.raised : "transparent")
                            border.width: workspaceButton.hasWindows && !workspaceButton.isActive ? 1 : 0
                            border.color: shellState.violet
                            Text {
                                anchors.centerIn: parent
                                visible: workspaceButton.isActive
                                text: workspaceButton.workspaceNumber < 10 ? "0" + workspaceButton.workspaceNumber : String(workspaceButton.workspaceNumber)
                                color: shellState.ink; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; font.bold: true
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                visible: !workspaceButton.isActive
                                width: workspaceButton.hasWindows ? 5 : 3
                                height: workspaceButton.hasWindows ? 5 : 3
                                radius: 3
                                color: workspaceButton.hasWindows ? shellState.violet : "#514b5d"
                            }
                        }
                        contentItem: Item {}
                    }
                }
            }

            PopupWindow {
                id: audioPopup
                color: "transparent"
                surfaceFormat.opaque: false
                anchor.item: volumeButton
                anchor.edges: Edges.Bottom | Edges.HCenter
                anchor.gravity: Edges.Bottom | Edges.HCenter
                anchor.margins.bottom: 0
                implicitWidth: Math.min(300, Math.max(270, barWindow.screen.width - 24)); implicitHeight: Math.min(310, barWindow.screen.height - 48)
                visible: barWindow.openPanel === "audio"
                grabFocus: barWindow.openPanel === "audio"
                onVisibleChanged: if (!visible) barWindow.closePanel("audio")
                FluidPanel {
                    anchors.fill: parent
                    attachmentX: width * 0.5
                    focus: true
                    Keys.onEscapePressed: function(event) { barWindow.closePanel("audio"); event.accepted = true; }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; anchors.topMargin: 21; spacing: 9
                        RowLayout {
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Text { text: "SOUND ROUTING"; color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1 }
                                Text { text: Pipewire.defaultAudioSink ? (Pipewire.defaultAudioSink.description || Pipewire.defaultAudioSink.name) : "No output device"; color: shellState.text; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            Text {
                                text: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Math.round(Pipewire.defaultAudioSink.audio.volume * 100) + "%" : "—"
                                color: shellState.violet; font.family: "Iosevka Nerd Font"; font.pixelSize: 18; font.bold: true
                            }
                        }
                        RowLayout {
                            ToolButton {
                                text: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted ? "×" : "◖"
                                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                                onClicked: if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted
                                background: Rectangle { radius: 14; color: shellState.raised }
                                contentItem: Text { text: parent.text; color: shellState.violet; font.pixelSize: 17; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
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
                                    contentItem: Text { text: parent.text; color: barWindow.audioTab === parent.modelData ? shellState.ink : shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                }
                            }
                        }
                        Text {
                            text: barWindow.audioTab === "outputs" ? "PLAYBACK DEVICES" : (barWindow.audioTab === "inputs" ? "RECORDING DEVICES" : "APPLICATION STREAMS")
                            color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.letterSpacing: 1
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
                                        Text { Layout.fillWidth: true; text: modelData.description || modelData.name || "Audio node"; color: shellState.text; font.pixelSize: 10; font.bold: true; elide: Text.ElideRight }
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
                                            color: shellState.violet; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; Layout.preferredWidth: 85
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
                                            contentItem: Text { text: parent.text; color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        }
                                    }
                                }
                            }
                            footer: Text {
                                visible: Pipewire.nodes.values.filter(node => node.audio && (barWindow.audioTab === "outputs" ? (node.isSink && !node.isStream) : (barWindow.audioTab === "inputs" ? (!node.isSink && !node.isStream) : node.isStream))).length === 0
                                text: "No matching PipeWire devices are available."; color: shellState.muted; font.pixelSize: 11; padding: 12
                            }
                        }
                        Text { text: "Live controls via Quickshell PipeWire · WirePlumber"; color: "#736b85"; font.family: "Iosevka Nerd Font"; font.pixelSize: 8 }
                    }
                }
            }

            PopupWindow {
                id: wifiPopup
                color: "transparent"
                surfaceFormat.opaque: false
                anchor.item: networkButton
                anchor.edges: Edges.Bottom | Edges.HCenter
                anchor.gravity: Edges.Bottom | Edges.HCenter
                anchor.margins.bottom: 0
                implicitWidth: Math.min(300, Math.max(270, barWindow.screen.width - 24))
                implicitHeight: Math.min(320, barWindow.screen.height - 48)
                visible: barWindow.openPanel === "wifi"
                grabFocus: barWindow.openPanel === "wifi"
                onVisibleChanged: {
                    if (visible) barWindow.scanWifi();
                    else barWindow.closePanel("wifi");
                }
                FluidPanel {
                    anchors.fill: parent
                    attachmentX: width * 0.5
                    focus: true
                    Keys.onEscapePressed: function(event) { barWindow.closePanel("wifi"); event.accepted = true; }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; anchors.topMargin: 21; spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Text { text: "NETWORK / WIFI"; color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1 }
                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        const connected = barWindow.currentWifiNetwork();
                                        return connected ? connected.name : (Networking.wifiEnabled ? "Not connected" : "Wi-Fi is turned off");
                                    }
                                color: shellState.text; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight
                                }
                            }
                            Button {
                                text: Networking.wifiEnabled ? "Turn off" : "Turn on"
                                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                                background: Rectangle { radius: 11; color: parent.down ? "#63aeba" : "#81cbd7" }
                                contentItem: Text { text: parent.text; color: "#10191b"; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.bold: true; padding: 8; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: Networking.wifiHardwareEnabled ? "Wireless radio available" : "Wireless radio blocked by hardware"; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 8 }
                            Button {
                                text: "Scan"
                                enabled: Networking.wifiEnabled && Networking.devices.values.some(device => device.type === DeviceType.Wifi)
                                onClicked: barWindow.scanWifi()
                                background: Rectangle { radius: 9; color: "#26272b"; border.color: "#485055"; border.width: 1 }
                                contentItem: Text { text: parent.text; color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; padding: 5; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: shellState.edge }
                        Text { text: "AVAILABLE NETWORKS"; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; font.letterSpacing: 1 }
                        ListView {
                            id: wifiNetworks
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 7
                            model: barWindow.availableWifiNetworks()
                            delegate: Rectangle {
                                required property var modelData
                                width: wifiNetworks.width; height: 54; radius: 10
                                color: modelData.connected ? "#5c9eabb8" : "#a9192225"
                                border.color: modelData.connected ? "#8ccfd9" : "#343d40"; border.width: 1
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 9
                                    Rectangle {
                                        Layout.preferredWidth: 32; Layout.preferredHeight: 32; radius: 10
                                        color: modelData.connected ? "#82cad6" : "#252c2f"
                                        Text { anchors.centerIn: parent; text: modelData.connected ? "●" : "⌁"; color: modelData.connected ? "#102023" : "#a5dce3"; font.pixelSize: 15 }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 4
                                            Text { Layout.fillWidth: true; text: modelData.name || "Hidden network"; color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight }
                                            Text { text: modelData.known ? "SAVED" : ""; color: "#a5dce3"; font.family: "Iosevka Nerd Font"; font.pixelSize: 7 }
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true; height: 6; radius: 3; color: "#252d30"
                                            Rectangle { width: parent.width * Math.max(0, Math.min(1, modelData.signalStrength)); height: parent.height; radius: 3; color: "#80cbd7" }
                                        }
                                        Text { text: Math.round(modelData.signalStrength * 100) + "% signal  ·  " + WifiSecurityType.toString(modelData.security); color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; elide: Text.ElideRight }
                                    }
                                    Button {
                                        text: modelData.connected ? "Active" : (modelData.stateChanging ? "…" : "Join")
                                        enabled: !modelData.connected && !modelData.stateChanging
                                        onClicked: {
                                            const security = WifiSecurityType.toString(modelData.security);
                                            if (modelData.known || security === "Open" || !["WpaPsk", "Wpa2Psk", "Sae"].includes(security)) modelData.connect();
                                            else { barWindow.selectedWifiNetwork = modelData; barWindow.wifiPassword = ""; }
                                        }
                                        background: Rectangle { radius: 9; color: parent.enabled ? "#82cad6" : "#30393b" }
                                        contentItem: Text { text: parent.text; color: parent.enabled ? "#102023" : shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; font.bold: true; padding: 7; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                    }
                                }
                            }
                            footer: Text {
                                visible: wifiNetworks.count === 0
                                text: !Networking.wifiEnabled ? "Turn Wi-Fi on to scan for nearby networks." : (Networking.devices.values.some(device => device.type === DeviceType.Wifi) ? "No networks found yet. Press Scan to search again." : "No Wi-Fi device is available to NetworkManager.")
                                color: shellState.muted; font.pixelSize: 10; wrapMode: Text.Wrap; padding: 12
                            }
                        }
                        Rectangle {
                            visible: barWindow.selectedWifiNetwork !== null
                            Layout.fillWidth: true; Layout.preferredHeight: 52; radius: 12; color: "#ae1b2427"; border.color: "#597b8588"; border.width: 1
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 7; spacing: 6
                                TextField {
                                    id: wifiPasswordField
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    placeholderText: "Password for " + (barWindow.selectedWifiNetwork ? barWindow.selectedWifiNetwork.name : "network")
                                    text: barWindow.wifiPassword; onTextChanged: barWindow.wifiPassword = text
                                    echoMode: TextInput.Password
                                    background: Rectangle { radius: 8; color: "#252d30"; border.color: "#435256"; border.width: 1 }
                                    color: shellState.text; placeholderTextColor: shellState.muted; leftPadding: 10
                                    Keys.onReturnPressed: {
                                        if (barWindow.selectedWifiNetwork && barWindow.wifiPassword.length > 0) {
                                            barWindow.selectedWifiNetwork.connectWithPsk(barWindow.wifiPassword);
                                            barWindow.selectedWifiNetwork = null;
                                            barWindow.wifiPassword = "";
                                        }
                                    }
                                }
                                Button {
                                    text: "Connect"
                                    enabled: barWindow.wifiPassword.length > 0
                                    onClicked: {
                                        if (barWindow.selectedWifiNetwork) barWindow.selectedWifiNetwork.connectWithPsk(barWindow.wifiPassword);
                                        barWindow.selectedWifiNetwork = null;
                                        barWindow.wifiPassword = "";
                                    }
                                    background: Rectangle { radius: 8; color: "#82cad6" }
                                    contentItem: Text { text: parent.text; color: "#102023"; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; font.bold: true; padding: 6; horizontalAlignment: Text.AlignHCenter }
                                }
                                Button {
                                    text: "×"; onClicked: barWindow.selectedWifiNetwork = null
                                    background: Rectangle { radius: 8; color: "#252d30" }
                                    contentItem: Text { text: parent.text; color: shellState.text; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter }
                                }
                            }
                        }
                        Text { text: Networking.connectivityCheckEnabled ? "NetworkManager connectivity check: enabled" : "Use saved network profiles for networks already joined."; color: "#808d8f"; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
            }

            PopupWindow {
                id: mediaPopup
                color: "transparent"
                surfaceFormat.opaque: false
                anchor.item: mediaButton
                anchor.edges: Edges.Bottom | Edges.HCenter
                anchor.gravity: Edges.Bottom | Edges.HCenter
                anchor.margins.bottom: 0
                implicitWidth: Math.min(360, Math.max(290, barWindow.screen.width - 24))
                implicitHeight: Math.min(330, barWindow.screen.height - 48)
                visible: barWindow.openPanel === "media"
                grabFocus: barWindow.openPanel === "media"
                onVisibleChanged: if (!visible) barWindow.closePanel("media")
                FluidPanel {
                    anchors.fill: parent
                    attachmentX: width * 0.5
                    focus: true
                    Keys.onEscapePressed: function(event) { barWindow.closePanel("media"); event.accepted = true; }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; anchors.topMargin: 18; spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 3
                                Text { text: "LYRIC / LIVE FIELD"; color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8 }
                                Text {
                                    Layout.fillWidth: true
                                    text: shellState.activePlayer ? (shellState.activePlayer.trackTitle || "Untitled") : "No player active"
                                    color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 12; font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: shellState.activePlayer ? (shellState.activePlayer.trackArtist || shellState.activePlayer.identity) : "Start music to follow lyrics"
                                    color: shellState.muted; font.pixelSize: 9; elide: Text.ElideRight
                                }
                            }
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: shellState.activePlayer && shellState.activePlayer.isPlaying ? shellState.chartreuse : shellState.edge
                            }
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: shellState.edge }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 7
                            Text { text: barWindow.formatDuration(shellState.activePlayer ? shellState.activePlayer.position : 0); color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; Layout.preferredWidth: 35 }
                            Slider {
                                id: mediaSeekSlider
                                Layout.fillWidth: true
                                from: 0
                                to: shellState.activePlayer && shellState.activePlayer.lengthSupported ? shellState.activePlayer.length : 1
                                value: shellState.activePlayer ? Math.min(to, shellState.activePlayer.position) : 0
                                enabled: shellState.activePlayer && shellState.activePlayer.canSeek && shellState.activePlayer.positionSupported && shellState.activePlayer.lengthSupported
                                onMoved: if (shellState.activePlayer) shellState.activePlayer.position = value
                            }
                            Text { text: barWindow.formatDuration(shellState.activePlayer ? shellState.activePlayer.length : 0); color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; Layout.preferredWidth: 35; horizontalAlignment: Text.AlignRight }
                        }
                        ListView {
                            id: lyricList
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 8
                            model: shellState.lyricLines
                            visible: shellState.lyricLines.length > 0
                            currentIndex: shellState.currentLyricIndex()
                            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Center)
                            delegate: Text {
                                required property int index
                                required property var modelData
                                width: ListView.view.width
                                text: modelData.text
                                color: index === lyricList.currentIndex ? shellState.chartreuse : "#d3cfdb"
                                font.family: "Iosevka Nerd Font"; font.pixelSize: index === lyricList.currentIndex ? 13 : 10
                                font.bold: index === lyricList.currentIndex
                                wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                            }
                        }
                        Text {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: shellState.lyricLines.length === 0 && !!shellState.lyricData.plain
                            text: shellState.lyricData.plain || ""
                            color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 12; wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 5
                            visible: shellState.lyricLines.length === 0 && !shellState.lyricData.plain
                            Text {
                                Layout.fillWidth: true
                                text: shellState.lyricData.status === "offline" ? "LYRICS SERVICE OFFLINE" : shellState.lyricData.status === "no-match" ? "NO MATCH FOR THIS TRACK" : "SYNCING LYRICS"
                                color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 11; font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                Layout.fillWidth: true
                                text: shellState.lyricData.message || "The current line will follow playback here."
                                color: shellState.muted; font.pixelSize: 9; wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 4
                            Text { text: "LRCLIB · " + (shellState.lyricData.status || "waiting").toUpperCase(); color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 8 }
                            Item { Layout.fillWidth: true }
                            ToolButton { text: "−"; Layout.preferredWidth: 20; Layout.preferredHeight: 22; onClicked: shellState.lyricOffset -= 250; contentItem: Text { text: parent.text; color: shellState.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
                            Text { text: (shellState.lyricOffset >= 0 ? "+" : "") + shellState.lyricOffset + " ms"; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 8 }
                            ToolButton { text: "+"; Layout.preferredWidth: 20; Layout.preferredHeight: 22; onClicked: shellState.lyricOffset += 250; contentItem: Text { text: parent.text; color: shellState.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
                            ToolButton {
                                text: "SEARCH ↗"
                                visible: !!shellState.lyricData.search_url
                                onClicked: launcherForLyrics.exec([Quickshell.shellDir + "/../scripts/corvantium-launch", "browser", shellState.lyricData.search_url])
                                contentItem: Text { text: parent.text; color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 8 }
                            }
                        }
                    }
                }
            }
            Process { id: launcherForLyrics }
            Process { id: launcherForWeather }

            PopupWindow {
                id: calendarPopup
                color: "transparent"
                surfaceFormat.opaque: false
                anchor.item: barWindow.calendarAnchor
                anchor.edges: Edges.Bottom | Edges.HCenter
                anchor.gravity: Edges.Bottom | Edges.HCenter
                anchor.margins.bottom: 0
                implicitWidth: Math.min(500, Math.max(300, barWindow.screen.width - 24)); implicitHeight: Math.min(310, barWindow.screen.height - 48)
                visible: barWindow.openPanel === "calendar"
                grabFocus: barWindow.openPanel === "calendar"
                onVisibleChanged: if (!visible) barWindow.closePanel("calendar")
                FluidPanel {
                    anchors.fill: parent
                    attachmentX: width * 0.5
                    focus: true
                    Keys.onEscapePressed: function(event) { barWindow.closePanel("calendar"); event.accepted = true; }
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 16; anchors.topMargin: 21; spacing: 12
                        ColumnLayout {
                            Layout.preferredWidth: Math.min(270, Math.max(150, (calendarPopup.width - 64) * 0.38)); Layout.fillHeight: true; spacing: 12
                            RowLayout {
                                ToolButton { text: "‹"; onClicked: barWindow.changeMonth(-1); contentItem: Text { text: parent.text; color: shellState.text; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter } }
                                Text { Layout.fillWidth: true; text: Qt.formatDate(new Date(barWindow.monthYear, barWindow.monthIndex, 1), "MMMM yyyy").toUpperCase(); color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 11; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                                ToolButton { text: "›"; onClicked: barWindow.changeMonth(1); contentItem: Text { text: parent.text; color: shellState.text; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter } }
                            }
                            GridLayout {
                                Layout.fillWidth: true; columns: 7; rowSpacing: 5; columnSpacing: 3
                                Repeater {
                                    model: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
                                    delegate: Text { required property string modelData; text: modelData; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
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
                                            font.family: "Iosevka Nerd Font"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                            Item { Layout.fillHeight: true }
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 72; color: shellState.raised; radius: 14
                                Column {
                                    anchors.centerIn: parent; spacing: 3
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: shellState.nowTime; color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 24; font.bold: true }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDate(barWindow.pickedDate, "dddd · dd MMMM yyyy"); color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 9 }
                                }
                            }
                        }
                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: shellState.edge }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 13
                            RowLayout {
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 4
                                    Text { text: "FORECAST / LOCAL TIME"; color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.letterSpacing: 1 }
                                    Text { text: shellState.nowTime; color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 28; font.bold: true }
                                    Text { text: Qt.formatDate(new Date(), "dddd, dd MMMM yyyy"); color: shellState.muted; font.pixelSize: 11 }
                                }
                                ColumnLayout {
                                    Layout.preferredWidth: 170; spacing: 3
                                    Text { text: shellState.weatherData.ok ? Math.round(shellState.weatherData.current.temperature) + shellState.weatherData.unit : "—"; color: shellState.violet; font.family: "Iosevka Nerd Font"; font.pixelSize: 26; font.bold: true; horizontalAlignment: Text.AlignRight; Layout.fillWidth: true }
                                    Text { text: shellState.weatherData.ok ? barWindow.weatherText(shellState.weatherData.current.weather_code) : "Weather unavailable"; color: shellState.text; font.pixelSize: 11; horizontalAlignment: Text.AlignRight; Layout.fillWidth: true }
                                    Text { text: shellState.weatherData.location || shellState.weatherData.message || "Set a city in settings"; color: shellState.muted; font.pixelSize: 9; horizontalAlignment: Text.AlignRight; Layout.fillWidth: true; elide: Text.ElideRight }
                                }
                            }
                            Text { text: "NEXT HOURS"; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.letterSpacing: 1 }
                            ListView {
                                Layout.fillWidth: true; Layout.preferredHeight: 112; orientation: ListView.Horizontal; spacing: 7; clip: true
                                model: shellState.weatherData.hourly || []
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 76; height: 96; radius: 14; color: shellState.raised; border.color: shellState.edge; border.width: 1
                                    Column {
                                        anchors.centerIn: parent; spacing: 7
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: barWindow.timeLabel(modelData.time); color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 9 }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.temperature) + (shellState.weatherData.unit || "°"); color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 14; font.bold: true }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: (modelData.precipitation_probability || 0) + "% rain"; color: shellState.violet; font.family: "Iosevka Nerd Font"; font.pixelSize: 8 }
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
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 8 }
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.value; color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 14; font.bold: true }
                                        }
                                    }
                                }
                            }
                            Text {
                                text: shellState.weatherData.show_weather === false ? "Weather is disabled in Corvantium settings." : (shellState.weatherData.ok && shellState.weatherData.stale ? "Cached city forecast · " : "City opt-in · ") + "No GPS lookup · <a href='https://open-meteo.com/'>Open-Meteo data · CC BY 4.0</a>"
                                textFormat: Text.RichText
                                color: "#736b85"; linkColor: shellState.violet
                                font.family: "Iosevka Nerd Font"; font.pixelSize: 8
                                onLinkActivated: launcherForWeather.exec([Quickshell.shellDir + "/../scripts/corvantium-launch", "browser", link])
                            }
                        }
                    }
                }
            }

            PopupWindow {
                id: bluetoothPopup
                color: "transparent"
                surfaceFormat.opaque: false
                anchor.item: bluetoothButton
                anchor.edges: Edges.Bottom | Edges.HCenter
                anchor.gravity: Edges.Bottom | Edges.HCenter
                anchor.margins.bottom: 0
                implicitWidth: Math.min(320, Math.max(280, barWindow.screen.width - 24))
                implicitHeight: Math.min(360, barWindow.screen.height - 48)
                visible: barWindow.openPanel === "bluetooth"
                grabFocus: visible
                onVisibleChanged: if (!visible) barWindow.closePanel("bluetooth")
                FluidPanel {
                    anchors.fill: parent
                    attachmentX: width * 0.5
                    focus: true
                    Keys.onEscapePressed: function(event) { barWindow.closePanel("bluetooth"); event.accepted = true; }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; anchors.topMargin: 21; spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Text { text: "BLUETOOTH / DEVICES"; color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.7 }
                                Text {
                                    text: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.name + " · " + (Bluetooth.defaultAdapter.enabled ? "ready" : "off") : "No Bluetooth adapter detected"
                                    color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; elide: Text.ElideRight
                                }
                            }
                            Button {
                                text: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? "Power off" : "Power on"
                                enabled: Bluetooth.defaultAdapter !== null
                                onClicked: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                                background: Rectangle { radius: 8; color: parent.enabled ? "#d8f55a" : shellState.raised }
                                contentItem: Text { text: parent.text; color: parent.enabled ? shellState.ink : shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; font.bold: true; padding: 6; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: Bluetooth.defaultAdapter ? (Bluetooth.defaultAdapter.discovering ? "Searching for nearby devices…" : "Paired and nearby devices") : "Turn on an adapter to manage devices."
                                color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 8
                            }
                            Button {
                                text: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering ? "Stop scan" : "Find devices"
                                enabled: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled
                                onClicked: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = !Bluetooth.defaultAdapter.discovering
                                background: Rectangle { radius: 8; color: shellState.raised; border.color: shellState.edge; border.width: 1 }
                                contentItem: Text { text: parent.text; color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; padding: 6; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: shellState.edge }
                        ListView {
                            id: bluetoothDevices
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6
                            model: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.devices.values : []
                            delegate: Rectangle {
                                required property var modelData
                                width: bluetoothDevices.width; height: 64; radius: 9
                                color: modelData.connected ? "#252b25" : "#171c20"
                                border.color: modelData.connected ? "#7e9e4d" : shellState.edge; border.width: 1
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 9; spacing: 7
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 3
                                        Text { Layout.fillWidth: true; text: modelData.name || modelData.deviceName || "Bluetooth device"; color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.connected ? "CONNECTED" : (modelData.pairing ? "PAIRING…" : (modelData.paired ? "PAIRED · READY TO CONNECT" : "NEARBY · NOT PAIRED")) + (modelData.batteryAvailable ? " · " + Math.round(modelData.battery * 100) + "%" : "")
                                            color: modelData.connected ? shellState.chartreuse : shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; elide: Text.ElideRight
                                        }
                                    }
                                    Button {
                                        text: modelData.connected ? "Disconnect" : (modelData.pairing ? "Cancel" : (modelData.paired ? "Connect" : "Pair"))
                                        enabled: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled
                                        onClicked: {
                                            if (modelData.connected) modelData.disconnect();
                                            else if (modelData.pairing) modelData.cancelPair();
                                            else if (modelData.paired) modelData.connect();
                                            else modelData.pair();
                                        }
                                        background: Rectangle { radius: 7; color: parent.enabled ? "#d8f55a" : shellState.raised }
                                        contentItem: Text { text: parent.text; color: parent.enabled ? shellState.ink : shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; font.bold: true; padding: 5; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                    }
                                    Button {
                                        visible: modelData.paired && !modelData.connected
                                        text: "Forget"
                                        onClicked: modelData.forget()
                                        background: Rectangle { radius: 7; color: "#26262b" }
                                        contentItem: Text { text: parent.text; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; padding: 5; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                    }
                                }
                            }
                            footer: Text {
                                visible: bluetoothDevices.count === 0
                                text: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? "No devices yet. Choose Find devices to scan." : "No adapter is available. Check that BlueZ is running."
                                color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; wrapMode: Text.Wrap; padding: 10
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "For PIN-based pairing or advanced options:"; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; wrapMode: Text.Wrap }
                            Button {
                                text: "Open settings"
                                onClicked: barWindow.appCommand("bluetooth-settings")
                                background: Rectangle { radius: 7; color: shellState.raised }
                                contentItem: Text { text: parent.text; color: shellState.violet; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; padding: 5; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                    }
                }
            }

            PopupWindow {
                id: settingsPopup
                color: "transparent"
                surfaceFormat.opaque: false
                anchor.item: barWindow.settingsAnchor
                anchor.edges: Edges.Bottom | Edges.HCenter
                anchor.gravity: Edges.Bottom | Edges.HCenter
                anchor.margins.bottom: 0
                implicitWidth: 300; implicitHeight: 270
                visible: barWindow.openPanel === "settings"
                grabFocus: barWindow.openPanel === "settings"
                onVisibleChanged: if (!visible) barWindow.closePanel("settings")
                FluidPanel {
                    anchors.fill: parent
                    attachmentX: width * 0.5
                    focus: true
                    Keys.onEscapePressed: function(event) { barWindow.closePanel("settings"); event.accepted = true; }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; anchors.topMargin: 21; spacing: 8
                        Text { text: "CORVANTIUM / FIELD NOTES"; color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.7 }
                        Text { text: "Focus, flow, and signal."; color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 12; font.bold: true }
                        Text { Layout.fillWidth: true; text: "A quiet system surface for the things you check most. Move between fields, follow a track, or tune your connections."; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; wrapMode: Text.Wrap }
                        Rectangle { Layout.fillWidth: true; height: 1; color: shellState.edge }
                        Text { text: "CONNECTIONS"; color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.letterSpacing: 1 }
                        Text { text: Networking.devices.values.some(d => d.connected) ? "NetworkManager: connected" : "NetworkManager: disconnected / unavailable"; color: shellState.text; font.pixelSize: 10 }
                        Text { text: Bluetooth.defaultAdapter ? (Bluetooth.defaultAdapter.enabled ? "Bluetooth adapter: on · " + Bluetooth.devices.values.length + " connected" : "Bluetooth adapter: off") : "Bluetooth adapter: unavailable"; color: shellState.text; font.pixelSize: 10 }
                        Text { text: "CAMERA PRIVACY"; color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.letterSpacing: 1 }
                        Text { Layout.fillWidth: true; text: barWindow.cameraStatus; color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; wrapMode: Text.Wrap }
                        Text { Layout.fillWidth: true; text: "Only a reported V4L2 physical privacy control can be toggled. Software app permission is not represented as a hardware shutter."; color: shellState.muted; font.pixelSize: 9; wrapMode: Text.Wrap }
                        Button {
                            text: "Toggle detected V4L2 control"
                            onClicked: { cameraProcess.running = true }
                            background: Rectangle { radius: 12; color: shellState.raised }
                            contentItem: Text { text: parent.text; color: shellState.violet; font.pixelSize: 10; padding: 6; horizontalAlignment: Text.AlignHCenter }
                        }
                        Item { Layout.fillHeight: true }
                        Text { text: Quickshell.shellDir; color: "#736b85"; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; elide: Text.ElideMiddle; Layout.fillWidth: true }
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: overlayWindow
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            visible: shellState.overlayOpen
            color: "transparent"
            surfaceFormat.opaque: false
            WlrLayershell.namespace: "corvantium:overlay"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: shellState.overlayOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            MouseArea {
                anchors.fill: parent
                onClicked: shellState.overlayOpen = false
            }

            FluidPanel {
                id: overlayCard
                z: 1
                width: Math.min(360, overlayWindow.screen.width - 32)
                height: Math.min(300, overlayWindow.screen.height - 72)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 50
                attachmentX: width * 0.5
                focus: true
                Keys.onEscapePressed: function(event) { shellState.overlayOpen = false; event.accepted = true; }
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 15; anchors.topMargin: 29; spacing: 7
                    RowLayout {
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 3
                            Text { text: "CORVANTIUM / QUICK OVERLAY"; color: shellState.chartreuse; font.family: "Iosevka Nerd Font"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.2 }
                            Text { text: "Controls at a glance."; color: shellState.text; font.pixelSize: 15; font.bold: true }
                        }
                        Text { text: shellState.nowTime; color: "#9ad9e2"; font.family: "Iosevka Nerd Font"; font.pixelSize: 14; font.bold: true }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: shellState.edge }
                    GridLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        columns: 3; rowSpacing: 7; columnSpacing: 7
                        Repeater {
                            model: [
                                { title: "Circle to Search", detail: "Select region · open browser", action: "screen-search" },
                                { title: "Recognize music", detail: "Identify system audio", action: "music-identify" },
                                { title: "Sound devices", detail: "Outputs and inputs", action: "audio" },
                                { title: "Now playing", detail: "Track, controls, lyrics", action: "media" },
                                { title: "Calendar & weather", detail: "Date and forecast", action: "calendar" },
                                { title: "Wi-Fi & settings", detail: "Connections and controls", action: "wifi" },
                                { title: "Wallpaper", detail: "Choose a desktop backdrop", action: "wallpaper" }
                            ]
                            delegate: Button {
                                id: actionCard
                                required property var modelData
                                Layout.fillWidth: true; Layout.fillHeight: true
                                onClicked: {
                                    shellState.overlayOpen = false;
                                    if (modelData.action === "screen-search" || modelData.action === "music-identify" || modelData.action === "wallpaper") shellState.launchAction(modelData.action);
                                    else shellState.requestedPanel = modelData.action;
                                }
                                background: Rectangle { radius: 12; color: parent.down ? "#35454a" : "#851a2327"; border.color: "#557b969a"; border.width: 1 }
                                contentItem: ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 9; spacing: 3
                                    Text { text: actionCard.modelData.title; color: shellState.text; font.pixelSize: 10; font.bold: true; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                    Text { text: actionCard.modelData.detail; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 7; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 4
                        Text { text: "WORKSPACES"; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 7 }
                        Repeater {
                            model: 10
                            delegate: Button {
                                required property int index
                                Layout.fillWidth: true; Layout.preferredHeight: 23
                                onClicked: {
                                    Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.focus({ workspace = \"" + (index + 1) + "\" })" : "workspace " + (index + 1));
                                    shellState.overlayOpen = false;
                                }
                                contentItem: Text { text: String(index + 1); color: shellState.text; font.family: "Iosevka Nerd Font"; font.pixelSize: 8; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { radius: 8; color: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === index + 1 ? "#82cad6" : "#851a2327"; border.color: shellState.edge; border.width: 1 }
                            }
                        }
                    }
                    Text { text: "SUPER + /  KEYBIND GUIDE     ·     ESC  CLOSE"; color: shellState.muted; font.family: "Iosevka Nerd Font"; font.pixelSize: 7 }
                }
            }
        }
    }
}
