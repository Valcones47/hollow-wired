import QtQuick
import QtQuick.Shapes

// Área preenchida com o topo ondulado (senoide). Largura em múltiplos do
// período para o deslocamento horizontal em loop não mostrar emenda.
Shape {
    id: root

    property real amp: 4
    property real period: 40
    property color color: "white"

    preferredRendererType: Shape.CurveRenderer

    function build(w, h) {
        if (period <= 0 || w <= 0) return "";
        const steps = Math.ceil(w / period) * 8;
        let d = `M 0 ${h} L 0 ${amp}`;
        for (let i = 0; i <= steps; i++) {
            const x = i * w / steps;
            const y = amp - Math.sin(x / period * 2 * Math.PI) * amp;
            d += ` L ${x} ${y}`;
        }
        return d + ` L ${w} ${h} Z`;
    }

    ShapePath {
        strokeWidth: -1
        fillColor: root.color
        PathSvg { path: root.build(root.width, root.height) }
    }
}
