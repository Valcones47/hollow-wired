pragma ComponentBehavior: Bound
import QtQuick
import "."

// Chuva de glifos ilegíveis em volta do olho da tela de boas-vindas.
//
// Profundidade: cada instância desenha um ou mais planos, e o olho fica
// entre eles — as colunas dos planos de trás passam por baixo dele. Quanto
// mais ao fundo, menor, mais apagada e mais lenta a coluna cai.
//
// Custo: cada coluna é um único Text de várias linhas (mais um glifo "líder"
// mais claro na ponta), então são ~2 itens por coluna em vez de um item por
// caractere. Os glifos de só duas colunas são sorteados de novo a cada tique,
// o que mantém a tela viva sem refazer o layout de tudo a cada quadro.
Item {
    id: rain

    // Planos a desenhar: 0 = fundo, 1 = meio, 2 = frente.
    property var planes: [0, 1]
    property int perPlane: 7
    property bool running: true

    // Conexão elétrica com o olho (só a instância da frente usa).
    property bool connects: false
    property real eyeX: width / 2
    property real eyeY: height / 2
    property real eyeRadius: 70
    // Cor base do ciclo (vem da pupila). As conexões variam em volta dela em
    // vez de repetirem sempre o mesmo azul.
    property color linkColor: "#8fd0d8"
    readonly property var cablePalette: ["#8fd0d8", "#9ecb96", "#d8c98a", "#c2a1cf", "#d6a98a"]
    property color activeCable: rain.cablePalette[0]

    readonly property var planeSpec: [
        { size: 10, alpha: 0.16, minDur: 15000, maxDur: 21000 },
        { size: 12, alpha: 0.30, minDur: 10000, maxDur: 15000 },
        { size: 15, alpha: 0.52, minDur: 6500,  maxDur: 10000 }
    ]

    // Glifos sem significado: gregos, símbolos e dígitos, que qualquer fonte
    // monoespaçada instalada tem (katakana viraria quadradinho em muita gente).
    readonly property string alphabet: "ｱ0123456789ΔΞΨΩΣΦΛΓΘΠ#@$%&?*+=<>/\\|_~^≡≠≈∴∷⌁⌂"

    function glyph() {
        return rain.alphabet.charAt(Math.floor(Math.random() * rain.alphabet.length));
    }
    function glyphColumn(n) {
        let out = "";
        for (let i = 0; i < n; i++) out += rain.glyph() + "\n";
        return out;
    }

    property var columns: []
    property real _builtW: -1
    signal reglyph(int index)

    function build() {
        if (width <= 0 || height <= 0) return;
        // Reconstruir troca o model do Repeater, o que destrói e recria todas
        // as colunas (e reinicia as animações). Só vale a pena quando a área
        // muda de verdade.
        if (rain.columns.length > 0 && Math.abs(rain._builtW - width) < 40) return;
        rain._builtW = width;
        const out = [];
        for (let p = 0; p < rain.planes.length; p++) {
            const plane = rain.planes[p];
            const spec = rain.planeSpec[plane];
            for (let i = 0; i < rain.perPlane; i++) {
                out.push({
                    plane: plane,
                    // Espalha em faixas para as colunas não se amontoarem.
                    x: (i + Math.random() * 0.8) * (rain.width / rain.perPlane),
                    len: 8 + Math.floor(Math.random() * 12),
                    dur: spec.minDur + Math.random() * (spec.maxDur - spec.minDur),
                    delay: Math.random() * 6000,
                    text: rain.glyphColumn(8 + Math.floor(Math.random() * 12))
                });
            }
        }
        rain.columns = out;
    }

    onWidthChanged: build()
    onHeightChanged: build()
    Component.onCompleted: build()

    // Troca os glifos de uma coluna por vez, avisando só ela.
    Timer {
        running: rain.running && rain.columns.length > 0
        interval: 110
        repeat: true
        onTriggered: rain.reglyph(Math.floor(Math.random() * rain.columns.length))
    }

    // ---------------- colunas ----------------
    Repeater {
        id: colRepeater
        model: rain.columns

        delegate: Item {
            id: col
            required property var modelData
            required property int index

            readonly property var spec: rain.planeSpec[col.modelData.plane]
            readonly property bool linked: rain.connects && rain.linkedIndex === col.index
            property string glyphs: col.modelData.text

            Connections {
                target: rain
                function onReglyph(index) {
                    if (index === col.index) col.glyphs = rain.glyphColumn(col.modelData.len);
                }
            }

            x: col.modelData.x
            width: col.spec.size * 1.4
            height: colText.implicitHeight

            // A queda anima um progresso de 0 a 1 em vez do y direto: assim o
            // y continua sendo um binding (que acompanha a altura do texto,
            // que muda quando os glifos são sorteados de novo).
            property real prog: 0
            y: -height + col.prog * (rain.height + height)

            // Ponto onde o cabo encosta: a ponta de baixo da coluna.
            readonly property real tipX: x + width / 2
            readonly property real tipY: y + height

            SequentialAnimation on prog {
                running: rain.running
                // A espera inicial espalha as colunas em vez de largar todas
                // juntas do topo no primeiro segundo.
                PauseAnimation { duration: col.modelData.delay }
                NumberAnimation {
                    from: 0
                    to: 1
                    duration: col.modelData.dur
                    loops: Animation.Infinite
                }
                // Pausa em vez de parar: ao soltar, a coluna continua de onde
                // estava em vez de pular para o topo.
                paused: col.linked
            }

            Text {
                id: colText
                anchors.horizontalCenter: parent.horizontalCenter
                text: col.glyphs
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.05
                font.family: Theme.monoFamily
                font.pixelSize: col.spec.size
                color: Theme.primary
                // Conectada, a coluna vira o cabo: ela some e quem ocupa o
                // caminho são os glifos escorrendo para o olho.
                opacity: col.linked ? 0 : col.spec.alpha
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Behavior on color { ColorAnimation { duration: 180 } }
            }

            // Glifo da ponta, sempre mais claro: é o que dá o sentido de queda.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: colText.implicitHeight - font.pixelSize * 1.15
                text: rain.glyph()
                font.family: Theme.monoFamily
                font.pixelSize: col.spec.size
                color: Theme.mix(Theme.primary, "#ffffff", 0.7)
                opacity: col.linked ? 0 : Math.min(1, col.spec.alpha * 2.2)
            }
        }
    }

    // ---------------- conexão elétrica ----------------
    property int linkedIndex: -1
    property real linkX: 0
    property real linkY: 0
    property bool linkLive: false     // true = cabo preso; false = soltando
    property real whip: 0             // oscilação do cabo ao desconectar
    property real idleWave: 0         // respiração do cabo enquanto preso

    SequentialAnimation on idleWave {
        running: rain.linkLive
        loops: Animation.Infinite
        NumberAnimation { to: 0.07; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: -0.07; duration: 900; easing.type: Easing.InOutSine }
    }

    Timer {
        running: rain.connects && rain.running && rain.columns.length > 0
        interval: 5000 + Math.random() * 6000
        repeat: true
        onTriggered: {
            if (rain.linkedIndex >= 0) return;
            // Só vale conectar numa coluna que esteja à vista: sorteando
            // qualquer uma, o cabo saía do olho para fora da tela.
            let pick = -1;
            for (let t = 0; t < 10; t++) {
                const i = Math.floor(Math.random() * rain.columns.length);
                const item = colRepeater.itemAt(i);
                // Sempre antes de 60% do percurso: mais embaixo o cabo sairia
                // de fora da tela.
                if (item && item.prog > 0.1 && item.prog < 0.6) { pick = i; break; }
            }
            if (pick < 0) return;
            const src = colRepeater.itemAt(pick);
            rain.linkX = src.tipX;
            rain.linkY = src.y + src.height * 0.35;
            rain.activeCable = rain.cablePalette[Math.floor(Math.random() * rain.cablePalette.length)];
            rain.linkedIndex = pick;
            rain.linkLive = true;
            rain.whip = 0;
            holdLink.interval = 2600 + Math.random() * 2000;
            holdLink.restart();
            interval = 5000 + Math.random() * 6000;
        }
    }

    Timer {
        id: holdLink
        onTriggered: {
            rain.linkLive = false;
            release.restart();
        }
    }

    // Física do cabo soltando: em vez de simular uma corda (caro e sem ganho
    // visível nesse tamanho), o ponto de controle da curva oscila com
    // amplitude decrescente — o olho lê como chicote e custa quase nada.
    SequentialAnimation {
        id: release
        NumberAnimation { target: rain; property: "whip"; to: 1.0;  duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: rain; property: "whip"; to: -0.62; duration: 150; easing.type: Easing.InOutQuad }
        NumberAnimation { target: rain; property: "whip"; to: 0.34;  duration: 140; easing.type: Easing.InOutQuad }
        NumberAnimation { target: rain; property: "whip"; to: -0.16; duration: 130; easing.type: Easing.InOutQuad }
        NumberAnimation { target: rain; property: "whip"; to: 0;     duration: 160; easing.type: Easing.OutQuad }
        ScriptAction { script: rain.linkedIndex = -1 }
    }

    // O cabo é feito dos mesmos glifos da chuva, escorrendo para dentro do
    // olho: preso, a coluna some e vira este caminho.
    GlyphCable {
        id: link
        anchors.fill: parent
        visible: rain.linkedIndex >= 0
        z: 4
        x0: rain.linkX
        y0: rain.linkY
        x1: rain.eyeX
        y1: rain.eyeY
        // Densidade pela distância, senão um cabo longo fica ralo e um curto
        // vira um borrão de glifos.
        count: Math.max(10, Math.min(26, Math.round(link.len / 20)))
        fontSize: 13
        glyphColor: rain.activeCable
        // Solto, a ondulação cresce e vira chicote; preso, é só um serpenteio.
        amp: 22 + 46 * Math.abs(rain.whip)
        waves: 1.5
        flowing: rain.linkLive
        opacity: rain.linkLive ? 1 : 0.75
        Behavior on opacity { NumberAnimation { duration: 220 } }
    }

    // Clarão no ponto em que o cabo encosta no olho.
    Rectangle {
        visible: rain.linkedIndex >= 0 && rain.linkLive
        z: 5
        width: 14
        height: 14
        radius: 7
        x: rain.eyeX - width / 2
        y: rain.eyeY - height / 2
        color: rain.activeCable
        opacity: 0.75
        SequentialAnimation on scale {
            running: rain.linkedIndex >= 0 && rain.linkLive
            loops: Animation.Infinite
            NumberAnimation { to: 1.35; duration: 220 }
            NumberAnimation { to: 0.85; duration: 260 }
        }
    }
}
