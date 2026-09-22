pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Organização da interface: onde cada peça do shell fica e como ela aparece.
//
// O ShellCustomization cuida da *aparência* (estilo, escala, opacidade, cor);
// este singleton cuida do *arranjo*: se existe barra, onde ela fica, se a dock
// ocupa a largura toda, o que aparece só no hover, quantos botões de área de
// trabalho a barra mostra.
//
// Guardado em ~/.config/quickshell/shell-layout.json — estado do usuário, não
// vai para o repositório.
QtObject {
    id: root

    signal updated()

    // Mesma guarda dos outros singletons com FileView: a leitura é assíncrona,
    // e sem isso mexer numa opção logo após o Quickshell reiniciar gravaria os
    // padrões por cima da escolha real.
    property bool ready: false

    // "topbar"  — barra em cima, dock embaixo (o arranjo clássico do rice)
    // "sidebar" — barra vertical na lateral, sem barra em cima
    // "taskbar" — barra embaixo ocupando a largura toda, estilo Windows
    // "custom"  — o usuário mexeu em algo à mão
    property string preset: "topbar"

    property var config: ({
        preset: "topbar",
        bar: {
            enabled: true,
            position: "top",      // top | bottom | left | right
            autohide: false,
            workspaceCount: 0,    // 0 = só as áreas que existem; 1..10 = fixas
            showTitle: true
        },
        dock: {
            enabled: true,
            position: "bottom",   // bottom | top | left | right
            autohide: true,
            fullWidth: false
        },
        sidebar: {
            enabled: true,
            position: "right",    // right | left
            autohide: true
        }
    })

    function group(name) {
        return (config && config[name]) ? config[name] : {};
    }

    function get(groupName, prop, fallback) {
        const g = group(groupName);
        return g[prop] === undefined ? fallback : g[prop];
    }

    // --- atalhos de leitura usados pelos componentes ---
    readonly property string barPosition: get("bar", "position", "top")
    readonly property bool barEnabled: get("bar", "enabled", true)
    readonly property bool barAutohide: get("bar", "autohide", false)
    readonly property bool barVertical: barPosition === "left" || barPosition === "right"
    readonly property int workspaceCount: get("bar", "workspaceCount", 0)
    readonly property bool barShowTitle: get("bar", "showTitle", true)

    readonly property bool dockEnabled: get("dock", "enabled", true)
    readonly property string dockPosition: get("dock", "position", "bottom")
    readonly property bool dockAutohide: get("dock", "autohide", true)
    readonly property bool dockFullWidth: get("dock", "fullWidth", false)

    readonly property bool sidebarEnabled: get("sidebar", "enabled", true)
    readonly property string sidebarPosition: get("sidebar", "position", "right")
    readonly property bool sidebarAutohide: get("sidebar", "autohide", true)

    function set(groupName, prop, value) {
        const next = Object.assign({}, root.config);
        next[groupName] = Object.assign({}, next[groupName] || {});
        next[groupName][prop] = value;
        // Mexer numa opção solta tira do preset: o que vale a partir daí é a
        // combinação que a pessoa montou.
        next.preset = "custom";
        root.config = next;
        root.preset = "custom";
        root.save();
    }

    // Arranjos prontos. Cada um é um ponto de partida completo — quem quiser
    // ajustar depois cai no "custom" sozinho.
    readonly property var presets: ({
        topbar: {
            bar: { enabled: true, position: "top", autohide: false, workspaceCount: 0, showTitle: true },
            dock: { enabled: true, position: "bottom", autohide: true, fullWidth: false },
            sidebar: { enabled: true, position: "right", autohide: true }
        },
        sidebar: {
            bar: { enabled: true, position: "left", autohide: false, workspaceCount: 9, showTitle: false },
            dock: { enabled: false, position: "bottom", autohide: true, fullWidth: false },
            sidebar: { enabled: true, position: "right", autohide: true }
        },
        taskbar: {
            bar: { enabled: true, position: "top", autohide: false, workspaceCount: 9, showTitle: true },
            dock: { enabled: true, position: "bottom", autohide: false, fullWidth: true },
            sidebar: { enabled: true, position: "right", autohide: true }
        }
    })

    function applyPreset(name) {
        const p = root.presets[name];
        if (!p) return;
        const next = { preset: name };
        for (const k in p) next[k] = Object.assign({}, p[k]);
        root.config = next;
        root.preset = name;
        root.save();
    }

    property FileView file: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/shell-layout.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = text().trim();
                if (!t) return;
                const d = JSON.parse(t);
                if (d && typeof d === "object") {
                    const merged = Object.assign({}, root.config);
                    for (const k in d) {
                        if (k === "preset") continue;
                        merged[k] = Object.assign({}, merged[k] || {}, d[k]);
                    }
                    if (typeof d.preset === "string") {
                        merged.preset = d.preset;
                        root.preset = d.preset;
                    }
                    root.config = merged;
                    root.updated();
                }
            } catch (e) {
                console.log("ShellLayout: shell-layout.json inválido:", e);
            } finally {
                root.ready = true;
            }
        }
        onLoadFailed: root.ready = true
    }

    function save() {
        if (!root.ready) return;
        file.setText(JSON.stringify(root.config, null, 2) + "\n");
        root.updated();
    }
}
