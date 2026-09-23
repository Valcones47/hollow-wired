import QtQuick
import "."

// Disco da mídia (o mesmo efeito do widget de música, em tamanho de ícone):
// a capa recortada numa forma de borda ondulada, com contorno claro, girando
// enquanto toca. Aqui a onda reage ao som (MediaState.level, do cava leve).
// Sem capa: vinil escuro com o selo na cor de destaque.
Item {
    id: d
    property real size: 24
    readonly property bool playing: MediaState.playing
    readonly property real level: MediaState.level
    readonly property string artUrl: MediaState.player && MediaState.player.trackArtUrl ? MediaState.player.trackArtUrl : ""
    implicitWidth: size
    implicitHeight: size

    RotationAnimation on rotation {
        loops: Animation.Infinite
        from: 0; to: 360; duration: 9000
        running: d.playing && d.visible
    }

    Canvas {
        id: c
        anchors.centerIn: parent
        width: d.size + 8
        height: d.size + 8
        property real phase: 0
        // amplitude suavizada: sobe rápido com o som, desce devagar
        property real amp: 0
        property string loaded: ""
        property bool artReady: false
        onPhaseChanged: requestPaint()
        onImageLoaded: {
            artReady = loaded !== "" && isImageLoaded(loaded);
            requestPaint();
        }

        // Mesma carga com endereço próprio e novas tentativas do widget (capas
        // em /tmp reaproveitadas entre faixas chegavam antes de estarem escritas).
        Connections {
            target: d
            function onArtUrlChanged() { c.swapArt(); }
        }
        property int tries: 0
        function swapArt() { tries = 0; reload(); }
        function reload() {
            if (loaded !== "") unloadImage(loaded);
            const url = d.artUrl;
            loaded = url === "" ? "" : url + (url.indexOf("?") >= 0 ? "&" : "?") + "v=" + Date.now();
            artReady = false;
            if (loaded !== "") {
                loadImage(loaded);
                retry.restart();
            }
            requestPaint();
        }
        Timer {
            id: retry
            interval: 700
            onTriggered: {
                if (c.loaded === "" || c.artReady) return;
                if (c.isImageLoaded(c.loaded)) { c.artReady = true; c.requestPaint(); }
                else if (++c.tries < 6) c.reload();
            }
        }
        Component.onCompleted: swapArt()

        Timer {
            interval: 33
            repeat: true
            running: d.playing && d.visible
            onTriggered: {
                const target = d.level;
                c.amp += (target - c.amp) * (target > c.amp ? 0.6 : 0.15);
                c.phase += 0.1 + d.level * 0.25;
            }
            onRunningChanged: if (!running) { c.amp = 0; c.requestPaint(); }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2;
            const base = d.size / 2 - 2;
            const A = 0.5 + c.amp * 2.6;
            function shape(off, k1, k2, sp) {
                ctx.beginPath();
                const steps = 72;
                for (let i = 0; i <= steps; i++) {
                    const t = i / steps * Math.PI * 2;
                    const r = base + off + A * (0.6 * Math.sin(k1 * t + c.phase * sp)
                                              + 0.4 * Math.sin(k2 * t - c.phase * sp * 1.4));
                    const x = cx + Math.cos(t) * r, y = cy + Math.sin(t) * r;
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                }
                ctx.closePath();
            }
            ctx.save();
            shape(0, 7, 11, 1.0);
            ctx.clip();
            if (c.artReady) {
                const s = (base + 4) * 2;
                ctx.drawImage(c.loaded, cx - s / 2, cy - s / 2, s, s);
            } else {
                ctx.fillStyle = "#111215";
                ctx.fillRect(0, 0, width, height);
                ctx.beginPath();
                ctx.arc(cx, cy, base * 0.38, 0, Math.PI * 2);
                ctx.fillStyle = Theme.primary;
                ctx.fill();
            }
            ctx.restore();
            ctx.strokeStyle = "white";
            ctx.lineJoin = "round";
            shape(0, 7, 11, 1.0);
            ctx.globalAlpha = 0.9;
            ctx.lineWidth = 1.3;
            ctx.stroke();
        }
    }
}
