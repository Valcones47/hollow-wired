import QtQuick
import "."

// Gauge estilo Caelestia: arco externo de 270° (abertura embaixo) com o
// valor principal, arco interno mais fino com o valor secundário, texto
// grande no centro e o secundário pequeno dentro da abertura de baixo.
// Tudo é desenhado em cima do mesmo centro, então não existe como o texto
// "escorregar" pro lado do anel (causa do desalinhamento da versão antiga:
// anel de 96px ancorado em coluna larga + legendas de larguras diferentes).
Item {
    id: root

    property real value: 0            // 0-1, arco externo
    property real secondaryValue: 0   // 0-1, arco interno
    property string valueText: ""
    property string label: ""
    property string secondaryText: ""
    property string secondaryLabel: ""
    property color color: Theme.primary
    property color secondaryColor: Theme.subtext
    property real thickness: Math.max(8, width * 0.055)

    readonly property real startAngle: 135 * Math.PI / 180
    readonly property real sweep: 270 * Math.PI / 180

    property real animValue: value
    property real animSecondary: secondaryValue
    Behavior on animValue { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
    Behavior on animSecondary { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 400 } }

    onAnimValueChanged: canvas.requestPaint()
    onAnimSecondaryChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onSecondaryColorChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        function arc(ctx, r, frac, style, lw) {
            ctx.strokeStyle = style;
            ctx.lineWidth = lw;
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, r, root.startAngle, root.startAngle + root.sweep * frac);
            ctx.stroke();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.lineCap = "round";
            const rOuter = Math.min(width, height) / 2 - root.thickness / 2;
            const rInner = rOuter - root.thickness * 1.9;
            const thin = root.thickness * 0.55;
            const v = Math.max(0, Math.min(1, root.animValue));
            const s = Math.max(0, Math.min(1, root.animSecondary));

            arc(ctx, rOuter, 1, Theme.withAlpha(root.color, 0.18), root.thickness);
            if (v > 0.002)
                arc(ctx, rOuter, v, root.color, root.thickness);

            arc(ctx, rInner, 1, Theme.withAlpha(root.secondaryColor, 0.15), thin);
            if (s > 0.002)
                arc(ctx, rInner, s, root.secondaryColor, thin);
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -root.height * 0.03
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.valueText
            font.family: Theme.fontFamily
            font.pixelSize: root.width * 0.17
            font.weight: Font.Medium
            color: Theme.textColor
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(11, root.width * 0.065)
            color: Theme.subtext
        }
    }

    // Secundário dentro da abertura de 90° na base do arco.
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.height * 0.02
        spacing: -2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.secondaryText
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(12, root.width * 0.075)
            font.weight: Font.Medium
            color: root.secondaryColor
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.secondaryLabel
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(10, root.width * 0.055)
            color: Theme.withAlpha(Theme.subtext, 0.8)
        }
    }
}
