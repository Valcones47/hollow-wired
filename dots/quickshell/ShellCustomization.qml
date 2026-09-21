pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

QtObject {
    id: root

    property var config: ({
        hub: { style: "glass", scale: 1.0, opacity: 0.85, accent: "" },
        sidebar: { style: "glass", scale: 1.0, opacity: 0.85, accent: "" },
        dock: { style: "glass", scale: 1.0, opacity: 0.85, accent: "" }
    })

    signal updated()

    // Fica false até shell-customization.json terminar de carregar (leitura é
    // assíncrona). Sem isso, mexer num slider/estilo logo após o Quickshell
    // (re)iniciar pode disparar save() com os valores padrão acima ainda em
    // memória, sobrescrevendo as customizações reais salvas no arquivo.
    property bool ready: false

    function getStyle(comp) {
        return (config[comp] && config[comp].style) ? config[comp].style : "glass";
    }

    function getScale(comp) {
        return (config[comp] && config[comp].scale !== undefined) ? config[comp].scale : 1.0;
    }

    function getOpacity(comp) {
        return (config[comp] && config[comp].opacity !== undefined) ? config[comp].opacity : 0.85;
    }

    function getAccent(comp) {
        const acc = (config[comp] && config[comp].accent) ? config[comp].accent : "";
        return acc !== "" ? acc : Theme.primary;
    }

    function getBgColor(comp) {
        const st = getStyle(comp);
        const op = getOpacity(comp);
        if (st === "borderless") return "transparent";
        if (st === "solid") return Theme.surface;
        if (st === "glow") return Theme.withAlpha(Theme.surface, Math.max(0.75, op));
        return Theme.withAlpha(Theme.surface, op);
    }

    function getBorderColor(comp) {
        const st = getStyle(comp);
        const acc = getAccent(comp);
        if (st === "borderless") return "transparent";
        if (st === "glow") return acc;
        if (st === "solid") return Theme.withAlpha(Theme.outline, 0.25);
        return Theme.withAlpha(acc, 0.35);
    }

    function getBorderWidth(comp) {
        const st = getStyle(comp);
        if (st === "borderless") return 0;
        if (st === "glow") return 2;
        return 1;
    }

    property FileView file: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/shell-customization.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = text().trim();
                if (!t) return;
                const d = JSON.parse(t);
                if (d && typeof d === "object") {
                    root.config = Object.assign({}, root.config, d);
                    root.updated();
                }
            } catch (e) {
                console.log("ShellCustomization: erro ao carregar:", e);
            } finally {
                root.ready = true;
            }
        }
        onLoadFailed: (error) => {
            console.log("ShellCustomization: erro ao carregar arquivo:", error);
            root.ready = true;
        }
    }

    function save() {
        if (!root.ready) return;
        file.setText(JSON.stringify(config, null, 2) + "\n");
        updated();
    }

    function setComponentProp(comp, prop, val) {
        const newCfg = Object.assign({}, config);
        if (!newCfg[comp]) newCfg[comp] = { style: "glass", scale: 1.0, opacity: 0.85, accent: "" };
        newCfg[comp] = Object.assign({}, newCfg[comp]);
        newCfg[comp][prop] = val;
        config = newCfg;
        save();
    }

    // Layout da aba Mídia do hub: "disc" (disco + equalizador) ou "ring"
    // (espectro + letra). Mora aqui para ir junto com o resto do visual.
    function getMediaLayout() {
        const l = config.media && config.media.layout;
        return l === "ring" ? "ring" : "disc";
    }

    function setMediaLayout(layout) {
        setComponentProp("media", "layout", layout === "ring" ? "ring" : "disc");
    }

    function applyToAll(sourceComp) {
        const src = config[sourceComp] || { style: "glass", scale: 1.0, opacity: 0.85, accent: "" };
        config = {
            hub: Object.assign({}, src),
            sidebar: Object.assign({}, src),
            dock: Object.assign({}, src),
            media: Object.assign({}, config.media || {})
        };
        save();
    }

    function reset(comp) {
        const defaults = { style: "glass", scale: 1.0, opacity: 0.85, accent: "" };
        if (comp) {
            setComponentProp(comp, "style", defaults.style);
            setComponentProp(comp, "scale", defaults.scale);
            setComponentProp(comp, "opacity", defaults.opacity);
            setComponentProp(comp, "accent", defaults.accent);
        } else {
            config = {
                hub: Object.assign({}, defaults),
                sidebar: Object.assign({}, defaults),
                dock: Object.assign({}, defaults),
                media: Object.assign({}, config.media || {})
            };
            save();
        }
    }
}
