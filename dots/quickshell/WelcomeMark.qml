pragma ComponentBehavior: Bound
import QtQuick
import "."

// Marca da tela de boas-vindas: três órbitas em ângulos diferentes girando
// devagar em torno de um núcleo.
//
// Cada órbita é uma elipse desenhada uma única vez num Canvas; quem gira é o
// item que a contém, então a animação é só transformação na GPU — nada é
// repintado a cada quadro, o que importa na placa integrada.
Item {
    id: mark

    // Desligado, a marca fica parada (usada pequena, ao lado do nome).
    property bool spin: true
    readonly property real unit: Math.min(width, height)

    Repeater {
        model: [
            { tilt: 0,   dur: 16000, w: 0.98, h: 0.44, c: 0 },
            { tilt: 60,  dur: 21000, w: 0.94, h: 0.40, c: 1 },
            { tilt: 120, dur: 27000, w: 0.90, h: 0.36, c: 0 }
        ]
        delegate: Item {
            id: orbit
            required property var modelData
            anchors.centerIn: parent
            width: mark.unit
            height: mark.unit

            property real spinAngle
            rotation: orbit.modelData.tilt + orbit.spinAngle

            NumberAnimation on spinAngle {
                running: mark.spin
                from: 0
                to: 360
                duration: orbit.modelData.dur
                loops: Animation.Infinite
            }

            Canvas {
                id: ringCanvas
                anchors.fill: parent
                readonly property color stroke: Theme.withAlpha(
                    orbit.modelData.c === 0 ? Theme.primary : Theme.secondary, 0.8)
                onStrokeChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const lw = Math.max(1.5, mark.unit * 0.022);
                    ctx.lineWidth = lw;
                    ctx.strokeStyle = ringCanvas.stroke;
                    ctx.beginPath();
                    ctx.ellipse(
                        (width - mark.unit * orbit.modelData.w) / 2 + lw / 2,
                        (height - mark.unit * orbit.modelData.h) / 2 + lw / 2,
                        mark.unit * orbit.modelData.w - lw,
                        mark.unit * orbit.modelData.h - lw);
                    ctx.stroke();
                }
            }
        }
    }

    // Núcleo com um halo, para o centro não ficar vazio.
    Rectangle {
        anchors.centerIn: parent
        width: mark.unit * 0.26
        height: width
        radius: width / 2
        color: Theme.withAlpha(Theme.primary, 0.16)
    }
    Rectangle {
        anchors.centerIn: parent
        width: mark.unit * 0.13
        height: width
        radius: width / 2
        color: Theme.primary
    }
}
