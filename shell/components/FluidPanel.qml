import QtQuick

Item {
    id: root

    default property alias contentData: contentLayer.data

    property real attachmentX: width * 0.5
    property real phase: 0
    property color fillColor: "#fa171c1f"
    property color rimColor: "#708bd0d8"
    property color glowColor: "#338bd0d8"
    property bool animationEnabled: true
    property real reveal: animationEnabled ? 1 : 0

    opacity: reveal
    scale: 0.975 + reveal * 0.025
    Behavior on reveal {
        NumberAnimation { duration: 145; easing.type: Easing.OutCubic }
    }
    onRevealChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const radius = 14;
            const x = Math.max(48, Math.min(width - 48, root.attachmentX));
            const breathe = (root.reveal - 0.5) * 1.1;
            const top = 10;
            const apex = 0;

            ctx.beginPath();
            ctx.moveTo(radius, top);
            ctx.lineTo(x - 25, top);
            ctx.bezierCurveTo(x - 12, top, x - 15, apex + breathe, x, apex + breathe);
            ctx.bezierCurveTo(x + 15, apex + breathe, x + 12, top, x + 25, top);
            ctx.lineTo(width - radius, top);
            ctx.quadraticCurveTo(width, top, width, top + radius);
            ctx.lineTo(width, height - radius);
            ctx.quadraticCurveTo(width, height, width - radius, height);
            ctx.lineTo(radius, height);
            ctx.quadraticCurveTo(0, height, 0, height - radius);
            ctx.lineTo(0, top + radius);
            ctx.quadraticCurveTo(0, top, radius, top);
            ctx.closePath();

            const wash = ctx.createLinearGradient(0, 0, width, height);
            wash.addColorStop(0, root.fillColor.toString());
            wash.addColorStop(0.55, "#fa1b2326");
            wash.addColorStop(1, "#fa171c1f");
            ctx.shadowColor = root.glowColor.toString();
            ctx.shadowBlur = 14;
            ctx.fillStyle = wash;
            ctx.fill();
            ctx.shadowBlur = 0;
            ctx.lineWidth = 1.2;
            ctx.strokeStyle = root.rimColor.toString();
            ctx.stroke();

            ctx.globalAlpha = 0.3;
            ctx.fillStyle = "#8bd2dc";
            ctx.beginPath(); ctx.arc(width - 25, 49 + breathe, 2, 0, Math.PI * 2); ctx.fill();
            ctx.fillStyle = "#c4dfe2";
            ctx.beginPath(); ctx.arc(width - 42, 49 - breathe, 1.5, 0, Math.PI * 2); ctx.fill();
            ctx.globalAlpha = 1;
        }
    }

    Item {
        id: contentLayer
        anchors.fill: parent
        y: 8 * (1 - root.reveal)
        Behavior on y {
            NumberAnimation { duration: 145; easing.type: Easing.OutCubic }
        }
        z: 1
    }
}
