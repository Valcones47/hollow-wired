import QtQuick
import QtQuick.Layouts
import "."

// Tabela de processos do Gerenciador de Tarefas.
//   grouped — Processos: apps (por janela) com seta que abre os subprocessos,
//             mais a seção "em segundo plano";
//   flat    — Detalhes: todos os processos, sem agrupar.
// Colunas (ordem, largura e visibilidade) vêm das preferências do controlador.
Item {
    id: tb

    property var ctrl
    property string mode: "grouped"     // grouped | flat
    property string query: ""
    property bool active: false

    property string sortKey: "mem"
    property bool sortDesc: true
    property string selKey: ""
    property var selRow: null
    property var expanded: ({})
    property var collapsed: ({})
    property int rowCount: 0

    signal rowMenu(var row, real x, real y)
    signal headerMenu(real x, real y)

    // ---------------------------------------------------------- aparência
    readonly property int rowH: {
        const d = tb.ctrl ? tb.ctrl.settings.density : "normal";
        return d === "compact" ? 30 : (d === "comfortable" ? 46 : 38);
    }
    readonly property int fs: {
        const f = tb.ctrl ? tb.ctrl.settings.fontSize : "normal";
        return f === "small" ? 12 : (f === "large" ? 15 : 13);
    }
    readonly property bool heatOn: tb.ctrl ? tb.ctrl.settings.heat !== false : true

    // ---------------------------------------------------------- colunas
    property var cols: []
    function refreshCols() {
        if (!tb.ctrl) return;
        const s = tb.ctrl.settings;
        const ids = s.colOrder.filter(id => s.cols[id] && tb.ctrl.colDef(id).modes.indexOf(tb.mode) >= 0);
        if (ids.join("|") !== tb.cols.join("|")) tb.cols = ids;
    }
    Connections {
        target: tb.ctrl
        function onSettingsChanged() { tb.refreshCols(); }
    }
    onModeChanged: { tb.refreshCols(); tb.selKey = ""; tb.selRow = null; tb.rebuild(); }
    onCtrlChanged: tb.refreshCols()

    function colW(id) { return tb.ctrl.colWidth(id); }
    function isNum(id) { return ["cpu", "mem", "swap", "disk", "gpu", "vram"].indexOf(id) >= 0; }

    function accent(id) {
        switch (id) {
        case "cpu": return Theme.primary;
        case "mem": return Theme.tertiary;
        case "swap": return Theme.color3;
        case "disk": return Theme.color12;
        default: return Theme.color2;   // gpu, vram
        }
    }
    function level(id, v) {
        let l = 0;
        switch (id) {
        case "cpu": l = v / 30; break;
        case "mem": l = tb.ctrl.mem.total > 0 ? v / (tb.ctrl.mem.total * 0.12) : 0; break;
        case "swap": l = v / 1073741824; break;
        case "disk": l = v / (30 * 1048576); break;
        case "gpu": l = v / 40; break;
        case "vram": l = v / 1073741824; break;
        }
        return Math.max(0, Math.min(1, l));
    }
    function heat(id, v) {
        if (!tb.heatOn || !(v > 0)) return "transparent";
        const l = tb.level(id, v);
        return Theme.withAlpha(l > 0.85 ? Theme.critical : tb.accent(id), 0.08 + 0.46 * l);
    }
    function total(id) {
        const c = tb.ctrl;
        switch (id) {
        case "cpu": return c.sys.cpu;
        case "mem": return c.mem.used;
        case "swap": return c.mem.swap_used;
        case "disk": { let m = 0; for (const d of c.disks) m = Math.max(m, d.busy); return m; }
        case "gpu": { let m = 0; for (const g of c.gpus) if (g.util !== null) m = Math.max(m, g.util); return m; }
        case "vram": { let m = 0; for (const g of c.gpus) if (g.mem_used) m += g.mem_used; return m; }
        }
        return 0;
    }
    function totalText(id) {
        const c = tb.ctrl;
        const v = tb.total(id);
        switch (id) {
        case "cpu": case "gpu": case "disk": return c.fmtPct(v);
        case "mem": return c.mem.total > 0 ? c.fmtPct(v * 100 / c.mem.total) : "—";
        case "swap": return c.mem.swap_total > 0 ? c.fmtPct(v * 100 / c.mem.swap_total) : "—";
        case "vram": return v > 0 ? c.fmtBytes(v) : "—";
        }
        return "";
    }
    function totalHeat(id) {
        if (!tb.isNum(id)) return "transparent";
        const v = tb.total(id);
        if (id === "disk") return tb.heat("disk", v / 100 * 30 * 1048576);
        if (id === "mem") return tb.heat("mem", v);
        return tb.heat(id, v);
    }
    function cellText(id, r) {
        const c = tb.ctrl;
        switch (id) {
        case "cpu": case "gpu": return c.fmtPct(r[id]);
        case "mem": case "swap": case "vram": return r[id] > 0 ? c.fmtBytes(r[id]) : "0 MB";
        case "disk": return r.disk > 0 ? c.fmtRate(r.disk) : "0 MB/s";
        case "n": return String(r.n);
        case "threads": return String(r.threads);
        case "pid": return r.pid > 0 ? String(r.pid) : "";
        case "status": return r.pstate === "T" ? Theme.t("taskman.suspended", "Suspenso") : "";
        case "cmd": return r.cmd;
        }
        return "";
    }
    function devLabel(d) { return d === "nvidia" ? "NVIDIA" : (d === "amd" ? "AMD" : "Intel"); }

    // ---------------------------------------------------------- linhas
    ListModel { id: lm }

    function _sortVal(it, k) {
        switch (k) {
        case "name": return it.label.toLowerCase();
        case "gpuused": return it.devs || "";
        case "status": return it.pstate === "T" ? 1 : 0;
        case "cmd": return (it.cmd || "").toLowerCase();
        default: return it[k] || 0;
        }
    }
    function _cmp() {
        const k = tb.sortKey, d = tb.sortDesc ? -1 : 1;
        return (a, b) => {
            const x = tb._sortVal(a, k), y = tb._sortVal(b, k);
            let r = x < y ? -1 : x > y ? 1 : 0;
            if (r === 0) r = a.label.toLowerCase() < b.label.toLowerCase() ? -1 : 1;
            return r * d;
        };
    }

    // Linha da tabela a partir de um grupo (app) ou de um processo.
    function _grpItem(g, label) {
        const main = g.procs.reduce((m, p) => (!m || p[0] < m[0]) ? p : m, null);
        return {
            label: label, cpu: g.cpu, mem: g.mem, swap: g.swap, disk: g.disk, gpu: g.gpu, vram: g.vram,
            n: g.n, threads: g.procs.reduce((a, p) => a + p[11], 0), devs: g.devs,
            pstate: g.procs.every(p => p[10] === "T") ? "T" : "S", pid: 0,
            nice: main ? main[12] : 0, ppid: 0, cmd: main ? main[14] : "", exe: main ? main[15] : "",
            addr: g.addrs && g.addrs.length > 0 ? g.addrs[0] : "", wins: g.wins,
            pids: g.procs.map(p => p[0]).join(","),
            gdev: g.procs.reduce((a, p) => a || (p[8] || ""), ""), g: g
        };
    }
    function _procItem(p, label) {
        return {
            label: label, cpu: p[2], mem: p[3], swap: p[4], disk: p[5], gpu: p[6], vram: p[7],
            n: 1, threads: p[11], devs: p[9] || "", pstate: p[10], pid: p[0], nice: p[12], ppid: p[13],
            cmd: p[14] || "", exe: p[15] || "", addr: "", wins: 0, pids: String(p[0]), gdev: p[8] || ""
        };
    }
    function _row(key, kind, it, extra) {
        return Object.assign({
            key: key, kind: kind, label: it.label, sub: "", icon: "", expanded: false, depth: 0,
            n: it.n, pid: it.pid, pids: it.pids, cpu: it.cpu, mem: it.mem, swap: it.swap, disk: it.disk,
            gpu: it.gpu, vram: it.vram, devs: it.devs, gdev: it.gdev, pstate: it.pstate, threads: it.threads,
            nice: it.nice, ppid: it.ppid, cmd: it.cmd, exe: it.exe, addr: it.addr, wins: it.wins
        }, extra || {});
    }

    function rebuild() {
        const c = tb.ctrl;
        if (!c || !tb.active) return;
        const q = tb.query.trim().toLowerCase();
        const rows = [];
        const cmp = tb._cmp();

        if (tb.mode === "flat") {
            const items = [];
            for (const g of c.groups) {
                for (const p of g.procs) {
                    const it = tb._procItem(p, String(p[1]));
                    if (q && it.label.toLowerCase().indexOf(q) < 0 && it.cmd.toLowerCase().indexOf(q) < 0
                            && String(p[0]).indexOf(q) < 0) continue;
                    items.push(it);
                }
            }
            items.sort(cmp);
            for (const it of items) rows.push(tb._row("proc:" + it.pid, "proc", it));
            tb.rowCount = items.length;
            tb.syncModel(rows);
            tb._fixSelection();
            return;
        }

        const ap = [], bg = [];
        let nproc = 0;
        for (const g of c.groups) {
            nproc += g.n;
            const label = g.kind === "app" ? c.appLabel(g) : g.name;
            if (q) {
                let hit = label.toLowerCase().indexOf(q) >= 0 || g.name.toLowerCase().indexOf(q) >= 0;
                if (!hit) for (const p of g.procs) if (String(p[1]).toLowerCase().indexOf(q) >= 0) { hit = true; break; }
                if (!hit) continue;
            }
            const it = tb._grpItem(g, label);
            (g.kind === "app" ? ap : bg).push(it);
        }
        ap.sort(cmp);
        bg.sort(cmp);
        tb.rowCount = nproc;

        const sect = (key, title, items) => {
            const closed = q ? false
                : (tb.collapsed[key] !== undefined ? tb.collapsed[key]
                   : (key === "sect:bg" ? !c.settings.bgOpen : false));
            rows.push(tb._row(key, "sect", { label: title, n: items.length, pid: 0, pids: "", cpu: 0, mem: 0, swap: 0,
                                             disk: 0, gpu: 0, vram: 0, devs: "", gdev: "", pstate: "", threads: 0,
                                             nice: 0, ppid: 0, cmd: "", exe: "", addr: "", wins: 0 },
                              { expanded: !closed, sub: String(items.length) }));
            if (closed) return;
            for (const it of items) {
                const g = it.g;
                const open = !!tb.expanded[g.key] && g.n > 1;
                rows.push(tb._row(g.key, "grp", it, {
                    sub: g.n > 1 ? "(" + g.n + ")" : "", expanded: open,
                    icon: g.kind === "app" ? c.appIcon(g) : "" }));
                if (!open) continue;
                const ps = g.procs.map(p => tb._procItem(p, String(p[1])));
                ps.sort(cmp);
                for (const pi of ps) rows.push(tb._row("proc:" + pi.pid, "proc", pi, { depth: 1, sub: "PID " + pi.pid }));
            }
        };
        sect("sect:apps", Theme.t("taskman.sect_apps", "Aplicativos"), ap);
        if (bg.length > 0) sect("sect:bg", Theme.t("taskman.sect_bg", "Processos em segundo plano"), bg);
        tb.syncModel(rows);
        tb._fixSelection();
    }

    function _fixSelection() {
        if (tb.selKey === "") return;
        for (let i = 0; i < lm.count; i++) {
            if (lm.get(i).key === tb.selKey) { tb.selRow = tb.snapshot(i); return; }
        }
        tb.selKey = ""; tb.selRow = null;
    }

    // Atualiza o ListModel no lugar: reatribuir recriaria os delegates a cada
    // leitura (perde o hover e pisca).
    function syncModel(rows) {
        const want = {};
        for (const r of rows) want[r.key] = true;
        for (let i = lm.count - 1; i >= 0; i--)
            if (!want[lm.get(i).key]) lm.remove(i);
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i];
            let j = -1;
            for (let k = i; k < lm.count; k++) {
                if (lm.get(k).key === r.key) { j = k; break; }
            }
            if (j === -1) lm.insert(i, r);
            else {
                if (j !== i) lm.move(j, i, 1);
                lm.set(i, r);
            }
        }
    }

    function snapshot(i) {
        const o = lm.get(i), r = {};
        for (const k of ["key", "kind", "label", "sub", "icon", "expanded", "depth", "n", "pid", "pids", "cpu",
                         "mem", "swap", "disk", "gpu", "vram", "devs", "gdev", "pstate", "threads", "nice",
                         "ppid", "cmd", "exe", "addr", "wins"]) r[k] = o[k];
        return r;
    }

    function toggleExpanded(key) {
        const e = Object.assign({}, tb.expanded);
        e[key] = !e[key];
        tb.expanded = e;
        tb.rebuild();
    }
    function toggleSect(key, wasOpen) {
        const c = Object.assign({}, tb.collapsed);
        c[key] = wasOpen;
        tb.collapsed = c;
        tb.rebuild();
    }
    function setSort(k) {
        if (tb.sortKey === k) tb.sortDesc = !tb.sortDesc;
        else { tb.sortKey = k; tb.sortDesc = ["name", "pid", "status", "gpuused", "cmd"].indexOf(k) < 0; }
        tb.rebuild();
    }
    function reset() {
        tb.selKey = ""; tb.selRow = null;
        tb.expanded = ({}); tb.collapsed = ({});
    }
    function clear() { lm.clear(); }

    Connections {
        target: tb.ctrl
        function onDataRevChanged() { tb.rebuild(); }
    }
    onQueryChanged: tb.rebuild()
    onActiveChanged: { if (tb.active) { tb.refreshCols(); tb.rebuild(); } else tb.clear(); }

    // ---------------------------------------------------------- layout
    // Se as colunas escolhidas não cabem, a tabela rola na horizontal (o nome
    // nunca fica menor que nameMin).
    readonly property int nameMin: 240
    readonly property int contentW: {
        let w = tb.nameMin + 40;
        if (tb.ctrl) for (const id of tb.cols) w += tb.colW(id);
        return w;
    }

    Flickable {
        id: hscroll
        anchors.fill: parent
        contentWidth: Math.max(tb.width, tb.contentW)
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

    ColumnLayout {
        width: hscroll.contentWidth
        height: hscroll.height
        spacing: 0

        // ---- cabeçalho: nome + uma coluna por métrica (total em cima)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 54
            radius: 10
            color: Theme.withAlpha(Theme.tile, 0.55)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.minimumWidth: tb.nameMin
                    Layout.fillHeight: true
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 52
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.t("taskman.col_name", "Nome") + (tb.sortKey === "name" ? (tb.sortDesc ? "  ▾" : "  ▴") : "")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: tb.sortKey === "name" ? Theme.textColor : Theme.subtext
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (m) => {
                            if (m.button === Qt.RightButton) {
                                const p = mapToItem(tb, m.x, m.y);
                                tb.headerMenu(p.x, p.y);
                            } else tb.setSort("name");
                        }
                    }
                }

                Repeater {
                    model: tb.cols
                    delegate: Item {
                        id: hc
                        required property string modelData
                        readonly property bool num: tb.isNum(hc.modelData)
                        readonly property bool alignRight: tb.ctrl.colDef(hc.modelData).right
                        Layout.preferredWidth: tb.colW(hc.modelData)
                        Layout.fillHeight: true

                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 4
                            anchors.bottomMargin: 4
                            anchors.leftMargin: 2
                            anchors.rightMargin: 2
                            radius: 8
                            color: tb.totalHeat(hc.modelData)
                        }
                        Column {
                            anchors.right: hc.alignRight ? parent.right : undefined
                            anchors.left: hc.alignRight ? undefined : parent.left
                            anchors.rightMargin: 10
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                visible: hc.num
                                anchors.right: parent.right
                                text: hc.num ? tb.totalText(hc.modelData) : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                color: Theme.textColor
                            }
                            Text {
                                anchors.right: hc.alignRight ? parent.right : undefined
                                text: tb.ctrl.colTitle(hc.modelData)
                                      + (tb.sortKey === hc.modelData ? (tb.sortDesc ? "  ▾" : "  ▴") : "")
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: tb.sortKey === hc.modelData ? Theme.textColor : Theme.subtext
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.leftMargin: 7
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (m) => {
                                if (m.button === Qt.RightButton) {
                                    const p = mapToItem(tb, m.x, m.y);
                                    tb.headerMenu(p.x, p.y);
                                } else tb.setSort(hc.modelData);
                            }
                        }
                        // borda esquerda: arrastar redimensiona a coluna
                        MouseArea {
                            id: grip
                            property real startX: 0
                            property real startW: 0
                            width: 8
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            cursorShape: Qt.SplitHCursor
                            preventStealing: true
                            onPressed: (m) => { grip.startX = mapToItem(tb, m.x, 0).x; grip.startW = tb.colW(hc.modelData); }
                            onPositionChanged: (m) => {
                                if (!pressed) return;
                                tb.ctrl.setColWidth(hc.modelData, grip.startW - (mapToItem(tb, m.x, 0).x - grip.startX), false);
                            }
                            onReleased: tb.ctrl.setColWidth(hc.modelData, tb.colW(hc.modelData), true)
                            Rectangle {
                                anchors.centerIn: parent
                                width: 1; height: parent.height - 22
                                color: Theme.withAlpha(Theme.subtext, grip.containsMouse || grip.pressed ? 0.6 : 0.16)
                            }
                            hoverEnabled: true
                        }
                    }
                }
                Item { Layout.preferredWidth: 10 }
            }
        }

        // ---- linhas
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 4
            clip: true
            model: lm
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds

            Text {
                anchors.centerIn: parent
                visible: lm.count === 0
                text: Theme.t("taskman.loading", "Lendo processos…")
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.subtext
            }

            delegate: Item {
                id: row
                required property int index
                required property string key
                required property string kind
                required property string label
                required property string sub
                required property string icon
                required property bool expanded
                required property int depth
                required property int n
                required property int pid
                required property string pids
                required property real cpu
                required property real mem
                required property real swap
                required property real disk
                required property real gpu
                required property real vram
                required property string devs
                required property string gdev
                required property string pstate
                required property int threads
                required property string cmd

                readonly property bool isSect: kind === "sect"
                readonly property bool selected: tb.selKey === key
                readonly property bool canExpand: tb.mode === "grouped" && kind === "grp" && n > 1
                readonly property bool suspended: pstate === "T"
                width: list.width
                height: isSect ? Math.round(tb.rowH * 1.05) : tb.rowH

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 1
                    anchors.bottomMargin: 1
                    radius: 8
                    color: row.selected ? Theme.withAlpha(Theme.primary, 0.2)
                           : (rowArea.containsMouse ? Theme.withAlpha(Theme.tile, 0.75) : "transparent")
                }
                Rectangle {
                    visible: row.selected
                    width: 3; height: parent.height - 14; radius: 2
                    anchors.left: parent.left
                    anchors.leftMargin: 1
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.primary
                }
                Rectangle {
                    visible: !row.isSect && !row.selected && !rowArea.containsMouse
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.withAlpha(Theme.subtext, 0.07)
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => {
                        if (row.isSect) {
                            if (m.button === Qt.LeftButton) tb.toggleSect(row.key, row.expanded);
                            return;
                        }
                        tb.selKey = row.key;
                        tb.selRow = tb.snapshot(row.index);
                        if (m.button === Qt.RightButton) {
                            const p = mapToItem(tb, m.x, m.y);
                            tb.rowMenu(tb.selRow, p.x, p.y);
                        }
                    }
                    onDoubleClicked: (m) => { if (m.button === Qt.LeftButton && row.canExpand) tb.toggleExpanded(row.key); }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    spacing: 0

                    // seta + ícone + nome
                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: tb.nameMin - 10
                        Layout.fillHeight: true
                        clip: true

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: row.depth * 26
                            spacing: 8

                            Item {
                                width: 22; height: 24
                                anchors.verticalCenter: parent.verticalCenter
                                visible: tb.mode === "grouped"
                                Text {
                                    anchors.centerIn: parent
                                    visible: row.canExpand || row.isSect
                                    text: Theme.icons.chevronRight
                                    rotation: row.expanded ? 90 : 0
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 15
                                    color: Theme.subtext
                                    Behavior on rotation { NumberAnimation { duration: Theme.ms(120) } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: row.canExpand
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: tb.toggleExpanded(row.key)
                                }
                            }
                            Item {
                                width: 24; height: 24
                                anchors.verticalCenter: parent.verticalCenter
                                visible: row.kind === "grp"
                                Image {
                                    anchors.fill: parent
                                    visible: row.icon !== ""
                                    source: row.icon
                                    sourceSize: Qt.size(48, 48)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: row.icon === ""
                                    text: Theme.icons.chip
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 16
                                    color: Theme.withAlpha(Theme.subtext, 0.6)
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.isSect ? row.label + "  ·  " + row.sub : row.label
                                font.family: Theme.fontFamily
                                font.pixelSize: row.isSect ? tb.fs : tb.fs + 1
                                font.weight: row.isSect ? Font.Medium : Font.Normal
                                color: row.isSect ? Theme.primary
                                       : (row.suspended ? Theme.withAlpha(Theme.subtext, 0.8)
                                          : (row.depth > 0 ? Theme.subtext : Theme.textColor))
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !row.isSect && row.sub !== ""
                                text: row.sub
                                font.family: Theme.fontFamily
                                font.pixelSize: tb.fs - 1
                                color: Theme.withAlpha(Theme.subtext, 0.8)
                            }
                        }
                    }

                    Repeater {
                        model: row.isSect ? [] : tb.cols
                        delegate: Item {
                            id: mc
                            required property string modelData
                            readonly property bool num: tb.isNum(mc.modelData)
                            readonly property bool alignRight: tb.ctrl.colDef(mc.modelData).right
                            readonly property real v: mc.num ? row[mc.modelData] : 0
                            Layout.preferredWidth: tb.colW(mc.modelData)
                            Layout.fillHeight: true
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: 3
                                anchors.bottomMargin: 3
                                anchors.leftMargin: 2
                                anchors.rightMargin: 2
                                radius: 6
                                color: mc.num ? tb.heat(mc.modelData, mc.v) : "transparent"
                            }

                            // texto simples
                            Text {
                                visible: mc.modelData !== "gpuused"
                                anchors.right: mc.alignRight ? parent.right : undefined
                                anchors.left: mc.alignRight ? undefined : parent.left
                                anchors.rightMargin: 10
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, parent.width - 20)
                                elide: Text.ElideRight
                                text: tb.cellText(mc.modelData, row)
                                font.family: mc.modelData === "cmd" ? Theme.monoFamily : Theme.fontFamily
                                font.pixelSize: mc.modelData === "cmd" ? tb.fs - 1 : tb.fs
                                color: (mc.num && mc.v > 0) ? Theme.textColor
                                       : (mc.modelData === "status" ? Theme.warning : Theme.subtext)
                            }

                            // GPU usada: uma etiqueta por placa aberta; a que está
                            // trabalhando (maior uso) ganha a cor.
                            Row {
                                visible: mc.modelData === "gpuused"
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Repeater {
                                    model: row.devs === "" ? [] : row.devs.split(",")
                                    delegate: Rectangle {
                                        required property string modelData
                                        readonly property bool busy: row.gdev === modelData && row.gpu > 0
                                        width: tag.implicitWidth + 12
                                        height: 20
                                        radius: 10
                                        color: busy ? Theme.withAlpha(Theme.color2, 0.3) : Theme.withAlpha(Theme.subtext, 0.12)
                                        border.width: busy ? 1 : 0
                                        border.color: Theme.color2
                                        Text {
                                            id: tag
                                            anchors.centerIn: parent
                                            text: tb.devLabel(modelData)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            color: busy ? Theme.textColor : Theme.subtext
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Item { Layout.preferredWidth: 10 }
                }
            }
        }
    }
    }
}
