pragma ComponentBehavior: Bound
import QtQuick
import "."

// Marca da tela de boas-vindas: o olho do Wired.
//
// O rice se chama hollow-wired, e o símbolo vem daí — Serial Experiments Lain.
// Ele pisca, olha para os lados sozinho e de vez em quando dá um glitch, como
// uma imagem chegando por um cabo ruim.
//
// O contorno é um Canvas (repintado só quando a pálpebra mexe); a íris e os
// blocos de glitch são itens comuns, que a GPU move sem repintar nada.
Item {
    id: mark

    // Desligado, fica parado e aberto (usado pequeno, ao lado do nome).
    property bool alive: true
    readonly property real unit: Math.min(width, height)

    // Paleta de estado: muda a cada ciclo de 30 s e vale para a pupila e para
    // as conexões elétricas da chuva ao mesmo tempo — é o que amarra os dois
    // efeitos como se fossem o mesmo sinal.
    readonly property var statePalette: ["#00e5ff", "#39ff14", "#ffb300", "#ff2fd0", "#ff3b3b"]
    property int stateIndex: 0
    readonly property color stateColor: mark.statePalette[mark.stateIndex % mark.statePalette.length]

    // Onde o olho está, para a chuva saber onde encostar o cabo.
    readonly property real eyeX: width / 2
    readonly property real eyeY: height / 2 - unit * 0.06

    // Deslocamento vertical da pupila no evento de 30 s.
    property real irisOffsetY: 0

    // 0 = olho aberto, 1 = pálpebra fechada
    property real lid: 0
    // -1 = olhando para a esquerda, 1 = para a direita
    property real gaze: 0
    property bool glitching: false

    onLidChanged: eye.requestPaint()

    // ---- piscar de vez em quando ----
    Timer {
        running: mark.alive
        interval: 2600 + Math.random() * 4200
        repeat: true
        onTriggered: {
            blink.restart();
            interval = 2600 + Math.random() * 4200;
        }
    }
    SequentialAnimation {
        id: blink
        NumberAnimation { target: mark; property: "lid"; to: 1; duration: 90; easing.type: Easing.InQuad }
        NumberAnimation { target: mark; property: "lid"; to: 0; duration: 130; easing.type: Easing.OutQuad }
    }

    // ---- olhar para lugares diferentes ----
    Timer {
        running: mark.alive
        interval: 1800 + Math.random() * 2600
        repeat: true
        onTriggered: {
            gazeAnim.to = (Math.random() * 2 - 1) * 0.9;
            gazeAnim.restart();
            interval = 1800 + Math.random() * 2600;
        }
    }
    NumberAnimation {
        id: gazeAnim
        target: mark
        property: "gaze"
        duration: 340
        easing.type: Easing.OutCubic
    }

    // ---- glitch ----
    Timer {
        running: mark.alive
        interval: 3000 + Math.random() * 2000
        repeat: true
        onTriggered: {
            mark.glitching = true;
            glitchOff.restart();
            // Sorteado de novo a cada vez: em intervalo fixo o glitch vira
            // relógio e some da vista.
            interval = 3000 + Math.random() * 2000;
        }
    }
    Timer {
        id: glitchOff
        interval: 140 + Math.random() * 160
        onTriggered: mark.glitching = false
    }
    // Sacode o desenho enquanto o glitch dura.
    Timer {
        running: mark.glitching
        interval: 45
        repeat: true
        onTriggered: glitchGroup.x = (Math.random() * 2 - 1) * mark.unit * 0.02
        onRunningChanged: if (!running) glitchGroup.x = 0
    }

    // A cada 30 s a pupila sobe, atravessa a pálpebra e volta pela parte de
    // baixo noutra cor. O "errado" é de propósito: ela passa por onde não
    // caberia, e o corte da volta é seco em vez de suave.
    Timer {
        running: mark.alive
        interval: 30000
        repeat: true
        onTriggered: surge.restart()
    }

    SequentialAnimation {
        id: surge
        ScriptAction { script: mark.glitching = true }
        NumberAnimation {
            target: mark; property: "irisOffsetY"
            to: -mark.unit * 0.58; duration: 420; easing.type: Easing.InBack
        }
        ScriptAction {
            script: {
                mark.stateIndex = (mark.stateIndex + 1) % mark.statePalette.length;
                mark.irisOffsetY = mark.unit * 0.58;   // reaparece embaixo, sem transição
            }
        }
        PauseAnimation { duration: 90 }
        NumberAnimation {
            target: mark; property: "irisOffsetY"
            to: 0; duration: 520; easing.type: Easing.OutBack
        }
        ScriptAction { script: mark.glitching = false }
    }

    Item {
        id: glitchGroup
        anchors.fill: parent

        // Rastro colorido do glitch: duas cópias deslocadas, como canal de cor
        // fora de registro numa transmissão ruim.
        Repeater {
            model: mark.glitching ? [{ dx: -1, c: "#00e5ff" }, { dx: 1, c: "#39ff14" }] : []
            delegate: Canvas {
                id: ghost
                required property var modelData
                anchors.fill: parent
                x: ghost.modelData.dx * mark.unit * 0.025
                opacity: 0.55
                onPaint: mark.paintEye(getContext("2d"), width, height, ghost.modelData.c, true)
            }
        }

        Canvas {
            id: eye
            anchors.fill: parent
            // Acima da íris: a pálpebra tem que passar por cima da pupila
            // quando ela desce, e não o contrário.
            z: 2
            onWidthChanged: requestPaint()
            Connections {
                target: Theme
                function onPrimaryChanged() { eye.requestPaint(); }
            }
            onPaint: mark.paintEye(getContext("2d"), width, height, Theme.primary, false)
        }

        // Íris: fica dentro do olho e acompanha o olhar.
        Item {
            id: iris
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -mark.unit * 0.06 + mark.irisOffsetY
            anchors.horizontalCenterOffset: mark.gaze * mark.unit * 0.07
            width: mark.unit * 0.30
            height: width
            opacity: 1 - Math.min(1, mark.lid * 1.6)

            // halo claro em volta; ganha a cor do estado depois do primeiro ciclo
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: mark.stateIndex === 0
                    ? Theme.mix(Theme.primary, "#ffffff", 0.75)
                    : Theme.mix(mark.stateColor, "#ffffff", 0.55)
                Behavior on color { ColorAnimation { duration: 180 } }
            }
            // pupila escura com as linhas de varredura
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.74
                height: width
                radius: width / 2
                color: "#07070a"
                clip: true

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: Math.max(1, mark.unit * 0.012)
                    Repeater {
                        model: 7
                        delegate: Rectangle {
                            width: parent.width
                            height: Math.max(1, mark.unit * 0.011)
                            color: Theme.withAlpha(mark.stateIndex === 0
                                ? Theme.mix(Theme.primary, "#ffffff", 0.6)
                                : mark.stateColor, 0.85)
                        }
                    }
                }
            }
        }

        // Blocos que piscam durante o glitch.
        Repeater {
            model: mark.glitching ? 6 : 0
            delegate: Rectangle {
                required property int index
                z: 3
                width: mark.unit * (0.06 + Math.random() * 0.16)
                height: mark.unit * (0.02 + Math.random() * 0.05)
                x: mark.unit * (0.08 + Math.random() * 0.8) - width / 2
                y: mark.unit * (0.1 + Math.random() * 0.75)
                color: index % 3 === 0 ? "#39ff14" : (index % 3 === 1 ? "#00e5ff" : Theme.mix(Theme.primary, "#ffffff", 0.5))
                opacity: 0.55 + Math.random() * 0.35
            }
        }
    }

    // Desenha pálpebras, haste e ganchos. Sai numa função para o contorno
    // colorido do glitch reaproveitar o mesmo traçado.
    function paintEye(ctx, w, h, color, thin) {
        const u = Math.min(w, h);
        const cx = w / 2;
        const cy = h / 2 - u * 0.06;      // centro do olho
        const halfW = u * 0.40;           // meia largura do olho
        const open = 1 - mark.lid;        // 1 = aberto, 0 = fechado

        ctx.reset();
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.strokeStyle = color;
        ctx.lineWidth = u * (thin ? 0.035 : 0.055);

        // Pálpebras: duas curvas que se encontram nas pontas, um pouco acima
        // do centro — é o que dá o bico virado para cima do símbolo.
        const tipY = cy - u * 0.04;
        ctx.beginPath();
        ctx.moveTo(cx - halfW, tipY);
        ctx.quadraticCurveTo(cx, cy - u * 0.34 * open, cx + halfW, tipY);
        ctx.quadraticCurveTo(cx, cy + u * 0.34 * open, cx - halfW, tipY);
        ctx.stroke();

        // ---- detalhe de cima: dobra da pálpebra e raios ----
        // Tudo segue a curva da pálpebra de cima (a mesma Bézier), afastado
        // pela normal: quando ela fecha, a dobra e os raios achatam junto.
        const topCy = cy - u * 0.34 * open;
        const lidPt = t => {
            const a = 1 - t;
            const x = a * a * (cx - halfW) + 2 * a * t * cx + t * t * (cx + halfW);
            const y = a * a * tipY + 2 * a * t * topCy + t * t * tipY;
            // derivada -> normal apontando para fora (para cima)
            const dx = 2 * a * halfW + 2 * t * halfW;
            const dy = 2 * a * (topCy - tipY) + 2 * t * (tipY - topCy);
            const l = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
            return { x: x, y: y, nx: dy / l, ny: -dx / l };
        };
        const base = u * (thin ? 0.035 : 0.055);

        // dobra: traço fino paralelo, sem encostar nas pontas
        const crease = u * 0.075;
        ctx.lineWidth = base * 0.45;
        ctx.globalAlpha = 0.75;
        ctx.beginPath();
        for (let i = 0; i <= 20; i++) {
            const q = lidPt(0.16 + 0.68 * i / 20);
            const X = q.x + q.nx * crease, Y = q.y + q.ny * crease;
            if (i === 0) ctx.moveTo(X, Y); else ctx.lineTo(X, Y);
        }
        ctx.stroke();

        // raios saindo da dobra: o do meio mais longo, alternando longo/curto
        ctx.lineWidth = base * 0.38;
        const rays = [0.24, 0.33, 0.42, 0.5, 0.58, 0.67, 0.76];
        for (let r = 0; r < rays.length; r++) {
            const q = lidPt(rays[r]);
            const mid = r === 3;
            const len = u * (mid ? 0.1 : (r % 2 === 1 ? 0.065 : 0.045)) * (0.35 + 0.65 * open);
            const start = crease + u * 0.03;
            ctx.globalAlpha = mid ? 0.9 : 0.6;
            ctx.beginPath();
            ctx.moveTo(q.x + q.nx * start, q.y + q.ny * start);
            ctx.lineTo(q.x + q.nx * (start + len), q.y + q.ny * (start + len));
            ctx.stroke();
        }

        // marcas nas pontas do olho, como mira de instrumento
        ctx.lineWidth = base * 0.45;
        ctx.globalAlpha = 0.7;
        for (const side of [-1, 1]) {
            ctx.beginPath();
            ctx.moveTo(cx + side * (halfW + u * 0.035), tipY);
            ctx.lineTo(cx + side * (halfW + u * 0.085), tipY);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;
        ctx.lineWidth = base;

        // haste que desce do olho
        const stemTop = cy + u * 0.14;
        const stemBottom = cy + u * 0.34;
        ctx.beginPath();
        ctx.moveTo(cx, stemTop);
        ctx.lineTo(cx, stemBottom);
        ctx.stroke();

        // os dois ganchos da base, espelhados, virando para fora e para cima
        for (const side of [-1, 1]) {
            ctx.beginPath();
            ctx.moveTo(cx, stemBottom - u * 0.01);
            ctx.bezierCurveTo(cx + side * u * 0.02, stemBottom + u * 0.07,
                              cx + side * u * 0.20, stemBottom + u * 0.07,
                              cx + side * u * 0.19, stemBottom - u * 0.09);
            ctx.stroke();
        }

        // pontinhos ao lado do olho
        ctx.fillStyle = color;
        for (const side of [-1, 1]) {
            ctx.beginPath();
            ctx.ellipse(cx + side * u * 0.28 - u * 0.04, cy + u * 0.16, u * 0.08, u * 0.08);
            ctx.fill();
        }
    }
}
