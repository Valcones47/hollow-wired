import QtQuick
import QtQuick.Layouts
import "."

// Conteúdo do Gerenciador de Tarefas, no desenho do Windows: barra lateral
// (Processos, Desempenho, Configurações), tabela com células coloridas pelo uso
// e subprocessos que abrem ao clicar no app. Os dados vêm do controlador
// (TaskManager.qml) pela propriedade `ctrl`.
Item {
    id: view

    property var ctrl
    property bool active: false
    property bool closeOnEscape: false
    signal closeRequested()

    property string tab: "processes"      // processes | performance | settings
    property string selRes: "cpu"
    property string sortKey: "mem"        // name | cpu | mem | swap | disk | gpu | vram
    property bool sortDesc: true
    property string selKey: ""
    property string selPids: ""
    property var expanded: ({})
    property var collapsed: ({})

    // ---------------------------------------------------------- colunas
    readonly property var colSpecs: [
        { id: "cpu",  w: 100 },
        { id: "mem",  w: 108 },
        { id: "swap", w: 100 },
        { id: "disk", w: 108 },
        { id: "gpu",  w: 100 },
        { id: "vram", w: 116 }
    ]
    readonly property var activeCols: view.ctrl ? view.colSpecs.filter(c => view.ctrl.settings.cols[c.id]) : []

    function colTitle(id) {
        switch (id) {
        case "cpu": return Theme.t("taskman.col_cpu", "CPU");
        case "mem": return Theme.t("taskman.col_mem", "Memória");
        case "swap": return "Swap";
        case "disk": return Theme.t("taskman.col_disk", "Disco");
        case "gpu": return "GPU";
        case "vram": return Theme.t("taskman.col_vram", "Mem. de vídeo");
        }
        return id;
    }
    function accent(id) {
        switch (id) {
        case "cpu": return Theme.primary;
        case "mem": return Theme.tertiary;
        case "swap": return Theme.color3;
        case "disk": return Theme.color12;
        case "gpu": return Theme.color2;
        case "vram": return Theme.color2;
        }
        return Theme.primary;
    }
    // 0..1: o quanto a célula pesa (a cor acompanha, como no Windows).
    function level(id, v) {
        let l = 0;
        const c = view.ctrl;
        switch (id) {
        case "cpu": l = v / 30; break;
        case "mem": l = c.mem.total > 0 ? v / (c.mem.total * 0.12) : 0; break;
        case "swap": l = v / 1073741824; break;
        case "disk": l = v / (30 * 1048576); break;
        case "gpu": l = v / 40; break;
        case "vram": l = v / 1073741824; break;
        }
        return Math.max(0, Math.min(1, l));
    }
    function heat(id, v) {
        if (!(v > 0)) return "transparent";
        const l = view.level(id, v);
        return Theme.withAlpha(l > 0.85 ? Theme.critical : view.accent(id), 0.07 + 0.5 * l);
    }
    function cell(id, v) {
        const c = view.ctrl;
        switch (id) {
        case "cpu": case "gpu": return c.fmtPct(v);
        case "mem": case "swap": case "vram": return v > 0 ? c.fmtBytes(v) : "0 MB";
        case "disk": return v > 0 ? c.fmtRate(v) : "0 MB/s";
        }
        return "";
    }
    // Total do cabeçalho de cada coluna (valor bruto na mesma unidade da célula).
    function total(id) {
        const c = view.ctrl;
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
        const c = view.ctrl;
        const v = view.total(id);
        switch (id) {
        case "cpu": case "gpu": case "disk": return c.fmtPct(v);
        case "mem": return c.mem.total > 0 ? c.fmtPct(v * 100 / c.mem.total) : "—";
        case "swap": return c.mem.swap_total > 0 ? c.fmtPct(v * 100 / c.mem.swap_total) : "—";
        case "vram": return v > 0 ? c.fmtBytes(v) : "—";
        }
        return "";
    }
    // O cabeçalho usa a mesma escala da célula: converte o total para ela.
    function totalHeat(id) {
        const c = view.ctrl;
        const v = view.total(id);
        if (id === "disk") return view.heat("disk", v / 100 * 30 * 1048576);
        return view.heat(id, v);
    }

    // ---------------------------------------------------------- linhas
    ListModel { id: lm }

    function sortVal(it, k) {
        if (k === "name") return it.label.toLowerCase();
        return it.g[k] || 0;
    }
    function cmpFor() {
        const k = view.sortKey, d = view.sortDesc ? -1 : 1;
        return (a, b) => {
            const x = view.sortVal(a, k), y = view.sortVal(b, k);
            let r = x < y ? -1 : x > y ? 1 : 0;
            if (r === 0) r = a.label.toLowerCase() < b.label.toLowerCase() ? -1 : 1;
            return r * d;
        };
    }

    function rebuild() {
        const c = view.ctrl;
        if (!c || !view.active) return;
        const q = search.text.trim().toLowerCase();
        const ap = [], bg = [];
        for (const g of c.groups) {
            const label = g.kind === "app" ? c.appLabel(g) : g.name;
            if (q) {
                let hit = label.toLowerCase().indexOf(q) >= 0 || g.name.toLowerCase().indexOf(q) >= 0;
                if (!hit) for (const p of g.procs) if (String(p[1]).toLowerCase().indexOf(q) >= 0) { hit = true; break; }
                if (!hit) continue;
            }
            (g.kind === "app" ? ap : bg).push({ g: g, label: label });
        }
        const cmp = view.cmpFor();
        ap.sort(cmp);
        bg.sort(cmp);

        const rows = [];
        const sect = (key, title, items) => {
            const closed = q ? false
                : (view.collapsed[key] !== undefined ? view.collapsed[key]
                   : (key === "sect:bg" ? !c.settings.bgOpen : false));
            rows.push({ key: key, kind: "sect", label: title, sub: String(items.length), icon: "",
                        expanded: !closed, pids: "", cpu: 0, mem: 0, swap: 0, disk: 0, gpu: 0, vram: 0,
                        gdev: "", n: items.length, depth: 0 });
            if (closed) return;
            for (const it of items) {
                const g = it.g;
                const open = !!view.expanded[g.key] && g.n > 1;
                rows.push({ key: g.key, kind: "grp", label: it.label, sub: g.n > 1 ? "(" + g.n + ")" : "",
                            icon: g.kind === "app" ? c.appIcon(g) : "", expanded: open,
                            pids: g.procs.map(p => p[0]).join(","),
                            cpu: g.cpu, mem: g.mem, swap: g.swap, disk: g.disk, gpu: g.gpu, vram: g.vram,
                            gdev: g.procs.reduce((a, p) => a || (p[8] || ""), ""), n: g.n, depth: 0 });
                if (!open) continue;
                const ps = g.procs.slice();
                const idx = { cpu: 2, mem: 3, swap: 4, disk: 5, gpu: 6, vram: 7 }[view.sortKey];
                ps.sort((a, b) => view.sortKey === "name"
                         ? (view.sortDesc ? -1 : 1) * String(a[1]).localeCompare(String(b[1]))
                         : (view.sortDesc ? -1 : 1) * (a[idx] - b[idx]));
                for (const p of ps) {
                    rows.push({ key: "proc:" + p[0], kind: "proc", label: String(p[1]), sub: "PID " + p[0], icon: "",
                                expanded: false, pids: String(p[0]), cpu: p[2], mem: p[3], swap: p[4], disk: p[5],
                                gpu: p[6], vram: p[7], gdev: p[8] || "", n: 1, depth: 1 });
                }
            }
        };
        sect("sect:apps", Theme.t("taskman.sect_apps", "Aplicativos"), ap);
        if (bg.length > 0) sect("sect:bg", Theme.t("taskman.sect_bg", "Processos em segundo plano"), bg);
        view.syncModel(rows);

        // a seleção some se o processo sumiu
        if (view.selKey !== "") {
            let found = false;
            for (let i = 0; i < lm.count; i++) if (lm.get(i).key === view.selKey) { found = true; view.selPids = lm.get(i).pids; break; }
            if (!found) { view.selKey = ""; view.selPids = ""; }
        }
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

    function toggleExpanded(key) {
        const e = Object.assign({}, view.expanded);
        e[key] = !e[key];
        view.expanded = e;
        view.rebuild();
    }
    function toggleSect(key, openNow) {
        const c = Object.assign({}, view.collapsed);
        c[key] = openNow;   // openNow = estava aberta -> fecha
        view.collapsed = c;
        view.rebuild();
    }
    function setSort(k) {
        if (view.sortKey === k) view.sortDesc = !view.sortDesc;
        else { view.sortKey = k; view.sortDesc = k !== "name"; }
        view.rebuild();
    }
    function endSelected() {
        if (view.selKey === "" || view.selPids === "") return;
        view.ctrl.endPids(view.selKey, view.selPids.split(",").map(x => parseInt(x)));
    }

    Connections {
        target: view.ctrl
        function onDataRevChanged() { view.rebuild(); }
        function onTabRequestChanged() {
            const t = view.ctrl.tabRequest;
            if (t === "processes" || t === "performance" || t === "settings") view.tab = t;
        }
    }
    onActiveChanged: {
        if (view.active) {
            search.text = "";
            view.selKey = ""; view.selPids = "";
            view.expanded = ({}); view.collapsed = ({});
            view.ctrl.asked = ({});
            search.forceActiveFocus();
            view.rebuild();
        } else {
            lm.clear();
        }
    }
    Keys.onEscapePressed: if (view.closeOnEscape) view.closeRequested()

    // ---------------------------------------------------------- componentes (só Theme)
    component NavItem: Rectangle {
        id: nav
        property string icon: ""
        property string label: ""
        property bool on: false
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredHeight: 42
        radius: 10
        color: nav.on ? Theme.withAlpha(Theme.primary, 0.16)
                      : (navArea.containsMouse ? Theme.withAlpha(Theme.tile, 0.8) : "transparent")
        Rectangle {
            visible: nav.on
            width: 3; height: 18; radius: 2
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.primary
        }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 16
            spacing: 12
            Text {
                text: nav.icon
                font.family: Theme.iconFontFamily
                font.pixelSize: 18
                color: nav.on ? Theme.primary : Theme.subtext
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: nav.label
                font.family: Theme.fontFamily
                font.pixelSize: 14
                color: nav.on ? Theme.textColor : Theme.subtext
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: navArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.clicked()
        }
    }

    component Switch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled(bool value)
        width: 40; height: 22; radius: 11
        color: sw.checked ? Theme.primary : Theme.withAlpha(Theme.subtext, 0.3)
        Behavior on color { ColorAnimation { duration: Theme.ms(120) } }
        Rectangle {
            width: 16; height: 16; radius: 8
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? parent.width - width - 3 : 3
            color: sw.checked ? Theme.background : Theme.textColor
            Behavior on x { NumberAnimation { duration: Theme.ms(120) } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled(!sw.checked)
        }
    }

    component SettingRow: RowLayout {
        id: sr
        property string title: ""
        property string desc: ""
        property bool checked: false
        signal toggled(bool value)
        Layout.fillWidth: true
        spacing: 16
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: sr.title
                font.family: Theme.fontFamily
                font.pixelSize: 14
                color: Theme.textColor
            }
            Text {
                Layout.fillWidth: true
                visible: sr.desc !== ""
                text: sr.desc
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.subtext
            }
        }
        Switch { checked: sr.checked; onToggled: (v) => sr.toggled(v) }
    }

    // ---------------------------------------------------------- layout
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- barra lateral
        Rectangle {
            Layout.preferredWidth: 196
            Layout.fillHeight: true
            color: Theme.withAlpha(Theme.tile, 0.5)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4

                NavItem {
                    icon: Theme.icons.apps
                    label: Theme.t("taskman.nav_procs", "Processos")
                    on: view.tab === "processes"
                    onClicked: view.tab = "processes"
                }
                NavItem {
                    icon: Theme.icons.performance
                    label: Theme.t("taskman.nav_perf", "Desempenho")
                    on: view.tab === "performance"
                    onClicked: view.tab = "performance"
                }
                Item { Layout.fillHeight: true }
                NavItem {
                    icon: Theme.icons.settings
                    label: Theme.t("taskman.nav_settings", "Configurações")
                    on: view.tab === "settings"
                    onClicked: view.tab = "settings"
                }
            }
        }

        // ---- conteúdo
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ====================== Processos
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12
                visible: view.tab === "processes"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: Theme.t("taskman.nav_procs", "Processos")
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        font.weight: Font.Medium
                        color: Theme.textColor
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredWidth: 240
                        Layout.preferredHeight: 34
                        radius: 10
                        color: Theme.withAlpha(Theme.tile, 0.9)
                        Text {
                            id: magnify
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.icons.magnify
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 15
                            color: Theme.subtext
                        }
                        TextInput {
                            id: search
                            anchors.fill: parent
                            anchors.leftMargin: 34
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.textColor
                            selectionColor: Theme.primary
                            selectedTextColor: Theme.background
                            clip: true
                            onTextChanged: view.rebuild()
                            Keys.onEscapePressed: if (view.closeOnEscape) view.closeRequested(); else text = ""
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 34
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text === ""
                            text: Theme.t("taskman.search", "Buscar processo")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.withAlpha(Theme.subtext, 0.8)
                        }
                    }
                    Rectangle {
                        id: endBtn
                        readonly property bool can: view.selKey !== "" && view.selKey.indexOf("sect:") !== 0
                        readonly property bool forced: !!(view.ctrl && view.ctrl.asked[view.selKey])
                        Layout.preferredWidth: endLabel.implicitWidth + 32
                        Layout.preferredHeight: 34
                        radius: 10
                        opacity: endBtn.can ? 1 : 0.4
                        color: endBtn.forced ? Theme.critical
                               : (endArea.containsMouse && endBtn.can ? Theme.primary : Theme.withAlpha(Theme.primary, 0.85))
                        Text {
                            id: endLabel
                            anchors.centerIn: parent
                            text: endBtn.forced ? Theme.t("taskman.force", "Forçar encerramento")
                                                : Theme.t("taskman.end_task", "Encerrar tarefa")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: Theme.background
                        }
                        MouseArea {
                            id: endArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: endBtn.can
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.endSelected()
                        }
                    }
                }

                // cabeçalho: nome + uma coluna por métrica, com o total em cima
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    Layout.minimumHeight: 52
                    Layout.maximumHeight: 52
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 10
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 32
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            text: Theme.t("taskman.col_name", "Nome") + (view.sortKey === "name" ? (view.sortDesc ? "  ▾" : "  ▴") : "")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: view.sortKey === "name" ? Theme.textColor : Theme.subtext
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.setSort("name")
                        }
                    }
                    Repeater {
                        model: view.activeCols
                        delegate: Rectangle {
                            id: hc
                            required property var modelData
                            Layout.preferredWidth: hc.modelData.w
                            Layout.fillHeight: true
                            color: view.totalHeat(hc.modelData.id)
                            Column {
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                Text {
                                    anchors.right: parent.right
                                    text: view.totalText(hc.modelData.id)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 17
                                    color: Theme.textColor
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: view.colTitle(hc.modelData.id)
                                          + (view.sortKey === hc.modelData.id ? (view.sortDesc ? "  ▾" : "  ▴") : "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: view.sortKey === hc.modelData.id ? Theme.textColor : Theme.subtext
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.setSort(hc.modelData.id)
                            }
                        }
                    }
                    Item { Layout.preferredWidth: 12 }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
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
                        required property string pids
                        required property real cpu
                        required property real mem
                        required property real swap
                        required property real disk
                        required property real gpu
                        required property real vram
                        required property string gdev
                        required property int n
                        required property int depth

                        readonly property bool isSect: kind === "sect"
                        readonly property bool selected: view.selKey === key
                        readonly property bool canExpand: kind === "grp" && n > 1
                        width: list.width
                        height: isSect ? 40 : 38

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: row.selected ? Theme.withAlpha(Theme.primary, 0.2)
                                   : (rowArea.containsMouse ? Theme.withAlpha(Theme.tile, 0.7) : "transparent")
                        }
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (row.isSect) view.toggleSect(row.key, row.expanded);
                                else { view.selKey = row.key; view.selPids = row.pids; }
                            }
                            onDoubleClicked: if (row.canExpand) view.toggleExpanded(row.key)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            spacing: 0

                            // seta (abre os subprocessos) + ícone + nome
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: row.depth * 24
                                    spacing: 8
                                    width: parent.width - row.depth * 24

                                    Item {
                                        width: 20; height: 24
                                        anchors.verticalCenter: parent.verticalCenter
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
                                            onClicked: view.toggleExpanded(row.key)
                                        }
                                    }
                                    Item {
                                        width: 22; height: 22
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: row.kind === "grp"
                                        Image {
                                            anchors.fill: parent
                                            visible: row.icon !== ""
                                            source: row.icon
                                            sourceSize: Qt.size(44, 44)
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: row.icon === ""
                                            text: Theme.icons.chip
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 15
                                            color: Theme.withAlpha(Theme.subtext, 0.6)
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, parent.width - 120)
                                        text: row.isSect ? row.label + " (" + row.sub + ")" : row.label
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: row.isSect ? 13 : 14
                                        font.weight: row.isSect ? Font.Medium : Font.Normal
                                        color: row.isSect ? Theme.primary : (row.depth > 0 ? Theme.subtext : Theme.textColor)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !row.isSect && row.sub !== ""
                                        text: row.sub
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.withAlpha(Theme.subtext, 0.8)
                                    }
                                }
                            }

                            Repeater {
                                model: row.isSect ? [] : view.activeCols
                                delegate: Rectangle {
                                    id: mc
                                    required property var modelData
                                    readonly property real v: row[mc.modelData.id]
                                    Layout.preferredWidth: mc.modelData.w
                                    Layout.fillHeight: true
                                    color: view.heat(mc.modelData.id, mc.v)
                                    Column {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text {
                                            anchors.right: parent.right
                                            text: view.cell(mc.modelData.id, mc.v)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            color: mc.v > 0 ? Theme.textColor : Theme.subtext
                                        }
                                        Text {
                                            anchors.right: parent.right
                                            visible: mc.modelData.id === "gpu" && row.gdev !== "" && mc.v > 0
                                            text: row.gdev === "nvidia" ? "NVIDIA" : "Intel"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.subtext
                                        }
                                    }
                                }
                            }
                            Item { Layout.preferredWidth: 12 }
                        }
                    }
                }
            }

            // ====================== Desempenho
            RowLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 20
                visible: view.tab === "performance"

                // blocos dos recursos
                Flickable {
                    Layout.preferredWidth: 270
                    Layout.fillHeight: true
                    contentHeight: resCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: resCol
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: view.ctrl ? view.ctrl.resKeys : []
                            delegate: Rectangle {
                                id: tile
                                required property string modelData
                                readonly property var info: view.ctrl.resInfo(tile.modelData, view.ctrl.dataRev)
                                readonly property bool on: view.selRes === tile.modelData
                                width: resCol.width
                                height: 76
                                radius: 10
                                color: tile.on ? Theme.withAlpha(tile.info.color, 0.16)
                                               : (tileArea.containsMouse ? Theme.withAlpha(Theme.tile, 0.8) : Theme.withAlpha(Theme.tile, 0.4))
                                Rectangle {
                                    visible: tile.on
                                    width: 3; height: parent.height - 24; radius: 2
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: tile.info.color
                                }
                                TaskGraph {
                                    id: mini
                                    anchors.left: parent.left
                                    anchors.leftMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 78; height: 50
                                    values: tile.info.series
                                    maxValue: tile.info.max
                                    color: tile.info.color
                                }
                                Column {
                                    anchors.left: mini.right
                                    anchors.leftMargin: 12
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        width: parent.width
                                        text: tile.info.title
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                        color: Theme.textColor
                                    }
                                    Text {
                                        width: parent.width
                                        text: tile.info.value
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.subtext
                                    }
                                }
                                MouseArea {
                                    id: tileArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: view.selRes = tile.modelData
                                }
                            }
                        }
                    }
                }

                // detalhe
                ColumnLayout {
                    id: detail
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10
                    readonly property var info: view.ctrl ? view.ctrl.resInfo(view.selRes, view.ctrl.dataRev)
                                                          : ({ title: "", sub: "", color: Theme.primary, series: [], max: 100, unit: "", stats: [] })

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: detail.info.title
                            font.family: Theme.fontFamily
                            font.pixelSize: 24
                            font.weight: Font.Medium
                            color: Theme.textColor
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            Layout.maximumWidth: detail.width * 0.6
                            text: detail.info.sub
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            color: Theme.subtext
                        }
                    }
                    Text {
                        text: detail.info.unit
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.subtext
                    }
                    TaskGraph {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 140
                        values: detail.info.series
                        maxValue: detail.info.max
                        color: detail.info.color
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 28
                        Repeater {
                            model: detail.info.stats
                            delegate: Column {
                                required property var modelData
                                spacing: 2
                                Text {
                                    text: modelData.k
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.subtext
                                }
                                Text {
                                    text: modelData.v
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 18
                                    color: Theme.textColor
                                }
                            }
                        }
                    }
                }
            }

            // ====================== Configurações
            Flickable {
                anchors.fill: parent
                anchors.margins: 20
                contentHeight: settingsCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: view.tab === "settings"

                ColumnLayout {
                    id: settingsCol
                    width: Math.min(parent.width, 640)
                    spacing: 16

                    Text {
                        text: Theme.t("taskman.nav_settings", "Configurações")
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        font.weight: Font.Medium
                        color: Theme.textColor
                    }

                    Text {
                        text: Theme.t("taskman.set_cols", "Colunas da lista de processos")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.subtext
                    }
                    Repeater {
                        model: view.colSpecs
                        delegate: SettingRow {
                            required property var modelData
                            title: view.colTitle(modelData.id)
                            checked: view.ctrl ? !!view.ctrl.settings.cols[modelData.id] : false
                            onToggled: (v) => { view.ctrl.setCol(modelData.id, v); view.rebuild(); }
                        }
                    }

                    Text {
                        Layout.topMargin: 8
                        text: Theme.t("taskman.set_general", "Geral")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.subtext
                    }
                    SettingRow {
                        title: Theme.t("taskman.set_bg", "Abrir \"Processos em segundo plano\" ao iniciar")
                        checked: view.ctrl ? !!view.ctrl.settings.bgOpen : false
                        onToggled: (v) => { view.ctrl.setSetting("bgOpen", v); view.collapsed = ({}); view.rebuild(); }
                    }
                    SettingRow {
                        title: Theme.t("taskman.set_nvidia", "Ler a GPU NVIDIA")
                        desc: Theme.t("taskman.set_nvidia_desc", "Só quando ela já está ativa: a placa em repouso nunca é acordada para a leitura.")
                        checked: view.ctrl ? !!view.ctrl.settings.nvidia : true
                        onToggled: (v) => view.ctrl.setSetting("nvidia", v)
                    }

                    Text {
                        Layout.topMargin: 8
                        text: Theme.t("taskman.set_interval", "Atualização")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.subtext
                    }
                    Row {
                        spacing: 8
                        Repeater {
                            model: [1, 2, 5]
                            delegate: Rectangle {
                                id: iv
                                required property int modelData
                                readonly property bool on: view.ctrl && view.ctrl.settings.interval === iv.modelData
                                width: 72; height: 34; radius: 10
                                color: iv.on ? Theme.withAlpha(Theme.primary, 0.2)
                                             : (ivArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.8))
                                border.width: iv.on ? 1 : 0
                                border.color: Theme.primary
                                Text {
                                    anchors.centerIn: parent
                                    text: iv.modelData + " s"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    color: iv.on ? Theme.textColor : Theme.subtext
                                }
                                MouseArea {
                                    id: ivArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: view.ctrl.setSetting("interval", iv.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
