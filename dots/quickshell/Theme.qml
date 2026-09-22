pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Paleta lida de ~/.cache/wallust/colors-quickshell.json (gerada pelo
// wallust a partir do wallpaper atual — ver template em
// ~/.config/wallust/templates/quickshell-colors.json). Atualiza sozinho
// quando o wallpaper muda: FileView com watchChanges observa o arquivo e
// reprocessa o JSON, sem precisar reiniciar o Quickshell.
QtObject {
    id: root

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
    readonly property color primary: _vivid(_pick1, 0.38, 0.46, 0.62)
    readonly property color tertiary: _vivid(_pick2, 0.34, 0.52, 0.68)
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
    readonly property color tile: withAlpha(mix(background, foreground, 0.07), 0.9)
    readonly property color tileHigh: withAlpha(mix(background, foreground, 0.13), 0.95)

    readonly property int radius: 16
    readonly property int tileRadius: 14
    readonly property int gap: 8
    // Tamanho FIXO do painel — landscape (mais largo que alto, como a
    // Caelestia), igual em todas as abas. O conteúdo de cada aba se ajusta
    // DENTRO desse tamanho, nunca o contrário (prompt 5, problema 1).
    readonly property int panelWidth: 860
    readonly property int panelHeight: 460
    // Altura da barra do topo (TopBar.qml — antes era a waybar, por isso o
    // nome ficou). Hub, moldura e sidebar começam abaixo dela. O painel usa
    // exclusionMode Ignore (pra não empurrar/redimensionar outras janelas),
    // o que também faz ele parar de respeitar a exclusive zone da waybar
    // sozinho — por isso precisa somar isso na margem manualmente.
    readonly property int waybarHeight: 34

    // ---------- moldura em volta da tela (Frame.qml) ----------
    // Borda fina com o mesmo fundo da waybar; os cantos de dentro são
    // arredondados. Reserva esse espaço nas laterais e embaixo pras janelas.
    readonly property int frameThickness: 10
    readonly property int frameRadius: 20

    // ---------- barra lateral de energia/updates/trays ----------
    // A faixa da moldura direita (frameThickness) é o gatilho do hover.
    // Altura do corpo da dock — o Launcher usa para tirar a área da dock da sua
    // máscara de clique enquanto ela está aberta (ver Launcher.qml).
    readonly property int dockHeight: 64
    readonly property int sidebarWidth: 64
    readonly property int sidebarIconSize: 22
    readonly property int sidebarButtonSize: 46
    readonly property int popoutMaxWidth: 300

    // Texto do hub em fonte proporcional (a Caelestia usa sans, não mono —
    // era boa parte do aspecto "cru"). A waybar continua em Noto Sans Mono.
    readonly property string fontFamily: "Noto Sans"
    readonly property string monoFamily: "Noto Sans Mono"
    readonly property string iconFontFamily: "CaskaydiaCove Nerd Font"

    // Ícones Material Design da Nerd Font (codepoints conferidos no cmap da
    // CaskaydiaCove com fontTools — todos existem nessa build).
    readonly property var icons: ({
        dashboard: "\u{F0A1D}", media: "\u{F0CB8}", performance: "\u{F04C5}", workspaces: "\u{F11D9}",
        logout: "\u{F0343}", restart: "\u{F0709}", power: "\u{F0425}", update: "\u{F03D4}",
        account: "\u{F0009}", arch: "\u{F08C7}", monitor: "\u{F0379}", clock: "\u{F0150}",
        prev: "\u{F04AE}", play: "\u{F040A}", pause: "\u{F03E4}", next: "\u{F04AD}",
        lyrics: "\u{F0B77}", coffee: "\u{F0176}", coffeeOff: "\u{F0178}", shuffle: "\u{F049D}", repeat: "\u{F0456}", repeatOne: "\u{F0458}", repeatOff: "\u{F0457}",
        cpu: "\u{F0EE0}", memory: "\u{F035B}", disk: "\u{F02CA}", gpu: "\u{F08AE}",
        music: "\u{F0387}", confirm: "\u{F012C}",
        sunny: "\u{F0599}", night: "\u{F0594}", partly: "\u{F0595}", cloudy: "\u{F0590}",
        thermometer: "\u{F050F}", humidity: "\u{F058E}", wind: "\u{F059D}",
        sunrise: "\u{F059C}", sunset: "\u{F059B}",
        fog: "\u{F0591}", rainy: "\u{F0597}", pouring: "\u{F0596}", snowy: "\u{F0598}",
        lightning: "\u{F0593}",
        lock: "\u{F033E}", record: "\u{F044A}", coffee: "\u{F0176}", coffeeOff: "\u{F0FAA}",
        blur: "\u{F00A3}", blurOff: "\u{F00A4}",
        broom: "\u{F00E2}",
        volHigh: "\u{F057E}", volMid: "\u{F0580}", volLow: "\u{F057F}", volOff: "\u{F0581}",
        mic: "\u{F036C}", micOff: "\u{F036D}", brightness: "\u{F00DF}",
        wifi1: "\u{F091F}", wifi2: "\u{F0922}", wifi3: "\u{F0925}", wifi4: "\u{F0928}", wifiOff: "\u{F05AA}", wifiLock: "\u{F16BF}",
        bt: "\u{F00AF}", btOff: "\u{F00B2}", btConnected: "\u{F00B1}",
        bat: "\u{F0079}", batCharging: "\u{F0084}", batAlert: "\u{F0083}",
        bat10: "\u{F007A}", bat20: "\u{F007B}", bat30: "\u{F007C}", bat40: "\u{F007D}", bat50: "\u{F007E}",
        bat60: "\u{F007F}", bat70: "\u{F0080}", bat80: "\u{F0081}", bat90: "\u{F0082}",
        perf: "\u{F14DE}", balanced: "\u{F05D1}", saver: "\u{F032A}",
        headphones: "\u{F02CB}", speaker: "\u{F04C3}", chevronRight: "\u{F0142}", refresh: "\u{F0450}",
        magnify: "\u{F0349}", health: "\u{F05F6}",
        bell: "\u{F009C}", bellOff: "\u{F0A91}", history: "\u{F02DA}", backupRestore: "\u{F006F}",
        trash: "\u{F09E7}", plus: "\u{F0415}", info: "\u{F02FD}", laptop: "\u{F0322}", chip: "\u{F061A}",
        packages: "\u{F03D6}", console: "\u{F018D}", translate: "\u{F05CA}", cursor: "\u{F01C0}", font: "\u{F06D6}",
        network: "\u{F0C9D}", batHealth: "\u{F120F}", restore: "\u{F099B}", alert: "\u{F002A}",
        fileCompare: "\u{F08AA}", close: "\u{F0156}", verified: "\u{F0791}", camera: "\u{F0D5D}",
        gamepad: "\u{F0297}", pin: "\u{F0403}", pencil: "\u{F0CB6}",
        star: "\u{F04CE}", starOutline: "\u{F04D2}", content: "\u{F018F}",
        sleep: "\u{F0904}",
        tune: "\u{F062E}", palette: "\u{F03D8}", settings: "\u{F08B8}",
        check: "\u{F012C}",
        calendar: "\u{F00ED}", timer: "\u{F051B}", quote: "\u{F0281}", speed: "\u{F04C5}",
        equalizer: "\u{F0EA2}", album: "\u{F0025}", bezier: "\u{F0AE8}"
    })

    property FileView colorFile: FileView {
        path: Quickshell.env("HOME") + "/.cache/wallust/colors-quickshell.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (!data) return;
                if (data.background) root.background = data.background;
                if (data.foreground) root.foregroundRaw = data.foreground;
                if (data.color0) root.color0 = data.color0;
                if (data.color1) root.color1 = data.color1;
                if (data.color2) root.color2 = data.color2;
                if (data.color3) root.color3 = data.color3;
                if (data.color4) root.color4 = data.color4;
                if (data.color5) root.color5 = data.color5;
                if (data.color6) root.color6 = data.color6;
                if (data.color7) root.color7 = data.color7;
                if (data.color8) root.color8 = data.color8;
                if (data.color9) root.color9 = data.color9;
                if (data.color10) root.color10 = data.color10;
                if (data.color11) root.color11 = data.color11;
                if (data.color12) root.color12 = data.color12;
                if (data.color13) root.color13 = data.color13;
                if (data.color14) root.color14 = data.color14;
                if (data.color15) root.color15 = data.color15;
            } catch (e) {
                console.log("Theme: erro ao processar colors-quickshell.json:", e);
            }
        }
        onLoadFailed: (error) => {
            console.log("Theme: colors-quickshell.json ausente (usando paleta padrão dark):", error);
        }
    }

    property FileView waywallenWatcher: FileView {
        path: Quickshell.env("HOME") + "/.var/app/org.waywallen.waywallen/config/waywallen/config.toml"
        watchChanges: true
        onFileChanged: {
            Quickshell.execDetached(["rice-wallust-refresh"]);
        }
    }

    // ---------- Internacionalização (i18n) ----------
    property string locale: "pt-BR"
    // Locale do Qt para datas: Qt.formatDate usa o locale do processo (C/en),
    // e as datas saíam misturando os idiomas ("Monday, 21 de September").
    readonly property var qtLocale: Qt.locale(locale === "en" ? "en_US" : "pt_BR")
    function formatDate(d, fmt) { return qtLocale.toString(d, fmt); }
    property var translationsPt: ({})
    property var translationsEn: ({})

    function t(key, fallback) {
        const currentLoc = root.locale;
        const dict = (currentLoc === "en") ? root.translationsEn : root.translationsPt;
        if (dict && dict[key] !== undefined) return dict[key];
        if (currentLoc === "en" && root.translationsPt && root.translationsPt[key] !== undefined) return root.translationsPt[key];
        return fallback !== undefined ? fallback : key;
    }

    function setLocale(newLocale) {
        if (newLocale === "en" || newLocale === "pt-BR") {
            root.locale = newLocale;
            localeConfigFile.setText(JSON.stringify({ "locale": newLocale }, null, 2) + "\n");
        }
    }

    property FileView localeConfigFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/locale.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = text().trim();
                if (!t) return;
                const d = JSON.parse(t);
                if (d.locale === "en" || d.locale === "pt-BR") {
                    root.locale = d.locale;
                }
            } catch (e) {
                console.log("Theme: erro ao carregar locale.json:", e);
            }
        }
        onLoadFailed: (error) => {
            console.log("Theme: falha ao carregar locale.json:", error);
        }
    }

    property FileView i18nPtFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/i18n/pt-BR.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.translationsPt = JSON.parse(text());
            } catch (e) {
                console.log("Theme: erro ao carregar pt-BR.json:", e);
            }
        }
    }

    property FileView i18nEnFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/i18n/en.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.translationsEn = JSON.parse(text());
            } catch (e) {
                console.log("Theme: erro ao carregar en.json:", e);
            }
        }
    }
}
