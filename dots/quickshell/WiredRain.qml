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
            // Deslocamento somado ao progresso: ao ser absorvida pelo olho, a
            // coluna volta a nascer lá em cima em vez de reaparecer onde estava.
            property real shift: 0
            readonly property real p: (col.prog + col.shift) - Math.floor(col.prog + col.shift)
            y: -height + col.p * (rain.height + height)
            onLinkedChanged: if (!col.linked) col.shift = 1 - (col.prog - Math.floor(col.prog))

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
                // Conectada, a coluna vira o cabo: o texto dela some e quem
                // continua descendo são os glifos do GlyphCable, no mesmo lugar.
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
    // A coluna escolhida não congela nem some: ela continua caindo na mesma
    // linha, e na altura do olho faz a curva e entra nele. Os glifos andam
    // juntos (como a coluna andava) e são absorvidos um a um, por ~7 s, até a
    // coluna inteira ter entrado. Aí ela renasce no topo como outra qualquer.
    property int linkedIndex: -1
    property real linkX: 0
    property real linkY: 0            // onde o trecho reto vira curva
    property bool linkLive: false
    property real headS: 0            // posição do glifo da frente no caminho
    property int streamCount: 0
    property int streamSolid: 0
    property real streamFade: 0
    readonly property real streamSpacing: 15 * 1.1
    readonly property real streamSpeed: 130   // px/s, perto da queda do plano da frente

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
                // Sempre antes de 60% do percurso, e com a ponta acima do
                // olho: abaixo dele a curva teria que dar ré para subir.
                if (item && item.p > 0.1 && item.p < 0.6
                        && item.y + item.height < rain.eyeY - 40) { pick = i; break; }
            }
            if (pick < 0) return;
            const src = colRepeater.itemAt(pick);
            const tip = src.y + src.height;
            // A curva começa acima do olho, tanto mais cedo quanto mais longe
            // na horizontal ele estiver — senão vira um cotovelo seco.
            const dxE = Math.abs(rain.eyeX - src.tipX);
            rain.linkX = src.tipX;
            rain.linkY = Math.max(tip + 24, rain.eyeY - dxE * 0.85);
            rain.activeCable = rain.cablePalette[Math.floor(Math.random() * rain.cablePalette.length)];

            // A frente do fluxo começa na ponta da coluna; o trecho reto vai
            // do alto da tela até a curva.
            const stemTop = -rain.height;
            const head0 = tip - stemTop;
            const L = (rain.linkY - stemTop) + link.curveLen;
            const sp = rain.streamSpacing;
            // Quantos glifos: os da coluna mais o que couber para a absorção
            // durar ~7 s. Com teto, pelo custo de cada glifo.
            const colGlyphs = Math.max(1, Math.round(src.height / sp));
            const n = Math.max(colGlyphs, Math.min(36,
                Math.round((head0 + rain.streamSpeed * 7 - L) / sp) + 1));
            rain.streamSolid = colGlyphs;
            rain.streamCount = n;
            rain.headS = head0;
            streamAnim.from = head0;
            streamAnim.to = L + (n - 1) * sp + 4;
            streamAnim.duration = Math.max(1500, (streamAnim.to - head0) / rain.streamSpeed * 1000);
            rain.linkedIndex = pick;
            rain.linkLive = true;
            rain.streamFade = 0;
            fadeIn.restart();
            streamAnim.restart();
            interval = 5000 + Math.random() * 6000;
        }
    }

    NumberAnimation {
        id: streamAnim
        target: rain
        property: "headS"
        onFinished: {
            rain.linkLive = false;
            rain.linkedIndex = -1;
            rain.streamCount = 0;
        }
    }
    NumberAnimation {
        id: fadeIn
        target: rain
        property: "streamFade"
        to: 1
        duration: 900
    }

    // O cabo é feito dos mesmos glifos da chuva, escorrendo para dentro do
    // olho: a coluna conectada vira este caminho.
    GlyphCable {
        id: link
        anchors.fill: parent
        visible: rain.linkedIndex >= 0
        z: 4
        stream: true
        stemTop: -rain.height
        x0: rain.linkX
        y0: rain.linkY
        x1: rain.eyeX
        y1: rain.eyeY
        count: rain.streamCount
        spacing: rain.streamSpacing
        solidCount: rain.streamSolid
        extraFade: rain.streamFade
        headS: rain.headS
        fontSize: 15
        glyphColor: rain.activeCable
        // Serpenteio só na curva (a onda zera nas pontas), proporcional ao
        // tamanho dela para uma curva curta não virar zigue-zague.
        amp: Math.min(20, link.curveLen * 0.07)
        waves: 1.2
    }

    // Clarão no ponto em que o cabo encosta no olho.
    Rectangle {
        // Só depois que a frente do fluxo chegou no olho.
        visible: rain.linkLive && rain.headS >= link.pathLen
        z: 5
        width: 14
        height: 14
        radius: 7
        x: rain.eyeX - width / 2
        y: rain.eyeY - height / 2
        color: rain.activeCable
        opacity: 0.75
        SequentialAnimation on scale {
            running: rain.linkLive && rain.headS >= link.pathLen
            loops: Animation.Infinite
            NumberAnimation { to: 1.35; duration: 220 }
            NumberAnimation { to: 0.85; duration: 260 }
        }
    }
}
