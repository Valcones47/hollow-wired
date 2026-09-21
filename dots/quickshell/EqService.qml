pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Estado do equalizador (rice-eq). Singleton porque o equalizador aparece em
// mais de um lugar — no layout "disco" da aba Mídia e no painel lateral do
// layout "letras" — e os dois têm de mostrar os mesmos valores.
QtObject {
    id: root

    readonly property var bands: [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    readonly property var presets: ["flat", "bass", "treble", "vocal", "pop", "rock", "jazz", "classic"]
    readonly property real limit: 12

    property bool enabled: false
    property string preset: "flat"
    property var gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    // Enquanto um slider é arrastado a resposta do script chega atrasada e
    // faria o knob pular para trás; ela é ignorada até soltar.
    property bool dragging: false

    function presetLabel(id) {
        const names = {
            flat: Theme.t("eq.flat", "Plano"),
            bass: Theme.t("eq.bass", "Graves"),
            treble: Theme.t("eq.treble", "Agudos"),
            vocal: Theme.t("eq.vocal", "Voz"),
            pop: "Pop",
            rock: "Rock",
            jazz: "Jazz",
            classic: Theme.t("eq.classic", "Clássico"),
            custom: Theme.t("eq.custom", "Personalizado")
        };
        return names[id] || id;
    }

    function bandLabel(i) {
        const f = bands[i];
        return f >= 1000 ? (f / 1000) + "k" : String(f);
    }

    function parse(text) {
        try {
            const d = JSON.parse(text);
            if (root.dragging)
                return;
            root.enabled = !!d.enabled;
            root.preset = d.preset || "flat";
            if (d.gains && d.gains.length === root.bands.length)
                root.gains = d.gains;
        } catch (e) {}
    }

    function run(args) {
        cmd.command = ["rice-eq"].concat(args);
        cmd.running = false;
        cmd.running = true;
    }

    function refresh() { run(["status"]); }
    function setEnabled(on) { root.enabled = on; run([on ? "on" : "off"]); }
    function applyPreset(id) {
        root.preset = id;
        root.enabled = true;
        run(["preset", id]);
    }

    // Durante o arrasto só o valor em memória muda (a onda e o knob seguem o
    // mouse); o envio ao PipeWire é agrupado pelo timer para não abrir um
    // processo a cada pixel.
    function setBand(i, db) {
        const g = root.gains.slice();
        g[i] = Math.round(Math.max(-root.limit, Math.min(root.limit, db)) * 2) / 2;
        root.gains = g;
        root.preset = "custom";
        root.enabled = true;
        pushTimer.restart();
    }

    function flush() {
        pushTimer.stop();
        run(["gains"].concat(root.gains.map(v => String(v))));
    }

    property Timer pushTimer: Timer {
        interval: 140
        onTriggered: root.flush()
    }

    property Process cmd: Process {
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Component.onCompleted: refresh()
}
