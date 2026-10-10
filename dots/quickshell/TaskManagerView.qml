import QtQuick
import QtQuick.Layouts
import "."

// Conteúdo do Gerenciador de Tarefas, no desenho do Windows: barra lateral
// (Processos, Desempenho, Detalhes, Configurações), tabela com células
// coloridas pelo uso, subprocessos ao clicar no app e menu de clique direito.
// Os dados vêm do controlador (TaskManager.qml) pela propriedade `ctrl`.
Item {
    id: view

    property var ctrl
    property bool active: false
    property bool closeOnEscape: false
    signal closeRequested()

    property string tab: "processes"      // processes | details | performance | settings
    property string selRes: "cpu"
    property var menuRow: null

    readonly property bool onTable: view.tab === "processes" || view.tab === "details"

    function tr(k, f) { return Theme.t(k, f); }

    // ---------------------------------------------------------- resumo
    readonly property int appCount: {
        if (!view.ctrl) return 0;
        let n = 0;
        for (const g of view.ctrl.groups) if (g.kind === "app") n++;
        return n;
    }
    readonly property int procCount: view.ctrl ? view.ctrl.sys.procs : 0

    // ---------------------------------------------------------- ações
    function pidList(row) { return String(row.pids || "").split(",").filter(x => x !== "").map(x => parseInt(x)); }

    function endRow(row, force) {
        const pids = view.pidList(row);
        if (pids.length === 0) return;
        if (force) view.ctrl.sendSignal("KILL", pids);
        else view.ctrl.endPids(row.key, pids);
    }
    function endSelected() {
        const r = table.selRow;
        if (r && r.kind !== "sect") view.endRow(r, false);
    }

    function openRowMenu(row, x, y) {
        view.menuRow = row;
        const items = [];
        if (row.addr) items.push({ id: "focus", label: tr("taskman.m_goto", "Ir para a janela") }, { sep: true });
        items.push({ id: "end", label: tr("taskman.end_task", "Encerrar tarefa"), danger: true });
        items.push({ id: "kill", label: tr("taskman.force", "Forçar encerramento"), danger: true });
        if (row.kind === "proc" && row.pid > 0)
            items.push({ id: "tree", label: tr("taskman.m_tree", "Encerrar árvore de processos"), danger: true });
        items.push({ sep: true });
        items.push(row.pstate === "T"
                   ? { id: "resume", label: tr("taskman.m_resume", "Retomar") }
                   : { id: "suspend", label: tr("taskman.m_suspend", "Suspender") });
        items.push({ header: tr("taskman.m_prio", "Prioridade") });
        const opts = [[19, tr("taskman.p_lowest", "Muito baixa")], [10, tr("taskman.p_low", "Baixa")],
                      [0, tr("taskman.p_normal", "Normal")], [-5, tr("taskman.p_high", "Alta")]];
        const cur = row.nice;
        const curOpt = cur >= 15 ? 19 : (cur >= 5 ? 10 : (cur >= 0 ? 0 : -5));
        for (const o of opts)
            items.push({ id: "nice:" + o[0], label: o[1], checked: o[0] === curOpt, enabled: o[0] >= cur });
        items.push({ sep: true });
        if (row.exe) items.push({ id: "folder", label: tr("taskman.m_folder", "Abrir local do arquivo") });
        items.push({ id: "copypid", label: tr("taskman.m_copypid", "Copiar PID") });
        if (row.cmd) items.push({ id: "copycmd", label: tr("taskman.copy_cmd", "Copiar comando") });
        items.push({ id: "props", label: tr("taskman.m_props", "Propriedades") });
        ctxMenu.openAt(x, y, items);
    }

    function onRowAction(id) {
        const r = view.menuRow;
        if (!r) return;
        const c = view.ctrl;
        const pids = view.pidList(r);
        if (id === "focus") c.focusWindow(r.addr);
        else if (id === "end") view.endRow(r, false);
        else if (id === "kill") c.sendSignal("KILL", pids);
        else if (id === "tree") c.sendSignal("TERM", c.descendants(r.pid));
        else if (id === "suspend") c.sendSignal("STOP", pids);
        else if (id === "resume") c.sendSignal("CONT", pids);
        else if (id.indexOf("nice:") === 0) c.setNice(parseInt(id.slice(5)), pids);
        else if (id === "folder") c.openFolder(r.exe);
        else if (id === "copypid") c.copyText(r.kind === "proc" ? String(r.pid) : r.pids);
        else if (id === "copycmd") c.copyText(r.cmd);
        else if (id === "props") view.showProps(r);
    }

    function showProps(r) {
        const c = view.ctrl;
        const rows = [];
        const add = (k, v, mono) => { if (v !== "" && v !== undefined && v !== null) rows.push({ k: k, v: String(v), mono: !!mono }); };
        add(tr("taskman.col_name", "Nome"), r.label);
        if (r.kind === "proc") {
            add("PID", r.pid);
            add(tr("taskman.p_ppid", "PID pai"), r.ppid);
        } else {
            add(tr("taskman.col_n", "Processos"), r.n);
            add("PIDs", r.pids);
        }
        add(tr("taskman.col_status", "Status"), r.pstate === "T" ? tr("taskman.suspended", "Suspenso") : tr("taskman.running", "Em execução"));
        add("Threads", r.threads);
        add(tr("taskman.p_nice", "Prioridade (nice)"), r.nice);
        add("CPU", c.fmtPct(r.cpu));
        add(tr("taskman.col_mem", "Memória"), c.fmtBytes(r.mem));
        add("Swap", c.fmtBytes(r.swap));
        add(tr("taskman.col_disk", "Disco"), c.fmtRate(r.disk));
        add(tr("taskman.col_gpuused", "GPU usada"), r.devs === "" ? "—" : r.devs.split(",").map(d => table.devLabel(d)).join(", "));
        add(tr("taskman.p_exe", "Arquivo"), r.exe, true);
        add(tr("taskman.col_cmd", "Linha de comando"), r.cmd, true);
        props.title = r.label;
        props.rows = rows;
        props.show();
    }

    function openHeaderMenu(x, y) {
        const c = view.ctrl;
        const items = [{ header: tr("taskman.set_cols", "Colunas") }];
        for (const id of c.settings.colOrder) {
            if (c.colDef(id).modes.indexOf(table.mode) < 0) continue;
            items.push({ id: "col:" + id, label: c.colTitle(id), checked: !!c.settings.cols[id] });
        }
        items.push({ sep: true });
        items.push({ id: "heat", label: tr("taskman.set_heat", "Realçar células pelo uso"), checked: c.settings.heat !== false });
        items.push({ id: "reset", label: tr("taskman.set_reset", "Restaurar colunas padrão") });
        headerMenu.openAt(x, y, items);
    }
    function onHeaderAction(id) {
        const c = view.ctrl;
        if (id.indexOf("col:") === 0) {
            const k = id.slice(4);
            c.setCol(k, !c.settings.cols[k]);
        } else if (id === "heat") c.setSetting("heat", !(c.settings.heat !== false));
        else if (id === "reset") c.resetCols();
    }

    // ---------------------------------------------------------- ciclo de vida
    onActiveChanged: {
        if (view.active) {
            search.text = "";
            table.reset();
            view.ctrl.asked = ({});
            const st = view.ctrl.settings.startTab;
            if (st === "processes" || st === "details" || st === "performance" || st === "settings") view.tab = st;
            table.mode = view.tab === "details" ? "flat" : "grouped";
            table.active = view.onTable;
            search.forceActiveFocus();
        } else {
            table.active = false;
        }
    }
    onTabChanged: {
        if (view.tab === "processes") table.mode = "grouped";
        else if (view.tab === "details") {
            if (table.sortKey === "n") table.sortKey = "mem";
            table.mode = "flat";
        }
        table.active = view.active && view.onTable;
    }
    Connections {
        target: view.ctrl
        function onTabRequestChanged() {
            const t = view.ctrl.tabRequest;
            if (t === "processes" || t === "details" || t === "performance" || t === "settings") view.tab = t;
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

    // Escolha de uma opção entre poucas.
    component Seg: Row {
        id: sg
        property var options: []      // [{ v, t }]
        property var current: null
        signal picked(var v)
        spacing: 6
        Repeater {
            model: sg.options
            delegate: Rectangle {
                id: opt
                required property var modelData
                readonly property bool on: sg.current === opt.modelData.v
                width: optText.implicitWidth + 28
                height: 32
                radius: 10
                color: opt.on ? Theme.withAlpha(Theme.primary, 0.2)
                              : (optArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.8))
                border.width: opt.on ? 1 : 0
                border.color: Theme.primary
                Text {
                    id: optText
                    anchors.centerIn: parent
                    text: opt.modelData.t
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: opt.on ? Theme.textColor : Theme.subtext
                }
                MouseArea {
                    id: optArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sg.picked(opt.modelData.v)
                }
            }
        }
    }

    component SmallBtn: Rectangle {
        id: sb
        property string text: ""
        property bool enabledBtn: true
        signal clicked()
        width: Math.max(30, sbText.implicitWidth + 18)
        height: 28
        radius: 8
        opacity: sb.enabledBtn ? 1 : 0.35
        color: sbArea.containsMouse && sb.enabledBtn ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.8)
        Text {
            id: sbText
            anchors.centerIn: parent
            text: sb.text
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: Theme.textColor
        }
        MouseArea {
            id: sbArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: sb.enabledBtn
            cursorShape: Qt.PointingHandCursor
            onClicked: sb.clicked()
        }
    }

    component SectionLabel: Text {
        Layout.topMargin: 10
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
        color: Theme.primary
    }

    component FieldLabel: Text {
        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: Theme.subtext
    }

    // ---------------------------------------------------------- layout
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- barra lateral
        Rectangle {
            Layout.preferredWidth: 228
            Layout.fillHeight: true
            color: Theme.withAlpha(Theme.tile, 0.5)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4

                // identidade + resumo ao vivo
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 14
                    Layout.topMargin: 4
                    spacing: 10
                    Rectangle {
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 38
                        radius: 11
                        color: Theme.withAlpha(Theme.primary, 0.18)
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icons.performance
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 20
                            color: Theme.primary
                        }
                    }
                    Column {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            width: parent.width
                            text: view.tr("taskman.title", "Gerenciador de Tarefas")
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: Theme.textColor
                        }
                        Text {
                            width: parent.width
                            text: view.ctrl ? view.ctrl.fmtPct(view.ctrl.sys.cpu) + " CPU  ·  "
                                              + (view.ctrl.mem.total > 0 ? view.ctrl.fmtPct(view.ctrl.mem.used * 100 / view.ctrl.mem.total) : "—") + " RAM" : ""
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.subtext
                        }
                    }
                }

                NavItem {
                    icon: Theme.icons.apps
                    label: view.tr("taskman.nav_procs", "Processos")
                    on: view.tab === "processes"
                    onClicked: view.tab = "processes"
                }
                NavItem {
                    icon: Theme.icons.performance
                    label: view.tr("taskman.nav_perf", "Desempenho")
                    on: view.tab === "performance"
                    onClicked: view.tab = "performance"
                }
                NavItem {
                    icon: Theme.icons.console
                    label: view.tr("taskman.nav_details", "Detalhes")
                    on: view.tab === "details"
                    onClicked: view.tab = "details"
                }
                Item { Layout.fillHeight: true }
                NavItem {
                    icon: Theme.icons.settings
                    label: view.tr("taskman.nav_settings", "Configurações")
                    on: view.tab === "settings"
                    onClicked: view.tab = "settings"
                }
            }
        }

        // ---- conteúdo
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ====================== Processos / Detalhes
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                anchors.bottomMargin: 12
                spacing: 12
                visible: view.onTable

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Column {
                        spacing: 2
                        Text {
                            text: view.tab === "details" ? view.tr("taskman.nav_details", "Detalhes")
                                                         : view.tr("taskman.nav_procs", "Processos")
                            font.family: Theme.fontFamily
                            font.pixelSize: 22
                            font.weight: Font.Medium
                            color: Theme.textColor
                        }
                        Text {
                            text: view.tab === "details"
                                  ? view.tr("taskman.procs_n", "%1 processos").replace("%1", view.procCount)
                                  : view.tr("taskman.apps_n", "%1 aplicativos").replace("%1", view.appCount)
                                    + "  ·  " + view.tr("taskman.procs_n", "%1 processos").replace("%1", view.procCount)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.subtext
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredWidth: 250
                        Layout.preferredHeight: 36
                        radius: 10
                        color: Theme.withAlpha(Theme.tile, 0.9)
                        Text {
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
                            onTextChanged: table.query = text
                            Keys.onEscapePressed: if (view.closeOnEscape) view.closeRequested(); else text = ""
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 34
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text === ""
                            text: view.tr("taskman.search", "Buscar processo")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.withAlpha(Theme.subtext, 0.8)
                        }
                    }
                    Rectangle {
                        id: endBtn
                        readonly property bool can: table.selRow !== null && table.selRow.kind !== "sect"
                        readonly property bool forced: !!(view.ctrl && table.selRow && view.ctrl.asked[table.selRow.key])
                        Layout.preferredWidth: endLabel.implicitWidth + 32
                        Layout.preferredHeight: 36
                        radius: 10
                        opacity: endBtn.can ? 1 : 0.4
                        color: endBtn.forced ? Theme.critical
                               : (endArea.containsMouse && endBtn.can ? Theme.primary : Theme.withAlpha(Theme.primary, 0.85))
                        Text {
                            id: endLabel
                            anchors.centerIn: parent
                            text: endBtn.forced ? view.tr("taskman.force", "Forçar encerramento")
                                                : view.tr("taskman.end_task", "Encerrar tarefa")
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

                TaskTable {
                    id: table
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ctrl: view.ctrl
                    onRowMenu: (row, x, y) => {
                        const p = table.mapToItem(view, x, y);
                        view.openRowMenu(row, p.x, p.y);
                    }
                    onHeaderMenu: (x, y) => {
                        const p = table.mapToItem(view, x, y);
                        view.openHeaderMenu(p.x, p.y);
                    }
                }

                // barra de estado: como estão as GPUs (qual está ativa)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    spacing: 18
                    Repeater {
                        model: view.ctrl ? view.ctrl.gpus : []
                        delegate: Row {
                            required property var modelData
                            required property int index
                            spacing: 6
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.state === "active" && modelData.util !== null && modelData.util > 1
                                       ? Theme.color2 : Theme.withAlpha(Theme.subtext, 0.5)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "GPU " + index + "  " + modelData.name + "  ·  "
                                      + (modelData.state === "suspended" ? view.tr("taskman.gpu_rest_short", "Em repouso")
                                         : (modelData.state === "off" ? view.tr("taskman.gpu_off_short", "Leitura desligada")
                                            : (modelData.util === null ? "—" : view.ctrl.fmtPct(modelData.util))))
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.subtext
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: view.tr("taskman.hint", "Clique direito: mais ações  ·  seta: subprocessos")
                        visible: view.tab === "processes"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.withAlpha(Theme.subtext, 0.75)
                    }
                }
            }

            // ====================== Desempenho
            RowLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 22
                visible: view.tab === "performance"

                Flickable {
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true
                    contentHeight: resCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: resCol
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: view.ctrl ? view.ctrl.visibleResKeys : []
                            delegate: Rectangle {
                                id: tile
                                required property string modelData
                                readonly property var info: view.ctrl.resInfo(tile.modelData, view.ctrl.dataRev)
                                readonly property bool on: view.selRes === tile.modelData
                                width: resCol.width
                                height: 78
                                radius: 12
                                color: tile.on ? Theme.withAlpha(tile.info.color, 0.16)
                                               : (tileArea.containsMouse ? Theme.withAlpha(Theme.tile, 0.85) : Theme.withAlpha(Theme.tile, 0.45))
                                border.width: tile.on ? 1 : 0
                                border.color: Theme.withAlpha(tile.info.color, 0.7)
                                TaskGraph {
                                    id: mini
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 80; height: 52
                                    compact: true
                                    values: tile.info.series
                                    points: tile.info.points
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

                // detalhe do recurso escolhido
                Flickable {
                    id: detailScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: detail.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: detail
                        width: detailScroll.width
                        spacing: 12
                        readonly property var info: view.ctrl ? view.ctrl.resInfo(view.selRes, view.ctrl.dataRev)
                                                              : ({ title: "", sub: "", color: Theme.primary, series: [], points: 60,
                                                                   max: 100, unit: "", stats: [], users: [] })
                        readonly property real seriesMax: {
                            let m = 0;
                            for (const x of detail.info.series) if (x > m) m = x;
                            return m * 1.15;
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: detail.info.title
                                font.family: Theme.fontFamily
                                font.pixelSize: 26
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
                            Layout.preferredHeight: Math.max(170, detailScroll.height * 0.42)
                            values: detail.info.series
                            points: detail.info.points
                            maxValue: detail.info.max
                            color: detail.info.color
                            topLabel: detail.info.max === 100 ? "100 %" : (view.ctrl ? view.ctrl.fmtRate(detail.seriesMax) : "")
                            bottomLeftLabel: view.ctrl ? view.ctrl.settings.graphWindow + " s" : ""
                            bottomRightLabel: "0"
                        }
                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            spacing: 30
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
                                        font.pixelSize: 19
                                        color: Theme.textColor
                                    }
                                }
                            }
                        }

                        // quem está usando esta GPU
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            spacing: 2
                            visible: !!detail.info.users && detail.info.users.length > 0
                            Text {
                                text: view.tr("taskman.gpu_users", "Aplicativos usando esta GPU")
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: Theme.primary
                            }
                            Repeater {
                                model: detail.info.users || []
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        color: Theme.textColor
                                    }
                                    Text {
                                        text: modelData.vram > 0 ? view.ctrl.fmtBytes(modelData.vram) : ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.subtext
                                    }
                                    Text {
                                        Layout.preferredWidth: 64
                                        horizontalAlignment: Text.AlignRight
                                        text: view.ctrl.fmtPct(modelData.pct)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        color: modelData.pct > 0 ? Theme.textColor : Theme.subtext
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ====================== Configurações
            Flickable {
                id: setScroll
                anchors.fill: parent
                anchors.margins: 22
                contentHeight: settingsCol.implicitHeight + 20
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: view.tab === "settings"

                ColumnLayout {
                    id: settingsCol
                    width: Math.min(setScroll.width, 700)
                    spacing: 12

                    Text {
                        text: view.tr("taskman.nav_settings", "Configurações")
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        font.weight: Font.Medium
                        color: Theme.textColor
                    }

                    // ---- aparência
                    SectionLabel { text: view.tr("taskman.set_look", "Aparência") }
                    FieldLabel { text: view.tr("taskman.set_density", "Densidade das linhas") }
                    Seg {
                        options: [{ v: "compact", t: view.tr("taskman.d_compact", "Compacta") },
                                  { v: "normal", t: view.tr("taskman.d_normal", "Normal") },
                                  { v: "comfortable", t: view.tr("taskman.d_comfortable", "Confortável") }]
                        current: view.ctrl ? view.ctrl.settings.density : "normal"
                        onPicked: (v) => view.ctrl.setSetting("density", v)
                    }
                    FieldLabel { text: view.tr("taskman.set_fontsize", "Tamanho do texto da tabela") }
                    Seg {
                        options: [{ v: "small", t: view.tr("taskman.f_small", "Pequeno") },
                                  { v: "normal", t: view.tr("taskman.f_normal", "Normal") },
                                  { v: "large", t: view.tr("taskman.f_large", "Grande") }]
                        current: view.ctrl ? view.ctrl.settings.fontSize : "normal"
                        onPicked: (v) => view.ctrl.setSetting("fontSize", v)
                    }
                    SettingRow {
                        title: view.tr("taskman.set_heat", "Realçar células pelo uso")
                        desc: view.tr("taskman.set_heat_desc", "A cor da célula acompanha o peso do processo, como no Windows.")
                        checked: view.ctrl ? view.ctrl.settings.heat !== false : true
                        onToggled: (v) => view.ctrl.setSetting("heat", v)
                    }

                    // ---- colunas
                    SectionLabel { text: view.tr("taskman.set_cols", "Colunas") }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: view.tr("taskman.set_cols_hint", "Use as setas para mudar a ordem. Na tabela, arraste a borda esquerda do cabeçalho para ajustar a largura e clique com o botão direito no cabeçalho para escolher colunas.")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.subtext
                    }
                    Repeater {
                        model: view.ctrl ? view.ctrl.settings.colOrder : []
                        delegate: RowLayout {
                            id: cr
                            required property string modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 12
                            Switch {
                                checked: view.ctrl ? !!view.ctrl.settings.cols[cr.modelData] : false
                                onToggled: (v) => view.ctrl.setCol(cr.modelData, v)
                            }
                            Text {
                                Layout.fillWidth: true
                                text: view.ctrl ? view.ctrl.colTitle(cr.modelData) : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                color: Theme.textColor
                            }
                            Text {
                                text: {
                                    if (!view.ctrl) return "";
                                    const m = view.ctrl.colDef(cr.modelData).modes;
                                    return m.length === 2 ? view.tr("taskman.in_both", "Processos e Detalhes")
                                         : (m[0] === "flat" ? view.tr("taskman.nav_details", "Detalhes")
                                                            : view.tr("taskman.nav_procs", "Processos"));
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.subtext
                            }
                            SmallBtn { text: "↑"; enabledBtn: cr.index > 0; onClicked: view.ctrl.moveCol(cr.modelData, -1) }
                            SmallBtn {
                                text: "↓"
                                enabledBtn: view.ctrl && cr.index < view.ctrl.settings.colOrder.length - 1
                                onClicked: view.ctrl.moveCol(cr.modelData, 1)
                            }
                        }
                    }
                    SmallBtn {
                        text: view.tr("taskman.set_reset", "Restaurar colunas padrão")
                        onClicked: view.ctrl.resetCols()
                    }

                    // ---- desempenho
                    SectionLabel { text: view.tr("taskman.nav_perf", "Desempenho") }
                    FieldLabel { text: view.tr("taskman.set_window", "Janela de tempo do gráfico") }
                    Seg {
                        options: [{ v: 30, t: "30 s" }, { v: 60, t: "60 s" }, { v: 120, t: "120 s" }]
                        current: view.ctrl ? view.ctrl.settings.graphWindow : 60
                        onPicked: (v) => view.ctrl.setSetting("graphWindow", v)
                    }
                    FieldLabel { text: view.tr("taskman.set_resources", "Recursos mostrados") }
                    Repeater {
                        model: view.ctrl ? view.ctrl.resKeys : []
                        delegate: SettingRow {
                            required property string modelData
                            title: view.ctrl ? view.ctrl.resInfo(modelData, view.ctrl.dataRev).title : modelData
                            checked: view.ctrl ? view.ctrl.settings.resHidden.indexOf(modelData) < 0 : true
                            onToggled: (v) => view.ctrl.toggleRes(modelData, v)
                        }
                    }

                    // ---- geral
                    SectionLabel { text: view.tr("taskman.set_general", "Geral") }
                    FieldLabel { text: view.tr("taskman.set_starttab", "Aba inicial") }
                    Seg {
                        options: [{ v: "processes", t: view.tr("taskman.nav_procs", "Processos") },
                                  { v: "performance", t: view.tr("taskman.nav_perf", "Desempenho") },
                                  { v: "details", t: view.tr("taskman.nav_details", "Detalhes") }]
                        current: view.ctrl ? view.ctrl.settings.startTab : "processes"
                        onPicked: (v) => view.ctrl.setSetting("startTab", v)
                    }
                    SettingRow {
                        title: view.tr("taskman.set_bg", "Abrir \"Processos em segundo plano\" ao iniciar")
                        checked: view.ctrl ? !!view.ctrl.settings.bgOpen : false
                        onToggled: (v) => { view.ctrl.setSetting("bgOpen", v); table.collapsed = ({}); table.rebuild(); }
                    }
                    SettingRow {
                        title: view.tr("taskman.set_nvidia", "Ler a GPU NVIDIA")
                        desc: view.tr("taskman.set_nvidia_desc", "Só quando ela já está ativa: a placa em repouso nunca é acordada para a leitura.")
                        checked: view.ctrl ? !!view.ctrl.settings.nvidia : true
                        onToggled: (v) => view.ctrl.setSetting("nvidia", v)
                    }
                    FieldLabel { text: view.tr("taskman.set_interval", "Atualização") }
                    Seg {
                        options: [{ v: 1, t: "1 s" }, { v: 2, t: "2 s" }, { v: 5, t: "5 s" }]
                        current: view.ctrl ? view.ctrl.settings.interval : 2
                        onPicked: (v) => view.ctrl.setSetting("interval", v)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- menus e diálogos
    TaskMenu { id: ctxMenu; onChosen: (id) => view.onRowAction(id) }
    TaskMenu { id: headerMenu; onChosen: (id) => view.onHeaderAction(id) }
    TaskProps {
        id: props
        onCopyCommand: if (view.menuRow) view.ctrl.copyText(view.menuRow.cmd)
    }
}
