pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// NotifService: Gerenciador central de notificações do Quickshell.
// Suporta servidor nativo do Quickshell (NotificationServer) com Toasts,
// histórico com timestamps reais, modo Não Perturbe persistido e fallback
// transparente ao mako caso o usuário prefira ou em caso de contingência.
QtObject {
    id: root

    // Configurações lidas de ~/.config/hollow-wired/notifications.json
    property string provider: "quickshell"
    property int defaultTimeout: 5000
    property string position: "top-right"
    property bool soundEnabled: false

    // Estado operacional
    property bool dnd: false
    property int unreadCount: 0
    property int maxId: 0
    property int clearedUpTo: 0
    property bool ready: false
    property string currentOwner: "unknown"

    // Filas de notificações ativas (toasts na tela) e histórico completo
    property var activeToasts: []
    property var history: []

    // Players de música cujo OSD já mostra a faixa (para não duplicar toast)
    readonly property var musicApps: [
        "YouTube Music Desktop App", "YouTube Music", "youtube-music",
        "Spotify", "spotify", "Tidal", "tidal-hifi", "Cider", "Amberol",
        "Elisa", "Rhythmbox", "Lollypop", "Strawberry", "Clementine",
        "Audacious", "mpv", "Plexamp", "Feishin", "Sonixd"
    ]

    // Servidor nativo de notificações D-Bus
    property NotificationServer server: NotificationServer {
        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true

        onNotification: notif => {
            root.handleNotification(notif);
        }
    }

    // Monitora o arquivo de configuração
    property FileView confFile: FileView {
        path: Quickshell.env("HOME") + "/.config/hollow-wired/notifications.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.provider = c.provider || "quickshell";
                root.defaultTimeout = parseInt(c.timeout) || 5000;
                root.position = c.position || "top-right";
                root.soundEnabled = !!c.sound;
            } catch (e) {}
        }
    }

    // Monitora o estado de Não Perturbe (DND)
    property FileView dndFile: FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/notif-dnd"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.dnd = text().trim() === "true";
        }
    }

    // Monitora o maior ID limpo
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

    // Poller de contingência: verifica se o mako está ativo e faz fallback se necessário
    property Timer pollTimer: Timer {
        interval: 3500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    property Process syncProc: Process {
        command: ["rice-notif-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (root.currentOwner === "mako") {
                        root.dnd = !!data.dnd;
                        root.unreadCount = data.count || 0;
                        root.maxId = data.maxId || 0;
                        if (root.ready && root.maxId < root.clearedUpTo) {
                            root.setCleared(0);
                        }
                    }
                } catch (e) {}
            }
        }
    }

    property Process ownerCheckProc: Process {
        command: ["bash", "-c", "busctl --user status org.freedesktop.Notifications 2>/dev/null | grep -q 'Comm=quickshell' && echo quickshell || (busctl --user status org.freedesktop.Notifications 2>/dev/null | grep -q 'Comm=mako' && echo mako || echo none)"]
        stdout: StdioCollector {
            onStreamFinished: {
                const owner = text.trim();
                root.currentOwner = owner;
                if (owner === "none") {
                    // Fallback de emergência se nenhum servidor estiver com o D-Bus
                    fallbackProc.running = true;
                }
            }
        }
    }

    property Process fallbackProc: Process {
        command: ["rice-notif-daemon", "fallback"]
    }

    property Process toggleDndProc: Process {
        command: ["rice-dnd"]
        onExited: root.refresh()
    }

    function refresh() {
        if (!ownerCheckProc.running) ownerCheckProc.running = true;
        if (!syncProc.running) syncProc.running = true;
    }

    function toggleDnd() {
        toggleDndProc.running = true;
    }

    function setCleared(id) {
        clearedUpTo = id;
        clearedFile.setText(String(id));
        unreadCount = 0;
        activeToasts = [];
        if (currentOwner === "mako") {
            Quickshell.execDetached(["makoctl", "dismiss", "-a"]);
        }
        refresh();
    }

    function handleNotification(notif) {
        if (!notif) return;

        const id = notif.id || (Date.now() % 1000000);
        const appName = notif.appName || "Sistema";
        const hints = notif.hints || {};

        // Ignora avisos de faixas de música (já exibidos no OSD de mídia)
        if (musicApps.includes(appName) || hints["category"] === "x-gnome.music") {
            return;
        }

        const appIcon = notif.appIcon || notif.desktopEntry || "";
        const summary = notif.summary || "";
        const body = notif.body || "";
        const urgency = typeof notif.urgency === "number" ? notif.urgency : 1;
        const actions = notif.actions || [];
        const image = notif.image || "";
        const progress = hints["value"] !== undefined ? Number(hints["value"]) : -1;
        const expireTimeout = notif.expireTimeout > 0 ? notif.expireTimeout : root.defaultTimeout;

        const notifData = {
            id: id,
            appName: appName,
            appIcon: appIcon,
            summary: summary,
            body: body,
            urgency: urgency,
            actions: actions,
            image: image,
            progress: progress,
            expireTimeout: expireTimeout,
            time: Date.now(),
            ref: notif
        };

        // Adiciona ao histórico do Quickshell
        history = [notifData].concat(history).slice(0, 100);

        if (id > root.clearedUpTo) {
            unreadCount += 1;
            maxId = Math.max(maxId, id);
        }

        // Se NÃO estiver em modo Não Perturbe, adiciona à fila de Toasts flutuantes
        if (!root.dnd) {
            activeToasts = activeToasts.concat([notifData]);

            // Som suave de notificação se ativado
            if (root.soundEnabled) {
                Quickshell.execDetached(["paplay", "/usr/share/sounds/freedesktop/stereo/message.oga"]);
            }
        }
    }

    function dismissToast(id) {
        const item = activeToasts.find(t => t.id === id);
        if (item && item.ref && typeof item.ref.dismiss === "function") {
            try { item.ref.dismiss(); } catch (e) {}
        }
        activeToasts = activeToasts.filter(t => t.id !== id);
    }

    function iconSource(n) {
        if (!n) return "";
        const i = n.appIcon || n.desktopEntry || "";
        if (i === "") return "";
        if (i.startsWith("/")) return "file://" + i;
        if (i.startsWith("file://")) return i;
        return Quickshell.iconPath(i, true);
    }

    Component.onCompleted: {
        // Ao iniciar, sincroniza com o daemon supervisor de notificações
        Quickshell.execDetached(["rice-notif-daemon", "sync"]);
    }
}
