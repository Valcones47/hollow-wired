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

    // ---- modo coluna (stream) ----
    // Usado pela conexão com o olho: um trecho reto vertical (a coluna que
    // continua caindo) de stemTop até (x0, y0), e dali uma curva que sai na
    // vertical e chega no olho. Os glifos andam juntos, espaçados como numa
    // coluna, empurrados por headS (posição do glifo da frente no caminho,
    // em pixels); passando do fim do caminho, somem — o olho os absorve.
    property bool stream: false
    property real stemTop: y0
    property real headS: 0
    property real spacing: fontSize * 1.1
    // Glifos a partir deste índice ficam acima da coluna original: aparecem
    // com `extraFade` em vez de surgir do nada no meio da tela.
    property int solidCount: 0
    property real extraFade: 1
    readonly property real stemLen: Math.max(0, y0 - stemTop)
    // Curva: Bézier quadrática com o controle em (x0, y1) — desce reto e vira
    // para o olho. Tabela de comprimento de arco para os glifos ficarem
    // igualmente espaçados (a Bézier anda mais rápido perto do canto).
    readonly property var lut: {
        if (!cable.stream) return [0];
        const out = [0];
        let px0 = cable.x0, py0 = cable.y0, acc = 0;
        for (let i = 1; i <= 32; i++) {
            const u = i / 32, a = 1 - u;
            const qx = a * a * cable.x0 + 2 * a * u * cable.x0 + u * u * cable.x1;
            const qy = a * a * cable.y0 + 2 * a * u * cable.y1 + u * u * cable.y1;
            acc += Math.sqrt((qx - px0) * (qx - px0) + (qy - py0) * (qy - py0));
            out.push(acc);
            px0 = qx; py0 = qy;
        }
        return out;
    }
    readonly property real curveLen: Math.max(1, cable.lut[cable.lut.length - 1])
    readonly property real pathLen: cable.stemLen + cable.curveLen

    // Ponto do caminho a `s` pixels do começo.
    function pointAt(s) {
        if (s <= cable.stemLen)
            return Qt.point(cable.x0, cable.stemTop + s);
        const target = s - cable.stemLen;
        const L = cable.lut;
        let i = 1;
        while (i < L.length - 1 && L[i] < target) i++;
        const seg = Math.max(1e-6, L[i] - L[i - 1]);
        const u = Math.min(1, ((i - 1) + (target - L[i - 1]) / seg) / (L.length - 1));
        const a = 1 - u;
        const qx = a * a * cable.x0 + 2 * a * u * cable.x0 + u * u * cable.x1;
        const qy = a * a * cable.y0 + 2 * a * u * cable.y1 + u * u * cable.y1;
        const w = cable.amp * cable.wave(u);
        return Qt.point(qx + cable.nx * w, qy + cable.ny * w);
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

            readonly property real s: cable.headS - bead.index * cable.spacing
            // Glifo ainda fora do caminho ou já absorvido: não calcula nada.
            readonly property bool onPath: bead.s >= 0 && bead.s <= cable.pathLen
            readonly property point sp: cable.stream && bead.onPath ? cable.pointAt(bead.s) : Qt.point(-100, -100)

            x: (cable.stream ? bead.sp.x : cable.px(bead.t)) - width / 2
            y: (cable.stream ? bead.sp.y : cable.py(bead.t)) - height / 2
            text: bead.glyph
            property string glyph: cable.alphabet.charAt(Math.floor(Math.random() * cable.alphabet.length))

            font.family: Theme.monoFamily
            font.pixelSize: cable.fontSize
            color: cable.glyphColor
            Behavior on color { ColorAnimation { duration: 260 } }
            // Some ao chegar na ponta: é o olho absorvendo o glifo.
            opacity: cable.stream
                ? (bead.s < 0 || bead.s > cable.pathLen ? 0
                   : Math.min(1, (cable.pathLen - bead.s) / 36)
                     * (bead.index >= cable.solidCount ? cable.extraFade : 1))
                : cable.flowing
                ? (bead.t > 1 - cable.headFade ? (1 - bead.t) / cable.headFade
                   : (bead.t < 0.06 ? bead.t / 0.06 : 1))
                : 1

            Timer {
                running: cable.visible && (!cable.stream || bead.onPath)
                interval: (cable.stream ? 520 : 260) + Math.random() * 500
                repeat: true
                onTriggered: bead.glyph = cable.alphabet.charAt(Math.floor(Math.random() * cable.alphabet.length))
            }
        }
    }
}
