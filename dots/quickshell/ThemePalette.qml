import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Paleta de uma tela extra (várias telas, wallpaper diferente em cada uma).
// Lê ~/.cache/wallust/screens/<tela>.json (gerado pelo rice-screen-colors no
// mesmo formato do colors-quickshell.json) e deriva as cores com as MESMAS
// regras do Theme.qml — o trecho de cores abaixo é cópia dele; ao mudar a
// derivação lá, mude aqui também. Sem arquivo (mesmo wallpaper da principal),
// `valid` fica falso e quem usa cai no Theme.
QtObject {
    id: root

    property string screenName: ""
    property bool valid: false

    property color background: "#111218"
    property color foregroundRaw: "#e2e8f0"
    property color color0: "#181922"
    property color color1: "#f43f5e"
    property color color2: "#10b981"
    property color color3: "#f59e0b"
    property color color4: "#3b82f6"
    property color color5: "#d946ef"
    property color color6: "#06b6d4"
    property color color7: "#94a3b8"
    property color color8: "#475569"
    property color color9: "#fb7185"
    property color color10: "#ff2a85"
    property color color11: "#ef4444"
    property color color12: "#60a5fa"
    property color color13: "#e879f9"
    property color color14: "#22d3ee"
    property color color15: "#f8fafc"

    // Aliases semânticos, no mesmo espírito das variáveis @wallust_* do
    // waybar/eww (mesmo mapeamento: accent1=color4, accent2=color6,
    // inactive=color8, warning=color3, critical=color11).
    // ---------- cor de texto legível ----------
    // O wallust às vezes devolve um "foreground" colorido (num papel de parede
    // vermelho veio #DA4B5B): o texto ficava vermelho-escuro sobre fundo quase
    // preto e não dava para ler. A cor de texto mantém só uma pitada do matiz e
    // é clareada até ter contraste de verdade com o fundo.
    function _lum(c) {
        const f = x => x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }
    function contrast(a, b) {
        const l1 = Math.max(root._lum(a), root._lum(b));
        const l2 = Math.min(root._lum(a), root._lum(b));
        return (l1 + 0.05) / (l2 + 0.05);
    }
    readonly property color foreground: {
        const raw = root.foregroundRaw;
        const h = raw.hslHue < 0 ? 0 : raw.hslHue;
        let c = Qt.hsla(h, Math.min(raw.hslSaturation, 0.18), Math.max(raw.hslLightness, 0.88), 1);
        // Fundo claro (papel de parede claro): escurece em vez de clarear.
        const goDark = root._lum(root.background) > 0.4;
        if (goDark) c = Qt.hsla(h, Math.min(raw.hslSaturation, 0.25), Math.min(raw.hslLightness, 0.18), 1);
        let guard = 0;
        while (root.contrast(c, root.background) < 8 && guard < 14) {
            c = root.mix(c, goDark ? "#000000" : "#ffffff", 0.12);
            guard++;
        }
        return c;
    }

    readonly property color accent1: color4
    readonly property color accent2: color6
    readonly property color inactive: color8
    readonly property color warning: color3
    readonly property color critical: color11

    function withAlpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function mix(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    // ---------- tokens de superfície (estilo Material 3 / Caelestia) ----------
    // A paleta do wallust tem os accents muito escuros (color4/color6 quase
    // somem em cima do background), por isso o "primary" usa a cor viva
    // mais clara (color10) e os cards são o background clareado um pouco na
    // direção do foreground, em vez de bordas finas.
    // ---------- escolha dos destaques ----------
    // Papéis de parede escuros/dessaturados davam uma paleta quase cinza: o
    // painel inteiro saía de uma cor só. Aqui a interface escolhe as duas cores
    // mais vivas da paleta (com matizes diferentes entre si) e garante um
    // mínimo de saturação e de claridade para elas aparecerem sobre o fundo.
    function _vivid(c, minS, lo, hi) {
        const sat = Math.max(c.hslSaturation, minS);
        const h = c.hslHue < 0 ? 0 : c.hslHue;
        let out = Qt.hsla(h, sat, Math.min(hi, Math.max(lo, c.hslLightness)), 1);
        // Piso de contraste contra o fundo: numa paleta escura (vermelho, roxo)
        // o destaque saía quase invisível em cima do fundo quase preto.
        let l = out.hslLightness, guard = 0;
        while (root.contrast(out, root.background) < 4.5 && guard < 14) {
            l = root._lum(root.background) > 0.4 ? Math.max(0.08, l - 0.05) : Math.min(0.92, l + 0.05);
            out = Qt.hsla(h, sat, l, 1);
            guard++;
        }
        return out;
    }
    function _score(c) {
        // Saturação manda; claridade no meio da faixa ajuda a legibilidade.
        const l = c.hslLightness;
        return c.hslSaturation * (1 - Math.abs(l - 0.58) * 0.9);
    }
    function _hueGap(a, b) {
        if (a.hslHue < 0 || b.hslHue < 0) return 1;
        const d = Math.abs(a.hslHue - b.hslHue);
        return Math.min(d, 1 - d);
    }
    readonly property var _accentKeys: ["color10", "color13", "color12", "color9", "color14", "color11", "color5", "color4", "color6", "color2", "color3", "color1"]
    readonly property var _accentPool: [color10, color13, color12, color9, color14, color11, color5, color4, color6, color2, color3, color1]
    // Índices escolhidos: o painel de cores mostra e deixa editar justamente as
    // cores que viraram destaque (antes ele mostrava color4/color10 fixos, que
    // podiam não ter nada a ver com o destaque em uso).
    readonly property int _idx1: {
        let bi = 0, bestScore = -1;
        for (let i = 0; i < _accentPool.length; i++) {
            const sc = root._score(_accentPool[i]);
            if (sc > bestScore) { bi = i; bestScore = sc; }
        }
        return bi;
    }
    readonly property int _idx2: {
        let bi = -1, bestScore = -1;
        for (let i = 0; i < _accentPool.length; i++) {
            if (root._hueGap(_accentPool[i], root._pick1) < 0.12) continue;
            const sc = root._score(_accentPool[i]);
            if (sc > bestScore) { bi = i; bestScore = sc; }
        }
        return bestScore < 0.12 ? -1 : bi;
    }
    readonly property string primaryKey: _accentKeys[_idx1]
    // -1 = o segundo destaque foi criado girando o matiz, não veio da paleta.
    readonly property string secondaryKey: _idx2 >= 0 ? _accentKeys[_idx2] : ""
    readonly property color _pick1: _accentPool[_idx1]
    readonly property color _pick2: {
        // Paleta de matiz único (papel de parede monocromático): em vez de
        // repetir a mesma cor, gira o matiz para ter um segundo destaque.
        if (root._idx2 < 0) {
            const h = root._pick1.hslHue < 0 ? 0.55 : root._pick1.hslHue;
            return Qt.hsla((h + 0.42) % 1, 0.42, 0.60, 1);
        }
        return _accentPool[root._idx2];
    }
    // Destaques escolhidos à mão no painel (rice-colors set accent1/accent2,
    // guardados no color-overrides.json): valem exatamente como escolhidos,
    // sem o ajuste de vivacidade, e vencem a escolha automática.
    // Destaques escolhidos à mão no painel valem em todas as telas.
    readonly property string accentOverride1: Theme.accentOverride1
    readonly property string accentOverride2: Theme.accentOverride2
    readonly property color primary: accentOverride1 !== "" ? accentOverride1 : _vivid(_pick1, 0.38, 0.46, 0.62)
    readonly property color tertiary: accentOverride2 !== "" ? accentOverride2 : _vivid(_pick2, 0.34, 0.52, 0.68)
    readonly property color primaryOld: color10
    // Usado em vários lugares mas nunca tinha sido definido: virava
    // `undefined` e o QML desenhava preto (o medidor da GPU nos widgets).
    readonly property color secondary: tertiary
    readonly property color textColor: foreground
    // Texto de apoio: um degrau abaixo do título, mas nunca "apagado". Tem piso
    // de contraste próprio — antes dava para cair em cinza difícil de ler.
    function _readable(c, minContrast) {
        let out = c, l = c.hslLightness, guard = 0;
        const dark = root._lum(root.background) <= 0.4;
        const h = c.hslHue < 0 ? 0 : c.hslHue;
        while (root.contrast(out, root.background) < minContrast && guard < 18) {
            l = dark ? Math.min(0.97, l + 0.04) : Math.max(0.05, l - 0.04);
            out = Qt.hsla(h, c.hslSaturation, l, 1);
            guard++;
        }
        return out;
    }
    readonly property color subtext: _readable(mix(background, foreground, 0.86), 7)
    readonly property color subtextSoft: _readable(mix(background, foreground, 0.74), 5.5)
    readonly property color outline: color8
    readonly property color surface: withAlpha(background, 0.85) // = fundo da waybar
    // Contorno neutro de cartões e campos (usado pelos toasts, sessão e polkit).
    readonly property color border: withAlpha(outline, 0.3)
    readonly property color tile: withAlpha(mix(background, foreground, 0.07), 0.9)
    readonly property color tileHigh: withAlpha(mix(background, foreground, 0.13), 0.95)


    property FileView colorFile: FileView {
        path: root.screenName === "" ? "" : Quickshell.env("HOME") + "/.cache/wallust/screens/" + root.screenName + ".json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (!data || !data.background) { root.valid = false; return; }
                root.background = data.background;
                if (data.foreground) root.foregroundRaw = data.foreground;
                for (let i = 0; i < 16; i++) if (data["color" + i]) root["color" + i] = data["color" + i];
                root.valid = true;
            } catch (e) {
                root.valid = false;
            }
        }
        onLoadFailed: root.valid = false
    }
    // O arquivo some quando a tela volta a ter o mesmo wallpaper da principal;
    // o watcher não avisa remoção de forma confiável, então confere de vez em quando.
    property Timer recheck: Timer {
        interval: 5000
        running: root.screenName !== ""
        repeat: true
        onTriggered: root.colorFile.reload()
    }
}
