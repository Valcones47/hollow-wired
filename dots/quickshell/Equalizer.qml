import QtQuick
import QtQuick.Layouts
import "."

// Equalizador de 10 bandas: sliders verticais com uma onda luminosa passando
// pelos knobs, e os presets embaixo. `compact` é a versão estreita usada no
// painel lateral do layout "letras" (presets em duas linhas, textos menores).
Item {
    id: root

    property bool compact: false
    readonly property color accent: Theme.accent2

    // Ganhos exibidos. Ao trocar de preset eles deslizam do valor antigo para
    // o novo (knobs e onda juntos); durante o arrasto seguem o mouse direto.
    property var fromGains: EqService.gains
    property var shown: EqService.gains
    property real mix: 1
    // Troca de preset "eletrizando" da esquerda para a direita: cada banda
    // só começa a andar quando a frente da onda chega nela (front = posição
    // da frente, em bandas).
    readonly property real front: mix * (EqService.gains.length + 1.5)
    readonly property bool sweeping: mixAnim.running && !EqService.dragging
    function bandT(i) {
        const t = Math.max(0, Math.min(1, root.front - i));
        return 1 - Math.pow(1 - t, 3);
    }
    function blend() {
        const out = [];
        for (let i = 0; i < EqService.gains.length; i++) {
            const a = root.fromGains[i] || 0;
            out.push(a + ((EqService.gains[i] || 0) - a) * root.bandT(i));
        }
        root.shown = out;
    }
    onMixChanged: blend()
    NumberAnimation {
        id: mixAnim
        target: root
        property: "mix"
        from: 0
        to: 1
        duration: 760
        easing.type: Easing.Linear
    }
    Connections {
        target: EqService
        function onGainsChanged() {
            mixAnim.stop();
            if (EqService.dragging) {
                root.fromGains = EqService.gains;
                root.mix = 1;
                root.blend();
            } else {
                root.fromGains = root.shown;
                mixAnim.start();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.compact ? 8 : 10

        // ---------- cabeçalho ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: Theme.icons.equalizer
                font.family: Theme.iconFontFamily
                font.pixelSize: 14
                color: root.accent
            }
            Text {
                text: Theme.t("eq.title", "Equalizador")
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Theme.foreground
            }
            Item { Layout.fillWidth: true }

            Rectangle {
                visible: EqService.enabled
                Layout.preferredHeight: 20
                Layout.preferredWidth: presetName.implicitWidth + 16
                radius: 10
                color: Theme.withAlpha(root.accent, 0.18)
                Text {
                    id: presetName
                    anchors.centerIn: parent
                    text: EqService.presetLabel(EqService.preset)
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: root.accent
                }
            }

            // Liga/desliga. Desligado, o filtro sai do caminho do áudio de
            // vez (o processo é encerrado), não só zera os ganhos.
            Rectangle {
                id: eqSwitch
                Layout.preferredWidth: 34
                Layout.preferredHeight: 18
                radius: 9
                color: EqService.enabled ? root.accent : Theme.withAlpha(Theme.subtext, 0.3)
                Behavior on color { ColorAnimation { duration: 140 } }
                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    y: 2
                    x: EqService.enabled ? parent.width - width - 2 : 2
                    color: Theme.background
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: EqService.setEnabled(!EqService.enabled)
                }
            }
        }

        // ---------- sliders + onda ----------
        Item {
            id: bandsArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 90
            opacity: EqService.enabled ? 1 : 0.45
            Behavior on opacity { NumberAnimation { duration: 160 } }

            readonly property int count: EqService.bands.length
            readonly property real labelH: 16
            readonly property real trackTop: 8
            readonly property real trackH: height - labelH - trackTop - 8
            readonly property real colW: width / count

            function knobY(db) {
                return trackTop + (1 - (db + EqService.limit) / (2 * EqService.limit)) * trackH;
            }
            function colX(i) {
                return colW * i + colW / 2;
            }

            // Linha do 0 dB, para dar referência de onde é "neutro".
            Rectangle {
                x: 0
                width: parent.width
                height: 1
                y: bandsArea.knobY(0)
                color: Theme.withAlpha(Theme.subtext, 0.15)
            }

            // A onda: curva suave passando pelos knobs, desenhada algumas vezes
            // com espessura e transparência diferentes para parecer brilho.
            Canvas {
                id: wave
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const n = bandsArea.count;
                    const pts = [];
                    for (let i = 0; i < n; i++)
                        pts.push([bandsArea.colX(i), bandsArea.knobY(root.shown[i] || 0)]);
                    // Estende para as bordas para a onda não começar cortada.
                    pts.unshift([0, pts[0][1]]);
                    pts.push([width, pts[pts.length - 1][1]]);

                    function trace() {
                        ctx.beginPath();
                        ctx.moveTo(pts[0][0], pts[0][1]);
                        for (let i = 0; i < pts.length - 1; i++) {
                            const mx = (pts[i][0] + pts[i + 1][0]) / 2;
                            ctx.bezierCurveTo(mx, pts[i][1], mx, pts[i + 1][1], pts[i + 1][0], pts[i + 1][1]);
                        }
                    }

                    // Preenchimento até a base, bem sutil.
                    trace();
                    ctx.lineTo(width, height - bandsArea.labelH);
                    ctx.lineTo(0, height - bandsArea.labelH);
                    ctx.closePath();
                    const grad = ctx.createLinearGradient(0, 0, 0, height);
                    grad.addColorStop(0, Theme.withAlpha(root.accent, 0.22));
                    grad.addColorStop(1, Theme.withAlpha(root.accent, 0.0));
                    ctx.fillStyle = grad;
                    ctx.fill();

                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    const layers = [[14, 0.06], [8, 0.12], [4, 0.25], [1.6, 0.9]];
                    for (const l of layers) {
                        trace();
                        ctx.lineWidth = l[0];
                        ctx.strokeStyle = Theme.withAlpha(root.accent, l[1]);
                        ctx.stroke();
                    }
                }
                Connections {
                    target: root
                    function onShownChanged() { wave.requestPaint(); }
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }

            // Faíscas da frente da onda: raio em zigue-zague descendo pelo
            // trilho da banda que está "carregando" e arco até o knob vizinho.
            Canvas {
                id: sparks
                anchors.fill: parent
                z: 3
                visible: root.sweeping
                onPaint: {
                    const c = getContext("2d");
                    c.reset();
                    if (!root.sweeping) return;
                    const n = bandsArea.count;
                    c.lineCap = "round";
                    for (let i = 0; i < n; i++) {
                        const d = root.front - i - 0.5;
                        if (d < -0.6 || d > 0.8) continue;
                        const a = 1 - Math.min(1, Math.abs(d) / 0.8);
                        const x = bandsArea.colX(i);
                        const top = bandsArea.trackTop, bot = bandsArea.trackTop + bandsArea.trackH;
                        c.beginPath();
                        c.moveTo(x, top);
                        const seg = 9;
                        for (let k = 1; k < seg; k++)
                            c.lineTo(x + (Math.random() - 0.5) * 9, top + (bot - top) * k / seg);
                        c.lineTo(x, bot);
                        c.lineWidth = 1.6;
                        c.strokeStyle = Theme.withAlpha(root.accent, 0.85 * a);
                        c.stroke();
                        if (i > 0) {
                            const x0 = bandsArea.colX(i - 1), y0 = bandsArea.knobY(root.shown[i - 1] || 0);
                            const y1 = bandsArea.knobY(root.shown[i] || 0);
                            c.beginPath();
                            c.moveTo(x0, y0);
                            for (let k = 1; k < 5; k++) {
                                const t = k / 5;
                                c.lineTo(x0 + (x - x0) * t, y0 + (y1 - y0) * t + (Math.random() - 0.5) * 12);
                            }
                            c.lineTo(x, y1);
                            c.lineWidth = 1.2;
                            c.strokeStyle = Theme.withAlpha(Theme.foreground, 0.7 * a);
                            c.stroke();
                        }
                    }
                }
                Connections {
                    target: root
                    function onFrontChanged() { sparks.requestPaint(); }
                }
            }

            Repeater {
                model: bandsArea.count
                delegate: Item {
                    id: band
                    required property int index
                    readonly property real db: root.shown[index] || 0
                    // 0..1: quanto a frente da onda está em cima desta banda.
                    readonly property real charge: root.sweeping ? Math.max(0, 1 - Math.abs(root.front - index - 0.5) / 0.9) : 0
                    x: bandsArea.colW * index
                    width: bandsArea.colW
                    height: bandsArea.height

                    Rectangle {
                        id: track
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: bandsArea.trackTop
                        width: root.compact ? 4 : 5
                        height: bandsArea.trackH
                        radius: width / 2
                        color: Theme.withAlpha(Theme.subtext, 0.18)

                        // Preenchimento do 0 dB até o knob: para cima é
                        // reforço, para baixo é corte.
                        Rectangle {
                            width: parent.width
                            radius: width / 2
                            readonly property real zeroY: bandsArea.knobY(0) - bandsArea.trackTop
                            readonly property real kY: bandsArea.knobY(band.db) - bandsArea.trackTop
                            y: Math.min(zeroY, kY)
                            height: Math.abs(zeroY - kY)
                            color: Theme.withAlpha(root.accent, 0.8)
                        }
                    }

                    Rectangle {
                        id: knob
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.compact ? 14 : 18
                        height: root.compact ? 8 : 10
                        radius: height / 2
                        y: bandsArea.knobY(band.db) - height / 2
                        color: Theme.foreground
                        border.width: 2
                        border.color: root.accent
                        scale: bandMouse.pressed || bandMouse.containsMouse ? 1.2 : 1 + band.charge * 0.35
                        // Brilho em volta do knob quando a onda passa.
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + 12
                            height: parent.height + 12
                            radius: height / 2
                            color: "transparent"
                            border.width: 3
                            border.color: Theme.withAlpha(root.accent, 0.45 * band.charge)
                            visible: band.charge > 0
                        }
                        Behavior on scale { NumberAnimation { duration: 90 } }
                    }

                    // Valor em dB enquanto arrasta.
                    Rectangle {
                        visible: bandMouse.pressed
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: knob.y - height - 6
                        width: dbText.implicitWidth + 10
                        height: 16
                        radius: 8
                        color: root.accent
                        Text {
                            id: dbText
                            anchors.centerIn: parent
                            text: (band.db > 0 ? "+" : "") + band.db.toFixed(1)
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: Theme.background
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        text: EqService.bandLabel(band.index)
                        font.family: Theme.fontFamily
                        font.pixelSize: root.compact ? 9 : 10
                        color: Theme.subtext
                    }

                    MouseArea {
                        id: bandMouse
                        anchors.fill: parent
                        anchors.bottomMargin: bandsArea.labelH
                        hoverEnabled: true
                        cursorShape: Qt.SizeVerCursor
                        preventStealing: true

                        function dbAt(py) {
                            const t = (py - bandsArea.trackTop) / bandsArea.trackH;
                            return (1 - Math.max(0, Math.min(1, t))) * 2 * EqService.limit - EqService.limit;
                        }
                        onPressed: mouse => {
                            EqService.dragging = true;
                            EqService.setBand(band.index, dbAt(mouse.y));
                        }
                        onPositionChanged: mouse => {
                            if (pressed)
                                EqService.setBand(band.index, dbAt(mouse.y));
                        }
                        onReleased: {
                            EqService.dragging = false;
                            EqService.flush();
                        }
                        onCanceled: EqService.dragging = false
                        // Duplo clique zera a banda.
                        onDoubleClicked: {
                            EqService.setBand(band.index, 0);
                            EqService.flush();
                        }
                        onWheel: wheel => {
                            EqService.dragging = true;
                            EqService.setBand(band.index, (EqService.gains[band.index] || 0) + (wheel.angleDelta.y > 0 ? 0.5 : -0.5));
                            EqService.dragging = false;
                        }
                    }
                }
            }
        }

        // ---------- presets ----------
        GridLayout {
            Layout.fillWidth: true
            columns: root.compact ? 4 : 8
            rowSpacing: 6
            columnSpacing: 6

            Repeater {
                model: EqService.presets
                delegate: Rectangle {
                    id: presetBtn
                    required property string modelData
                    readonly property bool active: EqService.enabled && EqService.preset === modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.compact ? 24 : 28
                    radius: height / 2
                    color: active ? root.accent
                                  : (presetMouse.containsMouse ? Theme.withAlpha(Theme.subtext, 0.18)
                                                               : Theme.withAlpha(Theme.subtext, 0.08))
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: EqService.presetLabel(presetBtn.modelData)
                        font.family: Theme.fontFamily
                        font.pixelSize: root.compact ? 10 : 11
                        font.weight: presetBtn.active ? Font.DemiBold : Font.Normal
                        color: presetBtn.active ? Theme.background : Theme.foreground
                    }
                    MouseArea {
                        id: presetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: EqService.applyPreset(presetBtn.modelData)
                    }
                }
            }
        }
    }
}
