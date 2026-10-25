import QtQuick

Item {
    id: root

    default property alias contentData: contentLayer.data

    property real attachmentX: width * 0.5
    property real phase: 0
    property color fillColor: "#dc15121e"
    property color rimColor: "#80a88bfa"
    property color glowColor: "#55a88bfa"

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const x = Math.max(42, Math.min(width - 42, root.attachmentX));
            const breathe = Math.sin(root.phase) * 2.2;
            const widthPulse = Math.cos(root.phase * 0.7) * 2.5;

            ctx.beginPath();
            ctx.moveTo(31, 24);
            ctx.lineTo(x - 29, 24);
            ctx.bezierCurveTo(x - 13, 24, x - 17, 5 + breathe, x, 5 + breathe);
            ctx.bezierCurveTo(x + 17, 5 + breathe, x + 13, 24, x + 29, 24);
            ctx.lineTo(width - 32, 24);
            ctx.bezierCurveTo(width - 13, 24, width - 9 + widthPulse, 43, width - 15, 65);
            ctx.bezierCurveTo(width - 5, height * 0.48, width - 13, height - 48, width - 42, height - 26);
            ctx.bezierCurveTo(width * 0.72, height + 4, width * 0.32, height + 3, 42, height - 25);
            ctx.bezierCurveTo(12, height - 42, 13, height - 83, 17, height * 0.55);
            ctx.bezierCurveTo(3, height * 0.34, 8, 24, 31, 24);
            ctx.closePath();

            const wash = ctx.createLinearGradient(0, 0, width, height);
            wash.addColorStop(0, root.fillColor.toString());
            wash.addColorStop(0.55, "#df1b1728");
            wash.addColorStop(1, "#e012101a");
            ctx.shadowColor = root.glowColor.toString();
            ctx.shadowBlur = 22;
            ctx.fillStyle = wash;
            ctx.fill();
            ctx.shadowBlur = 0;
            ctx.lineWidth = 1.2;
            ctx.strokeStyle = root.rimColor.toString();
            ctx.stroke();

            ctx.globalAlpha = 0.22;
            ctx.fillStyle = "#d8f55a";
            ctx.beginPath(); ctx.arc(width - 47, 46 + breathe, 2, 0, Math.PI * 2); ctx.fill();
            ctx.fillStyle = "#a88bfa";
            ctx.beginPath(); ctx.arc(width - 64, 58 - breathe, 1.5, 0, Math.PI * 2); ctx.fill();
            ctx.globalAlpha = 1;
        }
    }

    Item {
        id: contentLayer
        anchors.fill: parent
        z: 1
    }

    Timer {
        interval: 70
        repeat: true
        running: root.visible
        onTriggered: {
            root.phase = (root.phase + 0.045) % (Math.PI * 2);
            canvas.requestPaint();
        }
    }
}
