import QtQuick
import "."

// Gráfico de linha com preenchimento em degradê (histórico recente). O mais
// novo fica à direita. maxValue 0 = escala automática. `compact` é a versão
// pequena (blocos da lista): sem rótulos.
Canvas {
    id: g

    property var values: []
    property real maxValue: 100
    property color color: Theme.primary
    property int points: 60
    property bool compact: false
    property string topLabel: ""
    property string bottomLeftLabel: ""
    property string bottomRightLabel: ""

    onValuesChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPointsChanged: requestPaint()
    onTopLabelChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const w = width, h = height;
        if (w < 8 || h < 8) return;

        // fundo e grade
        ctx.fillStyle = Theme.withAlpha(Theme.tile, 0.55);
        ctx.fillRect(0, 0, w, h);
        ctx.lineWidth = 1;
        ctx.strokeStyle = Theme.withAlpha(Theme.subtext, g.compact ? 0.08 : 0.11);
        const rows = g.compact ? 2 : 4;
        for (let i = 1; i < rows; i++) {
            const y = Math.round(h * i / rows) + 0.5;
            ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
        }
        if (!g.compact) {
            for (let i = 1; i < 6; i++) {
                const x = Math.round(w * i / 6) + 0.5;
                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke();
            }
        }

        const v = g.values || [];
        if (v.length >= 2) {
            let mx = g.maxValue;
            if (mx <= 0) {
                mx = 1;
                for (const x of v) if (x > mx) mx = x;
                mx *= 1.15;
            }
            const step = w / Math.max(1, g.points - 1);
            const x0 = w - (v.length - 1) * step;
            const pt = (i) => [x0 + i * step, h - 1 - Math.min(1, Math.max(0, v[i] / mx)) * (h - 4)];

            const grad = ctx.createLinearGradient(0, 0, 0, h);
            grad.addColorStop(0, Theme.withAlpha(g.color, 0.5));
            grad.addColorStop(1, Theme.withAlpha(g.color, 0.04));
            ctx.beginPath();
            let p = pt(0);
            ctx.moveTo(p[0], h);
            ctx.lineTo(p[0], p[1]);
            for (let i = 1; i < v.length; i++) { p = pt(i); ctx.lineTo(p[0], p[1]); }
            ctx.lineTo(w, h);
            ctx.closePath();
            ctx.fillStyle = grad;
            ctx.fill();

            ctx.beginPath();
            p = pt(0);
            ctx.moveTo(p[0], p[1]);
            for (let i = 1; i < v.length; i++) { p = pt(i); ctx.lineTo(p[0], p[1]); }
            ctx.lineWidth = g.compact ? 1.4 : 2;
            ctx.lineJoin = "round";
            ctx.strokeStyle = g.color;
            ctx.stroke();
        }

        // moldura
        ctx.lineWidth = 1;
        ctx.strokeStyle = Theme.withAlpha(g.color, g.compact ? 0.45 : 0.6);
        ctx.strokeRect(0.5, 0.5, w - 1, h - 1);

        if (!g.compact) {
            ctx.font = "11px 'Noto Sans'";
            ctx.fillStyle = Theme.withAlpha(Theme.subtext, 0.9);
            if (g.topLabel !== "") { ctx.textAlign = "right"; ctx.fillText(g.topLabel, w - 6, 15); }
            ctx.textBaseline = "alphabetic";
            if (g.bottomLeftLabel !== "") { ctx.textAlign = "left"; ctx.fillText(g.bottomLeftLabel, 6, h - 6); }
            if (g.bottomRightLabel !== "") { ctx.textAlign = "right"; ctx.fillText(g.bottomRightLabel, w - 6, h - 6); }
        }
    }
}
