pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Serviço central de Pomodoro Timer (estilo end-4).
// Modos: work (25m), shortBreak (5m), longBreak (15m).
// Emite notificação nativa com notify-send e alerta sonoro ao encerrar cada ciclo.
QtObject {
    id: root

    property string mode: "work"
    property int workMinutes: 25
    property int shortBreakMinutes: 5
    property int longBreakMinutes: 15

    property int secondsLeft: workMinutes * 60
    property bool running: false
    property bool paused: false
    property int cycleCount: 0

    readonly property bool active: running || paused

    readonly property string timeString: {
        const m = Math.floor(secondsLeft / 60);
        const s = secondsLeft % 60;
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }

    readonly property real progress: {
        const total = totalSecondsForMode(root.mode);
        if (total <= 0) return 0;
        return Math.max(0, Math.min(1, 1 - (secondsLeft / total)));
    }

    function totalSecondsForMode(m) {
        if (m === "work") return workMinutes * 60;
        if (m === "shortBreak") return shortBreakMinutes * 60;
        if (m === "longBreak") return longBreakMinutes * 60;
        return 25 * 60;
    }

    function start() {
        if (paused) {
            paused = false;
            running = true;
            return;
        }
        if (!running) {
            secondsLeft = totalSecondsForMode(root.mode);
            running = true;
            paused = false;
        }
    }

    function pause() {
        if (running) {
            running = false;
            paused = true;
        }
    }

    function toggle() {
        if (running) pause();
        else start();
    }

    function reset() {
        running = false;
        paused = false;
        secondsLeft = totalSecondsForMode(root.mode);
    }

    function setMode(newMode) {
        if (root.mode === newMode && !running && !paused) return;
        root.mode = newMode;
        root.reset();
    }

    function notifyFinished() {
        let title = "Pomodoro Timer";
        let msg = "";
        if (root.mode === "work") {
            root.cycleCount++;
            if (root.cycleCount % 4 === 0) {
                msg = Theme.t("pomodoro.work_done_long", "Sessão de foco concluída! Hora de uma pausa longa (15 min).");
                root.mode = "longBreak";
            } else {
                msg = Theme.t("pomodoro.work_done_short", "Sessão de foco concluída! Hora de uma pausa curta (5 min).");
                root.mode = "shortBreak";
            }
        } else {
            msg = Theme.t("pomodoro.break_done", "Pausa terminada! Pronto para mais uma rodada de foco?");
            root.mode = "work";
        }
        root.reset();
        Quickshell.execDetached(["notify-send", "-a", "Pomodoro", "-u", "normal", "-i", "alarm", title, msg]);
        Quickshell.execDetached(["paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga"]);
    }

    property Timer tickTimer: Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: {
            if (root.secondsLeft > 1) {
                root.secondsLeft--;
            } else {
                root.secondsLeft = 0;
                root.running = false;
                root.notifyFinished();
            }
        }
    }
}
