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
//   wipe   varredura em diagonal, como o swww
//   wave   varredura com a borda ondulada
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
    property int coverMs: 450

    // `hold` deixou de ser o caminho normal e virou só o limite: quem revela é
    // o `reveal()`, chamado assim que o renderizador novo aparece de verdade.
    // Antes era um tempo fixo de 1200ms, e quando o backend demorava mais que
    // isso a camada começava a sumir com o wallpaper antigo ainda na tela — os
    // dois apareciam ao mesmo tempo, meio transparentes.
    property int hold: 6000
    property int revealMs: 450

    // Ângulo da varredura, em graus, como o --transition-angle do swww.
    readonly property real wipeAngle: 30

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
        // Mesma curva do swww (--transition-bezier 0.25,0.1,0.25,1.0), que é
        // o ease padrão do CSS: arranca rápido e assenta devagar.
        easing.type: Easing.Bezier
        easing.bezierCurve: [0.25, 0.1, 0.25, 1.0, 1.0, 1.0]
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
            // Dentro da mesma camada vale a ordem de mapeamento, e esta janela
            // só é mapeada na hora de trocar — bem depois do wallpaper subir.
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
            // As máscaras ficam DENTRO do layer.effect. Declaradas como itens
            // irmãos com `visible: false`, elas pareciam funcionar mas não
            // mascaravam nada: um item invisível não é desenhado, logo não gera
            // a textura que o OpacityMask consome, e o resultado era igual ao
            // crossfade em todos os estilos. Medido lado a lado: `fade` e
            // `wipe` davam exatamente a mesma curva de brilho.
            //
            // Gradiente e Canvas são desenhados pela GPU e não precisam de
            // shader compilado (.qsb), que obrigaria uma etapa de build no
            // repositório.

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
                        duration: fadeScope.covering ? (fadeScope.masked ? 0 : fadeScope.coverMs)
                                                     : fadeScope.revealMs
                        easing.type: Easing.InOutQuad
                    }
                }

                layer.enabled: fadeScope.masked
                layer.effect: OpacityMask {
                    maskSource: Item {
                        width: fadeWin.width
                        height: fadeWin.height

                        // Varredura em diagonal, como o swww. A faixa de
                        // transição percorre a tela no ângulo escolhido.
                        LinearGradient {
                            id: wipeMask
                            anchors.fill: parent
                            visible: fadeScope.style === "wipe"

                            readonly property real rad: fadeScope.wipeAngle * Math.PI / 180
                            readonly property real dx: Math.cos(rad)
                            readonly property real dy: Math.sin(rad)
                            readonly property real span: Math.abs(width * dx) + Math.abs(height * dy)
                            // Largura da borda macia, equivalente ao
                            // --transition-step do swww.
                            readonly property real feather: 0.16
                            // Empurra a faixa de -feather até 1 + feather, para
                            // que ela comece e termine fora da tela.
                            readonly property real p: fadeScope.progress * (1 + 2 * feather) - feather

                            start: Qt.point(0, 0)
                            end: Qt.point(dx * span, dy * span)

                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "white" }
                                GradientStop {
                                    position: Math.max(0, Math.min(1, wipeMask.p))
                                    color: "white"
                                }
                                GradientStop {
                                    position: Math.max(0, Math.min(1, wipeMask.p + wipeMask.feather))
                                    color: "transparent"
                                }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }

                        // Círculo que abre do centro.
                        RadialGradient {
                            id: growMask
                            anchors.fill: parent
                            visible: fadeScope.style === "grow"

                            readonly property real feather: 0.14
                            readonly property real p: fadeScope.progress * (1 + feather)

                            horizontalRadius: Math.max(width, height) * 0.75
                            verticalRadius: horizontalRadius

                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "white" }
                                GradientStop {
                                    position: Math.max(0, Math.min(1, growMask.p))
                                    color: "white"
                                }
                                GradientStop {
                                    position: Math.max(0, Math.min(1, growMask.p + growMask.feather))
                                    color: "transparent"
                                }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }

                        // Varredura com a borda ondulada. Desenhada num Canvas
                        // deliberadamente pequeno e escalado: é uma máscara
                        // suave, então a ampliação não aparece, e repintar
                        // 1920x1080 no CPU a cada quadro seria lento demais.
                        Canvas {
                            id: waveMask
                            anchors.fill: parent
                            visible: fadeScope.style === "wave"
                            renderTarget: Canvas.FramebufferObject
                            canvasSize: Qt.size(320, 180)

                            readonly property real feather: 0.18
                            readonly property real p: fadeScope.progress * (1 + 2 * feather) - feather

                            onPChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const w = width;
                                const h = height;
                                const edge = p * w;
                                const band = feather * w;       // borda macia
                                const amp = w * 0.045;          // altura da onda
                                const cycles = 2.2;             // ondas na tela
                                const steps = 64;

                                // Cada fatia horizontal recebe o mesmo degradê,
                                // deslocado pela onda: é isso que dá a borda
                                // ondulada sem precisar de shader.
                                const sliceH = h / steps;
                                for (let i = 0; i < steps; i++) {
                                    const t = (i + 0.5) / steps;
                                    const off = Math.sin(t * Math.PI * 2 * cycles) * amp;
                                    const x0 = edge + off;
                                    const g = ctx.createLinearGradient(x0, 0, x0 + band, 0);
                                    g.addColorStop(0, "white");
                                    g.addColorStop(1, "transparent");
                                    ctx.fillStyle = g;
                                    ctx.fillRect(0, i * sliceH, x0 + band, sliceH + 1);
                                }
                            }
                        }
                    }
                }
            }

            Connections {
                target: fadeScope
                function onProgressChanged() {
                    // O Canvas da onda desliza inteiro, então não precisa ser
                    // repintado — só os gradientes reavaliam sozinhos.
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
    }
}
