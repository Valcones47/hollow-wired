import QtQuick
import Quickshell.Widgets
import "."

// Ícone de um item da bandeja (SystemTrayItem), igual em todas as barras.
//
// O Discord não manda nome de ícone, só a imagem pronta, com cores fixas:
// branca parado ou em chamada, verde enquanto a pessoa fala, vermelha no
// mudo. Aqui a imagem dele é redesenhada num Canvas trocando só as cores —
// branco/cinza vira a cor do texto do tema, verde vira o destaque, vermelho
// vira o "crítico" — e o formato (logo, alto-falante...) continua o do
// Discord, então todos os estados aparecem. Os outros apps ficam como estão.
Item {
    id: ti
    required property var item
    property int size: 20

    readonly property bool isDiscord: /^discord/i.test(String(item ? item.id : ""))

    implicitWidth: size
    implicitHeight: size

    IconImage {
        anchors.centerIn: parent
        visible: !ti.isDiscord
        implicitSize: ti.size
        source: ti.isDiscord ? "" : ti.item.icon
    }

    Canvas {
        id: tinted
        anchors.centerIn: parent
        visible: ti.isDiscord
        width: ti.size
        height: ti.size
        property string src: ti.isDiscord ? String(ti.item.icon) : ""
        // Repinta quando a imagem ou o tema mudam.
        property color fg: Theme.textColor
        property color hot: Theme.primary
        property color bad: Theme.critical
        onSrcChanged: if (src !== "") { unloadImage(src); loadImage(src); }
        onImageLoaded: requestPaint()
        onFgChanged: requestPaint()
        onHotChanged: requestPaint()
        onBadChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.clearRect(0, 0, width, height);
            if (src === "" || !isImageLoaded(src)) return;
            c.drawImage(src, 0, 0, width, height);
            // O putImageData não desenha neste Canvas (testado: fica vazio),
            // então os pixels são lidos e redesenhados um a um com fillRect.
            const d = c.getImageData(0, 0, width, height).data;
            c.clearRect(0, 0, width, height);
            for (let y = 0; y < height; y++) {
                for (let x = 0; x < width; x++) {
                    const i = (y * width + x) * 4;
                    const a = d[i + 3] / 255;
                    if (a === 0) continue;
                    const r = d[i] / 255, g = d[i + 1] / 255, b = d[i + 2] / 255;
                    const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
                    let to = fg, k = mx;             // k: mantém o sombreado
                    if (mx - mn >= 0.25) {
                        let h;
                        if (mx === r) h = ((g - b) / (mx - mn)) % 6;
                        else if (mx === g) h = (b - r) / (mx - mn) + 2;
                        else h = (r - g) / (mx - mn) + 4;
                        h = (h * 60 + 360) % 360;
                        if (h >= 80 && h < 170) { to = hot; k = 1; }
                        else if (h >= 330 || h < 25) { to = bad; k = 1; }
                    }
                    c.fillStyle = Qt.rgba(to.r * k, to.g * k, to.b * k, a);
                    c.fillRect(x, y, 1, 1);
                }
            }
        }
    }
}
