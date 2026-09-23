pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

// Estado da mídia tocando, compartilhado pelas barras e pela central.
//
// Por que não usar só o Mpris do Quickshell:
//   - o `isPlaying` dele trava com alguns players (o Sonora, players web): medido,
//     ficou 5+ s dizendo "pausado" com a música tocando. A verdade vem do
//     `playerctl status` (a cada 2 s, 0,5 s logo após um clique e sempre que o
//     Mpris muda). Logo após um clique vale o estado pedido;
//   - o clique usa PlayPause do próprio player (`playerctl play-pause`), que
//     inverte o estado real dele. `play()`/`pause()` pelo ícone falhavam com o
//     ícone atrasado, e o `togglePlaying()` decide pelo `isPlaying` que trava.
//
// Volume do app: navegadores ignoram o volume do MPRIS, então o volume é o do
// stream do app no PipeWire, achado pelo nome do player (dbus
// `org.mpris.MediaPlayer2.<nome>[.instanceN]` ↔ application.name /
// process.binary / node.name do stream). Ex.: sonora → "PipeWire ALSA [sonora]",
// firefox, chromium/chrome ("Google Chrome"), spotify, brave. Sem stream, cai
// para o volume do MPRIS se o player aceitar.
Singleton {
    id: root

    // Depois de um clique o player fica preso (lock): senão, ao pausar, a barra
    // podia pular para outro player e o segundo clique ia para ele.
    property var lock: null
    readonly property var player: {
        const ps = Mpris.players.values.filter(p => !String(p.dbusName).endsWith(".playerctld"));
        if (lock && ps.indexOf(lock) >= 0) return lock;
        return ps.find(p => p.isPlaying) || (ps.length > 0 ? ps[0] : null);
    }
    readonly property string name: player ? String(player.dbusName).replace("org.mpris.MediaPlayer2.", "") : ""
    readonly property string key: name.replace(/\.instance.*$/, "").toLowerCase()

    // ---------- tocando / pausado ----------
    property var override: null
    property int fast: 0
    property real clickAt: 0
    readonly property bool playing: override !== null ? override : (player !== null && player.isPlaying)

    function toggle() {
        if (!player) return;
        lock = player;
        override = !playing;
        clickAt = Date.now();
        Quickshell.execDetached(["playerctl", "-p", name, "play-pause"]);
        fast = 10;
    }
    function next() { skip("next"); }
    function previous() { skip("previous"); }
    function skip(cmd) {
        if (!player) return;
        Quickshell.execDetached(["playerctl", "-p", name, cmd]);
        lock = null;
        fast = 3;
        poll();
    }
    function poll() {
        if (!player || statusProc.running) return;
        statusProc.command = ["playerctl", "-p", name, "status"];
        statusProc.running = true;
    }
    onPlayerChanged: {
        if (!lock) { override = null; poll(); }
        position = player ? player.position : 0;
    }
    property Connections mprisConn: Connections {
        target: root.player
        function onIsPlayingChanged() { root.poll(); }
    }
    property Timer pollTimer: Timer {
        interval: root.fast > 0 ? 500 : 2000
        repeat: true
        running: root.player !== null
        onTriggered: root.poll()
    }
    property Process statusProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.fast > 0) root.fast--;
                else root.lock = null;
                // resposta de antes do player processar o clique: ignora
                if (Date.now() - root.clickAt < 1600) return;
                const st = text.trim();
                if (st === "Playing" || st === "Paused" || st === "Stopped")
                    root.override = st === "Playing";
            }
        }
    }

    // ---------- posição na faixa ----------
    // O MPRIS não empurra a posição durante a reprodução; ler `player.position`
    // devolve a estimativa atual, então um timer relê a cada segundo tocando.
    property real position: 0
    readonly property real length: player && player.length > 0 ? player.length : 0
    readonly property bool canSeek: player !== null && player.canSeek && length > 0
    property Timer posTimer: Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.player !== null && root.playing
        onTriggered: root.position = root.player.position
    }
    property Connections trackConn: Connections {
        target: root.player
        function onTrackTitleChanged() { root.position = root.player.position; }
        function onPositionChanged() { root.position = root.player.position; }
    }
    function seek(sec) {
        if (!canSeek) return;
        sec = Math.max(0, Math.min(length, sec));
        player.position = sec;
        position = sec;
    }
    function fmt(sec) {
        sec = Math.max(0, Math.floor(sec || 0));
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
        const ss = (s < 10 ? "0" : "") + s;
        return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss;
    }

    // ---------- nível do som (disco da barra) ----------
    // Um cava leve (cava-bar.conf, 8 faixas) só enquanto algo toca e alguém
    // mostra o disco (levelWanted, ligado pela TopBar). level = média 0..1.
    property bool levelWanted: false
    property real level: 0
    property Process levelProc: Process {
        running: root.levelWanted && root.player !== null && root.playing
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/quickshell/cava-bar.conf"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = line.split(";").filter(x => x.length > 0).map(Number);
                if (parts.length === 0) return;
                let sum = 0;
                for (const v of parts) sum += v;
                root.level = Math.max(0, Math.min(1, sum / parts.length / 100));
            }
        }
        onRunningChanged: if (!running) root.level = 0
    }

    // ---------- volume do app ----------
    function matches(n) {
        if (root.key === "") return false;
        const p = n.properties;
        const fields = [n.name, n.description, p["application.name"], p["application.process.binary"],
                        p["application.id"], p["pipewire.access.portal.app_id"]];
        const ident = player && player.identity ? String(player.identity).toLowerCase() : "";
        for (const f of fields) {
            if (!f) continue;
            const v = String(f).toLowerCase();
            if (v.includes(root.key) || (ident !== "" && v.includes(ident))) return true;
        }
        return false;
    }
    // Sem vínculo (PwObjectTracker) o nó não traz `properties`, só o nome, então
    // todos os streams de reprodução ficam vinculados e o casamento usa o nome
    // (`alsa_playback.sonora`) além das propriedades. Stream de reprodução tem
    // isSink = true no Quickshell (recebe o áudio do app).
    readonly property var playbackStreams: Pipewire.nodes.values.filter(n => n.audio && n.isStream && n.isSink)
    property PwObjectTracker tracker: PwObjectTracker { objects: root.playbackStreams }
    readonly property var streams: playbackStreams.filter(n => root.matches(n))

    readonly property bool mprisVolume: player !== null && player.volumeSupported && player.canControl
    readonly property bool hasVolume: streams.length > 0 || mprisVolume
    readonly property real volume: streams.length > 0 && streams[0].audio ? streams[0].audio.volume
        : (mprisVolume ? player.volume : 0)
    readonly property bool muted: streams.length > 0 && streams[0].audio ? streams[0].audio.muted : false

    function setVolume(v) {
        v = Math.max(0, Math.min(1, v));
        if (streams.length > 0) {
            for (const s of streams) if (s.audio) s.audio.volume = v;
        } else if (mprisVolume) {
            player.volume = v;
        }
    }
    function toggleMute() {
        const m = !muted;
        for (const s of streams) if (s.audio) s.audio.muted = m;
    }
    // Roda do mouse: 5 % por clique inteiro, somando do último valor pedido
    // (o PipeWire demora a refletir e o valor "voltava").
    property real wheelAcc: 0
    property real wheelTarget: -1
    property Timer wheelSettle: Timer { interval: 800; onTriggered: { root.wheelTarget = -1; root.wheelAcc = 0; } }
    function wheel(delta) {
        if (!hasVolume) return;
        wheelAcc += delta;
        const steps = Math.trunc(wheelAcc / 120);
        if (steps === 0) return;
        wheelAcc -= steps * 120;
        const base = wheelTarget >= 0 ? wheelTarget : volume;
        wheelTarget = Math.max(0, Math.min(1, Math.round((base + steps * 0.05) * 20) / 20));
        wheelSettle.restart();
        setVolume(wheelTarget);
    }
    readonly property real shownVolume: wheelTarget >= 0 ? wheelTarget : volume
}
