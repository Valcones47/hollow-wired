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
//   wave   ondas circulares saindo do canto superior direito
//   grow   círculo que abre do centro
//
// Uso (ver rice-wallpaper-fade):
//   qs ipc call wallfade cover /caminho/imagem.png
//   qs ipc call wallfade dismiss
Scope {
    id: fadeScope

    property string style: "wipe"

    // Tempos. O que manda na sensação de "travou" é o coverMs: ele é tempo
    // morto entre o clique e a troca começar de verdade, porque quem troca
    // espera a tela estar coberta antes de mandar o comando. Era 1300 e, com o
    // ~1s que o backend leva por conta própria, o wallpaper só mudava 3s
    // depois do clique.
    property int coverMs: 900

    // `hold` deixou de ser o caminho normal e virou só o limite: quem revela é
    // o `reveal()`, chamado assim que o renderizador novo aparece de verdade.
    // Antes era um tempo fixo de 1200ms, e quando o backend demorava mais que
    // isso a camada começava a sumir com o wallpaper antigo ainda na tela — os
    // dois apareciam ao mesmo tempo, meio transparentes.
    // Com a espera pelo renderizador assentar e pela paleta nova (ver
    // rice-wallpaper-fade), o caminho normal leva de 1,5 a 4s depois de cobrir.
    property int hold: 9000
    // Mais lento que a entrada de propósito: a saída é quando o olho está
    // procurando o wallpaper novo, e qualquer tranco do renderizador que ainda
    // sobrar fica diluído num esmaecer longo.
    property int revealMs: 750

    property string source: ""
    property bool covering: false

    // Progresso da máscara: 0 = nada coberto, 1 = tela inteira coberta.
    // Os estilos com máscara animam isto; o `fade` anima a opacidade e deixa
    // o progresso em 1 o tempo todo.
    property real progress: 0

    // Se algo der errado no meio do caminho (o backend travou, o script morreu),
    // a camada NUNCA pode ficar presa cobrindo a área de trabalho inteira.
    readonly property int safetyTimeout: coverMs + hold + revealMs + 4000

    readonly property bool masked: style === "wipe" || style === "wave" || style === "grow"

    // Espera a imagem estar decodificada antes de animar. Uma imagem de tela
    // cheia leva algumas dezenas de ms para decodificar, e começar a varredura
    // antes disso desperdiça o começo da animação desenhando nada.
    property bool pendingCover: false

    // Duração da animação de opacidade. É definida ANTES de mexer em
    // `covering`, de propósito: um `Behavior` avalia as próprias propriedades
    // com o valor que elas tinham antes da mudança que o disparou, então
    // amarrar a duração a `covering` dentro dele não funciona — medindo, a
    // imagem subia de 0 a 1 em 450ms uniformemente pela tela, por cima da
    // varredura, e era isso que aparecia como "meio transparente junto com o
    // wallpaper antigo".
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
        // Nos estilos com máscara a opacidade salta para 1 e quem revela a
        // imagem aos poucos é a máscara.
        fadeScope.opDuration = fadeScope.masked ? 0 : fadeScope.coverMs;
        fadeScope.covering = true;
        // Sem o restart explícito, cobrir duas vezes seguidas deixaria a
        // animação de máscara parada no valor anterior.
        if (fadeScope.masked)
            coverAnim.restart();
    }

    // Se a imagem não carregar (arquivo sumiu, formato estranho), a transição
    // não pode ficar esperando para sempre.
    Timer {
        id: decodeGuard
        interval: 250
        onTriggered: fadeScope.maybeStart()
    }

    // Revela o wallpaper novo. Chamado quando o renderizador novo já está no ar
    // (ver rice-wallpaper-fade --reveal-when-ready).
    function reveal() {
        if (!fadeScope.covering && !fadeScope.pendingCover)
            return;
        fadeScope.pendingCover = false;
        fadeScope.opDuration = fadeScope.revealMs;
        fadeScope.covering = false;
        holdTimer.stop();
    }

    function dismiss() {
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
        // Na onda a frente anda quase por igual do começo ao fim — com o ease
        // do CSS ela cobria 70% da tela no primeiro terço e os anéis mal
        // apareciam. Os outros estilos seguem a curva do swww
        // (0.25,0.1,0.25,1.0), que arranca rápido e assenta devagar.
        easing.type: Easing.Bezier
        easing.bezierCurve: fadeScope.style === "wave" ? [0.45, 0.05, 0.55, 0.95, 1.0, 1.0]
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

            // Onda: ondas circulares que nascem no canto superior direito e se
            // espalham pela tela, como uma pedra na água. A frente é um arco
            // de círculo com a borda ondulando (e a ondulação anda enquanto
            // cresce), e à frente dela correm dois anéis mais fracos, por onde
            // o wallpaper novo já aparece em faixas.
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
                    const cx = w;          // canto superior direito
                    const cy = 0;
                    const diag = Math.sqrt(w * w + h * h);
                    const band = diag * 0.09;   // largura da borda macia
                    const amp = diag * 0.03;    // altura da ondulação
                    const gap = diag * 0.085;   // distância entre os anéis
                    const lobes = 6;
                    const phase = p * Math.PI * 4;
                    // Em p = 1 a parte sólida já passou do canto oposto.
                    const R = p * (diag + band + amp * 2);

                    function radius(base, th, shift) {
                        return base + amp * Math.sin(th * lobes + phase + shift)
                                    + amp * 0.45 * Math.sin(th * lobes * 2.3 - phase * 1.6 + shift);
                    }
                    // Arco de 90° a 180° (para baixo até para a esquerda), com
                    // uma folga para a ondulação não deixar frestas nas bordas.
                    const a0 = Math.PI / 2 - 0.08;
                    const a1 = Math.PI + 0.08;
                    const steps = 90;

                    function fillWave(base, shift) {
                        if (base <= 0)
                            return;
                        ctx.beginPath();
                        ctx.moveTo(cx, cy);
                        for (let i = 0; i <= steps; i++) {
                            const th = a0 + (a1 - a0) * i / steps;
                            const r = Math.max(0, radius(base, th, shift));
                            ctx.lineTo(cx + r * Math.cos(th), cy + r * Math.sin(th));
                        }
                        ctx.closePath();
                        ctx.fill();
                    }
                    function strokeWave(base, shift) {
                        ctx.beginPath();
                        for (let i = 0; i <= steps; i++) {
                            const th = a0 + (a1 - a0) * i / steps;
                            const r = Math.max(0, radius(base, th, shift));
                            const x = cx + r * Math.cos(th);
                            const y = cy + r * Math.sin(th);
                            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                        }
                        ctx.stroke();
                    }

                    ctx.fillStyle = "white";
                    // Miolo sólido.
                    fillWave(R - band, 0);
                    // Borda macia: camadas finas empilhadas até a frente. O
                    // alfa se acumula, então o miolo chega a opaco e a frente
                    // fica quase transparente, sem perder o contorno ondulado.
                    const layers = 7;
                    ctx.globalAlpha = 0.22;
                    for (let k = 1; k <= layers; k++)
                        fillWave(R - band + band * k / layers, 0);

                    // Anéis à frente. Aparecem logo no começo e somem no fim,
                    // quando a tela já está quase coberta.
                    const fadeIn = Math.min(1, p * 5);
                    ctx.lineCap = "round";
                    ctx.strokeStyle = "white";
                    for (let k = 1; k <= 3; k++) {
                        const base = R + gap * k;
                        const lw = gap * (0.55 - 0.1 * k);
                        const a = (0.95 - 0.25 * k) * fadeIn;
                        // Três passadas de largura decrescente: anel com borda
                        // suave em vez de uma linha dura.
                        for (const f of [1.0, 0.6, 0.3]) {
                            ctx.globalAlpha = a * 0.5;
                            ctx.lineWidth = lw * f;
                            strokeWave(base, k * 0.9);
                        }
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
        function coverDelay(): string { return String(fadeScope.coverMs + 180); }
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
