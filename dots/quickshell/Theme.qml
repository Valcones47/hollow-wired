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

    property color background: "#191B1C"
    property color foreground: "#42FFFF"
    property color color0: "#04131F"
    property color color1: "#A4296F"
    property color color2: "#A8295F"
    property color color3: "#A22246"
    property color color4: "#179394"
    property color color5: "#A52557"
    property color color6: "#079595"
    property color color7: "#39FFFF"
    property color color8: "#00B5B6"
    property color color9: "#FE36A7"
    property color color10: "#FE3087"
    property color color11: "#F01F59"
    property color color12: "#16E6E7"
    property color color13: "#F62877"
    property color color14: "#05FEFE"
    property color color15: "#94F7F7"

    // Aliases semânticos, no mesmo espírito das variáveis @wallust_* do
    // waybar/eww (mesmo mapeamento: accent1=color4, accent2=color6,
    // inactive=color8, warning=color3, critical=color11).
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
    readonly property color primary: color10
    readonly property color textColor: foreground
    readonly property color subtext: color7
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
        cpu: "\u{F0EE0}", memory: "\u{F035B}", disk: "\u{F02CA}", gpu: "\u{F08AE}",
        music: "\u{F0387}", confirm: "\u{F012C}",
        sunny: "\u{F0599}", night: "\u{F0594}", partly: "\u{F0595}", cloudy: "\u{F0590}",
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
        tune: "\u{F062E}", palette: "\u{F03D8}", settings: "\u{F08B8}",
        calendar: "\u{F00ED}", timer: "\u{F051B}", quote: "\u{F0281}", speed: "\u{F04C5}"
    })

    property FileView colorFile: FileView {
        path: Quickshell.env("HOME") + "/.cache/wallust/colors-quickshell.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const data = JSON.parse(text());
            root.background = data.background;
            root.foreground = data.foreground;
            root.color0 = data.color0;
            root.color1 = data.color1;
            root.color2 = data.color2;
            root.color3 = data.color3;
            root.color4 = data.color4;
            root.color5 = data.color5;
            root.color6 = data.color6;
            root.color7 = data.color7;
            root.color8 = data.color8;
            root.color9 = data.color9;
            root.color10 = data.color10;
            root.color11 = data.color11;
            root.color12 = data.color12;
            root.color13 = data.color13;
            root.color14 = data.color14;
            root.color15 = data.color15;
        }
        onLoadFailed: (error) => {
            console.log("Theme: falha ao carregar colors-quickshell.json:", error);
        }
    }

    // ---------- Internacionalização (i18n) ----------
    property string locale: "pt-BR"
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
