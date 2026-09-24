pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Eventos dos calendários .ics (arquivo ou URL) via rice-calendar. As fontes
// ficam em ~/.config/hollow-wired/calendar.json; URLs são baixadas de novo a
// cada 30 min (o script usa o cache se estiver sem internet).
Singleton {
    id: root

    property var events: []
    property var byDay: ({})
    property var sources: []
    property bool pending: false

    function key(y, m, d) {
        return y + "-" + String(m + 1).padStart(2, "0") + "-" + String(d).padStart(2, "0");
    }
    function eventsOn(k) { return root.byDay[k] || []; }

    Process {
        id: evProc
        command: ["rice-calendar", "events"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text) || [];
                    const m = {};
                    for (const e of list) (m[e.date] = m[e.date] || []).push(e);
                    root.events = list;
                    root.byDay = m;
                } catch (e) {}
            }
        }
        onExited: if (root.pending) { root.pending = false; running = true; }
    }
    function refresh() {
        if (evProc.running) { pending = true; return; }
        evProc.running = true;
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/hollow-wired/calendar.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.sources = (JSON.parse(text()) || {}).sources || []; } catch (e) { root.sources = []; }
            root.refresh();
        }
        onLoadFailed: { root.sources = []; root.events = []; root.byDay = {}; }
    }

    Timer { interval: 30 * 60 * 1000; running: root.sources.length > 0; repeat: true; onTriggered: root.refresh() }

    // add/remove gravam o calendar.json; o FileView acima recarrega sozinho.
    function add(src) {
        const s = (src || "").trim();
        if (s !== "") Quickshell.execDetached(["rice-calendar", "add", s]);
    }
    function remove(src) { Quickshell.execDetached(["rice-calendar", "remove", src]); }
}
