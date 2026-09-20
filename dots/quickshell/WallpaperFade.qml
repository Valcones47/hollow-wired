import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Transição suave entre wallpapers.
//
// O Waywallen (e qualquer backend de wallpaper animado) não consegue manter
// dois renderizadores vivos ao mesmo tempo: trocar de papel de parede mata o
// renderizador atual e sobe outro, o que dá o engasgo de ~1s e o flash preto.
//
// A saída é não tentar misturar dois vídeos. Esta camada mostra o *preview
// estático* do wallpaper que está entrando e o faz aparecer por cima do antigo,
// que continua animando normalmente por baixo. Só quando a imagem cobre a tela
// inteira é que a troca de verdade acontece — o engasgo fica escondido atrás
// dela. Depois a camada some e revela o novo wallpaper já rodando.
//
// É exatamente o comportamento que se vê nos rices de referência: o wallpaper
// que sai continua em movimento, o que entra fica parado até o outro sumir.
//
// Uso (ver rice-wallpaper-fade):
//   qs ipc call wallfade cover /caminho/preview.gif
//   qs ipc call wallfade dismiss
Scope {
    id: fadeScope

    // Tempos em ms. Somados dão a duração total da transição.
    readonly property int fadeIn: 700      // antigo (animando) -> preview do novo
    readonly property int hold: 1500       // tela coberta: é aqui que a troca ocorre
    readonly property int fadeOut: 550     // revela o novo wallpaper já rodando

    property string source: ""
    property bool covering: false

    // Se algo der errado no meio do caminho (o backend travou, o script morreu),
    // a camada NUNCA pode ficar presa cobrindo a área de trabalho inteira.
    readonly property int safetyTimeout: fadeIn + hold + fadeOut + 4000

    function cover(path) {
        if (!path)
            return;
        fadeScope.source = path.startsWith("file://") ? path : "file://" + path;
        fadeScope.covering = true;
        holdTimer.restart();
        safetyTimer.restart();
    }

    function dismiss() {
        fadeScope.covering = false;
        holdTimer.stop();
        safetyTimer.stop();
    }

    // Fim do tempo coberto: começa a revelar o wallpaper novo.
    Timer {
        id: holdTimer
        interval: fadeScope.fadeIn + fadeScope.hold
        onTriggered: fadeScope.covering = false
    }

    Timer {
        id: safetyTimer
        interval: fadeScope.safetyTimeout
        onTriggered: fadeScope.dismiss()
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

            Image {
                id: fadeImage
                anchors.fill: parent
                source: fadeScope.source
                fillMode: Image.PreserveAspectCrop
                // Os previews do Wallpaper Engine são pequenos (geralmente
                // 512px); sem isso a escala pra tela cheia fica serrilhada.
                smooth: true
                mipmap: true
                asynchronous: true
                cache: false

                opacity: fadeScope.covering ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: fadeScope.covering ? fadeScope.fadeIn : fadeScope.fadeOut
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "wallfade"

        // Cobre a tela com o preview do wallpaper que está entrando.
        function cover(path: string): void { fadeScope.cover(path); }
        // Tira a camada na hora (usado quando a troca falhou).
        function dismiss(): void { fadeScope.dismiss(); }
        // Quanto tempo o chamador deve esperar antes de aplicar a troca.
        function coverDelay(): string { return String(fadeScope.fadeIn + 120); }
    }
}
