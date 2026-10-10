import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Monitor do sistema do rice: aplicativos abertos com CPU e memória, busca e
// "Encerrar". Quem lê os processos é o `rice-procs watch`, que só roda com a
// janela aberta: fechar encerra o processo e esvazia a lista (não fica nada
// em segundo plano).
//
// Dois modos, mesmo conteúdo:
//   window — cartão no centro com fundo escurecido (Super + Esc);
//   drop   — desce do topo como o terminal drop-down, sem escurecer a tela
//            (Super + Shift + '). Apertar de novo fecha por completo.
PanelWindow {
    id: tm

    property bool open: false
    property string mode: "window"       // window | drop
    property string query: ""
    property string sortKey: "mem"       // name | cpu | mem
    property bool sortDesc: true
    property bool showBg: false
    property var asked: ({})             // key -> já pediu TERM (próximo clique força)
    property var stat: ({ cpu: 0, temp: null, memUsed: 0, memTotal: 0, swapUsed: 0, swapTotal: 0 })
    property var groups: []
    property real slide: tm.open ? 1 : 0
    Behavior on slide { NumberAnimation { duration: Theme.ms(180); easing.type: Easing.OutCubic } }

    readonly property int colCpu: 92
    readonly property int colMem: 108
    readonly property int colAct: 104

    function openWindow() {
        if (tm.open && tm.mode === "window") { tm.open = false; return; }
        tm.mode = "window";
        tm.open = true;
    }
    function openDrop() {
        if (tm.open && tm.mode === "drop") { tm.open = false; return; }
        tm.mode = "drop";
        tm.open = true;
    }

    // ---------------------------------------------------------- dados
    Process {
        id: feed
        running: tm.open
        command: ["rice-procs", "watch", "2"]
        stdout: SplitParser { onRead: (line) => tm.ingest(line) }
    }

    function ingest(line) {
        let d = null;
        try { d = JSON.parse(line); } catch (e) { return; }
        tm.stat = { cpu: d.cpu, temp: d.temp, memUsed: d.mem_used, memTotal: d.mem_total,
                    swapUsed: d.swap_used, swapTotal: d.swap_total };
        tm.groups = d.groups;
        tm.rebuild();
    }

    property var _names: ({})
    function appLabel(g) {
        const k = g.cls;
        if (tm._names[k] === undefined) {
            let name = k;
            try {
                const e = DockConfig.entryForWindow(k, g.title);
                if (e && e.name) name = e.name;
            } catch (e) {}
            tm._names[k] = name;
        }
        return tm._names[k];
    }

    function cmp(a, b) {
        let r;
        if (tm.sortKey === "name") r = a.label.localeCompare(b.label);
        else r = a[tm.sortKey] - b[tm.sortKey];
        if (r === 0) r = a.label.localeCompare(b.label);
        return tm.sortDesc ? -r : r;
    }

    function rebuild() {
        const q = tm.query.trim().toLowerCase();
        const apps = [], bg = [];
        for (const g of tm.groups) {
            const label = g.kind === "app" ? tm.appLabel(g) : g.name;
            if (q && label.toLowerCase().indexOf(q) < 0 && g.name.toLowerCase().indexOf(q) < 0) continue;
            let sub = "";
            if (g.kind === "app") {
                sub = (g.wins === 1 ? Theme.t("taskman.window_one", "1 janela")
                                    : Theme.t("taskman.windows_n", "%1 janelas").replace("%1", g.wins));
                sub += " · ";
            }
            sub += (g.n === 1 ? Theme.t("taskman.proc_one", "1 processo")
                              : Theme.t("taskman.procs_n", "%1 processos").replace("%1", g.n));
            let icon = "";
            if (g.kind === "app") {
                try { icon = String(DockConfig.iconForWindow(g.cls, g.title) || ""); } catch (e) {}
            }
            (g.kind === "app" ? apps : bg).push({
                key: g.key, kind: g.kind, label: label, sub: sub, icon: icon,
                pids: g.pids, cpu: g.cpu, mem: g.mem, n: g.n
            });
        }
        apps.sort(tm.cmp);
        bg.sort(tm.cmp);
        const rows = apps;
        if (bg.length > 0) {
            rows.push({ key: "head:bg", kind: "head", label: Theme.t("taskman.background", "Em segundo plano"),
                        sub: String(bg.length), icon: "", pids: "", cpu: 0, mem: 0, n: bg.length });
            if (tm.showBg || q) for (const r of bg) rows.push(r);
        }
        tm.syncModel(rows);
    }

    // Atualiza o ListModel no lugar (reatribuir um array recriaria todos os
    // delegates a cada 2 s: perde o hover e pisca).
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

    function endApp(key, pids) {
        const force = !!tm.asked[key];
        Quickshell.execDetached(["rice-procs", "kill", force ? "KILL" : "TERM"].concat(pids.split(",")));
        const a = Object.assign({}, tm.asked);
        a[key] = true;
        tm.asked = a;
    }

    function fmtBytes(b) {
        const pt = String(Theme.locale || "").indexOf("pt") === 0;
        let v, u;
        if (b >= 1073741824) { v = (b / 1073741824).toFixed(1); u = " GB"; }
        else { v = String(Math.round(b / 1048576)); u = " MB"; }
        return (pt ? v.replace(".", ",") : v) + u;
    }
    function fmtPct(p) {
        const pt = String(Theme.locale || "").indexOf("pt") === 0;
        const v = p >= 10 ? String(Math.round(p)) : p.toFixed(1);
        return (pt ? v.replace(".", ",") : v) + " %";
    }

    function setSort(k) {
        if (tm.sortKey === k) tm.sortDesc = !tm.sortDesc;
        else { tm.sortKey = k; tm.sortDesc = k !== "name"; }
        tm.rebuild();
    }

    ListModel { id: lm }

    // ---------------------------------------------------------- janela
    visible: tm.open || tm.slide > 0.001
    color: "transparent"
    focusable: true
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-taskmanager"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: tm.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    // No modo drop só o cartão recebe clique; o resto da tela segue com as janelas.
    mask: tm.mode === "drop" ? dropMask : null
    Region { id: dropMask; item: card }

    property var targetScreen: null
    screen: targetScreen || Theme.primaryScreen
    readonly property bool _openForScreen: tm.open
    on_OpenForScreenChanged: if (_openForScreen) targetScreen = Theme.focusedScreen()

    onOpenChanged: {
        if (tm.open) {
            tm.query = "";
            searchField.text = "";
            tm.asked = ({});
            searchField.forceActiveFocus();
        }
    }
    onSlideChanged: {
        if (tm.slide < 0.001 && !tm.open) {
            lm.clear();
            tm.groups = [];
            tm.showBg = false;
        }
    }

    // ---------------------------------------------------------- fundo (modo janela)
    Rectangle {
        anchors.fill: parent
        visible: tm.mode === "window"
        color: Qt.rgba(0, 0, 0, 0.6 * tm.slide)
        MouseArea { anchors.fill: parent; onClicked: tm.open = false }
    }

    // ---------------------------------------------------------- cartão
    Rectangle {
        id: card
        readonly property bool drop: tm.mode === "drop"
        width: drop ? Math.min(1100, parent.width * 0.64) : Math.min(900, parent.width - 80)
        height: drop ? Math.min(parent.height * 0.62, 640) : Math.min(660, parent.height - 100)
        x: Math.round((parent.width - width) / 2)
        y: drop ? Math.round(Theme.waybarHeight + 10 - (height + Theme.waybarHeight + 10) * (1 - tm.slide))
                : Math.round((parent.height - height) / 2)
        opacity: drop ? 1 : tm.slide
        radius: 18
        color: Theme.background
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.35)
        focus: true
        Keys.onEscapePressed: tm.open = false
        MouseArea { anchors.fill: parent }   // não fecha ao clicar dentro

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            // ---- título, busca, fechar
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: Theme.t("taskman.title", "Monitor do sistema")
                    font.family: Theme.fontFamily
                    font.pixelSize: 17
                    font.weight: Font.Medium
                    color: Theme.textColor
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.preferredWidth: 240
                    Layout.preferredHeight: 32
                    radius: 10
                    color: Theme.withAlpha(Theme.tile, 0.8)
                    TextInput {
                        id: searchField
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textColor
                        selectionColor: Theme.primary
                        selectedTextColor: Theme.background
                        clip: true
                        onTextChanged: { tm.query = text; tm.rebuild(); }
                        Keys.onEscapePressed: tm.open = false
                    }
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        visible: searchField.text === ""
                        text: Theme.t("taskman.search", "Buscar aplicativo")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.withAlpha(Theme.subtext, 0.8)
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 10
                    color: closeArea.containsMouse ? Theme.tileHigh : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: Theme.icons.close
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 15
                        color: Theme.subtext
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tm.open = false
                    }
                }
            }

            // ---- totais: texto com uma barra fina, sem caixas
            RowLayout {
                Layout.fillWidth: true
                spacing: 28

                component Total: ColumnLayout {
                    id: tot
                    property string label: ""
                    property string value: ""
                    property real fraction: 0
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: tot.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.subtext
                    }
                    Text {
                        text: tot.value
                        font.family: Theme.fontFamily
                        font.pixelSize: 19
                        color: Theme.textColor
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 3
                        radius: 2
                        color: Theme.withAlpha(Theme.subtext, 0.22)
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, tot.fraction))
                            height: parent.height
                            radius: 2
                            color: Theme.primary
                            Behavior on width { NumberAnimation { duration: Theme.ms(300) } }
                        }
                    }
                }

                Total {
                    label: Theme.t("taskman.col_cpu", "Processador")
                    value: tm.fmtPct(tm.stat.cpu) + (tm.stat.temp !== null && tm.stat.temp !== undefined
                           ? "  ·  " + tm.stat.temp + " °C" : "")
                    fraction: tm.stat.cpu / 100
                }
                Total {
                    label: Theme.t("taskman.col_mem", "Memória")
                    value: tm.fmtBytes(tm.stat.memUsed) + " " + Theme.t("taskman.of", "de") + " " + tm.fmtBytes(tm.stat.memTotal)
                    fraction: tm.stat.memTotal > 0 ? tm.stat.memUsed / tm.stat.memTotal : 0
                }
                Total {
                    visible: tm.stat.swapTotal > 0
                    label: "Swap"
                    value: tm.fmtBytes(tm.stat.swapUsed) + " " + Theme.t("taskman.of", "de") + " " + tm.fmtBytes(tm.stat.swapTotal)
                    fraction: tm.stat.swapTotal > 0 ? tm.stat.swapUsed / tm.stat.swapTotal : 0
                }
            }

            // ---- cabeçalho das colunas (clicável: ordena)
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                spacing: 0

                // Componente inline não enxerga os ids do arquivo: o estado de
                // ordenação entra por propriedade e o clique sai por sinal.
                component Head: Text {
                    id: hd
                    property string text0: ""
                    property bool on: false
                    property bool desc: true
                    property bool alignRight: true
                    signal activated()
                    text: hd.text0 + (hd.on ? (hd.desc ? "  ▾" : "  ▴") : "")
                    horizontalAlignment: hd.alignRight ? Text.AlignRight : Text.AlignLeft
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: hd.on ? Theme.textColor : Theme.subtext
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: hd.activated()
                    }
                }

                Head {
                    Layout.fillWidth: true
                    Layout.leftMargin: 36
                    alignRight: false
                    text0: Theme.t("taskman.col_app", "Aplicativo")
                    on: tm.sortKey === "name"; desc: tm.sortDesc
                    onActivated: tm.setSort("name")
                }
                Head {
                    Layout.preferredWidth: tm.colCpu
                    text0: Theme.t("taskman.col_cpu", "Processador")
                    on: tm.sortKey === "cpu"; desc: tm.sortDesc
                    onActivated: tm.setSort("cpu")
                }
                Head {
                    Layout.preferredWidth: tm.colMem
                    text0: Theme.t("taskman.col_mem", "Memória")
                    on: tm.sortKey === "mem"; desc: tm.sortDesc
                    onActivated: tm.setSort("mem")
                }
                Item { Layout.preferredWidth: tm.colAct }
            }

            // ---- lista
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: lm
                spacing: 2
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
                    required property string pids
                    required property real cpu
                    required property real mem
                    readonly property bool isHead: kind === "head"
                    readonly property bool hot: rowArea.containsMouse || endArea.containsMouse
                    width: list.width
                    height: isHead ? 34 : 46

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: row.hot ? Theme.withAlpha(Theme.tile, 0.7) : "transparent"
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: row.isHead ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (row.isHead) { tm.showBg = !tm.showBg; tm.rebuild(); }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 0

                        // ícone do app (ou um ponto discreto no segundo plano)
                        Item {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            Layout.rightMargin: 12
                            visible: !row.isHead
                            Image {
                                anchors.fill: parent
                                visible: row.kind === "app" && row.icon !== ""
                                source: row.icon
                                sourceSize: Qt.size(48, 48)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !(row.kind === "app" && row.icon !== "")
                                text: Theme.icons.apps
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 16
                                color: Theme.withAlpha(Theme.subtext, 0.6)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: row.isHead ? row.label + "  ·  " + row.sub : row.label
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: row.isHead ? 12 : 14
                                color: row.isHead ? Theme.subtext : Theme.textColor
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: !row.isHead && row.kind === "app"
                                text: row.sub
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.withAlpha(Theme.subtext, 0.85)
                            }
                        }

                        Text {
                            visible: !row.isHead
                            Layout.preferredWidth: tm.colCpu
                            horizontalAlignment: Text.AlignRight
                            text: tm.fmtPct(row.cpu)
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: row.cpu >= 25 ? Theme.textColor : Theme.subtext
                        }
                        Text {
                            visible: !row.isHead
                            Layout.preferredWidth: tm.colMem
                            horizontalAlignment: Text.AlignRight
                            text: tm.fmtBytes(row.mem)
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.textColor
                        }

                        // Encerrar: aparece ao passar o mouse; depois do primeiro
                        // pedido vira "Forçar" (SIGKILL) e fica visível.
                        Item {
                            Layout.preferredWidth: tm.colAct
                            Layout.preferredHeight: 28
                            visible: !row.isHead
                            readonly property bool forced: !!tm.asked[row.key]
                            Rectangle {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: endLabel.implicitWidth + 24
                                height: 28
                                radius: 8
                                opacity: (row.hot || parent.forced) ? 1 : 0
                                color: endArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.8)
                                Behavior on opacity { NumberAnimation { duration: Theme.ms(100) } }
                                Text {
                                    id: endLabel
                                    anchors.centerIn: parent
                                    text: parent.parent.forced ? Theme.t("taskman.force", "Forçar") : Theme.t("taskman.end", "Encerrar")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: parent.parent.forced ? Theme.critical : Theme.textColor
                                }
                                MouseArea {
                                    id: endArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: tm.endApp(row.key, row.pids)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "taskmanager"
        function window(): void { tm.openWindow(); }
        function drop(): void { tm.openDrop(); }
        function toggle(): void { tm.openWindow(); }
        function hide(): void { tm.open = false; }
    }
}
