pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool dnd: false
    property int unreadCount: 0
    property int maxId: 0
    property int clearedUpTo: 0

    property Timer pollTimer: Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Fica false até notif-cleared terminar de carregar (leitura assíncrona).
    // clearedUpTo começa em 0 por padrão; sem essa guarda, a checagem de
    // rollover do syncProc (maxId < clearedUpTo) pode disparar setCleared(0)
    // antes do valor real ser lido, marcando notificações já lidas como não-lidas.
    property bool ready: false

    property FileView clearedFile: FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/notif-cleared"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.clearedUpTo = parseInt(text()) || 0;
            root.ready = true;
            root.refresh();
        }
        onLoadFailed: {
            root.clearedUpTo = 0;
            root.ready = true;
        }
    }

    property Process syncProc: Process {
        command: ["rice-notif-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.dnd = !!data.dnd;
                    root.unreadCount = data.count || 0;
                    root.maxId = data.maxId || 0;
                    if (root.ready && root.maxId < root.clearedUpTo) {
                        root.setCleared(0);
                    }
                } catch (e) {
                    console.log("NotifService: erro no parse:", e);
                }
            }
        }
    }

    property Process toggleDndProc: Process {
        command: ["rice-dnd"]
        onExited: root.refresh()
    }

    function refresh() {
        if (!syncProc.running) {
            syncProc.running = true;
        }
    }

    function toggleDnd() {
        toggleDndProc.running = true;
    }

    function setCleared(id) {
        clearedUpTo = id;
        clearedFile.setText(String(id));
        unreadCount = 0;
        refresh();
    }
}
