pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Leituras de sistema compartilhadas entre a Dashboard (barrinhas de
// recursos) e a aba Performance (gauges). Antes cada aba tinha os próprios
// pollers e eles rodavam o tempo todo, mesmo com o hub fechado; agora só
// rodam enquanto `active` (ligado ao hub.visible em shell.qml).
QtObject {
    id: root

    property bool active: false

    property real cpuUsage: 0      // 0-1
    property real cpuTemp: 0       // °C
    property real gpuUsage: 0      // 0-1
    property real gpuTemp: 0       // °C
    property string gpuName: "GPU" // Modelo simplificado dinâmico (ex: RTX 3050, GTX 950, RX 6600)
    property real ramRealGiB: 0
    property real ramCacheGiB: 0
    property real ramUsedGiB: 0
    property real ramTotalGiB: 0
    property real zramUsedGiB: 0
    property real zramTotalGiB: 0
    property real diskUsedGiB: 0
    property real diskTotalGiB: 0

    readonly property real ramRealFrac: ramTotalGiB > 0 ? ramRealGiB / ramTotalGiB : 0
    readonly property real ramCacheFrac: ramTotalGiB > 0 ? ramCacheGiB / ramTotalGiB : 0
    readonly property real ramFrac: ramRealFrac
    readonly property real diskFrac: diskTotalGiB > 0 ? diskUsedGiB / diskTotalGiB : 0

    readonly property real gib: 1024 * 1024 * 1024

    // ---------- Identificação dinâmica de GPU ----------
    property Process gpuNameProc: Process {
        command: ["bash", "-c",
            "name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | sed -E 's/NVIDIA (GeForce )?//; s/ Laptop GPU//; s/ Mobile//; s/ OEM//'); " +
            "if [ -z \"$name\" ]; then name=$(lspci 2>/dev/null | awk -F': ' '/(VGA|3D)/ {print $NF}' | grep -v Intel | head -1 | sed -E 's/.*\\[(.*)\\]/\\1/'); fi; " +
            "if [ -z \"$name\" ]; then name=$(lspci 2>/dev/null | awk -F': ' '/(VGA|3D)/ {print $NF}' | head -1 | sed -E 's/.*\\[(.*)\\]/\\1/'); fi; " +
            "if [ -z \"$name\" ]; then name=\"GPU\"; fi; echo \"$name\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = text.trim();
                if (n !== "") root.gpuName = n;
            }
        }
    }

    // ---------- CPU: uso % (delta de /proc/stat em 1s) + temperatura ----------
    property Timer cpuTimer: Timer {
        interval: 2500
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.cpuProc.running = true;
            if (root.gpuName === "GPU") root.gpuNameProc.running = true;
        }
    }
    property Process cpuProc: Process {
        command: ["bash", "-c",
            "read _ u1 n1 s1 i1 w1 ir1 so1 _ < /proc/stat; sleep 1; " +
            "read _ u2 n2 s2 i2 w2 ir2 so2 _ < /proc/stat; " +
            "t1=$((u1+n1+s1+i1+w1+ir1+so1)); t2=$((u2+n2+s2+i2+w2+ir2+so2)); " +
            "id1=$((i1+w1)); id2=$((i2+w2)); dt=$((t2-t1)); di=$((id2-id1)); " +
            "pct=$(( dt>0 ? (100*(dt-di))/dt : 0 )); " +
            "temp=$(sensors 2>/dev/null | awk '/(Package id 0|Tctl|Tdie|CPU Temperature|Core 0)/ {match($0, /[0-9]+\\.[0-9]+/, a); print a[0]; exit}'); " +
            "echo \"$pct ${temp:-0}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                root.cpuUsage = parseFloat(parts[0]) / 100 || 0;
                root.cpuTemp = parts[1] ? parseFloat(parts[1]) : 0;
            }
        }
    }

    // ---------- GPU (nvidia-smi ou sysfs): uso % + temperatura ----------
    property Timer gpuTimer: Timer {
        interval: 2500
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: root.gpuProc.running = true
    }
    property Process gpuProc: Process {
        command: ["bash", "-c",
            "if command -v nvidia-smi >/dev/null 2>&1; then " +
            "    nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo '0,0'; " +
            "else " +
            "    echo '0,0'; " +
            "fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",").map(s => s.trim());
                root.gpuUsage = parseFloat(parts[0]) / 100 || 0;
                root.gpuTemp = parts[1] ? parseFloat(parts[1]) : 0;
            }
        }
    }

    // ---------- RAM + zram ----------
    // LC_ALL=C: em pt-BR o free imprime "Mem.:" e o awk não batia.
    property Timer ramTimer: Timer {
        interval: 5000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.ramProc.running = true;
            root.zramProc.running = true;
        }
    }
    property Process ramProc: Process {
        command: ["bash", "-c",
            "awk '/^MemTotal:/{tot=$2} /^AnonPages:/{anon=$2} /^Shmem:/{shmem=$2} " +
            "/^Cached:/{cached=$2} /^Buffers:/{buf=$2} /^SReclaimable:/{srec=$2} " +
            "END { " +
            "real=anon*1024; cache=(cached-shmem+buf+srec)*1024; total=tot*1024; " +
            "print real, total, cache " +
            "}' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                if (parts.length >= 3) {
                    root.ramRealGiB = parseFloat(parts[0]) / root.gib || 0;
                    root.ramTotalGiB = parseFloat(parts[1]) / root.gib || 0;
                    root.ramCacheGiB = parseFloat(parts[2]) / root.gib || 0;
                    root.ramUsedGiB = root.ramRealGiB;
                }
            }
        }
    }
    property Process zramProc: Process {
        command: ["bash", "-c", "zramctl -b --noheadings 2>/dev/null | head -1 | awk '{print $4, $3}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                if (parts.length >= 2) {
                    root.zramUsedGiB = parseFloat(parts[0]) / root.gib || 0;
                    root.zramTotalGiB = parseFloat(parts[1]) / root.gib || 0;
                }
            }
        }
    }

    // ---------- Disco (/) ----------
    property Timer diskTimer: Timer {
        interval: 15000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: root.diskProc.running = true
    }
    property Process diskProc: Process {
        command: ["bash", "-c", "LC_ALL=C df -B1 / | tail -1 | awk '{print $3, $2}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                root.diskUsedGiB = parseFloat(parts[0]) / root.gib || 0;
                root.diskTotalGiB = parseFloat(parts[1]) / root.gib || 0;
            }
        }
    }
}
