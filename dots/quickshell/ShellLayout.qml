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

    // Itens da barra principal: catálogo que o usuário monta no modo edição.
    // Cada barra tem a sua lista (a de cima e a lateral são independentes), e a
    // ordem da lista é a ordem na tela. Guardado em bar.items.{top,side}.
    //   media    música tocando (na lateral fica no meio da barra)
    //   tray     apps em segundo plano
    //   control  bloco brilho/som/bateria → central de controle
    readonly property var barCatalog: ["media", "weather", "tray", "updates", "notifications", "network", "control",
        "night", "caffeine", "record", "screenshot", "clipboard", "picker", "gpu", "lock", "settings", "power"]
    // Ponto de privacidade (microfone/câmera/tela em uso): fora do catálogo
    // porque só aparece enquanto algo está em uso; desliga no painel.
    readonly property bool barPrivacy: get("bar", "privacy", true)
    readonly property var barItemsDefault: ({
        // "media" em cima substitui o ícone fixo do equalizador que existia
        // ao lado do relógio (o equalizador é uma aba do popup da mídia).
        top: ["media", "weather", "notifications", "network", "control"],
        side: ["media", "tray", "notifications", "network", "control", "power"]
    })
    function barItemsFor(kind) {
        const saved = (get("bar", "items", {}) || {})[kind];
        if (Array.isArray(saved)) {
            const out = [];
            for (const k of saved) if (root.barCatalog.includes(k) && !out.includes(k)) out.push(k);
            return out;
        }
        // Antes do catálogo, notificações e rede se escondiam por bar.modules.
        return root.barItemsDefault[kind].filter(k => root.barModule(k));
    }
    readonly property var barItemsTop: barItemsFor("top")
    readonly property var barItemsSide: barItemsFor("side")
    readonly property string barKind: barVertical ? "side" : "top"
    readonly property var barItems: barVertical ? barItemsSide : barItemsTop
    function barHas(key) { return root.barItems.includes(key); }
    function setBarItems(list) {
        const m = Object.assign({}, get("bar", "items", {}) || {});
        m[root.barKind] = list.slice();
        root.set("bar", "items", m);
    }
    function toggleBarItem(key) {
        const list = root.barItems.slice();
        const i = list.indexOf(key);
        if (i >= 0) list.splice(i, 1);
        else list.push(key);
        root.setBarItems(list);
    }

    // Lado direito da dock de ponta a ponta (como a área de notificação da
    // barra de tarefas do Windows): o que a sidebar mostraria. Lista ordenada
    // em dock.items; só aparece com dockFullWidth.
    readonly property var dockCatalog: ["tray", "updates", "record", "night", "caffeine", "gpu", "lock", "power"]
    readonly property var dockItemsDefault: ["tray", "updates", "night", "caffeine", "power"]
    readonly property var dockItems: {
        const saved = get("dock", "items", null);
        if (!Array.isArray(saved)) return root.dockItemsDefault;
        const out = [];
        for (const k of saved) if (root.dockCatalog.includes(k) && !out.includes(k)) out.push(k);
        return out;
    }
    function dockHas(key) { return root.dockFullWidth && root.dockItems.includes(key); }
    function toggleDockItem(key) {
        const list = root.dockItems.slice();
        const i = list.indexOf(key);
        if (i >= 0) list.splice(i, 1);
        else list.push(key);
        root.set("dock", "items", list);
    }

    // Sidebar da direita (central de ações): liga/desliga por item, tudo ligado
    // por padrão. Independente da barra (um item pode estar nas duas).
    readonly property var sidebarCatalog: ["avatar", "update", "record", "night", "caffeine", "gpu",
        "tray", "lock", "suspend", "logout", "reboot", "power"]
    readonly property var sidebarItems: get("sidebar", "items", ({}))
    function sidebarHas(key) {
        const m = root.sidebarItems;
        return !m || m[key] === undefined ? true : m[key] === true;
    }
    function toggleSidebarItem(key) {
        const next = Object.assign({}, root.sidebarItems || {});
        next[key] = !root.sidebarHas(key);
        root.set("sidebar", "items", next);
    }

    // Modo edição (estilo KDE): não é gravado. Enquanto ligado, os módulos
    // escondidos aparecem apagados na barra e um clique liga/desliga cada um.
    property bool editing: false
    // Abre a sidebar enquanto o modo edição mostra a lista dela (não gravado).
    property bool sidebarPeek: false
    onEditingChanged: if (!editing) sidebarPeek = false
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
        // Estilo Windows: barra de tarefas (dock de ponta a ponta sempre à
        // mostra) com a "área de notificação" à direita — o que a sidebar
        // mostraria vai para lá, então a sidebar fica desligada. A barra de
        // cima continua (o Windows não tem, mas o usuário quis manter).
        taskbar: {
            bar: { enabled: true, position: "top", autohide: false, workspaceCount: 9, showTitle: true },
            dock: { enabled: true, position: "bottom", autohide: false, fullWidth: true },
            sidebar: { enabled: false, position: "right", autohide: true }
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
        // O arranjo só troca os campos que ele define: itens escolhidos no modo
        // edição (bar.items, sidebar.items) e módulos escondidos continuam.
        const next = Object.assign({}, root.config, { preset: name });
        for (const k in p) next[k] = Object.assign({}, root.config[k] || {}, p[k]);
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
