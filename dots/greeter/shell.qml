pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd
import "."

// Greeter do greetd: a mesma tela da tela de bloqueio (LockView.qml), agora
// como tela de login do sistema. Roda como o usuário `greeter` num Hyprland
// mínimo (/etc/greetd/hyprland-greeter.lua), com HOME apontando para
// /var/lib/hollow-wired-greeter — onde o `rice-greeter sync` do usuário deixa
// cores, idioma, foto, wallpaper e nome (o greeter não lê a home de ninguém).
//
// Sem GREETD_SOCK (rodando pelo `rice-greeter test`) vira uma demonstração:
// Enter só toca a animação de saída e fecha.
ShellRoot {
    id: root

    readonly property string shared: Quickshell.env("HOME") + "/shared"
    readonly property bool demo: !Greetd.available

    // ---------- interface esperada pelo LockView ----------
    readonly property bool isGreeter: true
    property string buffer: ""
    property bool busy: false
    property int pamState: 0
    property bool capsLock: false
    property bool unlocking: false
    signal flash

    property string wallpaper: ""
    property string wallVideo: ""
    property string avatar: ""
    property bool avatarIsGif: false
    property string osName: "Linux"
    property string osLogo: ""
    property string userName: ""
    property string firstName: ""
    property string note: ""
    property real uptimeBase: 0
    property date uptimeAt: new Date()
    property var weather: null

    readonly property var notifGroups: []
    readonly property int notifTotal: 0
    readonly property var pendingOpen: null
    readonly property string expandedApp: ""
    readonly property int awayNotifs: 0
    readonly property var awayDownloads: []
    property int failCount: 0
    property string lockMessage: ""
    readonly property var sink: null
    readonly property var btAdapter: null
    readonly property real brightness: -1
    readonly property bool hasWifi: false
    readonly property bool wifiOn: false
    readonly property var players: []
    readonly property var player: null
    readonly property real tickPosition: 0
    readonly property string lyricLine: ""
    readonly property var cavaBars: []

    // ---------- sessões ----------
    property var sessions: []
    property int sessionIndex: 0
    function selectSession(i) {
        sessionIndex = i;
        stateFile.setText(JSON.stringify({ session: sessions[i]?.key ?? "" }));
    }

    function handleKey(event) {
        if (unlocking || busy) return;
        if (event.key === Qt.Key_CapsLock) { capsTimer.restart(); return; }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            if (sessions.length) selectSession((sessionIndex + (event.key === Qt.Key_Down ? 1 : sessions.length - 1)) % sessions.length);
            return;
        }
        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) submit();
        else if (event.key === Qt.Key_Backspace) buffer = (event.modifiers & Qt.ControlModifier) ? "" : buffer.slice(0, -1);
        else if (event.key === Qt.Key_Escape) buffer = "";
        else if (event.text && /^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) buffer += event.text;
    }

    function submit() {
        if (busy || unlocking || buffer.length === 0) return;
        // Nunca tenta entrar como root (o greeter chegou a ser montado assim
        // por um bug do install): avisa em vez de recusar a senha em silêncio.
        if (!userName || userName === "root") {
            lockMessage = Theme.t("greeter.no_user", "Tela de login sem usuário configurado. Use Ctrl+Alt+F3 e rode: sudo rice-greeter install");
            buffer = "";
            flash();
            return;
        }
        if (demo) { buffer = ""; unlocking = true; return; }
        busy = true;
        Greetd.createSession(userName);
    }

    // Chamado quando a animação de saída termina: agora sim inicia a sessão.
    function unlockFinished() {
        if (demo) { Qt.quit(); return; }
        const sess = sessions[sessionIndex];
        if (!sess) { Qt.quit(); return; }
        const env = ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=" + sess.key];
        if (sess.desktopNames) env.push("XDG_CURRENT_DESKTOP=" + sess.desktopNames);
        // O greetd junta o comando com espaços e o reinterpreta no shell:
        // `sh -c "exec X"` virava `sh -c exec` e a sessão fechava na hora.
        // Por isso vai só o comando em palavras, via rice-session-start
        // (que guarda a saída em ~/.cache/hollow-wired/session.log).
        const words = sess.exec.match(/"[^"]*"|\S+/g).map(w => w.replace(/^"|"$/g, ""));
        Greetd.launch(["/usr/local/bin/rice-session-start"].concat(words), env, true);
    }

    function sessionAction(action) {
        if (action === "suspend") Quickshell.execDetached(["systemctl", "suspend"]);
        else if (action === "reboot") Quickshell.execDetached(["systemctl", "reboot"]);
        else if (action === "poweroff") Quickshell.execDetached(["systemctl", "poweroff"]);
    }

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
    function iconSource(icon) { return ""; }
    function esc(t) { return String(t || ""); }
    function saveNote(t) {}
    function dismiss(i) {}
    function clearAll() {}
    function markOpen(i) {}
    function toggleGroup(a) {}
    function setVolume(v) {}
    function toggleMute() {}
    function setBrightness(v) {}
    function toggleWifi() {}
    function toggleBluetooth() {}
    function nextPlayer() {}
    function seek(f) {}

    // ---------- greetd ----------
    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (/locked|bloquead/i.test(message)) root.lockMessage = message;
            if (responseRequired) {
                Greetd.respond(root.buffer);
                root.buffer = "";
            }
        }
        function onAuthFailure(message) {
            root.busy = false;
            root.buffer = "";
            root.failCount++;
            root.pamState = 3;
            root.flash();
            stateReset.restart();
        }
        function onReadyToLaunch() {
            root.busy = false;
            root.pamState = 0;
            root.unlocking = true;
        }
        function onError(error) {
            root.busy = false;
            root.pamState = 1;
            root.flash();
            stateReset.restart();
        }
    }
    Timer { id: stateReset; interval: 4000; onTriggered: root.pamState = 0 }

    // ---------- dados compartilhados pelo usuário (rice-greeter sync) ----------
    Process {
        id: infoProc
        running: true
        command: ["bash", "-c",
            "d=\"$1\"; . /etc/os-release 2>/dev/null; echo \"os=${PRETTY_NAME:-${NAME:-Linux}}\"; " +
            "for f in /usr/share/icons/$LOGO.svg /usr/share/pixmaps/$LOGO.svg /usr/share/pixmaps/$LOGO.png " +
            "/usr/share/icons/hicolor/scalable/apps/$LOGO.svg; do [ -n \"$LOGO\" ] && [ -s \"$f\" ] && { echo \"logo=$f\"; break; }; done; " +
            "[ -s \"$d/wallpaper.jpg\" ] && echo \"wall=$d/wallpaper.jpg\"; " +
            "[ -s \"$d/wallpaper.mp4\" ] && echo \"video=$d/wallpaper.mp4\"; " +
            "[ -s \"$d/face\" ] && { echo \"avatar=$d/face\"; echo \"avatarmime=$(file -b --mime-type \"$d/face\")\"; }; " +
            "[ -s \"$d/user\" ] && echo \"user=$(head -1 \"$d/user\")\"; " +
            "[ -s \"$d/firstname\" ] && echo \"first=$(head -1 \"$d/firstname\")\"; " +
            "[ -s \"$d/note.txt\" ] && echo \"note=$(head -c 140 \"$d/note.txt\" | tr '\\n' ' ')\"; " +
            "echo \"up=$(cut -d' ' -f1 /proc/uptime)\"",
            "greeter-info", root.shared]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=");
                    if (i < 0) continue;
                    const k = line.slice(0, i), v = line.slice(i + 1);
                    if (k === "os") root.osName = v;
                    else if (k === "logo") root.osLogo = v;
                    else if (k === "wall") root.wallpaper = v;
                    else if (k === "video") root.wallVideo = v;
                    else if (k === "avatar") root.avatar = v;
                    else if (k === "avatarmime") root.avatarIsGif = v === "image/gif" || v === "image/webp";
                    else if (k === "user") root.userName = v;
                    else if (k === "first") root.firstName = v;
                    else if (k === "note") root.note = v.trim();
                    else if (k === "up") { root.uptimeBase = parseFloat(v) || 0; root.uptimeAt = new Date(); }
                }
            }
        }
    }

    // Sessões Wayland instaladas (/usr/share/wayland-sessions/*.desktop).
    Process {
        id: sessionsProc
        running: true
        command: ["bash", "-c",
            "for f in /usr/share/wayland-sessions/*.desktop; do [ -f \"$f\" ] || continue; " +
            "grep -qi '^NoDisplay=true' \"$f\" && continue; grep -qi '^Hidden=true' \"$f\" && continue; " +
            "n=$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-); e=$(grep -m1 '^Exec=' \"$f\" | cut -d= -f2-); " +
            "dn=$(grep -m1 '^DesktopNames=' \"$f\" | cut -d= -f2- | tr ';' ':' | sed 's/:$//'); " +
            "printf '%s\\t%s\\t%s\\t%s\\n' \"$(basename \"$f\" .desktop)\" \"$n\" \"$e\" \"$dn\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = [];
                for (const line of text.split("\n")) {
                    const p = line.split("\t");
                    if (p.length < 3 || !p[2]) continue;
                    list.push({ key: p[0], name: p[1] || p[0], exec: p[2].replace(/ %[fFuUdDnNickvm]/g, ""), desktopNames: p[3] || "" });
                }
                // Hyprland primeiro (a sessão "de casa"), o resto em ordem alfabética.
                list.sort((a, b) => (b.key === "hyprland") - (a.key === "hyprland") || a.name.localeCompare(b.name));
                root.sessions = list;
                stateFile.reload();
            }
        }
    }

    // Última sessão escolhida (gravada pelo próprio greeter, na home dele).
    FileView {
        id: stateFile
        path: Quickshell.env("HOME") + "/state.json"
        printErrors: false
        onLoaded: {
            try {
                const key = JSON.parse(text()).session;
                const i = root.sessions.findIndex(s => s.key === key);
                if (i >= 0) root.sessionIndex = i;
            } catch (e) {}
        }
    }

    // Clima (wttr.in, cache de 30 min na home do greeter).
    Process {
        id: weatherProc
        running: true
        command: ["bash", "-c",
            "f=\"$HOME/weather.json\"; " +
            "if [ -s \"$f\" ] && [ $(( $(date +%s) - $(stat -c %Y \"$f\") )) -lt 1800 ]; then cat \"$f\"; echo '@@'; exit; fi; " +
            "[ -s \"$f\" ] && cat \"$f\"; echo '@@'; " +
            "curl -sf --max-time 8 'http://wttr.in/?format=j1&lang=" + (Theme.locale === "en" ? "en" : "pt") + "' > \"$f.tmp\" && [ -s \"$f.tmp\" ] && mv \"$f.tmp\" \"$f\" && cat \"$f\" && echo '@@'"]
        stdout: SplitParser {
            splitMarker: "@@"
            onRead: data => {
                try {
                    const d = JSON.parse(data);
                    const cur = d.current_condition[0];
                    const today = (d.weather || [])[0] || {};
                    const desc = (Theme.locale !== "en" && cur.lang_pt) ? cur.lang_pt[0].value : cur.weatherDesc[0].value;
                    root.weather = {
                        temp: cur.temp_C, feels: cur.FeelsLikeC, code: parseInt(cur.weatherCode),
                        desc: desc ? desc.charAt(0).toUpperCase() + desc.slice(1) : "",
                        max: today.maxtempC ?? cur.temp_C, min: today.mintempC ?? cur.temp_C
                    };
                } catch (e) {}
            }
        }
    }

    Timer { id: capsTimer; interval: 120; onTriggered: capsProc.running = true }
    Process {
        id: capsProc
        running: true
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

    Component.onCompleted: SysStats.active = true

    // Uma tela por monitor; só a do monitor focado recebe o teclado.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            color: "black"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "hollow-greeter"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            LockView {
                anchors.fill: parent
                ctl: root
                screenH: win.screen?.height ?? 1080
            }
        }
    }
}
