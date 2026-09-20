pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets

// Estado compartilhado entre Dock e Launcher: apps fixados, jogos e
// contagem de uso (pra ordenar o launcher). Persistido em
// ~/.config/quickshell/dock.json — dá pra editar à mão.
QtObject {
    id: root

    property string launcherIcon: "/usr/share/pixmaps/archlinux-logo.png"
    // Padrão com o que o instalador garante (kitty e dolphin) + os apps comuns;
    // pins de programas não instalados são simplesmente ignorados pela dock.
    // Antes o padrão era só zen/discord/steam, e num PC recém-instalado a dock
    // nascia vazia.
    property var pins: ["kitty", "dolphin", "zen", "discord", "steam"]
    property var games: ["steam", "heroic"]
    property var usage: ({})

    // Fica false até o dock.json terminar de carregar do disco (leitura é assíncrona).
    // Sem isso, um clique num app logo após o Quickshell (re)iniciar dispara save()
    // com os valores padrão acima ainda em memória, sobrescrevendo o dock.json real
    // (ícone customizado, pins e jogos) antes mesmo dele ser lido.
    property bool ready: false

    property FileView file: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/dock.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = text().trim();
                if (!t) {
                    root.ready = true;
                    return;
                }
                const d = JSON.parse(t);
                if (typeof d.launcherIcon === "string" && d.launcherIcon.length > 0) {
                    root.launcherIcon = d.launcherIcon;
                } else {
                    root.launcherIcon = "/usr/share/pixmaps/archlinux-logo.png";
                }
                if (Array.isArray(d.pins)) root.pins = d.pins;
                if (Array.isArray(d.games)) root.games = d.games;
                if (d.usage && typeof d.usage === "object") {
                    delete d.usage["undefined"];
                    root.usage = d.usage;
                }
            } catch (e) {
                console.log("DockConfig: dock.json inválido:", e);
            } finally {
                root.ready = true;
            }
        }
        onLoadFailed: error => {
            console.log("DockConfig: erro ao carregar dock.json:", error);
            // Arquivo pode simplesmente não existir ainda (primeira execução) — libera
            // o save() pra criar um novo, em vez de travar "ready" pra sempre.
            root.ready = true;
        }
    }

    function save() {
        if (!root.ready) return;
        const u = Object.assign({}, usage);
        delete u["undefined"];
        file.setText(JSON.stringify({ launcherIcon: launcherIcon, pins: pins, games: games, usage: u }, null, 2) + "\n");
    }

    function setLauncherIcon(iconPath) {
        launcherIcon = iconPath || "/usr/share/pixmaps/archlinux-logo.png";
        save();
    }

    function canonicalId(id) {
        if (!id) return "";
        const clean = id.endsWith(".desktop") ? id.slice(0, -8) : id;
        try {
            if (typeof DesktopEntries !== "undefined") {
                const e = DesktopEntries.byId(clean)
                    || DesktopEntries.byId(id)
                    || DesktopEntries.heuristicLookup(clean)
                    || DesktopEntries.heuristicLookup(id);
                if (e && e.id) return e.id;
            }
        } catch (err) {}
        return clean;
    }

    function isPinned(id) {
        if (!id) return false;
        const target = canonicalId(id);
        return pins.some(p => p === id || canonicalId(p) === target);
    }
    function isGame(id) {
        if (!id) return false;
        const target = canonicalId(id);
        return games.some(g => g === id || canonicalId(g) === target);
    }

    function togglePin(id) {
        if (!id) return;
        const target = canonicalId(id);
        if (isPinned(id)) {
            pins = pins.filter(p => p !== id && canonicalId(p) !== target);
        } else {
            pins = pins.concat([target || id]);
        }
        save();
    }
    function toggleGame(id) {
        if (!id) return;
        const target = canonicalId(id);
        if (isGame(id)) {
            games = games.filter(g => g !== id && canonicalId(g) !== target);
        } else {
            games = games.concat([target || id]);
        }
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

    // Reordena a partir da ordem visível sem duplicatas e com IDs canônicos.
    function setPinsOrder(ids) {
        if (!Array.isArray(ids)) return;
        const result = [];
        const seen = {};
        for (const raw of ids) {
            const c = canonicalId(raw);
            if (c && !seen[c]) {
                seen[c] = true;
                result.push(c);
            }
        }
        for (const p of pins) {
            const c = canonicalId(p);
            if (c && !seen[c]) {
                seen[c] = true;
                result.push(p);
            }
        }
        pins = result;
        save();
    }
    function setGamesOrder(ids) {
        if (!Array.isArray(ids)) return;
        const result = [];
        const seen = {};
        for (const raw of ids) {
            const c = canonicalId(raw);
            if (c && !seen[c]) {
                seen[c] = true;
                result.push(c);
            }
        }
        for (const g of games) {
            const c = canonicalId(g);
            if (c && !seen[c]) {
                seen[c] = true;
                result.push(g);
            }
        }
        games = result;
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
