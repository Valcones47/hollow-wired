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
//   wave   mancha suave e arredondada vindo da direita (borda desfocada)
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
        easing.type: Easing.Bezier
        easing.bezierCurve: fadeScope.style === "wave" ? [0.4, 0.0, 0.25, 1.0, 1.0, 1.0]
                                                       : [0.25, 0.1, 0.25, 1.0, 1.0, 1.0]
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

            // "Onda": o wallpaper novo entra pela direita numa rampa suave —
            // topo primeiro, depois meio, depois base —, com borda
            // muito macia — como se viesse desfocado. Não é uma linha nem um
            // anel: a frente é um disco grande de borda larga, cercado de
            // bolhas também desfocadas que deixam o contorno irregular e
            // redondo, e que mudam de tamanho devagar enquanto avançam.
            //
            // Tudo desenhado aqui dentro, em coordenadas de pintura: um `Item`
            // girado dentro da máscara faz o alfa sair uniforme (regra 3).
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
                    // Centro do arco acima e à direita da tela, fora dela: a
                    // frente vira uma rampa — o topo chega primeiro, depois o
                    // meio, depois a base. Com o centro à altura do meio da
                    // tela ela parecia sair do meio.
                    const cx = w * 1.1;
                    const cy = -h * 0.45;
                    // Borda macia bem larga: é o que dá o ar de desfoque.
                    const feather = w * 0.24;
                    const far = Math.sqrt(cx * cx + (h - cy) * (h - cy));
                    // Começa com a frente já encostando no canto superior
                    // direito, sem gastar o começo da animação fora da tela.
                    const near = Math.sqrt((cx - w) * (cx - w) + cy * cy) * 0.9;
                    const R = near + p * (far + feather * 1.15 - near);

                    function softDisc(x, y, r, solid) {
                        // Opaco até `solid` do raio, some até a borda. Com a
                        // tela ainda sem tamanho o raio dá 0 e o `solid` NaN,
                        // que o gradiente recusa com erro.
                        if (!(r > 0) || !isFinite(x) || !isFinite(y)) return;
                        if (!isFinite(solid)) solid = 0;
                        const g = ctx.createRadialGradient(x, y, 0, x, y, r);
                        g.addColorStop(0, "rgba(255,255,255,1)");
                        g.addColorStop(Math.max(0, Math.min(0.99, solid)), "rgba(255,255,255,1)");
                        g.addColorStop(1, "rgba(255,255,255,0)");
                        ctx.fillStyle = g;
                        ctx.fillRect(x - r, y - r, r * 2, r * 2);
                    }

                    // Em p = 0 nada coberto: a frente ainda está fora da tela
                    // e o alfa sobe junto com o começo do movimento.
                    ctx.globalAlpha = Math.min(1, p * 6);

                    // Disco principal.
                    softDisc(cx, cy, R, (R - feather) / R);

                    // Bolhas na frente, espalhadas entre a direção do canto
                    // inferior direito e a do canto superior esquerdo. Tamanho
                    // e fase fixos por bolha, para o contorno não tremer.
                    const a0 = Math.atan2(h - cy, w - cx);
                    const a1 = Math.atan2(-cy, -cx);
                    const blobs = 9;
                    for (let i = 0; i < blobs; i++) {
                        const t = i / (blobs - 1);
                        const ang = a0 + (a1 - a0) * t;
                        const seed = Math.sin(i * 12.9898) * 43758.5453;
                        const rnd = seed - Math.floor(seed);
                        const breathe = 0.85 + 0.3 * Math.sin(p * Math.PI * 2 + i * 1.7);
                        const br = (w * 0.16 + w * 0.08 * rnd) * breathe + feather * 0.3;
                        const dist = R - feather * (0.55 + 0.35 * rnd);
                        if (dist <= 0)
                            continue;
                        softDisc(cx + Math.cos(ang) * dist, cy + Math.sin(ang) * dist, br, 0.35);
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
