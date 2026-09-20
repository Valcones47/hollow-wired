import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Moldura em volta da tela, estilo Caelestia: borda fina (Theme.frameThickness)
// nas laterais e embaixo, colada na waybar em cima, com os cantos de dentro
// arredondados. Mesmo fundo da waybar (background alpha 0.85 + blur), então
// barra, moldura, hub e sidebar parecem uma peça só.
//
// Só desenha: não recebe input (mask vazia) e fica no layer Bottom (janelas
// em tela cheia cobrem). O espaço da borda pras janelas tiled vem do
// gaps_out do Hyprland (hyprland.lua: 8 em cima, 8 + frameThickness nos
// outros lados) — superfícies com exclusive zone nas laterais faziam a
// waybar encolher pra não sobrepor elas.
Scope {
    id: frameScope

    // Esconde a moldura sem quebrar o binding de visibilidade (usado pelo IPC
    // "frame" e pelo modo de captura limpa do shell.qml — ver "capture" lá).
    property bool hidden: false

    PanelWindow {
        id: frame
        visible: !frameScope.hidden
        color: "transparent"
        focusable: false
        anchors { top: true; bottom: true; left: true; right: true }
        margins.top: Theme.waybarHeight
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}

        WlrLayershell.namespace: "quickshell-frame"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Canvas {
            id: canvas
            anchors.fill: parent

            // Retângulo da tela menos um retângulo arredondado por dentro
            // (regra par-ímpar: o miolo vira buraco).
            onPaint: {
                const ctx = getContext("2d");
                const w = width, h = height;
                const t = Theme.frameThickness, r = Theme.frameRadius;
                const x0 = t, y0 = 0, x1 = w - t, y1 = h - t;
                ctx.reset();
                ctx.fillStyle = Theme.surface;
                ctx.fillRule = Qt.OddEvenFill;
                ctx.beginPath();
                ctx.rect(0, 0, w, h);
                ctx.moveTo(x0 + r, y0);
                ctx.lineTo(x1 - r, y0);
                ctx.arc(x1 - r, y0 + r, r, -Math.PI / 2, 0, false);
                ctx.lineTo(x1, y1 - r);
                ctx.arc(x1 - r, y1 - r, r, 0, Math.PI / 2, false);
                ctx.lineTo(x0 + r, y1);
                ctx.arc(x0 + r, y1 - r, r, Math.PI / 2, Math.PI, false);
                ctx.lineTo(x0, y0 + r);
                ctx.arc(x0 + r, y0 + r, r, Math.PI, 3 * Math.PI / 2, false);
                ctx.closePath();
                ctx.fill();
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: Theme
                function onBackgroundChanged() { canvas.requestPaint(); }
            }
        }

        IpcHandler {
            target: "frame"
            function setVisible(v: bool): void { frameScope.hidden = !v; }
        }
    }
}
