pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Conta-gotas (hyprpicker) com histórico das últimas 8 cores. O histórico é
// estado do usuário: ~/.config/hollow-wired/color-history.json.
Singleton {
    id: root

    property var history: []
    readonly property bool picking: pickProc.running
    // Última cor copiada, para o popup mostrar "copiado" por um instante.
    property string copied: ""

    FileView {
        id: histFile
        path: Quickshell.env("HOME") + "/.config/hollow-wired/color-history.json"
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.history = Array.isArray(d) ? d.filter(h => root.isHex(h)).slice(0, 8) : [];
            } catch (e) { root.history = []; }
        }
    }

    Process {
        id: pickProc
        // -b: sem cores ANSI na saída; Esc no hyprpicker não imprime nada.
        command: ["hyprpicker", "-f", "hex", "-b", "-q"]
        stdout: StdioCollector {
            onStreamFinished: {
                const h = text.trim().split("\n").pop().trim();
                if (root.isHex(h)) root.add(h);
            }
        }
    }

    function isHex(h) { return typeof h === "string" && /^#[0-9a-fA-F]{6}$/.test(h); }

    function pick() {
        if (!pickProc.running) pickProc.running = true;
    }

    function add(h) {
        h = h.toUpperCase();
        copy(h);
        history = [h].concat(history.filter(x => x !== h)).slice(0, 8);
        histFile.setText(JSON.stringify(history) + "\n");
    }

    function copy(t) {
        Quickshell.execDetached(["wl-copy", "--", t]);
        copied = t;
        copiedTimer.restart();
    }
    Timer { id: copiedTimer; interval: 1200; onTriggered: root.copied = "" }

    function channels(h) {
        return [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)];
    }
    function rgb(h) {
        const c = channels(h);
        return "rgb(" + c[0] + ", " + c[1] + ", " + c[2] + ")";
    }
    function hsl(h) {
        const c = channels(h).map(v => v / 255);
        const max = Math.max(...c), min = Math.min(...c);
        const l = (max + min) / 2;
        let hue = 0, s = 0;
        if (max !== min) {
            const d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            if (max === c[0]) hue = (c[1] - c[2]) / d + (c[1] < c[2] ? 6 : 0);
            else if (max === c[1]) hue = (c[2] - c[0]) / d + 2;
            else hue = (c[0] - c[1]) / d + 4;
            hue *= 60;
        }
        return "hsl(" + Math.round(hue) + ", " + Math.round(s * 100) + "%, " + Math.round(l * 100) + "%)";
    }
}
