import QtQuick
import "."

// Gráfico de linha com preenchimento (histórico de ~60 amostras). O mais novo
// fica à direita. maxValue 0 = escala automática.
Canvas {
    id: g

    property var values: []
    property real maxValue: 100
    property color color: Theme.primary
    property int points: 60

    onValuesChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const w = width, h = height;
        if (w < 4 || h < 4) return;
        const line = Theme.withAlpha(Theme.subtext, 0.16);
        ctx.lineWidth = 1;
        ctx.strokeStyle = line;
        for (let i = 1; i < 4; i++) {
            const y = Math.round(h * i / 4) + 0.5;
            ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
        }
        const v = g.values || [];
        if (v.length < 2) return;
        let mx = g.maxValue;
        if (mx <= 0) {
            mx = 1;
            for (const x of v) if (x > mx) mx = x;
            mx *= 1.15;
        }
        const step = w / (g.points - 1);
        const x0 = w - (v.length - 1) * step;
        const pt = (i) => [x0 + i * step, h - 1 - Math.min(1, Math.max(0, v[i] / mx)) * (h - 3)];
        ctx.beginPath();
        let p = pt(0);
        ctx.moveTo(p[0], h);
        ctx.lineTo(p[0], p[1]);
        for (let i = 1; i < v.length; i++) { p = pt(i); ctx.lineTo(p[0], p[1]); }
        ctx.lineTo(w, h);
        ctx.closePath();
        ctx.fillStyle = Theme.withAlpha(g.color, 0.24);
        ctx.fill();
        ctx.beginPath();
        p = pt(0);
        ctx.moveTo(p[0], p[1]);
        for (let i = 1; i < v.length; i++) { p = pt(i); ctx.lineTo(p[0], p[1]); }
        ctx.lineWidth = 1.6;
        ctx.strokeStyle = g.color;
        ctx.stroke();
        // moldura discreta
        ctx.lineWidth = 1;
        ctx.strokeStyle = Theme.withAlpha(g.color, 0.5);
        ctx.strokeRect(0.5, 0.5, w - 1, h - 1);
    }
}
