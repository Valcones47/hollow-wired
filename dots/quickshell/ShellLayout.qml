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
    // "taskbar" — dock em largura total sempre à mostra e central de ações
    //             fixa na direita, para quem vem do Windows
    // "clean"   — nada à mostra: tudo aparece ao encostar o mouse na borda
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

    // Quais indicadores a barra mostra. Tudo ligado por padrão: a pessoa
    // desliga o que não usa em vez de precisar montar a barra do zero.
    readonly property var barModules: get("bar", "modules", ({}))
    function barModule(name) {
        const m = root.barModules;
        return !m || m[name] === undefined ? true : m[name] === true;
    }
    function setBarModule(name, on) {
        const next = Object.assign({}, root.barModules);
        next[name] = on === true;
        root.set("bar", "modules", next);
    }

    // Ordem dos indicadores do lado direito da barra (arrastados no modo edição).
    // Chaves que faltarem entram no fim, na ordem padrão.
    readonly property var barOrderDefault: ["notifications", "settings", "network", "bluetooth", "audio", "brightness", "battery"]
    readonly property var barOrder: {
        const saved = get("bar", "order", []);
        const out = [];
        for (const k of (Array.isArray(saved) ? saved : []))
            if (root.barOrderDefault.includes(k) && !out.includes(k)) out.push(k);
        for (const k of root.barOrderDefault) if (!out.includes(k)) out.push(k);
        return out;
    }
    function setBarOrder(keys) {
        root.set("bar", "order", keys.slice());
    }

    // Modo edição (estilo KDE): não é gravado. Enquanto ligado, os módulos
    // escondidos aparecem apagados na barra e um clique liga/desliga cada um.
    property bool editing: false
    function showModule(name) {
        return root.barModule(name) || root.editing;
    }

    // qs ipc call layout edit | editOn | editOff
    property IpcHandler ipc: IpcHandler {
        target: "layout"
        function edit(): void { root.editing = !root.editing; }
        function editOn(): void { root.editing = true; }
        function editOff(): void { root.editing = false; }
    }

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
        taskbar: {
            bar: { enabled: true, position: "top", autohide: false, workspaceCount: 9, showTitle: true },
            dock: { enabled: true, position: "bottom", autohide: false, fullWidth: true },
            sidebar: { enabled: true, position: "right", autohide: false }
        },
        sidebar: {
            bar: { enabled: true, position: "left", autohide: false, workspaceCount: 9, showTitle: false },
            dock: { enabled: true, position: "bottom", autohide: true, fullWidth: false },
            sidebar: { enabled: true, position: "right", autohide: true }
        },
        clean: {
            bar: { enabled: true, position: "top", autohide: true, workspaceCount: 0, showTitle: true },
            dock: { enabled: true, position: "bottom", autohide: true, fullWidth: false },
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
