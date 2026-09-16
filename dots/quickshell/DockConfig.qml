pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Estado compartilhado entre Dock e Launcher: apps fixados, jogos e
// contagem de uso (pra ordenar o launcher). Persistido em
// ~/.config/quickshell/dock.json — dá pra editar à mão.
QtObject {
    id: root

    property var pins: ["zen", "kitty", "org.kde.dolphin", "com.anthropic.Claude", "discord", "spotify"]
    property var games: ["steam", "heroic", "osu-lazer", "r2modman", "com.hypixel.HytaleLauncher"]
    property var usage: ({})

    property FileView file: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/dock.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = text().trim();
                if (!t) return;
                const d = JSON.parse(t);
                if (Array.isArray(d.pins)) root.pins = d.pins;
                if (Array.isArray(d.games)) root.games = d.games;
                if (d.usage && typeof d.usage === "object") {
                    delete d.usage["undefined"];
                    root.usage = d.usage;
                }
            } catch (e) {
                console.log("DockConfig: dock.json inválido:", e);
            }
        }
        onLoadFailed: error => {
            console.log("DockConfig: erro ao carregar dock.json:", error);
        }
    }

    function save() {
        const u = Object.assign({}, usage);
        delete u["undefined"];
        file.setText(JSON.stringify({ pins: pins, games: games, usage: u }, null, 2) + "\n");
    }

    function isPinned(id) { return pins.includes(id); }
    function isGame(id) { return games.includes(id); }

    function togglePin(id) {
        pins = isPinned(id) ? pins.filter(p => p !== id) : pins.concat([id]);
        save();
    }
    function toggleGame(id) {
        games = isGame(id) ? games.filter(g => g !== id) : games.concat([id]);
        save();
    }
    function move(list, from, to) {
        const a = list.slice();
        const [x] = a.splice(from, 1);
        a.splice(Math.max(0, Math.min(a.length, to)), 0, x);
        return a;
    }
    function movePin(from, to) {
        if (from === to) return;
        pins = move(pins, from, to);
        save();
    }
    function moveGame(from, to) {
        if (from === to) return;
        games = move(games, from, to);
        save();
    }

    // Reordena a partir da ordem visível (ids sem .desktop instalado ficam no fim).
    function setPinsOrder(ids) {
        pins = ids.concat(pins.filter(p => !ids.includes(p)));
        save();
    }
    function setGamesOrder(ids) {
        games = ids.concat(games.filter(g => !ids.includes(g)));
        save();
    }

    // Foca uma janela (Toplevel do Wayland) mesmo em outro workspace.
    // Toplevel.activate() só "pede" foco e o Hyprland ignora pra janelas fora
    // do workspace atual (misc.focus_on_activate=false), então usa o dispatch
    // de foco por endereço do Hyprland.
    function focusWindow(t) {
        const h = Hyprland.toplevels.values.find(x => x.wayland === t);
        if (!h) { t.activate(); return; }
        const addr = String(h.address).startsWith("0x") ? h.address : "0x" + h.address;
        Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })");
    }

    function launch(entry) {
        if (!entry) return;
        const id = entry.id || "";
        if (id !== "" && id !== "undefined") {
            const u = Object.assign({}, usage);
            delete u["undefined"];
            u[id] = (u[id] || 0) + 1;
            usage = u;
            save();
        }
        entry.execute();
    }
}
