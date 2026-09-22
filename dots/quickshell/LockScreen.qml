pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Bluetooth
import "."

// Tela de bloqueio do rice (substitui o hyprlock). O visual está em
// LockView.qml; aqui ficam o bloqueio de verdade (ext-session-lock), a senha
// via PAM, os dados mostrados e as ações de sessão.
//
// IPC: `qs ipc call lock lock | isLocked | preview`
//   preview abre a mesma tela numa janela comum, sem bloquear (para testar o
//   visual; Esc fecha, e a senha certa também fecha).
//
// Não existe `unlock` por IPC de propósito: qualquer programa do usuário
// poderia destravar a tela sem senha.
Scope {
    id: root

    readonly property bool isGreeter: false
    readonly property var sessions: []
    readonly property int sessionIndex: -1
    function selectSession(i) {}

    readonly property bool locked: sessionLock.locked
    property bool previewing: false
    readonly property bool active: locked || previewing

    // ---------- estado da senha ----------
    property string buffer: ""
    readonly property bool busy: pam.active
    property int pamState: 0            // 0 nada, 1 erro, 2 tentativas esgotadas, 3 senha errada
    property bool capsLock: false
    property bool unlocking: false
    signal flash

    // ---------- dados ----------
    property string wallpaper: ""
    property string avatar: ""
    property bool avatarIsGif: false
    property string osName: "Linux"
    property string osLogo: ""
    property string userName: Quickshell.env("USER") || ""
    property real uptimeBase: 0
    property date uptimeAt: new Date()
    property var weather: null
    property var notifGroups: []
    property int notifTotal: 0
    property int notifMaxId: 0
    property var hiddenIds: ({})          // dispensadas nesta tela
    property string expandedApp: ""
    property var pendingOpen: null        // notificação para abrir ao desbloquear
    property string wallVideo: ""
    property string firstName: ""
    property string note: ""

    // ---------- "enquanto você estava fora" ----------
    property date lockedAt: new Date()
    property int awayBaseId: 0
    property int awayNotifs: 0
    property var awayDownloads: []

    // ---------- senha: tentativas e faillock ----------
    property int failCount: 0
    property string lockMessage: ""       // "conta bloqueada por X min" do faillock

    // ---------- controles rápidos ----------
    readonly property PwNode sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [root.sink] }
    readonly property var btAdapter: Bluetooth.defaultAdapter
    property real brightness: -1          // -1 = sem backlight
    property bool wifiOn: true
    property bool hasWifi: false

    // ---------- mídia ----------
    property int playerIndex: 0
    readonly property var players: Mpris.players.values
    readonly property var player: {
        const list = players;
        if (!list.length) return null;
        if (playerIndex > 0 && playerIndex < list.length) return list[playerIndex];
        for (const p of list) if (p.isPlaying) return p;
        return list[0];
    }
    property real tickPosition: 0
    property var lyricsLines: []
    property bool lyricsSynced: false
    readonly property string lyricLine: {
        if (!lyricsSynced || !lyricsLines.length) return "";
        let line = "";
        for (const l of lyricsLines) {
            if (l.t <= tickPosition + 0.15) line = l.text; else break;
        }
        return line;
    }
    property var cavaBars: []

    function lock() {
        if (sessionLock.locked) return;
        reset();
        previewing = false;
        sessionLock.locked = true;
    }
    function preview() {
        if (active) return;
        reset();
        previewing = true;
    }
    function reset() {
        buffer = "";
        pamState = 0;
        unlocking = false;
        failCount = 0;
        lockMessage = "";
        hiddenIds = {};
        expandedApp = "";
        pendingOpen = null;
        playerIndex = 0;
        lockedAt = new Date();
        awayBaseId = NotifService.maxId;
        awayNotifs = 0;
        awayDownloads = [];
        if (player) tickPosition = player.position;
        brGet.running = true;
        wifiGet.running = true;
        noteFile.reload();
        lyricsProc.running = false;
        lyricsProc.running = true;
        wallVideo = "";
        infoProc.running = true;
        weatherProc.running = true;
        notifProc.running = true;
        capsProc.running = true;
    }

    // Chamado pela animação de saída do LockView (a primeira tela que
    // terminar destrava; as outras somem junto).
    function unlockFinished() {
        if (!unlocking) return;
        sessionLock.locked = false;
        previewing = false;
        unlocking = false;
        buffer = "";
        if (pendingOpen) {
            openNotification(pendingOpen);
            pendingOpen = null;
        }
    }

    // ---------- notificações ----------
    function toggleGroup(app) { expandedApp = expandedApp === app ? "" : app; }
    function dismiss(item) {
        const h = Object.assign({}, hiddenIds);
        h[item.id] = true;
        hiddenIds = h;
        if (pendingOpen && pendingOpen.id === item.id) pendingOpen = null;
        Quickshell.execDetached(["makoctl", "dismiss", "-n", String(item.id)]);
        notifProc.running = true;
    }
    function clearAll() {
        NotifService.setCleared(Math.max(NotifService.maxId, notifMaxId));
        Quickshell.execDetached(["makoctl", "dismiss", "--all"]);
        pendingOpen = null;
        notifGroups = [];
        notifTotal = 0;
    }
    function markOpen(item) {
        pendingOpen = (pendingOpen && pendingOpen.id === item.id) ? null : item;
    }
    // Abre depois de destravar: aciona a ação padrão se a notificação ainda
    // está ativa no mako; senão abre o app dela, ou a imagem (capturas de tela).
    function openNotification(item) {
        const icon = item.icon || "";
        const img = icon.startsWith("/") && /\.(png|jpe?g|webp|gif)$/i.test(icon) ? icon : "";
        const entry = item.entry || "";
        Quickshell.execDetached(["bash", "-c",
            "makoctl list -j 2>/dev/null | jq -e --argjson i \"$1\" '[.. | objects | select(.id? == $i)] | length > 0' >/dev/null " +
            "&& makoctl invoke -n \"$1\" default 2>/dev/null && exit 0; " +
            "[ -n \"$2\" ] && gtk-launch \"$2\" 2>/dev/null && exit 0; " +
            "[ -n \"$3\" ] && xdg-open \"$3\"",
            "rice-open", String(item.id), entry, img]);
    }

    // ---------- controles rápidos ----------
    function setVolume(v) {
        if (sink && sink.audio) sink.audio.volume = Math.max(0, Math.min(1, v));
    }
    function toggleMute() {
        if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
    }
    property int brPending: -1
    function setBrightness(v) {
        if (brightness < 0) return;
        brightness = Math.max(0.01, Math.min(1, v));
        const pct = Math.max(1, Math.round(brightness * 100));
        if (brSet.running) brPending = pct;
        else { brSet.pct = pct; brSet.running = true; }
    }
    function toggleWifi() {
        wifiOn = !wifiOn;
        Quickshell.execDetached(["nmcli", "radio", "wifi", wifiOn ? "on" : "off"]);
    }
    function toggleBluetooth() {
        if (btAdapter) btAdapter.enabled = !btAdapter.enabled;
    }

    // ---------- nota ----------
    function saveNote(t) {
        note = t.trim();
        noteFile.setText(note);
    }

    // ---------- mídia ----------
    function nextPlayer() {
        if (players.length < 2) return;
        const cur = players.indexOf(player);
        playerIndex = (cur + 1) % players.length;
        tickPosition = player ? player.position : 0;
    }
    function seek(frac) {
        if (!player || !player.canSeek || !(player.length > 0)) return;
        player.position = frac * player.length;
        tickPosition = frac * player.length;
    }

    function handleKey(event) {
        if (unlocking) return;
        if (event.key === Qt.Key_CapsLock) {
            capsTimer.restart();
            return;
        }
        if (previewing && event.key === Qt.Key_Escape && buffer.length === 0) {
            previewing = false;
            return;
        }
        if (pam.active || pamState === 2) return;

        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            submit();
        } else if (event.key === Qt.Key_Backspace) {
            buffer = (event.modifiers & Qt.ControlModifier) ? "" : buffer.slice(0, -1);
        } else if (event.key === Qt.Key_Escape) {
            buffer = "";
        } else if (event.text && /^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
            buffer += event.text;
        }
    }

    function submit() {
        if (pam.active || unlocking || buffer.length === 0) return;
        pam.start();
    }

    function sessionAction(action) {
        switch (action) {
        case "switch-wm":
            // Por enquanto sai da sessão e volta ao gerenciador de login, onde
            // se escolhe outro WM.
            Quickshell.execDetached(["rice-session-action", "logout"]);
            break;
        case "suspend":
            Quickshell.execDetached(["systemctl", "suspend"]);
            break;
        case "reboot":
            Quickshell.execDetached(["systemctl", "reboot"]);
            break;
        case "poweroff":
            Quickshell.execDetached(["systemctl", "poweroff"]);
            break;
        }
    }

    // ---------- ajudantes usados pelo LockView ----------
    function uptimeText(now) {
        const secs = uptimeBase + Math.max(0, (now - uptimeAt) / 1000);
        const m = Math.floor(secs / 60), h = Math.floor(m / 60), d = Math.floor(h / 24);
        const en = Theme.locale === "en";
        if (d > 0) return d + (en ? (d === 1 ? " day" : " days") : (d === 1 ? " dia" : " dias")) + ", " + (h % 24) + " h";
        if (h > 0) return h + " h " + (m % 60) + " min";
        return m + (en ? (m === 1 ? " minute" : " minutes") : (m === 1 ? " minuto" : " minutos"));
    }

    function weatherIcon(code, hour) {
        const night = hour < 6 || hour >= 18;
        if (code === 113) return night ? Theme.icons.night : Theme.icons.sunny;
        if (code === 116) return Theme.icons.partly;
        if (code === 119 || code === 122) return Theme.icons.cloudy;
        if ([143, 248, 260].includes(code)) return Theme.icons.fog;
        if ([200, 386, 389, 392, 395].includes(code)) return Theme.icons.lightning;
        if ([299, 302, 305, 308, 356, 359].includes(code)) return Theme.icons.pouring;
        if ([179, 182, 185, 227, 230, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377].includes(code))
            return Theme.icons.snowy;
        if (code >= 176) return Theme.icons.rainy;
        return Theme.icons.cloudy;
    }

    function iconSource(icon) {
        if (!icon) return "";
        if (icon.startsWith("/")) return "file://" + icon;
        if (icon.startsWith("file://")) return icon;
        return Quickshell.iconPath(icon, true);
    }

    function esc(t) {
        return String(t || "").replace(/<[^>]*>/g, "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // ---------- PAM ----------
    // Mesma pilha do hyprlock (/etc/pam.d/login, que também aplica o
    // faillock), então o comportamento de senha errada é o de sempre.
    PamContext {
        id: pam
        config: "login"

        // O faillock avisa por mensagem quando a conta foi travada.
        onMessageChanged: {
            if (/locked|bloquead/i.test(message)) root.lockMessage = message;
        }

        onResponseRequiredChanged: {
            if (!responseRequired) return;
            respond(root.buffer);
            root.buffer = "";
        }
        onCompleted: res => {
            if (res === PamResult.Success) {
                root.pamState = 0;
                root.failCount = 0;
                root.lockMessage = "";
                root.unlocking = true;
                return;
            }
            root.failCount++;
            if (res === PamResult.Error) root.pamState = 1;
            else if (res === PamResult.MaxTries) root.pamState = 2;
            else root.pamState = 3;
            root.buffer = "";
            root.flash();
            stateReset.restart();
        }
    }
    Timer {
        id: stateReset
        interval: root.pamState === 2 ? 30000 : 4000
        onTriggered: root.pamState = 0
    }

    // ---------- Caps Lock (o Qt não expõe; pergunta ao Hyprland) ----------
    Timer {
        id: capsTimer
        interval: 120
        onTriggered: capsProc.running = true
    }
    Process {
        id: capsProc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kbs = JSON.parse(text).keyboards || [];
                    const main = kbs.find(k => k.main) || kbs[0];
                    root.capsLock = !!(main && main.capsLock);
                } catch (e) {}
            }
        }
    }

    // ---------- sistema, wallpaper e foto ----------
    Process {
        id: infoProc
        command: ["bash", "-c",
            ". /etc/os-release 2>/dev/null; echo \"os=${PRETTY_NAME:-${NAME:-Linux}}\"; " +
            "for f in /usr/share/icons/$LOGO.svg /usr/share/pixmaps/$LOGO.svg /usr/share/pixmaps/$LOGO.png " +
            "/usr/share/icons/hicolor/scalable/apps/$LOGO.svg /usr/share/icons/hicolor/256x256/apps/$LOGO.png; do " +
            "[ -n \"$LOGO\" ] && [ -s \"$f\" ] && { echo \"logo=$f\"; break; }; done; " +
            "w=$(rice-wallpaper-current 2>/dev/null); [ -s \"$w\" ] || w=\"$HOME/.cache/hollow-wired/sddm-background.png\"; echo \"wall=$w\"; " +
            "for f in \"$HOME/.face.gif\" \"$HOME/.face\" \"$HOME/.face.icon\" \"/var/lib/AccountsService/icons/$USER\"; do " +
            "[ -s \"$f\" ] && { echo \"avatar=$f\"; echo \"avatarmime=$(file -b --mime-type \"$f\")\"; break; }; done; " +
            "echo \"up=$(cut -d' ' -f1 /proc/uptime)\"; " +
            "v=$(rice-wallpaper-current --media 2>/dev/null) && echo \"video=$v\"; " +
            "n=$(getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1 | cut -d' ' -f1); echo \"first=${n:-$USER}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=");
                    if (i < 0) continue;
                    const k = line.slice(0, i), v = line.slice(i + 1);
                    if (k === "os") root.osName = v;
                    else if (k === "logo") root.osLogo = v;
                    else if (k === "wall") root.wallpaper = v;
                    else if (k === "avatar") root.avatar = v;
                    else if (k === "avatarmime") root.avatarIsGif = v === "image/gif" || v === "image/webp";
                    else if (k === "video") root.wallVideo = v;
                    else if (k === "first") root.firstName = v;
                    else if (k === "up") { root.uptimeBase = parseFloat(v) || 0; root.uptimeAt = new Date(); }
                }
            }
        }
    }

    // ---------- clima (wttr.in, cache de 30 min) ----------
    Process {
        id: weatherProc
        command: ["bash", "-c",
            "f=\"${XDG_CACHE_HOME:-$HOME/.cache}/hollow-wired/weather.json\"; mkdir -p \"$(dirname \"$f\")\"; " +
            "if [ -s \"$f\" ] && [ $(( $(date +%s) - $(stat -c %Y \"$f\") )) -lt 1800 ]; then cat \"$f\"; echo '@@'; exit; fi; " +
            "[ -s \"$f\" ] && cat \"$f\"; echo '@@'; " +
            "curl -sf --max-time 8 'http://wttr.in/?format=j1&lang=" + (Theme.locale === "en" ? "en" : "pt") + "' > \"$f.tmp\" && [ -s \"$f.tmp\" ] && mv \"$f.tmp\" \"$f\" && cat \"$f\" && echo '@@'"]
        stdout: SplitParser {
            splitMarker: "@@"
            onRead: data => root.parseWeather(data)
        }
    }
    function parseWeather(text) {
        try {
            const data = JSON.parse(text);
            const cur = data.current_condition[0];
            const today = (data.weather || [])[0] || {};
            const desc = (Theme.locale !== "en" && cur.lang_pt) ? cur.lang_pt[0].value : cur.weatherDesc[0].value;
            root.weather = {
                temp: cur.temp_C,
                feels: cur.FeelsLikeC,
                code: parseInt(cur.weatherCode),
                desc: desc ? desc.charAt(0).toUpperCase() + desc.slice(1) : "",
                max: today.maxtempC ?? cur.temp_C,
                min: today.mintempC ?? cur.temp_C
            };
        } catch (e) {}
    }

    // ---------- notificações (mako), agrupadas por app ----------
    Process {
        id: notifProc
        command: ["bash", "-c",
            "c=$(cat \"$HOME/.cache/quickshell/notif-cleared\" 2>/dev/null); " +
            "{ makoctl list -j 2>/dev/null || echo '[]'; makoctl history -j 2>/dev/null || echo '[]'; } | " +
            "jq -s -c --argjson c \"${c:-0}\" '[.[] | if type == \"object\" then (.data[0] // []) else . end] | add // [] " +
            "| unique_by(.id) | map(select(.id > $c)) | group_by(.app_name) " +
            "| map({app: .[0].app_name, icon: ((sort_by(-.id)[0].app_icon) // \"\"), count: length, top: (map(.id) | max), " +
            "items: (sort_by(-.id) | .[0:20] | map({id: .id, s: (.summary // \"\"), b: (.body // \"\"), icon: (.app_icon // \"\"), entry: (.desktop_entry // \"\")}))}) | sort_by(-.top)'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const hidden = root.hiddenIds;
                    let maxId = 0, away = 0;
                    const groups = [];
                    for (const g of (JSON.parse(text) || [])) {
                        const items = g.items.filter(i => !hidden[i.id]);
                        if (!items.length) continue;
                        for (const i of items) {
                            maxId = Math.max(maxId, i.id);
                            if (i.id > root.awayBaseId) away++;
                        }
                        groups.push({ app: g.app, icon: g.icon, count: items.length, items: items });
                    }
                    root.notifGroups = groups;
                    root.notifTotal = groups.reduce((a, g) => a + g.count, 0);
                    root.notifMaxId = maxId;
                    root.awayNotifs = away;
                } catch (e) {
                    root.notifGroups = [];
                    root.notifTotal = 0;
                }
            }
        }
    }
    Timer {
        interval: 5000
        repeat: true
        running: root.active
        onTriggered: notifProc.running = true
    }

    // ---------- downloads concluídos desde o bloqueio ----------
    Process {
        id: awayProc
        command: ["bash", "-c",
            "d=$(xdg-user-dir DOWNLOAD 2>/dev/null); [ -d \"$d\" ] || exit 0; " +
            "find \"$d\" -maxdepth 1 -type f -newermt \"@$1\" ! -name '*.part' ! -name '*.crdownload' " +
            "! -name '*.tmp' ! -name '.*' -printf '%f\\n' 2>/dev/null | head -20",
            "rice-away", String(Math.floor(root.lockedAt.getTime() / 1000))]
        stdout: StdioCollector {
            onStreamFinished: root.awayDownloads = text.split("\n").filter(l => l.length > 0)
        }
    }
    Timer {
        interval: 10000
        repeat: true
        running: root.active
        onTriggered: awayProc.running = true
    }

    // ---------- brilho ----------
    Process {
        id: brGet
        command: ["bash", "-c", "ls /sys/class/backlight/ 2>/dev/null | grep -q . && brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(text);
                root.brightness = isNaN(v) ? -1 : v / 100;
            }
        }
    }
    Process {
        id: brSet
        property int pct: 0
        command: ["brightnessctl", "-q", "set", pct + "%"]
        onExited: {
            if (root.brPending >= 0) {
                pct = root.brPending;
                root.brPending = -1;
                running = true;
            }
        }
    }

    // ---------- Wi-Fi ----------
    Process {
        id: wifiGet
        command: ["bash", "-c", "nmcli -t -f TYPE device 2>/dev/null | grep -qx wifi && echo has; nmcli radio wifi 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.hasWifi = text.indexOf("has") >= 0;
                root.wifiOn = text.indexOf("enabled") >= 0;
            }
        }
    }

    // ---------- nota ----------
    FileView {
        id: noteFile
        path: Quickshell.env("HOME") + "/.config/hollow-wired/lock-note.txt"
        printErrors: false
        onLoaded: root.note = text().trim()
        onLoadFailed: root.note = ""
    }

    // ---------- mídia: posição, letra e cava ----------
    Timer {
        interval: 1000
        repeat: true
        running: root.active && root.player !== null && root.player.isPlaying
        onTriggered: root.tickPosition += 1
    }
    Connections {
        target: root.player
        function onPositionChanged() { root.tickPosition = root.player.position; }
        function onTrackTitleChanged() {
            root.tickPosition = root.player.position;
            if (root.active) {
                lyricsProc.running = false;
                lyricsProc.running = true;
            }
        }
    }
    Process {
        id: lyricsProc
        command: ["rice-lyrics"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.lyricsSynced = !!d.synced;
                    root.lyricsLines = d.lines || [];
                } catch (e) {
                    root.lyricsLines = [];
                }
            }
        }
    }
    Process {
        id: cavaProc
        running: root.active && root.player !== null && root.player.isPlaying
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/quickshell/cava.conf"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = line.split(";").filter(x => x.length > 0).map(Number);
                if (parts.length) root.cavaBars = parts;
            }
        }
        onRunningChanged: if (!running) root.cavaBars = []
    }

    // ---------- o bloqueio de verdade ----------
    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            id: surface
            color: "transparent"

            LockView {
                anchors.fill: parent
                ctl: root
                screenH: surface.screen?.height ?? 1080
            }
        }
    }

    // Janela de teste (sem bloquear).
    PanelWindow {
        id: previewWin
        visible: root.previewing
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell-lock-preview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Loader {
            anchors.fill: parent
            active: root.previewing
            sourceComponent: LockView {
                ctl: root
                screenH: previewWin.screen?.height ?? 1080
            }
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void { root.lock(); }
        function isLocked(): bool { return root.locked; }
        function preview(): void { root.preview(); }
    }
}
