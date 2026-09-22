pragma ComponentBehavior: Bound
import QtQuick
import "."

// Cabo feito de glifos: os mesmos caracteres da chuva, enfileirados ao longo
// de um caminho que serpenteia.
//
// Serve para os dois tipos de fiação da tela: o cabo cortado do cenário
// (parado, com barriga de gravidade) e o cabo que liga uma coluna ao olho
// (com os glifos escorrendo para dentro dele).
//
// O caminho não é uma Bézier: é a reta entre as pontas mais uma onda
// perpendicular cuja amplitude zera nas duas extremidades. Fica barato de
// calcular por glifo e é o que dá o movimento de cobra quando a fase anda.
Item {
    id: cable

    property real x0: 0
    property real y0: 0
    property real x1: 100
    property real y1: 100

    property int count: 14
    property real fontSize: 13
    property color glyphColor: "#8fd0d8"
    property real amp: 26           // altura da ondulação
    property real waves: 1.6        // quantas voltas a onda dá no caminho
    property real sag: 0            // barriga para baixo (cabo pendurado)
    property real phase: 0          // anda no tempo = serpenteia
    property real flow: 0           // 0..1, empurra os glifos para a ponta
    property bool flowing: false
    property real headFade: 0.12    // trecho final onde o glifo some (absorvido)
    property string alphabet: "0123456789ΔΞΨΩΣΦΛΓΘΠ#@$%&?*+=<>/\\|_~^≡≠≈"

    readonly property real dx: x1 - x0
    readonly property real dy: y1 - y0
    readonly property real len: Math.max(1, Math.sqrt(dx * dx + dy * dy))
    // normal unitária da reta entre as pontas
    readonly property real nx: -dy / len
    readonly property real ny: dx / len

    function wave(t) {
        return Math.sin(t * cable.waves * Math.PI * 2 + cable.phase) * Math.sin(t * Math.PI);
    }
    function px(t) {
        return cable.x0 + cable.dx * t + cable.nx * cable.amp * cable.wave(t);
    }
    function py(t) {
        return cable.y0 + cable.dy * t + cable.ny * cable.amp * cable.wave(t)
             + cable.sag * Math.sin(t * Math.PI);
    }

    SequentialAnimation on phase {
        running: cable.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: Math.PI * 2; duration: 4200 }
    }

    NumberAnimation on flow {
        running: cable.flowing && cable.visible
        from: 0
        to: 1
        duration: 1400
        loops: Animation.Infinite
    }

    Repeater {
        model: cable.count
        delegate: Text {
            id: bead
            required property int index

            // Cada glifo ocupa uma fatia do caminho; com o fluxo ligado, a
            // fatia anda para a ponta e volta ao começo.
            readonly property real t: {
                const base = (bead.index + 0.5) / cable.count;
                const v = cable.flowing ? base + cable.flow : base;
                return v - Math.floor(v);
            }

            x: cable.px(bead.t) - width / 2
            y: cable.py(bead.t) - height / 2
            text: bead.glyph
            property string glyph: cable.alphabet.charAt(Math.floor(Math.random() * cable.alphabet.length))

            font.family: Theme.monoFamily
            font.pixelSize: cable.fontSize
            color: cable.glyphColor
            // Some ao chegar na ponta: é o olho absorvendo o glifo.
            opacity: cable.flowing
                ? (bead.t > 1 - cable.headFade ? (1 - bead.t) / cable.headFade
                   : (bead.t < 0.06 ? bead.t / 0.06 : 1))
                : 1

            Timer {
                running: cable.visible
                interval: 260 + Math.random() * 500
                repeat: true
                onTriggered: bead.glyph = cable.alphabet.charAt(Math.floor(Math.random() * cable.alphabet.length))
            }
        }
    }
}
