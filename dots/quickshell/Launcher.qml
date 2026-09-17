import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "."

// Launcher de apps (substitui o rofi no Super+R / tecla Super sozinha).
//
// Sai de dentro da moldura de baixo, no centro, com cantos invertidos (mesma
// linguagem da dock). Busca embaixo, resultados crescem pra cima — o melhor
// resultado fica colado na busca.
//
// Teclado: digitar busca · ↑/↓ navega · Enter abre · Shift+Enter ou tecla
// Menu abre o menu do app · Esc fecha (menu primeiro, depois o launcher).
// Mouse: clique abre · botão direito abre o menu do app (ações do .desktop,
// fixar/desafixar na dock, adicionar/remover dos jogos, editar no kmenuedit).
// Clique fora fecha.
PanelWindow {
    id: launcher

    property bool open: false
    visible: false
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: true

    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Libera a TopBar (topo), Sidebar (direita) e Dock (base) para receberem mouse normalmente
    mask: launcher.open ? activeMask : emptyMask

    Region { id: emptyMask }
    Region {
        id: activeMask
        x: 0
        y: Theme.waybarHeight
        width: launcher.width - Theme.frameThickness
        height: launcher.height - Theme.waybarHeight - Theme.frameThickness
    }

    readonly property int panelW: 660
    readonly property int rowH: 54
    readonly property int maxRows: 8
    readonly property int searchH: 58
    readonly property real edgeY: height - Theme.frameThickness

    onOpenChanged: {
        if (open) {
            closeTimer.stop();
            input.text = "";
            query = "";
            menuEntry = null;
            visible = true;
            list.currentIndex = 0;
            if (list.count > 0) list.positionViewAtIndex(0, ListView.Beginning);
            focusTimer.restart();
        } else {
            menuEntry = null;
            closeTimer.restart();
        }
    }
    Timer { id: closeTimer; interval: 260; onTriggered: launcher.visible = false }
    Timer { id: focusTimer; interval: 20; onTriggered: input.forceActiveFocus() }

    // ================= busca =================
    property string query: ""
    readonly property var allApps: {
        const seen = {};
        return DesktopEntries.applications.values.filter(e => {
            if (!e || e.noDisplay || !e.name || seen[e.id]) return false;
            seen[e.id] = true;
            return true;
        });
    }

    function norm(s) {
        return (s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    }
    function score(e, q) {
        const name = norm(e.name);
        if (name === q) return 1000;
        if (name.startsWith(q)) return 800;
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 600;
        if (name.includes(q)) return 400;
        if (norm(e.genericName).includes(q)) return 250;
        if ((e.keywords || []).some(k => norm(k).includes(q))) return 200;
        if (norm(e.id).includes(q)) return 150;
        if (norm(e.comment).includes(q)) return 80;
        // subsequência para buscas com 2 ou mais caracteres (ex.: "vsc" → "Visual Studio Code")
        if (q.length >= 2) {
            let i = 0;
            for (const ch of name) if (ch === q[i]) i++;
            if (i === q.length) return 40;
        }
        return 0;
    }
    readonly property var results: {
        const q = norm(query.trim());
        const use = DockConfig.usage;
        let r;
        if (q === "") {
            r = allApps.slice().sort((a, b) => (a.name || "").localeCompare(b.name || ""));
        } else {
            r = allApps.map(e => ({ e: e, s: score(e, q) }))
                .filter(x => x.s > 0)
                .sort((a, b) => (b.s - a.s) || ((use[b.e.id] || 0) - (use[a.e.id] || 0)) || (a.e.name || "").localeCompare(b.e.name || ""))
                .map(x => x.e);
        }
        return r.slice(0, 60);
    }
    onResultsChanged: {
        list.currentIndex = 0;
        if (list.count > 0) list.positionViewAtIndex(0, ListView.Beginning);
    }

    function launchEntry(e) {
        if (!e) return;
        DockConfig.launch(e);
        open = false;
    }

    // ================= menu do app =================
    property var menuEntry: null
    property real menuY: 0
    function openMenu(entry, rowItem) {
        menuEntry = entry;
        menuY = rowItem.mapToItem(panelArea, 0, rowItem.height / 2).y;
    }
    Process { id: kmenuedit; property string entryId: ""; command: ["kmenuedit", entryId + ".desktop"] }

    // ================= fundo (clique fora fecha) =================
    MouseArea {
        anchors.fill: parent
        anchors.topMargin: Theme.waybarHeight
        anchors.rightMargin: Theme.frameThickness
        anchors.bottomMargin: Theme.frameThickness
        onClicked: launcher.open = false
    }

    // ================= painel =================
    Item {
        id: root
        anchors.fill: parent

        readonly property real radius: Theme.frameRadius
        readonly property real listH: Math.min(launcher.results.length, launcher.maxRows) * launcher.rowH
            + (launcher.results.length > 0 ? 12 : 44)
        readonly property real targetH: launcher.searchH + listH + 14
        property real panelH: launcher.open ? targetH : 0
        Behavior on panelH { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        onPanelHChanged: shape.requestPaint()
        Connections {
            target: Theme
            function onBackgroundChanged() { shape.requestPaint(); }
        }

        Canvas {
            id: shape
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const h = root.panelH;
                if (h < 0.5) return;
                const R = root.radius, B = launcher.edgeY, T = B - h;
                const L = (width - launcher.panelW) / 2, Rx = L + launcher.panelW;
                const f = Math.min(R, h), c = Math.min(R, h / 2);
                ctx.fillStyle = Theme.surface;
                ctx.beginPath();
                ctx.moveTo(L - f, B);
                ctx.arc(L - f, B - f, f, Math.PI / 2, 0, true);
                ctx.lineTo(L, T + c);
                ctx.arc(L + c, T + c, c, Math.PI, 3 * Math.PI / 2, false);
                ctx.lineTo(Rx - c, T);
                ctx.arc(Rx - c, T + c, c, 3 * Math.PI / 2, 2 * Math.PI, false);
                ctx.lineTo(Rx, B - f);
                ctx.arc(Rx + f, B - f, f, Math.PI, Math.PI / 2, true);
                ctx.closePath();
                ctx.fill();
            }
        }

        Item {
            id: panelArea
            x: (parent.width - launcher.panelW) / 2
            y: launcher.edgeY - root.panelH
            width: launcher.panelW
            height: root.panelH
            clip: true

            // engole cliques dentro do painel (não fecha)
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: launcher.menuEntry = null
            }

            // conteúdo preso na base: o painel "revela" subindo
            Item {
                id: content
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.targetH
                opacity: root.panelH > 8 ? Math.min(1, root.panelH / Math.max(1, root.targetH)) : 0

                // ---------- busca ----------
                Rectangle {
                    id: searchBox
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    height: launcher.searchH - 14
                    radius: height / 2
                    color: Theme.tile
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.primary, input.activeFocus ? 0.5 : 0.15)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10
                        Text {
                            text: Theme.icons.magnify
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 20
                            color: Theme.primary
                        }
                        TextInput {
                            id: input
                            Layout.fillWidth: true
                            text: launcher.query
                            onTextChanged: launcher.query = text
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            color: Theme.textColor
                            selectionColor: Theme.withAlpha(Theme.primary, 0.4)
                            clip: true

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: input.text === ""
                                text: "Buscar apps…"
                                font: input.font
                                color: Theme.subtext
                            }

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    if (launcher.menuEntry) launcher.menuEntry = null;
                                    else launcher.open = false;
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Down) {
                                    if (list.count > 0) {
                                        list.currentIndex = (list.currentIndex + 1) % list.count;
                                        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up) {
                                    if (list.count > 0) {
                                        list.currentIndex = (list.currentIndex - 1 + list.count) % list.count;
                                        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Tab) {
                                    if (list.count > 0) {
                                        list.currentIndex = (list.currentIndex + 1) % list.count;
                                        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Backtab) {
                                    if (list.count > 0) {
                                        list.currentIndex = (list.currentIndex - 1 + list.count) % list.count;
                                        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Menu
                                        || ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier))) {
                                    if (list.currentItem && list.currentIndex >= 0 && list.currentIndex < launcher.results.length)
                                        launcher.openMenu(launcher.results[list.currentIndex], list.currentItem);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    if (list.currentIndex >= 0 && list.currentIndex < launcher.results.length)
                                        launcher.launchEntry(launcher.results[list.currentIndex]);
                                    event.accepted = true;
                                }
                            }
                        }
                        Text {
                            visible: launcher.results.length > 0
                            text: launcher.results.length + (launcher.results.length >= 60 ? "+" : "")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.subtext
                        }
                    }
                }

                PopText {
                    visible: launcher.results.length === 0 && launcher.query.trim() !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: searchBox.top
                    anchors.bottomMargin: 14
                    text: "Nada encontrado pra “" + launcher.query + "”"
                }

                // ---------- resultados ----------
                ListView {
                    id: list
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: searchBox.top
                    anchors.leftMargin: 10
                    anchors.rightMargin: 16
                    anchors.bottomMargin: 6
                    height: Math.min(count, launcher.maxRows) * launcher.rowH
                    clip: true
                    model: launcher.results
                    verticalLayoutDirection: ListView.TopToBottom
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 140
                    highlightMoveVelocity: -1
                    highlightFollowsCurrentItem: true
                    keyNavigationEnabled: false

                    // Sensibilidade de scroll aumentada: avança 3 linhas por tick da roda
                    WheelHandler {
                        target: list
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => {
                            const delta = event.angleDelta.y;
                            if (delta !== 0) {
                                const step = (delta / 120) * (launcher.rowH * 3);
                                const targetY = list.contentY - step;
                                const maxY = Math.max(0, list.contentHeight - list.height);
                                list.contentY = Math.max(0, Math.min(maxY, targetY));
                            }
                        }
                    }

                    highlight: Rectangle {
                        radius: 14
                        color: Theme.withAlpha(Theme.primary, 0.2)
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.primary, 0.35)
                    }

                    delegate: Item {
                        id: rowItem
                        required property var modelData
                        required property int index
                        width: list.width
                        height: launcher.rowH

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            IconImage {
                                implicitSize: 34
                                source: Quickshell.iconPath(rowItem.modelData.icon, "application-x-executable")
                                scale: rowItem.ListView.isCurrentItem ? 1.08 : 1
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: rowItem.modelData.name
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    font.weight: rowItem.ListView.isCurrentItem ? Font.DemiBold : Font.Normal
                                    color: Theme.textColor
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: rowItem.modelData.genericName || rowItem.modelData.comment || ""
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.subtext
                                }
                            }
                            Text {
                                visible: DockConfig.isGame(rowItem.modelData.id)
                                text: Theme.icons.gamepad
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 15
                                color: Theme.subtext
                            }
                            Text {
                                visible: DockConfig.isPinned(rowItem.modelData.id)
                                text: Theme.icons.pin
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 15
                                color: Theme.subtext
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onPositionChanged: mouse => {
                                if (root.panelH >= root.targetH - 1 && !launcher.menuEntry && list.currentIndex !== rowItem.index)
                                    list.currentIndex = rowItem.index;
                            }
                            onClicked: mouse => {
                                list.currentIndex = rowItem.index;
                                if (mouse.button === Qt.RightButton) launcher.openMenu(rowItem.modelData, rowItem);
                                else if (launcher.menuEntry) launcher.menuEntry = null;
                                else launcher.launchEntry(rowItem.modelData);
                            }
                        }
                    }
                }

                // ---------- scrollbar lateral discreta ----------
                Rectangle {
                    id: scrollTrack
                    anchors.right: parent.right
                    anchors.top: list.top
                    anchors.bottom: list.bottom
                    anchors.topMargin: 4
                    anchors.bottomMargin: 4
                    anchors.rightMargin: 7
                    width: 4
                    radius: 2
                    color: Theme.withAlpha(Theme.textColor, 0.08)
                    visible: list.count > launcher.maxRows && root.panelH >= root.targetH - 2

                    Rectangle {
                        id: scrollThumb
                        width: parent.width
                        radius: 2
                        color: thumbArea.containsMouse || thumbArea.drag.active
                            ? Theme.primary
                            : Theme.withAlpha(Theme.primary, 0.65)
                        height: Math.max(20, scrollTrack.height * list.visibleArea.heightRatio)
                        y: Math.min(scrollTrack.height - height, Math.max(0, scrollTrack.height * list.visibleArea.yPosition))
                    }

                    MouseArea {
                        id: thumbArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        drag.target: scrollThumb
                        drag.axis: Drag.YAxis
                        drag.minimumY: 0
                        drag.maximumY: scrollTrack.height - scrollThumb.height
                        onPositionChanged: {
                            if (drag.active) {
                                const ratio = scrollThumb.y / Math.max(1, (scrollTrack.height - scrollThumb.height));
                                const maxY = Math.max(0, list.contentHeight - list.height);
                                list.contentY = ratio * maxY;
                            }
                        }
                        onClicked: mouse => {
                            const ratio = Math.max(0, Math.min(1, mouse.y / scrollTrack.height));
                            const maxY = Math.max(0, list.contentHeight - list.height);
                            list.contentY = ratio * maxY;
                        }
                    }
                }
            }

            // ---------- menu do app (botão direito) ----------
            Rectangle {
                id: menu
                readonly property var e: launcher.menuEntry
                visible: opacity > 0
                opacity: e ? 1 : 0
                scale: e ? 1 : 0.94
                transformOrigin: Item.Right
                Behavior on opacity { NumberAnimation { duration: 130 } }
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                width: 250
                height: menuCol.implicitHeight + 16
                x: parent.width - width - 16
                y: Math.max(8, Math.min(parent.height - height - launcher.searchH, launcher.menuY - height / 2))
                radius: 14
                color: Theme.tileHigh
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.3)

                MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

                ColumnLayout {
                    id: menuCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 3

                    PopTitle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.bottomMargin: 2
                        text: menu.e ? menu.e.name : ""
                        elide: Text.ElideRight
                    }
                    PopAction {
                        icon: Theme.icons.play
                        label: "Abrir"
                        onActivated: launcher.launchEntry(menu.e)
                    }
                    Repeater {
                        model: menu.e ? menu.e.actions : []
                        delegate: PopAction {
                            required property var modelData
                            icon: Theme.icons.chevronRight
                            label: modelData.name
                            onActivated: {
                                modelData.execute();
                                launcher.open = false;
                            }
                        }
                    }
                    PopAction {
                        Layout.topMargin: 4
                        icon: Theme.icons.pin
                        label: menu.e && DockConfig.isPinned(menu.e.id) ? "Desafixar da dock" : "Fixar na dock"
                        selected: menu.e && DockConfig.isPinned(menu.e.id)
                        onActivated: DockConfig.togglePin(menu.e.id)
                    }
                    PopAction {
                        icon: Theme.icons.gamepad
                        label: menu.e && DockConfig.isGame(menu.e.id) ? "Remover dos jogos" : "Adicionar aos jogos"
                        selected: menu.e && DockConfig.isGame(menu.e.id)
                        onActivated: DockConfig.toggleGame(menu.e.id)
                    }
                    PopAction {
                        icon: Theme.icons.pencil
                        label: "Editar entrada (kmenuedit)"
                        onActivated: {
                            kmenuedit.entryId = menu.e.id;
                            kmenuedit.running = true;
                            launcher.open = false;
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { launcher.open = !launcher.open; }
    }
}
