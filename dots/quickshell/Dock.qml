import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import "."

// Dock inferior, mesma linguagem da sidebar/top bar: sai de dentro da
// moldura de baixo com cantos invertidos, popups escorrem da borda de cima
// dela e deslizam entre ícones.
//
// APARECE: mouse na faixa central da moldura de baixo. SOME: mouse sai
// (com atraso).
//
// CONTEÚDO: apps fixados · apps abertos não fixados · botão Jogos.
// Clique: abre o app (sem janela) / foca (1 janela) / alterna entre as
// janelas (várias). Botão do meio: nova janela. Hover: popup com as janelas
// (clique foca, X fecha) e ações (nova janela, fixar/desafixar).
//
// Fixados e jogos: DockConfig (~/.config/quickshell/dock.json). Arrastar um
// ícone fixado reordena; jogos se editam no popup (Editar) e se adicionam
// pelo launcher (botão direito → Adicionar aos jogos).
PanelWindow {
    id: dock

    anchors { bottom: true; left: true; right: true }
    implicitHeight: Theme.frameThickness + dockH + 12 + 420
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    focusable: false

    WlrLayershell.namespace: "quickshell-dock"
    WlrLayershell.layer: launcherOpen ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property int dockH: 64
    readonly property int iconSize: 40
    readonly property real edgeY: height - Theme.frameThickness

    // ================= visibilidade =================
    property bool hovered: false
    property bool launcherOpen: false
    readonly property bool hasFullscreen: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen) || false
    readonly property bool allowHover: !hasFullscreen || launcherOpen
    property bool gamesEdit: false
    property int dragFrom: -1
    property int dragTo: -1
    readonly property bool workspaceEmpty: Hyprland.focusedWorkspace !== null
        && Hyprland.focusedWorkspace.toplevels.values.length === 0
    // Só aparece com o mouse
    readonly property bool shown: allowHover && (hovered || pop !== "" || dragFrom >= 0)
    onPopChanged: if (pop !== "games") gamesEdit = false

    Timer { id: hideDelay; interval: 450; onTriggered: dock.hovered = false }
    Timer { id: showDelay; interval: 80; onTriggered: dock.hovered = true }

    onHasFullscreenChanged: {
        if (hasFullscreen && !launcherOpen) {
            showDelay.stop();
            dock.hovered = false;
        }
    }
    onLauncherOpenChanged: {
        if (hasFullscreen && !launcherOpen) {
            showDelay.stop();
            dock.hovered = false;
        }
    }

    mask: (allowHover || dock.shown) ? fullMask : emptyMask

    Region { id: emptyMask }
    Region {
        id: fullMask
        // gatilho: faixa central da moldura de baixo (largura da dock + folga)
        x: (dock.width - Math.max(root.dockTargetW, 300)) / 2 - 60
        y: dock.edgeY
        width: Math.max(root.dockTargetW, 300) + 120
        height: Theme.frameThickness
        Region { item: bodyArea }
        Region { item: popArea }
    }

    // ================= apps =================
    // Força reavaliação reativa quando DesktopEntries terminar de indexar os apps
    readonly property int _appsLoaded: DesktopEntries.applications.values.length

    function entryFor(appId) {
        if (!appId) return null;
        const clean = appId.endsWith(".desktop") ? appId.slice(0, -8) : appId;
        return DesktopEntries.byId(clean)
            || DesktopEntries.byId(appId)
            || DesktopEntries.heuristicLookup(clean)
            || DesktopEntries.heuristicLookup(appId);
    }
    function windowsOf(key) {
        return ToplevelManager.toplevels.values.filter(t => {
            if (t.appId === "dropterm") return false;
            const e = dock.entryFor(t.appId);
            return (e ? e.id : t.appId) === key;
        });
    }
    // Lista de itens: fixados (na ordem) + abertos não fixados.
    readonly property var items: {
        const _ = dock._appsLoaded;
        const out = [];
        for (const id of DockConfig.pins) {
            const e = dock.entryFor(id);
            if (e) out.push({ key: e.id, entry: e, pinned: true });
        }
        for (const t of ToplevelManager.toplevels.values) {
            if (t.appId === "dropterm" || t.appId === "") continue;
            const e = dock.entryFor(t.appId);
            const key = e ? e.id : t.appId;
            if (!out.some(o => o.key === key))
                out.push({ key: key, entry: e, pinned: false, appId: t.appId });
        }
        return out;
    }
    readonly property int pinnedCount: items.filter(i => i.pinned).length

    function iconFor(item) {
        const name = item.entry ? item.entry.icon : item.appId;
        if (!name || name === "") return Quickshell.iconPath("application-x-executable");
        if (name.startsWith("/") || name.startsWith("file://")) {
            return name.startsWith("file://") ? name : "file://" + name;
        }
        return Quickshell.iconPath(name, "application-x-executable");
    }
    function activateItem(item) {
        const wins = windowsOf(item.key);
        if (wins.length === 0) {
            DockConfig.launch(item.entry);
            return;
        }
        // várias janelas: vai pra próxima depois da ativa
        const idx = wins.findIndex(w => w.activated);
        DockConfig.focusWindow(wins[(idx + 1) % wins.length]);
    }

    // ================= popup =================
    property string pop: ""          // "" | app | games
    property var popItem: null
    property real popAnchorX: 0
    Timer { id: popHide; interval: 260; onTriggered: dock.pop = "" }

    function showPop(kind, item, anchor) {
        popHide.stop();
        hideDelay.stop();
        popItem = item;
        popAnchorX = anchor.mapToItem(root, anchor.width / 2, 0).x;
        pop = kind;
    }
    function leavePop() { popHide.restart(); }

    // ================= conteúdo =================
    Item {
        id: root
        anchors.fill: parent

        HoverHandler {
            enabled: dock.allowHover
            onHoveredChanged: {
                if (!enabled) return;
                if (hovered) {
                    hideDelay.stop();
                    showDelay.restart();
                } else {
                    showDelay.stop();
                    hideDelay.restart();
                }
            }
        }

        // ---------- geometria ----------
        readonly property real radius: Theme.frameRadius
        readonly property real dockTargetW: row.implicitWidth + 24
        property real bodyH: dock.shown ? dock.dockH : 0
        property real bodyW: dockTargetW
        Behavior on bodyH { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        Behavior on bodyW { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        readonly property real popTargetW: dock.pop !== "" && dock.shown ? popContent.implicitWidth + 28 : 0
        readonly property real popTargetH: dock.pop !== "" && dock.shown ? popContent.implicitHeight + 24 : 0
        property real popW: popTargetW
        property real popH: popTargetH
        // Mantém o popup dentro da largura da dock quando cabe (aí os dois
        // lados ganham canto invertido); se for mais largo, centraliza na tela.
        readonly property real bodyL: (width - dockTargetW) / 2
        property real popX: {
            const w = popTargetW, m = radius * 1.8;   // canto da dock + canto invertido
            const fits = w <= dockTargetW - 2 * m;
            const lo = fits ? bodyL + m : Theme.frameThickness + radius;
            const hi = fits ? bodyL + dockTargetW - m - w : width - Theme.frameThickness - radius - w;
            return Math.max(lo, Math.min(hi, dock.popAnchorX - w / 2));
        }
        Behavior on popW { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on popH { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on popX { enabled: root.popH > 4; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        onBodyHChanged: shape.requestPaint()
        onBodyWChanged: shape.requestPaint()
        onPopWChanged: shape.requestPaint()
        onPopHChanged: shape.requestPaint()
        onPopXChanged: shape.requestPaint()
        onWidthChanged: shape.requestPaint()
        Connections {
            target: Theme
            function onBackgroundChanged() { shape.requestPaint(); }
        }
        Connections {
            target: ShellCustomization
            function onUpdated() { shape.requestPaint(); }
        }

        Canvas {
            id: shape
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const bh = root.bodyH;
                if (bh < 0.5) return;
                const R = root.radius, B = dock.edgeY, T = B - bh;
                const L = (width - root.bodyW) / 2, Rx = L + root.bodyW;
                const f = Math.min(R, bh), c = Math.min(R, bh / 2);
                ctx.fillStyle = ShellCustomization.getBgColor("dock");
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

                // Popup como segundo contorno no mesmo fill (união): encosta
                // 1px dentro da dock; canto invertido onde a borda do popup
                // cai em cima da dock, canto convexo onde passa dela.
                const pw = root.popW, ph = root.popH;
                if (pw > 0.5 && ph > 0.5) {
                    const PL = root.popX + (root.popTargetW - pw) / 2, PR = PL + pw, PT = T - ph, PB = T;
                    const cp = Math.min(R, pw / 2, ph / 2), fp = Math.min(R * 0.8, ph);
                    const leftIn = PL - fp >= L + c, rightIn = PR + fp <= Rx - c;
                    ctx.moveTo(PL + cp, PT);
                    ctx.lineTo(PR - cp, PT);
                    ctx.arc(PR - cp, PT + cp, cp, 3 * Math.PI / 2, 2 * Math.PI, false);
                    if (rightIn) {
                        ctx.lineTo(PR, PB - fp);
                        ctx.arc(PR + fp, PB - fp, fp, Math.PI, Math.PI / 2, true);
                        ctx.lineTo(PR + fp, PB + 1);
                    } else {
                        ctx.lineTo(PR, PB - cp);
                        ctx.arc(PR - cp, PB - cp, cp, 0, Math.PI / 2, false);
                    }
                    if (leftIn) {
                        ctx.lineTo(PL - fp, PB + 1);
                        ctx.lineTo(PL - fp, PB);
                        ctx.arc(PL - fp, PB - fp, fp, Math.PI / 2, 0, true);
                    } else {
                        ctx.lineTo(PL + cp, PB);
                        ctx.arc(PL + cp, PB - cp, cp, Math.PI / 2, Math.PI, false);
                    }
                    ctx.lineTo(PL, PT + cp);
                    ctx.arc(PL + cp, PT + cp, cp, Math.PI, 3 * Math.PI / 2, false);
                    ctx.closePath();
                }
                ctx.fill();

                if (ShellCustomization.getStyle("dock") === "glow") {
                    ctx.strokeStyle = ShellCustomization.getAccent("dock");
                    ctx.lineWidth = 2;
                    ctx.stroke();
                } else if (ShellCustomization.getStyle("dock") === "solid") {
                    ctx.strokeStyle = Theme.withAlpha(Theme.outline, 0.25);
                    ctx.lineWidth = 1;
                    ctx.stroke();
                } else if (ShellCustomization.getStyle("dock") === "glass") {
                    ctx.strokeStyle = Theme.withAlpha(ShellCustomization.getAccent("dock"), 0.35);
                    ctx.lineWidth = 1;
                    ctx.stroke();
                }
            }
        }

        // ================= corpo da dock =================
        Item {
            id: bodyArea
            x: (parent.width - root.bodyW) / 2
            y: dock.edgeY - root.bodyH
            width: root.bodyW
            height: root.bodyH
            scale: ShellCustomization.getScale("dock")
            transformOrigin: Item.Bottom
            clip: true

            RowLayout {
                id: row
                anchors.horizontalCenter: parent.horizontalCenter
                // preso na base: a dock "revela" os ícones ao subir
                y: dock.dockH - root.bodyH + (dock.dockH - height) / 2
                spacing: 4
                opacity: root.bodyH / dock.dockH

                // ---------- launcher (fixo à esquerda) ----------
                Item {
                    id: launcherBtn
                    implicitWidth: dock.iconSize + 12
                    implicitHeight: dock.dockH - 8

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 14
                        color: launcherArea.containsMouse ? Theme.tileHigh : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    AnimatedImage {
                        id: launcherImg
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -3
                        width: dock.iconSize
                        height: dock.iconSize
                        source: {
                            const p = DockConfig.launcherIcon;
                            if (!p) return "file:///home/val47/Imagens/Ícones/icons8-arch-linux-96(2).png";
                            return p.startsWith("/") ? "file://" + p : p;
                        }
                        fillMode: Image.PreserveAspectFit
                        mipmap: true
                        asynchronous: true
                    }

                    MouseArea {
                        id: launcherArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(["quickshell", "ipc", "call", "launcher", "toggle"]);
                        }
                    }
                }

                // Separador fixo entre launcher e apps
                Rectangle {
                    implicitWidth: 1
                    implicitHeight: 30
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.withAlpha(Theme.outline, 0.45)
                }

                Repeater {
                    model: dock.items
                    delegate: Item {
                        id: app
                        required property var modelData
                        required property int index
                        readonly property var wins: dock.windowsOf(modelData.key)
                        readonly property bool active: wins.some(w => w.activated)
                        // workspaces onde as janelas desse app estão (ordenados, sem repetir)
                        readonly property string wsLabel: {
                            const ids = [];
                            for (const w of wins) {
                                const h = Hyprland.toplevels.values.find(x => x.wayland === w);
                                if (!h || !h.workspace) continue;
                                const label = h.workspace.id > 0 ? String(h.workspace.id) : "✦";
                                if (!ids.includes(label)) ids.push(label);
                            }
                            return ids.sort((a, b) => (a === "✦") - (b === "✦") || Number(a) - Number(b)).join("·");
                        }

                        implicitWidth: dock.iconSize + 12
                        implicitHeight: dock.dockH - 8
                        z: dragging ? 10 : 0

                        // ----- arrastar pra reordenar (só fixados) -----
                        property bool dragging: false
                        property real dragX: 0
                        property bool justDragged: false
                        readonly property real shift: {
                            if (dock.dragFrom < 0 || dragging || !modelData.pinned) return 0;
                            if (dock.dragFrom < index && index <= dock.dragTo) return -width - 4;
                            if (dock.dragTo <= index && index < dock.dragFrom) return width + 4;
                            return 0;
                        }
                        transform: Translate {
                            x: app.dragging ? app.dragX : app.shift
                            Behavior on x {
                                enabled: !app.dragging
                                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }
                        }

                        // separador entre fixados e abertos
                        Rectangle {
                            visible: app.index === dock.pinnedCount && dock.pinnedCount > 0
                            x: -3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 1
                            height: 30
                            color: Theme.withAlpha(Theme.outline, 0.45)
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 14
                            color: appArea.containsMouse || (dock.pop === "app" && dock.popItem && dock.popItem.key === app.modelData.key)
                                ? Theme.tileHigh : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        IconImage {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -3
                            implicitSize: dock.iconSize
                            source: dock.iconFor(app.modelData)
                            scale: appArea.pressed ? 0.88 : appArea.containsMouse ? 1.08 : 1
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        }

                        // workspace do app (canto inferior esquerdo)
                        Rectangle {
                            visible: app.wsLabel !== ""
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 3
                            anchors.bottomMargin: 7
                            width: Math.max(16, wsBadge.implicitWidth + 8)
                            height: 16
                            radius: 8
                            color: app.active ? Theme.primary : Theme.tileHigh
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.background, 0.6)
                            Text {
                                id: wsBadge
                                anchors.centerIn: parent
                                text: app.wsLabel
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                                color: app.active ? Theme.background : Theme.textColor
                            }
                        }

                        // indicador de janelas abertas
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            spacing: 3
                            Repeater {
                                model: Math.min(app.wins.length, 3)
                                Rectangle {
                                    width: app.active && index === 0 ? 12 : 4
                                    height: 4
                                    radius: 2
                                    color: app.active ? Theme.primary : Theme.subtext
                                    Behavior on width { NumberAnimation { duration: 180 } }
                                }
                            }
                        }

                        MouseArea {
                            id: appArea
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: app.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            property real startX: 0
                            onEntered: if (dock.dragFrom < 0) dock.showPop("app", app.modelData, app)
                            onExited: dock.leavePop()
                            onPressed: mouse => {
                                startX = mapToItem(row, mouse.x, 0).x;
                                app.justDragged = false;
                            }
                            onPositionChanged: mouse => {
                                if (!pressed || !app.modelData.pinned || mouse.buttons !== Qt.LeftButton) return;
                                const dx = mapToItem(row, mouse.x, 0).x - startX;
                                if (!app.dragging && Math.abs(dx) > 8) {
                                    app.dragging = true;
                                    dock.dragFrom = app.index;
                                    dock.dragTo = app.index;
                                    dock.pop = "";
                                }
                                if (app.dragging) {
                                    app.dragX = dx;
                                    dock.dragTo = Math.max(0, Math.min(dock.pinnedCount - 1,
                                        app.index + Math.round(dx / (app.width + 4))));
                                }
                            }
                            // arraste interrompido (ex.: foco roubado): não deixa a dock presa aberta
                            onCanceled: {
                                app.dragging = false;
                                app.dragX = 0;
                                dock.dragFrom = -1;
                                dock.dragTo = -1;
                            }
                            onReleased: {
                                if (!app.dragging) return;
                                const keys = dock.items.filter(i => i.pinned).map(i => i.key);
                                const [k] = keys.splice(dock.dragFrom, 1);
                                keys.splice(dock.dragTo, 0, k);
                                app.dragging = false;
                                app.dragX = 0;
                                app.justDragged = true;
                                dock.dragFrom = -1;
                                dock.dragTo = -1;
                                DockConfig.setPinsOrder(keys);
                            }
                            onClicked: mouse => {
                                if (app.justDragged) return;
                                if (mouse.button === Qt.MiddleButton) {
                                    DockConfig.launch(app.modelData.entry);
                                } else {
                                    dock.activateItem(app.modelData);
                                }
                            }
                        }
                    }
                }

                // ---------- jogos ----------
                Rectangle {
                    Layout.leftMargin: 6
                    implicitWidth: 1
                    implicitHeight: 30
                    color: Theme.withAlpha(Theme.outline, 0.45)
                }
                Item {
                    id: gamesBtn
                    implicitWidth: dock.iconSize + 12
                    implicitHeight: dock.dockH - 8
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 14
                        color: gamesArea.containsMouse || dock.pop === "games" ? Theme.tileHigh : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Theme.icons.gamepad
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 30
                        color: Theme.primary
                        scale: gamesArea.containsMouse ? 1.08 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                    }
                    MouseArea {
                        id: gamesArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: dock.showPop("games", null, gamesBtn)
                        onExited: dock.leavePop()
                    }
                }
            }
        }

        // ================= popup =================
        Item {
            id: popArea
            x: root.popX + (root.popTargetW - root.popW) / 2
            y: dock.edgeY - root.bodyH - root.popH
            width: root.popW
            height: root.popH
            clip: true

            HoverHandler {
                onHoveredChanged: hovered ? popHide.stop() : dock.leavePop()
            }

            Item {
                id: popContent
                x: 14 - (root.popTargetW - root.popW) / 2
                y: 12 - (root.popTargetH - root.popH)
                implicitWidth: current ? Math.max(current.width, current.implicitWidth) : 0
                implicitHeight: current ? current.implicitHeight : 0
                width: implicitWidth
                height: implicitHeight
                readonly property Item current: dock.pop === "app" ? appPop : dock.pop === "games" ? gamesPop : null
                opacity: root.popTargetW > 0 && Math.abs(root.popW - root.popTargetW) < 30
                    && Math.abs(root.popH - root.popTargetH) < 30 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 130 } }

                // ---------- app ----------
                ColumnLayout {
                    id: appPop
                    visible: popContent.current === appPop
                    width: 260
                    spacing: 4
                    readonly property var item: dock.popItem
                    readonly property var wins: item ? dock.windowsOf(item.key) : []

                    PopTitle {
                        Layout.fillWidth: true
                        text: appPop.item ? (appPop.item.entry ? appPop.item.entry.name : appPop.item.appId) : ""
                        elide: Text.ElideRight
                    }
                    PopText {
                        visible: appPop.wins.length === 0
                        text: appPop.item && appPop.item.pinned ? "Clique para abrir · arraste para reordenar" : "Clique para abrir"
                    }

                    Repeater {
                        model: appPop.wins
                        delegate: Rectangle {
                            id: winRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: 9
                            color: winArea.containsMouse ? Theme.tileHigh : modelData.activated ? Theme.withAlpha(Theme.primary, 0.22) : Theme.tile
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 4
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    text: winRow.modelData.title
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.textColor
                                }
                                Rectangle {
                                    implicitWidth: 24
                                    implicitHeight: 24
                                    radius: 12
                                    color: closeArea.containsMouse ? Theme.withAlpha(Theme.critical, 0.6) : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: Theme.icons.close
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 14
                                        color: Theme.subtext
                                    }
                                    MouseArea {
                                        id: closeArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: winRow.modelData.close()
                                    }
                                }
                            }
                            MouseArea {
                                id: winArea
                                anchors.fill: parent
                                anchors.rightMargin: 30
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: DockConfig.focusWindow(winRow.modelData)
                            }
                        }
                    }

                    PopAction {
                        Layout.topMargin: 4
                        visible: appPop.item && appPop.item.entry && appPop.wins.length > 0
                        icon: Theme.icons.plus
                        label: Theme.t("dock.new_window", "Nova janela")
                        onActivated: DockConfig.launch(appPop.item.entry)
                    }
                    PopAction {
                        visible: appPop.item && appPop.item.entry
                        icon: Theme.icons.pin
                        selected: appPop.item && appPop.item.pinned
                        label: appPop.item && appPop.item.pinned ? Theme.t("launcher.unpin_dock", "Desafixar da dock") : Theme.t("launcher.pin_dock", "Fixar na dock")
                        onActivated: DockConfig.togglePin(appPop.item.key)
                    }
                }

                // ---------- jogos ----------
                ColumnLayout {
                    id: gamesPop
                    visible: popContent.current === gamesPop
                    width: 290
                    spacing: 6
                    readonly property var entries: {
                        const _ = dock._appsLoaded;
                        return DockConfig.games.map(id => dock.entryFor(id)).filter(e => e);
                    }
                    readonly property int cols: 3
                    property int dragFrom: -1
                    property int dragTo: -1

                    RowLayout {
                        Layout.fillWidth: true
                        PopTitle { text: Theme.t("dock.games", "Jogos"); Layout.fillWidth: true }
                        PopAction {
                            Layout.fillWidth: false
                            implicitHeight: 26
                            icon: dock.gamesEdit ? Theme.icons.confirm : Theme.icons.pencil
                            label: dock.gamesEdit ? Theme.t("common.done", "Pronto") : Theme.t("common.edit", "Editar")
                            selected: dock.gamesEdit
                            onActivated: dock.gamesEdit = !dock.gamesEdit
                        }
                    }
                    PopText {
                        visible: dock.gamesEdit || gamesPop.entries.length === 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: 11
                        text: (dock.gamesEdit ? Theme.t("dock.games_edit_hint", "Arraste para reordenar · X remove · ") : "")
                            + Theme.t("dock.games_add_hint", "Adicione pelo launcher: botão direito → Adicionar aos jogos")
                    }

                    GridLayout {
                        id: gamesGrid
                        Layout.fillWidth: true
                        columns: gamesPop.cols
                        rowSpacing: 6
                        columnSpacing: 6
                        Repeater {
                            model: gamesPop.entries
                            delegate: Rectangle {
                                id: game
                                required property var modelData
                                required property int index
                                property bool dragging: false
                                property real dx: 0
                                property real dy: 0
                                Layout.fillWidth: true
                                implicitHeight: 80
                                radius: 12
                                z: dragging ? 10 : 0
                                color: gameArea.containsMouse || dragging ? Theme.tileHigh : Theme.tile
                                border.width: gamesPop.dragFrom >= 0 && gamesPop.dragTo === index && !dragging ? 2 : 0
                                border.color: Theme.primary
                                Behavior on color { ColorAnimation { duration: 120 } }
                                transform: Translate { x: game.dx; y: game.dy }

                                // balança de leve no modo edição
                                rotation: dock.gamesEdit && !dragging ? wobble.value : 0
                                QtObject { id: wobble; property real value: 0 }
                                SequentialAnimation {
                                    running: dock.gamesEdit && !game.dragging
                                    loops: Animation.Infinite
                                    NumberAnimation { target: wobble; property: "value"; to: 1.2; duration: 140 }
                                    NumberAnimation { target: wobble; property: "value"; to: -1.2; duration: 140 }
                                    onStopped: wobble.value = 0
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width - 10
                                    spacing: 4
                                    IconImage {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitSize: 40
                                        source: Quickshell.iconPath(game.modelData.icon, "applications-games")
                                        scale: gameArea.containsMouse && !dock.gamesEdit ? 1.08 : 1
                                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: game.modelData.name
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.textColor
                                    }
                                }

                                MouseArea {
                                    id: gameArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: dock.gamesEdit ? (game.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.PointingHandCursor
                                    property point start
                                    onPressed: mouse => start = mapToItem(gamesGrid, mouse.x, mouse.y)
                                    onPositionChanged: mouse => {
                                        if (!pressed || !dock.gamesEdit) return;
                                        const p = mapToItem(gamesGrid, mouse.x, mouse.y);
                                        const dx = p.x - start.x, dy = p.y - start.y;
                                        if (!game.dragging && Math.hypot(dx, dy) > 6) {
                                            game.dragging = true;
                                            gamesPop.dragFrom = game.index;
                                        }
                                        if (game.dragging) {
                                            game.dx = dx;
                                            game.dy = dy;
                                            const cellW = gamesGrid.width / gamesPop.cols, cellH = game.height + gamesGrid.rowSpacing;
                                            const cx = game.x + game.width / 2 + dx, cy = game.y + game.height / 2 + dy;
                                            const col = Math.max(0, Math.min(gamesPop.cols - 1, Math.floor(cx / cellW)));
                                            const r = Math.max(0, Math.floor(cy / cellH));
                                            gamesPop.dragTo = Math.max(0, Math.min(gamesPop.entries.length - 1, r * gamesPop.cols + col));
                                        }
                                    }
                                    onReleased: {
                                        if (!game.dragging) return;
                                        const ids = gamesPop.entries.map(e => e.id);
                                        const [k] = ids.splice(gamesPop.dragFrom, 1);
                                        ids.splice(gamesPop.dragTo, 0, k);
                                        game.dragging = false;
                                        game.dx = 0;
                                        game.dy = 0;
                                        gamesPop.dragFrom = -1;
                                        gamesPop.dragTo = -1;
                                        DockConfig.setGamesOrder(ids);
                                    }
                                    onClicked: {
                                        if (dock.gamesEdit) return;
                                        DockConfig.launch(game.modelData);
                                        dock.pop = "";
                                    }
                                }

                                // remover (modo edição)
                                Rectangle {
                                    visible: dock.gamesEdit && !game.dragging
                                    width: 22
                                    height: 22
                                    radius: 11
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 4
                                    color: removeArea.containsMouse ? Theme.critical : Theme.withAlpha(Theme.critical, 0.75)
                                    Text {
                                        anchors.centerIn: parent
                                        text: Theme.icons.close
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 13
                                        color: Theme.textColor
                                    }
                                    MouseArea {
                                        id: removeArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: DockConfig.toggleGame(game.modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "dock"
        function toggle(): void { dock.hovered = !dock.hovered; }
        function games(): void { dock.hovered = true; dock.showPop("games", null, gamesBtn); }
        function hide(): void { dock.pop = ""; dock.hovered = false; }
        function state(): string {
            return "shown=" + dock.shown + " hovered=" + dock.hovered + " workspaceEmpty=" + dock.workspaceEmpty
                + " pop=" + dock.pop + " dragFrom=" + dock.dragFrom + " launcherOpen=" + dock.launcherOpen
                + " ws=" + (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id + " hasFullscreen=" + Hyprland.focusedWorkspace.hasFullscreen + " toplevels=" + Hyprland.focusedWorkspace.toplevels.values.length : "null");
        }
        function debug(): string {
            return "appsLoaded=" + dock._appsLoaded + " pinsCount=" + DockConfig.pins.length + " gamesCount=" + DockConfig.games.length
                + " itemsCount=" + dock.items.length + " gamesEntries=" + (gamesPop ? gamesPop.entries.length : -1);
        }
    }
}
