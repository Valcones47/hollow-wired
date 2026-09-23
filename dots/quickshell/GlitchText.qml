pragma ComponentBehavior: Bound
import QtQuick
import "."

// Frase que troca sozinha, com o texto se desfazendo no meio da troca.
//
// Usada embaixo do olho na tela de boas-vindas: a cada poucos segundos o texto
// se corrompe por um instante, troca por outro e assenta — como legenda
// chegando por um sinal ruim. As cópias em ciano e verde são o mesmo texto
// fora de registro, o que dá o ar de transmissão.
Item {
    id: gt
    // Cor de destaque: o tema, a menos que quem usa fixe outra (a tela de
    // boas-vindas usa sempre a mesma paleta, independente do wallpaper).
    property color accent: Theme.primary

    property var phrases: []
    property bool running: true
    property int index: 0
    property string display: gt.phrases.length > 0 ? gt.phrases[0] : ""
    property bool glitching: false
    property int fontSize: 14
    property color baseColor: gt.accent

    implicitHeight: mainText.implicitHeight
    implicitWidth: mainText.implicitWidth

    // Caracteres que entram no lugar dos originais durante a corrupção.
    readonly property string noise: "▓▒░/\\|_¦#<>*·×+=~^"

    function corrupt(text, amount) {
        let out = "";
        for (let i = 0; i < text.length; i++) {
            const c = text.charAt(i);
            if (c !== " " && Math.random() < amount)
                out += gt.noise.charAt(Math.floor(Math.random() * gt.noise.length));
            else
                out += c;
        }
        return out;
    }

    // Espera uns segundos, corrompe, troca a frase e assenta.
    Timer {
        id: cycle
        running: gt.running && gt.phrases.length > 1
        interval: 4000 + Math.random() * 2000
        repeat: true
        onTriggered: {
            gt.glitching = true;
            swap.restart();
            scramble.ticks = 0;
            scramble.restart();
            interval = 4000 + Math.random() * 2000;
        }
    }

    // Só no meio da corrupção o texto vira o próximo: a troca não aparece.
    Timer {
        id: swap
        interval: 130
        onTriggered: gt.index = (gt.index + 1) % gt.phrases.length
    }

    // Sem "running:" declarativo de propósito: o restart() abaixo quebraria o
    // binding e a corrupção só funcionaria na primeira troca.
    Timer {
        id: scramble
        interval: 45
        repeat: true
        property int ticks: 0
        onTriggered: {
            ticks++;
            if (ticks > 6) {
                scramble.stop();
                gt.glitching = false;
                gt.display = gt.phrases[gt.index];
                return;
            }
            gt.display = gt.corrupt(gt.phrases[gt.index], 0.45);
        }
    }

    onIndexChanged: if (!glitching) display = phrases[index]
    onRunningChanged: {
        if (gt.running) return;
        scramble.stop();
        swap.stop();
        gt.glitching = false;
        gt.display = gt.phrases.length > 0 ? gt.phrases[gt.index] : "";
    }
    onPhrasesChanged: {
        index = 0;
        display = phrases.length > 0 ? phrases[0] : "";
    }

    // cópias fora de registro, só enquanto o texto está se desfazendo
    Repeater {
        model: gt.glitching ? [{ dx: -2, c: "#00e5ff" }, { dx: 2, c: "#39ff14" }] : []
        delegate: Text {
            required property var modelData
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: modelData.dx
            text: gt.display
            font.family: Theme.fontFamily
            font.pixelSize: gt.fontSize
            font.letterSpacing: 2
            color: modelData.c
            opacity: 0.5
        }
    }

    Text {
        id: mainText
        anchors.centerIn: parent
        text: gt.display
        font.family: Theme.fontFamily
        font.pixelSize: gt.fontSize
        font.letterSpacing: 2
        color: gt.glitching ? Theme.mix(gt.baseColor, "#ffffff", 0.4) : gt.baseColor
    }
}
