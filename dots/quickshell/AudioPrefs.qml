pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Volume máximo da saída: 1.0 (100%) ou 1.5 (150%, com distorção possível).
// Fica em ~/.config/hollow-wired/audio.json; o painel (aba Áudio) grava.
Singleton {
    id: root
    property real maxVolume: 1.0
    readonly property string path: Quickshell.env("HOME") + "/.config/hollow-wired/audio.json"

    function setMax(pct) {
        root.maxVolume = pct > 100 ? 1.5 : 1.0;
        file.setText(JSON.stringify({ max_volume: Math.round(root.maxVolume * 100) }) + "\n");
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text()) || {};
                root.maxVolume = (d.max_volume || 100) > 100 ? 1.5 : 1.0;
            } catch (e) {}
        }
    }
}
