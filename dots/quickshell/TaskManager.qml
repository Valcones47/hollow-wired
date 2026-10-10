import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Gerenciador de Tarefas do rice. Este arquivo é o controlador: lê os dados do
// `rice-procs watch` (só roda com alguma janela aberta), guarda o histórico dos
// gráficos e as preferências, e oferece duas janelas com a mesma visão
// (TaskManagerView.qml):
//   app  — janela de aplicativo de verdade (FloatingWindow): Super + Esc;
//   drop — desce do topo como o terminal drop-down: Super + Shift + '.
// Mesma tecla de novo fecha por completo (para a leitura e esvazia a lista).
Scope {
    id: ctl

    property bool appOpen: false
    property bool dropOpen: false
    readonly property bool anyOpen: ctl.appOpen || ctl.dropOpen

    // ---------------------------------------------------------- colunas
    // modes: onde a coluna existe (grouped = Processos, flat = Detalhes).
    readonly property var colDefs: [
        { id: "pid",     w: 72,  right: true,  modes: ["flat"] },
        { id: "status",  w: 96, right: false, modes: ["grouped", "flat"] },
        { id: "n",       w: 84,  right: true,  modes: ["grouped"] },
        { id: "threads", w: 80,  right: true,  modes: ["grouped", "flat"] },
        { id: "cpu",     w: 84, right: true,  modes: ["grouped", "flat"] },
        { id: "mem",     w: 96, right: true,  modes: ["grouped", "flat"] },
        { id: "swap",    w: 88, right: true,  modes: ["grouped", "flat"] },
        { id: "disk",    w: 100, right: true,  modes: ["grouped", "flat"] },
        { id: "gpu",     w: 76,  right: true,  modes: ["grouped", "flat"] },
        { id: "gpuused", w: 130, right: false, modes: ["grouped", "flat"] },
        { id: "vram",    w: 104, right: true,  modes: ["grouped", "flat"] },
        { id: "cmd",     w: 360, right: false, modes: ["flat"] }
    ]
    function colDef(id) {
        for (const c of ctl.colDefs) if (c.id === id) return c;
        return { id: id, w: 100, right: true, modes: [] };
    }
    function colWidth(id) {
        const w = ctl.settings.colWidths ? ctl.settings.colWidths[id] : undefined;
        return w > 40 ? w : ctl.colDef(id).w;
    }
    function colTitle(id) {
        const T = (k, f) => Theme.t(k, f);
        switch (id) {
        case "pid": return "PID";
        case "status": return T("taskman.col_status", "Status");
        case "n": return T("taskman.col_n", "Processos");
        case "threads": return "Threads";
        case "cpu": return T("taskman.col_cpu", "CPU");
        case "mem": return T("taskman.col_mem", "Memória");
        case "swap": return "Swap";
        case "disk": return T("taskman.col_disk", "Disco");
        case "gpu": return "GPU";
        case "gpuused": return T("taskman.col_gpuused", "GPU usada");
        case "vram": return T("taskman.col_vram", "Mem. de vídeo");
        case "cmd": return T("taskman.col_cmd", "Linha de comando");
        }
        return id;
    }

    // ---------------------------------------------------------- preferências
    // ~/.config/hollow-wired/task-manager.json (estado do usuário).
    readonly property var defaultSettings: ({
        cols: { pid: true, status: false, n: true, threads: false, cpu: true, mem: true, swap: false,
                disk: true, gpu: true, gpuused: true, vram: false, cmd: true },
        colOrder: ["pid", "status", "n", "threads", "cpu", "mem", "swap", "disk", "gpu", "gpuused", "vram", "cmd"],
        colWidths: {},
        density: "normal",       // compact | normal | comfortable
        fontSize: "normal",      // small | normal | large
        heat: true,
        startTab: "processes",
        graphWindow: 60,
        resHidden: [],
        interval: 2, bgOpen: false, nvidia: true
    })
    property var settings: ctl.defaultSettings
    readonly property string cfgPath: Quickshell.env("HOME") + "/.config/hollow-wired/task-manager.json"
    FileView {
        id: cfgFile
        path: ctl.cfgPath
        printErrors: false
        onLoaded: {
            try {
                const j = JSON.parse(text());
                const s = Object.assign({}, ctl.defaultSettings);
                if (j.cols) s.cols = Object.assign({}, s.cols, j.cols);
                if (j.colWidths) s.colWidths = Object.assign({}, j.colWidths);
                if (Array.isArray(j.colOrder)) {
                    const known = ctl.defaultSettings.colOrder;
                    const o = j.colOrder.filter(x => known.indexOf(x) >= 0);
                    for (const k of known) if (o.indexOf(k) < 0) o.push(k);
                    s.colOrder = o;
                }
                for (const k of ["density", "fontSize", "heat", "startTab", "graphWindow", "resHidden",
                                 "interval", "bgOpen", "nvidia"])
                    if (j[k] !== undefined) s[k] = j[k];
                ctl.settings = s;
            } catch (e) {}
        }
    }
    function _save() { cfgFile.setText(JSON.stringify(ctl.settings, null, 2) + "\n"); }
    function setSetting(k, v) {
        const s = Object.assign({}, ctl.settings);
        s[k] = v;
        ctl.settings = s;
        ctl._save();
        if (k === "interval" || k === "nvidia") ctl.restartFeed();
    }
    function setCol(id, on) {
        const c = Object.assign({}, ctl.settings.cols);
        c[id] = on;
        ctl.setSetting("cols", c);
    }
    function setColWidth(id, w, persist) {
        const m = Object.assign({}, ctl.settings.colWidths);
        m[id] = Math.max(52, Math.round(w));
        const s = Object.assign({}, ctl.settings);
        s.colWidths = m;
        ctl.settings = s;
        if (persist) ctl._save();
    }
    function moveCol(id, dir) {
        const o = ctl.settings.colOrder.slice();
        const i = o.indexOf(id), j = i + dir;
        if (i < 0 || j < 0 || j >= o.length) return;
        o[i] = o[j]; o[j] = id;
        ctl.setSetting("colOrder", o);
    }
    function resetCols() {
        const s = Object.assign({}, ctl.settings);
        s.cols = Object.assign({}, ctl.defaultSettings.cols);
        s.colOrder = ctl.defaultSettings.colOrder.slice();
        s.colWidths = {};
        ctl.settings = s;
        ctl._save();
    }
    function toggleRes(key, on) {
        const h = ctl.settings.resHidden.filter(x => x !== key);
        if (!on) h.push(key);
        ctl.setSetting("resHidden", h);
    }

    // ---------------------------------------------------------- dados
    property var sys: ({ cpu: 0, temp: null, model: "", cores: 0, freq: null, procs: 0, threads: 0, uptime: 0 })
    property var mem: ({ total: 0, used: 0, avail: 0, cached: 0, swap_total: 0, swap_used: 0 })
    property var disks: []
    property var nets: []
    property var gpus: []
    property var groups: []
    property var hist: ({})
    property int dataRev: 0
    property bool feedRun: true
    // Aba pedida de fora (qs ipc call taskmanager tab performance).
    property string tabRequest: ""

    function restartFeed() { ctl.feedRun = false; feedRestart.restart(); }
    Timer { id: feedRestart; interval: 200; onTriggered: ctl.feedRun = true }

    Process {
        id: feed
        running: ctl.anyOpen && ctl.feedRun
        command: ["rice-procs", "watch", String(ctl.settings.interval)].concat(ctl.settings.nvidia ? [] : ["--no-nvidia"])
        stdout: SplitParser { onRead: (line) => ctl.ingest(line) }
    }

    function _push(h, key, v) {
        let a = h[key] || [];
        a = a.concat([v === null || v === undefined ? 0 : v]);
        if (a.length > 240) a = a.slice(a.length - 240);
        h[key] = a;
    }

    function ingest(line) {
        let d = null;
        try { d = JSON.parse(line); } catch (e) { return; }
        ctl.sys = d.sys; ctl.mem = d.mem; ctl.disks = d.disks; ctl.nets = d.nets;
        ctl.gpus = d.gpus; ctl.groups = d.groups;
        const h = Object.assign({}, ctl.hist);
        ctl._push(h, "cpu", d.sys.cpu);
        ctl._push(h, "mem", d.mem.total > 0 ? d.mem.used * 100 / d.mem.total : 0);
        for (const x of d.disks) ctl._push(h, "disk:" + x.name, x.busy);
        for (const x of d.nets) ctl._push(h, "net:" + x.name, x.rx + x.tx);
        for (const x of d.gpus) ctl._push(h, "gpu:" + x.id, x.util);
        ctl.hist = h;
        ctl.dataRev++;
    }

    function clearData() {
        ctl.groups = []; ctl.disks = []; ctl.nets = []; ctl.gpus = []; ctl.hist = ({});
    }

    // ---------------------------------------------------------- nomes e ícones
    property var _names: ({})
    function appLabel(g) {
        const k = g.cls;
        if (ctl._names[k] === undefined) {
            let name = k;
            try {
                const e = DockConfig.entryForWindow(k, g.title);
                if (e && e.name) name = e.name;
            } catch (e) {}
            ctl._names[k] = name;
        }
        return ctl._names[k];
    }
    function appIcon(g) {
        try { return String(DockConfig.iconForWindow(g.cls, g.title) || ""); } catch (e) { return ""; }
    }

    // ---------------------------------------------------------- encerrar
    property var asked: ({})   // chave -> já mandou TERM (o próximo clique força)
    function endPids(key, pids) {
        const force = !!ctl.asked[key];
        Quickshell.execDetached(["rice-procs", "kill", force ? "KILL" : "TERM"].concat(pids.map(String)));
        const a = Object.assign({}, ctl.asked);
        a[key] = true;
        ctl.asked = a;
    }

    function sendSignal(sig, pids) {
        Quickshell.execDetached(["rice-procs", "kill", sig].concat(pids.map(String)));
    }
    function setNice(value, pids) {
        Quickshell.execDetached(["rice-procs", "nice", String(value)].concat(pids.map(String)));
    }
    function focusWindow(addr) {
        if (!addr) return;
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"address:" + addr + "\" })"]);
    }
    function openFolder(path) {
        const i = path.lastIndexOf("/");
        if (i > 0) Quickshell.execDetached(["xdg-open", path.slice(0, i)]);
    }
    function copyText(t) { Quickshell.execDetached(["wl-copy", t]); }
    // O processo e todos os descendentes dele (pelo pid pai).
    function descendants(pid) {
        const kids = {};
        for (const g of ctl.groups) for (const p of g.procs) (kids[p[13]] = kids[p[13]] || []).push(p[0]);
        const out = [pid], todo = [pid];
        while (todo.length) {
            const c = todo.pop();
            for (const k of (kids[c] || [])) if (out.indexOf(k) < 0) { out.push(k); todo.push(k); }
        }
        return out;
    }

    // ---------------------------------------------------------- formatação
    function _pt() { return String(Theme.locale || "").indexOf("pt") === 0; }
    function _n(v) { const s = String(v); return ctl._pt() ? s.replace(".", ",") : s; }
    function fmtBytes(b) {
        if (b >= 1073741824) return ctl._n((b / 1073741824).toFixed(b >= 10737418240 ? 0 : 1)) + " GB";
        if (b >= 1048576) return ctl._n(Math.round(b / 1048576)) + " MB";
        if (b >= 1024) return ctl._n(Math.round(b / 1024)) + " KB";
        return "0 B";
    }
    function fmtRate(b) {
        if (b >= 1048576) return ctl._n((b / 1048576).toFixed(1)) + " MB/s";
        if (b >= 1024) return ctl._n(Math.round(b / 1024)) + " KB/s";
        return Math.round(b) + " B/s";
    }
    function fmtPct(p) {
        if (p === null || p === undefined) return "—";
        return ctl._n(p >= 10 ? Math.round(p) : p.toFixed(1)) + " %";
    }
    function fmtFreq(m) {
        if (m === null || m === undefined) return "—";
        return m >= 1000 ? ctl._n((m / 1000).toFixed(2)) + " GHz" : m + " MHz";
    }
    function fmtUptime(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        const p = (n) => (n < 10 ? "0" : "") + n;
        return (d > 0 ? d + ":" : "") + p(h) + ":" + p(m) + ":" + p(s % 60);
    }

    // ---------------------------------------------------------- recursos (aba Desempenho)
    // A lista de chaves só muda quando surge ou some um dispositivo: assim o
    // Repeater não recria os blocos a cada leitura.
    property var resKeys: ["cpu", "mem"]
    readonly property var visibleResKeys: ctl.resKeys.filter(k => ctl.settings.resHidden.indexOf(k) < 0)
    readonly property int graphPoints: Math.max(10, Math.round(ctl.settings.graphWindow / ctl.settings.interval))
    onDataRevChanged: {
        const k = ["cpu", "mem"];
        for (const x of ctl.disks) k.push("disk:" + x.name);
        for (const x of ctl.nets) k.push("net:" + x.name);
        for (const x of ctl.gpus) k.push("gpu:" + x.id);
        if (k.join("|") !== ctl.resKeys.join("|")) ctl.resKeys = k;
    }

    function _devHas(csv, v) { return ("," + (csv || "") + ",").indexOf("," + v + ",") >= 0; }
    function _find(arr, f) { for (const x of arr) if (f(x)) return x; return null; }

    // Dados de um recurso para o bloco da esquerda e o detalhe da direita.
    // `rev` só existe para o binding reavaliar a cada leitura.
    function resInfo(key, rev) {
        const H = (ctl.hist[key] || []).slice(-ctl.graphPoints);
        const pts = ctl.graphPoints;
        const T = (k, f) => Theme.t(k, f);
        if (key === "cpu") {
            const s = ctl.sys;
            return { title: T("taskman.res_cpu", "CPU"), sub: s.model, color: Theme.primary,
                value: ctl.fmtPct(s.cpu) + (s.freq ? "  " + ctl.fmtFreq(s.freq) : ""),
                series: H, points: pts, max: 100, unit: T("taskman.util_pct", "Utilização em %"),
                stats: [
                    { k: T("taskman.s_util", "Utilização"), v: ctl.fmtPct(s.cpu) },
                    { k: T("taskman.s_speed", "Velocidade"), v: ctl.fmtFreq(s.freq) },
                    { k: T("taskman.s_procs", "Processos"), v: String(s.procs) },
                    { k: T("taskman.s_threads", "Threads"), v: String(s.threads) },
                    { k: T("taskman.s_uptime", "Tempo ativo"), v: ctl.fmtUptime(s.uptime) },
                    { k: T("taskman.s_cores", "Núcleos lógicos"), v: String(s.cores) },
                    { k: T("taskman.s_temp", "Temperatura"), v: s.temp !== null && s.temp !== undefined ? s.temp + " °C" : "—" }
                ] };
        }
        if (key === "mem") {
            const m = ctl.mem;
            const pct = m.total > 0 ? m.used * 100 / m.total : 0;
            return { title: T("taskman.res_mem", "Memória"), sub: ctl.fmtBytes(m.total), color: Theme.tertiary,
                value: ctl.fmtBytes(m.used) + " (" + ctl.fmtPct(pct) + ")",
                series: H, points: pts, max: 100, unit: T("taskman.mem_pct", "Uso da memória em %"),
                stats: [
                    { k: T("taskman.s_inuse", "Em uso"), v: ctl.fmtBytes(m.used) },
                    { k: T("taskman.s_avail", "Disponível"), v: ctl.fmtBytes(m.avail) },
                    { k: T("taskman.s_cached", "Em cache"), v: ctl.fmtBytes(m.cached) },
                    { k: T("taskman.s_total", "Total"), v: ctl.fmtBytes(m.total) },
                    { k: "Swap", v: ctl.fmtBytes(m.swap_used) + " / " + ctl.fmtBytes(m.swap_total) }
                ] };
        }
        if (key.indexOf("disk:") === 0) {
            const n = key.slice(5);
            const d = ctl._find(ctl.disks, x => x.name === n) || { name: n, model: "", size: 0, read: 0, write: 0, busy: 0 };
            return { title: T("taskman.res_disk", "Disco") + " " + n, sub: d.model, color: Theme.color12,
                value: ctl.fmtPct(d.busy), series: H, points: pts, max: 100,
                unit: T("taskman.disk_pct", "Tempo ativo em %"),
                stats: [
                    { k: T("taskman.s_active", "Tempo ativo"), v: ctl.fmtPct(d.busy) },
                    { k: T("taskman.s_read", "Leitura"), v: ctl.fmtRate(d.read) },
                    { k: T("taskman.s_write", "Gravação"), v: ctl.fmtRate(d.write) },
                    { k: T("taskman.s_capacity", "Capacidade"), v: ctl.fmtBytes(d.size) }
                ] };
        }
        if (key.indexOf("net:") === 0) {
            const n = key.slice(4);
            const d = ctl._find(ctl.nets, x => x.name === n) || { name: n, rx: 0, tx: 0 };
            return { title: T("taskman.res_net", "Rede") + " " + n, sub: "", color: Theme.color6,
                value: "↓ " + ctl.fmtRate(d.rx) + "  ↑ " + ctl.fmtRate(d.tx),
                series: H, points: pts, max: 0, unit: T("taskman.net_traffic", "Tráfego (recebido + enviado)"),
                stats: [
                    { k: T("taskman.s_recv", "Recebido"), v: ctl.fmtRate(d.rx) },
                    { k: T("taskman.s_sent", "Enviado"), v: ctl.fmtRate(d.tx) }
                ] };
        }
        if (key.indexOf("gpu:") === 0) {
            const n = key.slice(4);
            const g = ctl._find(ctl.gpus, x => x.id === n);
            if (!g) return { title: "GPU", sub: "", color: Theme.color2, value: "—", series: [], max: 100, unit: "", stats: [] };
            const idx = ctl.gpus.indexOf(g);
            const resting = g.state === "suspended";
            const stats = [];
            if (resting) {
                stats.push({ k: T("taskman.s_state", "Estado"), v: T("taskman.gpu_rest", "Em repouso (economizando bateria)") });
            } else if (g.state === "off") {
                stats.push({ k: T("taskman.s_state", "Estado"), v: T("taskman.gpu_off", "Leitura desligada nas configurações") });
            } else {
                stats.push({ k: T("taskman.s_util", "Utilização"), v: ctl.fmtPct(g.util) });
                if (g.mem_total) stats.push({ k: T("taskman.s_vram", "Memória de vídeo"),
                                              v: ctl.fmtBytes(g.mem_used) + " / " + ctl.fmtBytes(g.mem_total) });
                if (g.freq !== null && g.freq !== undefined) stats.push({ k: T("taskman.s_speed", "Velocidade"), v: ctl.fmtFreq(g.freq) });
                if (g.temp !== null && g.temp !== undefined) stats.push({ k: T("taskman.s_temp", "Temperatura"), v: g.temp + " °C" });
                if (g.power !== null && g.power !== undefined) stats.push({ k: T("taskman.s_power", "Consumo"), v: ctl._n(g.power.toFixed(1)) + " W" });
                if (g.vendor === "nvidia" && g.util === null)
                    stats.push({ k: T("taskman.s_state", "Estado"), v: T("taskman.gpu_noread", "Sem leitura (o driver pede reinício)") });
            }
            const users = [];
            for (const gr of ctl.groups) {
                if (ctl._devHas(gr.devs, g.vendor)) {
                    let name = gr.kind === "app" ? ctl.appLabel(gr) : gr.name;
                    users.push({ name: name, pct: gr.gpu, vram: gr.vram, key: gr.key });
                }
            }
            users.sort((a, b) => (b.pct - a.pct) || (b.vram - a.vram));
            return { title: "GPU " + idx, sub: g.name, color: Theme.color2, users: users.slice(0, 8),
                value: resting ? T("taskman.gpu_rest_short", "Em repouso") : ctl.fmtPct(g.util),
                series: H, points: pts, max: 100, unit: T("taskman.util_pct", "Utilização em %"), stats: stats };
        }
        return { title: key, sub: "", color: Theme.primary, value: "", series: [], max: 100, unit: "", stats: [] };
    }

    // ---------------------------------------------------------- janela de aplicativo
    FloatingWindow {
        id: appWin
        visible: ctl.appOpen
        title: Theme.t("taskman.title", "Gerenciador de Tarefas")
        color: Theme.background
        implicitWidth: 1280
        implicitHeight: 760
        minimumSize: Qt.size(760, 480)
        // Fechar pelo botão do compositor: acompanha o estado.
        onVisibleChanged: if (!visible && ctl.appOpen) ctl.appOpen = false

        TaskManagerView {
            anchors.fill: parent
            ctrl: ctl
            active: ctl.appOpen
            onCloseRequested: ctl.appOpen = false
        }
    }

    // ---------------------------------------------------------- drop-down
    PanelWindow {
        id: dropWin

        property real slide: ctl.dropOpen ? 1 : 0
        Behavior on slide { NumberAnimation { duration: Theme.ms(180); easing.type: Easing.OutCubic } }

        visible: ctl.dropOpen || dropWin.slide > 0.001
        color: "transparent"
        focusable: true
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell-taskmanager"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: ctl.dropOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        // Só o cartão recebe clique; o resto da tela segue com as janelas.
        mask: Region { item: dropCard }

        property var targetScreen: null
        screen: targetScreen || Theme.primaryScreen
        readonly property bool _openForScreen: ctl.dropOpen
        on_OpenForScreenChanged: if (_openForScreen) targetScreen = Theme.focusedScreen()

        Rectangle {
            id: dropCard
            width: Math.min(1180, parent.width * 0.7)
            height: Math.min(parent.height * 0.68, 700)
            x: Math.round((parent.width - width) / 2)
            y: Math.round(Theme.waybarHeight + 10 - (height + Theme.waybarHeight + 10) * (1 - dropWin.slide))
            radius: 18
            color: Theme.background
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.35)
            clip: true

            TaskManagerView {
                anchors.fill: parent
                anchors.margins: 1
                ctrl: ctl
                active: ctl.dropOpen
                closeOnEscape: true
                onCloseRequested: ctl.dropOpen = false
            }
        }
    }

    // Esvazia tudo quando nenhuma janela está aberta (e o rice-procs já parou).
    onAnyOpenChanged: if (!ctl.anyOpen) ctl.clearData()

    // ---------------------------------------------------------- abrir/fechar
    function toggleApp() {
        ctl.dropOpen = false;
        ctl.appOpen = !ctl.appOpen;
    }
    function toggleDrop() {
        ctl.appOpen = false;
        ctl.dropOpen = !ctl.dropOpen;
    }

    IpcHandler {
        target: "taskmanager"
        function app(): void { ctl.toggleApp(); }
        function window(): void { ctl.toggleApp(); }
        function toggle(): void { ctl.toggleApp(); }
        function drop(): void { ctl.toggleDrop(); }
        function hide(): void { ctl.appOpen = false; ctl.dropOpen = false; }
        // processes | performance | settings: abre o aplicativo já nessa aba.
        function tab(name: string): void {
            if (!ctl.anyOpen) ctl.toggleApp();
            ctl.tabRequest = name;
        }
    }
}
