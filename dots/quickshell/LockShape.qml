import QtQuick
import QtQuick.Shapes

// Formas arredondadas no estilo Material 3 Expressive (a tela de bloqueio do
// Caelestia usa o plugin M3Shapes, em C++; aqui o contorno é gerado em JS a
// partir de um polígono com cantos suavizados por curvas quadráticas).
//
// shape: "circle" | "pentagon" | "triangle" | "diamond" | "slanted" | "gem" |
//        "sunny" | "verySunny" | "cookie4" | "cookie6" | "softBurst" |
//        "clamShell" | "arrow" | "square"
Shape {
    id: root

    property string shape: "circle"
    property color color: "white"
    property real size: 40

    // Parâmetros de cada forma: lados, raio interno (estrela quando < 1),
    // quanto do lado vira curva no canto, rotação em graus e achatamento.
    readonly property var presets: ({
        circle:    { n: 0 },
        pentagon:  { n: 5, inner: 1, round: 0.32, rot: -90 },
        triangle:  { n: 3, inner: 1, round: 0.34, rot: -90 },
        arrow:     { n: 3, inner: 1, round: 0.3, rot: 0 },
        diamond:   { n: 4, inner: 1, round: 0.26, rot: -90, sy: 1.12, sx: 0.9 },
        square:    { n: 4, inner: 1, round: 0.3, rot: 45 },
        slanted:   { n: 4, inner: 1, round: 0.3, rot: 36, sx: 0.96 },
        gem:       { n: 6, inner: 1, round: 0.3, rot: -90, sx: 0.92 },
        sunny:     { n: 8, inner: 0.82, round: 0.5, rot: -90 },
        verySunny: { n: 12, inner: 0.84, round: 0.5, rot: -90 },
        cookie4:   { n: 4, inner: 0.72, round: 0.5, rot: -45 },
        cookie6:   { n: 6, inner: 0.8, round: 0.5, rot: -90 },
        softBurst: { n: 10, inner: 0.76, round: 0.42, rot: -90 },
        clamShell: { n: 6, inner: 1, round: 0.28, rot: 0, sy: 0.8 }
    })
    readonly property var spec: presets[shape] ?? presets.circle
    readonly property real stretchY: spec.sy ?? 1

    implicitWidth: size
    implicitHeight: size * stretchY
    preferredRendererType: Shape.CurveRenderer

    function buildPath(w, h) {
        const s = root.spec;
        const cx = w / 2, cy = h / 2;
        const rx = w / 2 * (s.sx ?? 1), ry = h / 2;
        if (!s.n) {
            const r = Math.min(w, h) / 2;
            return `M ${cx - r} ${cy} a ${r} ${r} 0 1 0 ${2 * r} 0 a ${r} ${r} 0 1 0 ${-2 * r} 0 Z`;
        }
        const pts = [];
        const total = s.inner < 1 ? s.n * 2 : s.n;
        const rot = (s.rot ?? 0) * Math.PI / 180;
        for (let i = 0; i < total; i++) {
            const k = (s.inner < 1 && i % 2 === 1) ? s.inner : 1;
            const a = rot + i * 2 * Math.PI / total;
            pts.push([cx + Math.cos(a) * rx * k, cy + Math.sin(a) * ry * k]);
        }
        // Encaixa o polígono na caixa inteira: sem isso o pentágono ficava
        // deslocado para cima e cada forma saía de um tamanho diferente.
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const p of pts) {
            x0 = Math.min(x0, p[0]); x1 = Math.max(x1, p[0]);
            y0 = Math.min(y0, p[1]); y1 = Math.max(y1, p[1]);
        }
        const fx = w * (s.sx ?? 1) / Math.max(1e-6, x1 - x0), fy = h / Math.max(1e-6, y1 - y0);
        const ox = (w - (x1 - x0) * fx) / 2;
        for (const p of pts) {
            p[0] = ox + (p[0] - x0) * fx;
            p[1] = (p[1] - y0) * fy;
        }
        const t = s.round;
        const lerp = (p, q, f) => [p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f];
        let d = "";
        for (let i = 0; i < pts.length; i++) {
            const prev = pts[(i - 1 + pts.length) % pts.length];
            const cur = pts[i];
            const next = pts[(i + 1) % pts.length];
            const a = lerp(cur, prev, t);
            const b = lerp(cur, next, t);
            d += (i === 0 ? `M ${a[0]} ${a[1]} ` : `L ${a[0]} ${a[1]} `) + `Q ${cur[0]} ${cur[1]} ${b[0]} ${b[1]} `;
        }
        return d + "Z";
    }

    ShapePath {
        strokeWidth: -1
        fillColor: root.color
        PathSvg { path: root.buildPath(root.size, root.size * root.stretchY) }
    }
}
