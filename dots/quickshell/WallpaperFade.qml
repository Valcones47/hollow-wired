import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Transição entre wallpapers.
//
// O Waywallen (e qualquer backend de wallpaper animado) não consegue manter
// dois renderizadores vivos ao mesmo tempo: trocar de papel de parede mata o
// renderizador atual e sobe outro, o que dá o engasgo de ~1s e o flash preto.
//
// A saída é não tentar misturar dois vídeos. Esta camada mostra uma imagem
// estática do wallpaper que está entrando — um quadro em resolução real quando
// o item é vídeo (ver rice-wallpaper-frame) — e a faz aparecer por cima do
// antigo, que continua animando normalmente por baixo. Só quando a imagem
// cobre a tela inteira é que a troca de verdade acontece; o engasgo fica
// escondido atrás dela. Depois a camada some e revela o novo já rodando.
//
// O mesmo caminho que o mugen-shell segue para wallpaper de vídeo: mostra um
// quadro extraído, espera a transição terminar, e só então sobe o player.
//
// Estilos de entrada (user-prefs.json > wallpaper_transition):
//   fade   crossfade simples
//   wipe   varredura lateral
//   wave   frente diagonal contínua do canto sup. direito ao inf. esquerdo (borda macia)
//   grow   círculo que abre do centro
//
// Uso (ver rice-wallpaper-fade):
//   qs ipc call wallfade cover /caminho/imagem.png
//   qs ipc call wallfade dismiss
Scope {
    id: fadeScope

    property string style: "wipe"

    // Tempos calibrados para animação fluida:
    // a cobertura varre a tela a 60 FPS; a troca só é disparada com a tela
    // coberta para o carregamento do Waywallen não engasgar a animação.
    property int coverMs: 450
    property int hold: 4000
    property int revealMs: 0

    property string source: ""
    property bool covering: false

    // Progresso da máscara: 0 = nada coberto, 1 = tela inteira coberta.
    property real progress: 0

    readonly property int safetyTimeout: coverMs + hold + revealMs + 3000
    readonly property bool masked: style === "wipe" || style === "wave" || style === "grow"
    property bool pendingCover: false
    property int opDuration: 0

    function cover(path) {
        if (!path)
            return;
        fadeScope.source = path.startsWith("file://") ? path : "file://" + path;
        fadeScope.progress = 0;
        fadeScope.pendingCover = true;
        holdTimer.restart();
        safetyTimer.restart();
        decodeGuard.restart();
        fadeScope.maybeStart();
    }

    function maybeStart() {
        if (!fadeScope.pendingCover)
            return;
        fadeScope.pendingCover = false;
        decodeGuard.stop();
        fadeScope.opDuration = fadeScope.masked ? 0 : fadeScope.coverMs;
        fadeScope.covering = true;
        if (fadeScope.masked)
            coverAnim.restart();
    }

    Timer {
        id: decodeGuard
        interval: 150
        onTriggered: fadeScope.maybeStart()
    }

    property bool revealQueued: false

    function reveal(force = false) {
        if (!fadeScope.covering && !fadeScope.pendingCover)
            return;
        // Se a chamada veio externamente enquanto a onda ainda corre, aguarda;
        // se veio do onFinished (force=true), revela imediatamente.
        if (!force && coverAnim.running) {
            fadeScope.revealQueued = true;
            return;
        }
        fadeScope.revealQueued = false;
        fadeScope.pendingCover = false;
        fadeScope.opDuration = fadeScope.revealMs;
        fadeScope.covering = false;
        holdTimer.stop();
    }

    function dismiss() {
        fadeScope.revealQueued = false;
        fadeScope.pendingCover = false;
        fadeScope.covering = false;
        coverAnim.stop();
        decodeGuard.stop();
        holdTimer.stop();
        safetyTimer.stop();
    }

    NumberAnimation {
        id: coverAnim
        target: fadeScope
        property: "progress"
        from: 0
        to: 1
        duration: fadeScope.coverMs
        // Ao término da animação, a camada se retira imediatamente para o vídeo
        // aparecer na tela sem nenhuma pausa estática.
        onFinished: fadeScope.reveal(true)
        easing.type: Easing.InOutQuad
    }

    // Limite: se o sinal de "renderizador novo no ar" nunca chegar, revela
    // assim mesmo em vez de deixar a tela coberta.
    Timer {
        id: holdTimer
        interval: fadeScope.coverMs + fadeScope.hold
        onTriggered: fadeScope.reveal()
    }

    Timer {
        id: safetyTimer
        interval: fadeScope.safetyTimeout
        onTriggered: fadeScope.dismiss()
    }

    // Preferências do usuário. O arquivo é o mesmo dos gaps/blur.
    FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/user-prefs.json"
        watchChanges: true
        __printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (d.wallpaper_transition !== undefined)
                    fadeScope.style = d.wallpaper_transition;
                if (d.wallpaper_transition_ms !== undefined)
                    fadeScope.coverMs = d.wallpaper_transition_ms;
            } catch (e) {}
        }
        onFileChanged: reload()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: fadeWin
            required property var modelData
            screen: modelData

            // Background é a mesma camada do wallpaper (o waywallen fica aqui),
            // então a transição cobre só o papel de parede: a moldura, os
            // widgets de desktop, a barra e as janelas continuam visíveis por
            // cima dela. Em Bottom, que é onde ficam a moldura e os widgets,
            // esta janela passaria por cima dos dois durante a troca.
            //
            // Confirmado por `hyprctl layers` durante uma troca de verdade: o
            // waywallen mantém a mesma superfície e não remapeia por cima.
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "hollow-wallfade"
            exclusionMode: ExclusionMode.Ignore

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            // Só desenha, nunca recebe clique.
            mask: Region {}

            // Enquanto invisível a janela sai do compositor, pra não custar
            // nada de fillrate na iGPU no uso normal.
            visible: fadeScope.covering || fadeImage.opacity > 0.001

            // ---------------------------------------------- máscaras
            //
            // Três regras que custaram caro para descobrir, todas medidas:
            //
            // 1. a máscara fica FORA da área visível (x negativo), não
            //    escondida: um item `visible: false` não é desenhado e não gera
            //    a textura que o OpacityMask consome;
            // 2. nada de `LinearGradient` do Qt5Compat aqui. Nesta superfície
            //    ele devolve um valor uniforme igual ao progresso — o degradê
            //    vira uma média só. Com Rectangle o alfa sai 1,0 de um lado e
            //    0,0 do outro, como esperado. (O mesmo LinearGradient funciona
            //    numa janela comum do `qml6`: é a combinação que falha.)
            // 3. nada de contêiner girado. Com um `Item` girado por dentro da
            //    máscara o resultado voltava a ser uniforme; sem ele, a
            //    fronteira aparece. Por isso a varredura é horizontal e não
            //    diagonal como a do swww.

            // Varredura: um retângulo branco que cresce, com uma faixa de
            // degradê na ponta para a borda não ficar dura (o equivalente do
            // --transition-step do swww).
            Item {
                id: wipeMask
                width: fadeWin.width
                height: fadeWin.height
                x: -fadeWin.width - 64
                layer.enabled: true

                readonly property real feather: 0.16
                // Começa em -feather para a faixa entrar pela borda da tela.
                readonly property real p: fadeScope.progress * (1 + feather) - feather

                Rectangle {
                    width: Math.max(0, parent.width * wipeMask.p)
                    height: parent.height
                    color: "white"
                }

                Rectangle {
                    x: Math.max(0, parent.width * wipeMask.p)
                    width: parent.width * wipeMask.feather
                    height: parent.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "white" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
            }

            // Círculo que abre do centro. O `radius` recorta o alfa da
            // textura, que é justamente o que o OpacityMask usa.
            Item {
                id: growMask
                width: fadeWin.width
                height: fadeWin.height
                x: -fadeWin.width - 64
                layer.enabled: true

                readonly property real diag: Math.sqrt(width * width + height * height)

                Rectangle {
                    anchors.centerIn: parent
                    width: growMask.diag * 1.08 * fadeScope.progress
                    height: width
                    radius: width / 2
                    color: "white"
                }
            }

            // "Onda" (referência: vídeo 2042.mp4, analisado pelo Antigravity, e a
            // captura de um quadro enviada pelo usuário): uma frente na
            // diagonal, entrando pelo canto superior direito e saindo pelo
            // inferior esquerdo, o topo liderando (~37° da vertical), com
            // ondulações grandes e arredondadas e borda macia em camadas, como
            // fumaça desfocada. Não é líquido, não tem anel nem bolhas soltas.
            //
            // Tudo desenhado aqui dentro, em coordenadas de pintura, com um
            // degradê linear do próprio Canvas: um `Item` girado dentro da
            // máscara faz o alfa sair uniforme (regra 3), e o LinearGradient do
            // Qt5Compat devolve a média (regra 2).
            Canvas {
                id: waveMask
                width: fadeWin.width
                height: fadeWin.height
                x: -fadeWin.width - 64
                layer.enabled: true
                renderTarget: Canvas.FramebufferObject

                readonly property real p: fadeScope.progress

                onPChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Component.onCompleted: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width;
                    const h = height;
                    if (!(w > 0) || !(h > 0)) return;
                    // n: normal da frente, apontando para o lado ainda não
                    // coberto (esquerda e para baixo); t: ao longo da frente.
                    // u = ponto · n, s = ponto · t.
                    const theta = 37 * Math.PI / 180;
                    const nx = -Math.cos(theta), ny = Math.sin(theta);
                    const tx = Math.sin(theta), ty = Math.cos(theta);
                    const diag = Math.sqrt(w * w + h * h);
                    // Ondulações grandes e arredondadas na frente (a captura do
                    // usuário: "ondulações feitas com desfoque, meio suave, não
                    // líquido"): duas ondas lentas somadas, que andam devagar
                    // ao longo da frente enquanto ela avança.
                    const A = w * 0.06;
                    const l1 = diag * 0.55, l2 = diag * 0.31;
                    const ph = p * 2.6;
                    function bump(sv) {
                        return A * (0.62 * Math.sin(2 * Math.PI * sv / l1 + ph)
                                  + 0.38 * Math.sin(2 * Math.PI * sv / l2 - ph * 1.35 + 1.3));
                    }
                    const feather = Math.max(90, Math.min(170, w * 0.08));
                    const uMin = w * nx, uMax = h * ny;
                    // s nos quatro cantos, para a frente atravessar a tela toda.
                    const sA = 0, sB = w * tx, sC = h * ty, sD = w * tx + h * ty;
                    const sLo = Math.min(sA, sB, sC, sD) - diag * 0.1;
                    const sHi = Math.max(sA, sB, sC, sD) + diag * 0.1;
                    // Frente F: de "nada na tela" (a ondulação mais saliente
                    // ainda antes do canto) a "tudo coberto, borda fora da tela".
                    const F0 = uMin - A;
                    const F1 = uMax + A + feather;
                    const F = F0 + p * (F1 - F0);
                    // Borda macia em camadas: N cópias da forma, cada uma um
                    // pouco mais para fora e bem transparente. A soma dá opaco
                    // por dentro e some na borda (desfoque real no Canvas custa
                    // caro a cada quadro).
                    const N = 12;
                    const steps = 56;
                    const back = uMin - diag;   // bem atrás, lado já coberto
                    ctx.fillStyle = "white";
                    ctx.globalAlpha = 0.34;
                    for (let i = 0; i < N; i++) {
                        const off = -feather + feather * i / (N - 1);
                        ctx.beginPath();
                        for (let k = 0; k <= steps; k++) {
                            const sv = sLo + (sHi - sLo) * k / steps;
                            const u = F + off + bump(sv);
                            const x = nx * u + tx * sv, y = ny * u + ty * sv;
                            if (k === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                        }
                        ctx.lineTo(nx * back + tx * sHi, ny * back + ty * sHi);
                        ctx.lineTo(nx * back + tx * sLo, ny * back + ty * sLo);
                        ctx.closePath();
                        ctx.fill();
                    }
                    ctx.globalAlpha = 1;
                }
            }

            Image {
                id: fadeImage
                anchors.fill: parent
                source: fadeScope.source
                fillMode: Image.PreserveAspectCrop
                // Quando a origem é um preview de cena (scene.pkg) a imagem é
                // pequena e quadrada; sem isso a ampliação fica serrilhada.
                smooth: true
                mipmap: true
                asynchronous: true
                cache: false
                onStatusChanged: {
                    if (status === Image.Ready || status === Image.Error)
                        fadeScope.maybeStart();
                }

                // No `fade` quem anima é a opacidade; nos outros ela salta para
                // 1 e quem revela a imagem é a máscara.
                opacity: fadeScope.covering ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: fadeScope.opDuration
                        easing.type: Easing.InOutQuad
                    }
                }

                layer.enabled: fadeScope.masked
                layer.effect: OpacityMask {
                    maskSource: fadeScope.style === "grow" ? growMask
                              : (fadeScope.style === "wave" ? waveMask : wipeMask)
                }
            }
        }
    }

    IpcHandler {
        target: "wallfade"

        // Cobre a tela com a imagem do wallpaper que está entrando.
        function cover(path: string): void { fadeScope.cover(path); }
        // Tira a camada na hora (usado quando a troca falhou).
        function dismiss(): void { fadeScope.dismiss(); }
        // Revela o wallpaper novo, agora que o renderizador dele está no ar.
        function reveal(): void { fadeScope.reveal(); }
        // Quanto tempo o chamador deve esperar antes de aplicar a troca.
        // O renderizador do Waywallen leva cerca de 800-850ms no total (Flatpak + Vulkan)
        // para entregar o primeiro quadro. Disparamos a troca com antecedência calculada
        // para que a entrega do quadro coincida exatamente com o final da animação,
        // sem deixar a tela parada após a varredura nem engasgar o início.
        function coverDelay(): string { return String(Math.max(0, fadeScope.coverMs - 850)); }
        // Troca o estilo sem reiniciar o shell (usado pelo painel e para teste).
        function setStyle(name: string): void { fadeScope.style = name; }
        function currentStyle(): string { return fadeScope.style; }
        // Diagnóstico: diz o progresso da varredura neste instante.
        function progressNow(): string {
            return fadeScope.progress.toFixed(3) + " covering=" + fadeScope.covering
                 + " anim=" + coverAnim.running;
        }
    }
}
