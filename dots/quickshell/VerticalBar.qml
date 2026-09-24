pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.SystemTray
import Quickshell.Services.Mpris
import Quickshell.Widgets
import "."

// Barra lateral vertical — a alternativa à barra de cima, que é como a maior
// parte dos rices de Hyprland se organiza.
//
// É um componente à parte, e não um modo dentro do TopBar.qml, de propósito: a
// barra de cima desenha os popups num Canvas com cantos invertidos preso à
// borda de baixo dela, e virar aquilo de lado significaria refazer o desenho
// inteiro. Aqui o clique abre o lugar que resolve o assunto (hub, painel,
// central de ações) e o hover abre um popup simples ao lado da barra.
//
// Só existe quando o arranjo pede barra vertical (ShellLayout).
PanelWindow {
    id: vbar

    signal clockClicked()
    signal notifClicked()
    signal visualConfigClicked()
    signal controlClicked()
    signal controlHovered(bool on)
    // A sidebar (EnergySidebar): estados/ações dos itens do catálogo.
    property var energy: null

    property bool launcherOpen: false
    readonly property bool onLeft: ShellLayout.barPosition === "left"
    readonly property bool hasFullscreen: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen) || false

    readonly property int barW: 52

    visible: ShellLayout.barEnabled && ShellLayout.barVertical
    color: "transparent"
    focusable: false

    anchors {
        top: true
        bottom: true
        left: vbar.onLeft
        right: !vbar.onLeft
    }
    // A janela é mais larga que a barra para caber o popup lateral; a zona
    // exclusiva continua sendo só a barra e a máscara deixa o resto clicável.
    readonly property int stripW: vbar.barW + Theme.frameThickness
    readonly property int popMaxW: 330
    implicitWidth: vbar.stripW + 10 + vbar.popMaxW
    exclusiveZone: ShellLayout.barAutohide ? 0 : vbar.barW + Theme.frameThickness

    WlrLayershell.namespace: "quickshell-vbar"
    WlrLayershell.layer: vbar.launcherOpen ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // ---- esconder no hover ----
    property bool barHovered: false
    readonly property bool shown: !ShellLayout.barAutohide || barHovered || vbar.pop !== ""
    Timer { id: hideDelay; interval: 400; onTriggered: vbar.barHovered = false }

    // ---- popup do hover ----
    property string pop: ""
    property real popAnchorY: 0
    property var popTray: null
    function showPop(kind, item, trayItem) {
        popHide.stop();
        vbar.popTray = trayItem || null;
        vbar.popAnchorY = item.mapToItem(null, 0, item.height / 2).y;
        vbar.pop = kind;
    }
    function leavePop() { popHide.restart(); }
    Timer { id: popHide; interval: 280; onTriggered: if (!popBox.busy) vbar.pop = "" }
    Timer { id: showDelay; interval: 60; onTriggered: vbar.barHovered = true }

    mask: Region {
        x: vbar.onLeft ? 0 : (vbar.shown ? vbar.width - vbar.stripW : vbar.width - 4)
        y: 0
        width: vbar.shown ? vbar.stripW : 4
        height: vbar.height
        Region { item: vbar.pop !== "" ? popBox : null }
    }

    // ================= dados =================
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [vbar.sink, vbar.source] }

    // Mídia: estado e comandos no MediaState (compartilhado com a TopBar e a
    // central; lá está o porquê do playerctl).
    readonly property var player: MediaState.player

    function fmtTime(secs) {
        if (!secs || secs <= 0) return "";
        const h = Math.floor(secs / 3600), m = Math.floor(secs % 3600 / 60);
        return h > 0 ? h + "h " + m + "min" : m + " min";
    }

    function volIcon() {
        const n = vbar.sink;
        if (!n || !n.audio || n.audio.muted) return Theme.icons.volOff;
        const v = n.audio.volume;
        return v > 0.66 ? Theme.icons.volHigh : v > 0.33 ? Theme.icons.volMid : Theme.icons.volLow;
    }

    readonly property var battery: UPower.displayDevice
    function batIcon() {
        if (!vbar.battery || !vbar.battery.isLaptopBattery) return Theme.icons.bat;
        if (vbar.battery.state === UPowerDeviceState.Charging || vbar.battery.state === UPowerDeviceState.FullyCharged)
            return Theme.icons.batCharging;
        const p = Math.round(vbar.battery.percentage * 10);
        return p <= 0 ? Theme.icons.batAlert : p >= 10 ? Theme.icons.bat : Theme.icons["bat" + p + "0"];
    }

    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var activeNetwork: wifiDevice ? wifiDevice.networks.values.find(n => n.connected) || null : null
    function wifiIcon() {
        if (!Networking.wifiEnabled || !vbar.activeNetwork) return Theme.icons.wifiOff;
        const s = vbar.activeNetwork.signalStrength;
        return s > 0.75 ? Theme.icons.wifi4 : s > 0.5 ? Theme.icons.wifi3 : s > 0.25 ? Theme.icons.wifi2 : Theme.icons.wifi1;
    }

    // Só para decidir se o bloco da central mostra o ícone de brilho.
    FileView { id: brMax; path: "/sys/class/backlight/intel_backlight/max_brightness"; blockLoading: true; printErrors: false }
    readonly property bool hasBacklight: brMax.text().trim() !== ""

    // Áreas de trabalho: mesma regra da barra de cima (ver TopBar.wsModel).
    readonly property var wsModel: {
        const existing = Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id);
        const n = ShellLayout.workspaceCount;
        if (n <= 0)
            return existing.map(w => ({ id: w.id, urgent: w.urgent, occupied: true }));
        const byId = {};
        for (const w of existing) byId[w.id] = w;
        const out = [];
        for (let i = 1; i <= n; i++) {
            const w = byId[i] || null;
            out.push({ id: i, urgent: w ? w.urgent : false, occupied: w ? w.toplevels.values.length > 0 : false });
        }
        for (const w of existing) if (w.id > n) out.push({ id: w.id, urgent: w.urgent, occupied: true });
        return out;
    }

    property string timeText: ""
    property string dateText: ""
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const d = new Date();
            vbar.timeText = Qt.formatDateTime(d, "HH:mm");
            vbar.dateText = Qt.formatDateTime(d, "dd/MM");
        }
    }

    // ================= peças =================
    component BarButton: Rectangle {
        id: bb
        property string icon: ""
        property color iconColor: Theme.textColor
        property string badge: ""
        property string popKind: ""
        property string editKey: ""
        readonly property bool editable: ShellLayout.editing && bb.editKey !== ""
        readonly property bool inCatalog: ShellLayout.barCatalog.includes(bb.editKey)
        opacity: bb.editKey !== "" && !bb.inCatalog && !ShellLayout.barModule(bb.editKey) ? 0.35 : 1
        border.width: bb.editable ? 1 : 0
        border.color: Theme.withAlpha(Theme.primary, 0.7)
        signal activated()
        signal secondary()
        signal wheel(real delta)

        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 36
        implicitHeight: 36
        radius: 12
        color: bbArea.containsMouse ? Theme.tileHigh : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.ms(130) } }

        Text {
            anchors.centerIn: parent
            text: bb.icon
            font.family: Theme.iconFontFamily
            font.pixelSize: 17
            color: bb.iconColor
        }

        Rectangle {
            visible: bb.badge !== ""
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 2
            width: Math.max(14, badgeText.implicitWidth + 6)
            height: 14
            radius: 7
            color: Theme.primary

            Text {
                id: badgeText
                anchors.centerIn: parent
                text: bb.badge
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.weight: Font.Bold
                color: Theme.background
            }
        }

        // Itens do catálogo mudam de ordem arrastando no modo edição
        // (ShellLayout.barItems da barra lateral); entram e saem pela aba.
        readonly property bool reorderable: bb.editable && bb.inCatalog
        property bool dragging: false
        property real pressY: 0
        z: dragging ? 5 : 0
        scale: dragging ? 1.1 : 1
        Behavior on scale { NumberAnimation { duration: Theme.ms(120) } }

        MouseArea {
            id: bbArea
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: bb.dragging ? Qt.ClosedHandCursor : bb.reorderable ? Qt.OpenHandCursor : Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: if (bb.popKind !== "" && !bb.editable) vbar.showPop(bb.popKind, bb)
            onExited: if (bb.popKind !== "") vbar.leavePop()
            onPressed: mouse => bb.pressY = mapToItem(mainCol, 0, mouse.y).y
            onPositionChanged: mouse => {
                if (!pressed || !bb.reorderable) return;
                const y = mapToItem(mainCol, 0, mouse.y).y;
                if (!bb.dragging && Math.abs(y - bb.pressY) > 8) {
                    bb.dragging = true;
                    vbar.dragOrder = ShellLayout.barItems.slice();
                }
                if (bb.dragging) vbar.dragModuleTo(bb.editKey, y);
            }
            onReleased: {
                if (!bb.dragging) return;
                bb.dragging = false;
                const order = vbar.dragOrder;
                vbar.dragOrder = null;
                ShellLayout.setBarItems(order);
            }
            onCanceled: {
                if (!bb.dragging) return;
                bb.dragging = false;
                vbar.dragOrder = null;
                vbar.applyBarOrder();
            }
            onClicked: mouse => {
                if (bb.editable) {
                    if (!bb.inCatalog && mouse.button === Qt.LeftButton && Math.abs(mapToItem(mainCol, 0, mouse.y).y - bb.pressY) <= 8)
                        ShellLayout.setBarModule(bb.editKey, !ShellLayout.barModule(bb.editKey));
                    return;
                }
                mouse.button === Qt.RightButton ? bb.secondary() : bb.activated();
            }
            onWheel: w => bb.wheel(w.angleDelta.y)
        }
    }

    // ================= ordem dos indicadores =================
    // Como na TopBar: reparentar põe o item no fim da coluna, então os itens
    // voltam na ordem da lista, embaixo (depois do espaço flexível). A mídia não
    // entra: ela fica sempre no meio da barra.
    property var dragOrder: null
    function barModuleItems() {
        return { notifications: vNotif, network: vNet, control: vCtl, tray: vTray, updates: vUpd,
                 night: vNight, caffeine: vCaf, record: vRec, screenshot: vShot, clipboard: vClip,
                 picker: vPick, gpu: vGpu, lock: vLock, settings: vSet, power: vPower };
    }
    function applyBarOrder() {
        const items = vbar.barModuleItems();
        const seq = [];
        for (const k of (vbar.dragOrder || ShellLayout.barItems)) if (items[k]) seq.push(items[k]);
        for (const it of seq) {
            it.parent = orderParking;
            it.parent = mainCol;
        }
    }
    function dragModuleTo(key, y) {
        const items = vbar.barModuleItems();
        const order = vbar.dragOrder;
        const from = order.indexOf(key);
        for (let i = 0; i < order.length; i++) {
            const it = items[order[i]];
            if (i === from || !it || !it.visible) continue;
            const mid = it.y + it.height / 2;
            if ((i > from && y > mid) || (i < from && y < mid)) {
                const next = order.slice();
                next.splice(from, 1);
                next.splice(i, 0, key);
                vbar.dragOrder = next;
                vbar.applyBarOrder();
                return;
            }
        }
    }
    Connections {
        target: ShellLayout
        function onBarItemsChanged() { if (!vbar.dragOrder) vbar.applyBarOrder(); }
    }
    Item { id: orderParking; visible: false }

    // ================= conteúdo =================
    Item {
        width: vbar.stripW
        height: parent.height
        // Sai pela lateral quando está escondida.
        x: (vbar.onLeft ? 0 : parent.width - width) + (vbar.shown ? 0 : (vbar.onLeft ? -vbar.barW : vbar.barW))
        Behavior on x { NumberAnimation { duration: Theme.ms(260); easing.type: Easing.OutCubic } }

        HoverHandler {
            enabled: ShellLayout.barAutohide
            onHoveredChanged: {
                if (!enabled) return;
                if (hovered) { hideDelay.stop(); showDelay.restart(); }
                else { showDelay.stop(); hideDelay.restart(); }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: vbar.onLeft ? 0 : Theme.frameThickness
            anchors.rightMargin: vbar.onLeft ? Theme.frameThickness : 0
            color: Theme.surface
            // Só os cantos do lado de dentro são arredondados; o de fora
            // encosta na borda da tela.
            topRightRadius: vbar.onLeft ? Theme.frameRadius : 0
            bottomRightRadius: vbar.onLeft ? Theme.frameRadius : 0
            topLeftRadius: vbar.onLeft ? 0 : Theme.frameRadius
            bottomLeftRadius: vbar.onLeft ? 0 : Theme.frameRadius

            // Botão direito no fundo da barra: modo edição (como no KDE).
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: ShellLayout.editing = !ShellLayout.editing
            }

            ColumnLayout {
                id: mainCol
                anchors.fill: parent
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 6
                Component.onCompleted: vbar.applyBarOrder()

                // ---- launcher ----
                BarButton {
                    icon: Theme.icons.arch
                    iconColor: Theme.primary
                    onActivated: Quickshell.execDetached(["quickshell", "ipc", "call", "launcher", "toggle"])
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 1
                    color: Theme.withAlpha(Theme.outline, 0.35)
                }

                // ---- áreas de trabalho ----
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6

                    Repeater {
                        model: vbar.wsModel
                        delegate: Rectangle {
                            id: wsDot
                            required property var modelData
                            readonly property bool active: Hyprland.focusedWorkspace
                                && Hyprland.focusedWorkspace.id === wsDot.modelData.id
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 10
                            implicitHeight: wsDot.active ? 26 : (wsDot.modelData.occupied ? 10 : 7)
                            radius: width / 2
                            color: wsDot.active ? Theme.primary
                                : wsDot.modelData.urgent ? Theme.critical
                                : wsArea.containsMouse ? Theme.textColor
                                : Theme.withAlpha(Theme.subtext, wsDot.modelData.occupied ? 0.55 : 0.28)
                            Behavior on implicitHeight { NumberAnimation { duration: Theme.ms(220); easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: Theme.ms(160) } }

                            MouseArea {
                                id: wsArea
                                anchors.fill: parent
                                anchors.margins: -5
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsDot.modelData.id + " })")
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // ---- relógio ----
                Rectangle {
                    visible: ShellLayout.showModule("clock")
                    opacity: ShellLayout.barModule("clock") ? 1 : 0.35
                    border.width: ShellLayout.editing ? 1 : 0
                    border.color: Theme.withAlpha(Theme.primary, 0.7)
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 40
                    implicitHeight: clockCol.implicitHeight + 12
                    radius: 12
                    color: clockArea.containsMouse ? Theme.tileHigh : "transparent"

                    ColumnLayout {
                        id: clockCol
                        anchors.centerIn: parent
                        spacing: 0

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: vbar.timeText.split(":")[0]
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Theme.textColor
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: vbar.timeText.split(":")[1] || ""
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            color: Theme.subtext
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 4
                            Layout.preferredWidth: 14
                            Layout.preferredHeight: 1
                            color: Theme.withAlpha(Theme.outline, 0.4)
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 3
                            text: vbar.dateText
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Theme.subtext
                        }
                    }

                    MouseArea {
                        id: clockArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (ShellLayout.editing) {
                                ShellLayout.setBarModule("clock", !ShellLayout.barModule("clock"));
                                return;
                            }
                            vbar.clockClicked();
                        }
                    }
                }

                // ---- mídia: capa pequena no meio da barra, popup no hover ----
                Rectangle {
                    id: mediaBtn
                    visible: ShellLayout.barHas("media") && vbar.player !== null
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: 10
                    color: Theme.tileHigh
                    clip: true
                    Image {
                        id: artImg
                        anchors.fill: parent
                        source: vbar.player && vbar.player.trackArtUrl ? vbar.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(72, 72)
                        asynchronous: true
                        visible: status === Image.Ready
                        opacity: MediaState.playing ? 1 : 0.55
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !artImg.visible
                        text: Theme.icons.album
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 17
                        color: Theme.textColor
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: vbar.showPop("media", mediaBtn)
                        onExited: vbar.leavePop()
                        onClicked: MediaState.toggle()
                        // roda: volume do app que está tocando
                        onWheel: w => MediaState.wheel(w.angleDelta.y)
                    }
                }

                Item { Layout.fillHeight: true }

                // ---- bandeja (apps em segundo plano) ----
                ColumnLayout {
                    id: vTray
                    visible: ShellLayout.barHas("tray") && SystemTray.items.values.length > 0
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    // No modo edição a bandeja se arrasta como um item só.
                    property bool dragging: false
                    property real pressY: 0
                    MouseArea {
                        z: 10
                        visible: ShellLayout.editing
                        anchors.fill: parent
                        preventStealing: true
                        cursorShape: vTray.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onPressed: mouse => vTray.pressY = mapToItem(mainCol, 0, mouse.y).y
                        onPositionChanged: mouse => {
                            const y = mapToItem(mainCol, 0, mouse.y).y;
                            if (!vTray.dragging && Math.abs(y - vTray.pressY) > 8) {
                                vTray.dragging = true;
                                vbar.dragOrder = ShellLayout.barItems.slice();
                            }
                            if (vTray.dragging) vbar.dragModuleTo("tray", y);
                        }
                        onReleased: {
                            if (!vTray.dragging) return;
                            vTray.dragging = false;
                            const order = vbar.dragOrder;
                            vbar.dragOrder = null;
                            ShellLayout.setBarItems(order);
                        }
                    }
                Repeater {
                    model: SystemTray.items
                    delegate: Item {
                        id: trayBtn
                        required property SystemTrayItem modelData
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 36
                        implicitHeight: 30
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: trayArea.containsMouse || (vbar.pop === "tray" && vbar.popTray === trayBtn.modelData)
                                ? Theme.tileHigh : "transparent"
                        }
                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 18
                            source: trayBtn.modelData.icon
                            opacity: trayBtn.modelData.status === Status.Passive ? 0.6 : 1
                        }
                        MouseArea {
                            id: trayArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onEntered: vbar.showPop("tray", trayBtn, trayBtn.modelData)
                            onExited: vbar.leavePop()
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton)
                                    trayBtn.modelData.secondaryActivate();
                                else if (!trayBtn.modelData.onlyMenu)
                                    trayBtn.modelData.activate();
                            }
                            onWheel: wheel => trayBtn.modelData.scroll(wheel.angleDelta.y, false)
                        }
                    }
                }

                }

                // ---- indicadores ----
                BarButton {
                    id: vNotif
                    editKey: "notifications"
                    visible: ShellLayout.barHas("notifications")
                    icon: NotifService.dnd ? Theme.icons.bellOff : Theme.icons.bell
                    iconColor: NotifService.dnd ? Theme.secondary
                        : (NotifService.unreadCount > 0 ? Theme.primary : Theme.textColor)
                    badge: NotifService.unreadCount > 0
                        ? (NotifService.unreadCount > 99 ? "99+" : String(NotifService.unreadCount)) : ""
                    onActivated: vbar.notifClicked()
                    onSecondary: NotifService.toggleDnd()
                }

                BarButton {
                    id: vNet
                    editKey: "network"
                    visible: ShellLayout.barHas("network")
                    icon: vbar.wifiIcon()
                    popKind: "wifi"
                    iconColor: vbar.activeNetwork ? Theme.textColor : Theme.subtext
                    onActivated: Quickshell.execDetached(["quickshell", "ipc", "call", "visualconfig", "tab", "11"])
                }

                // Brilho, som e bateria num bloco só: o clique abre a central de
                // controle; a roda muda o volume.
                Rectangle {
                    id: vCtl
                    readonly property bool editable: ShellLayout.editing
                    visible: ShellLayout.barHas("control")
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 36
                    implicitHeight: ctlCol.implicitHeight + 16
                    radius: 12
                    color: ctlArea.containsMouse || vCtl.dragging ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.6)
                    border.width: vCtl.editable ? 1 : 0
                    border.color: Theme.withAlpha(Theme.primary, 0.7)
                    Behavior on color { ColorAnimation { duration: Theme.ms(130) } }
                    property bool dragging: false
                    property real pressY: 0
                    z: dragging ? 5 : 0
                    scale: dragging ? 1.1 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.ms(120) } }

                    ColumnLayout {
                        id: ctlCol
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            visible: vbar.hasBacklight
                            text: Theme.icons.brightness
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 16
                            color: Theme.textColor
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: vbar.volIcon()
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 17
                            color: (vbar.sink && vbar.sink.audio && vbar.sink.audio.muted) ? Theme.subtext : Theme.textColor
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            visible: vbar.battery !== null && vbar.battery.isLaptopBattery
                            text: vbar.batIcon()
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 17
                            color: vbar.battery && vbar.battery.percentage < 0.15 ? Theme.critical : Theme.textColor
                        }
                    }
                    MouseArea {
                        id: ctlArea
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: vCtl.dragging ? Qt.ClosedHandCursor : vCtl.editable ? Qt.OpenHandCursor : Qt.PointingHandCursor
                        onEntered: if (!vCtl.editable) vbar.controlHovered(true)
                        onExited: vbar.controlHovered(false)
                        onPressed: mouse => vCtl.pressY = mapToItem(mainCol, 0, mouse.y).y
                        onPositionChanged: mouse => {
                            if (!pressed || !vCtl.editable) return;
                            const y = mapToItem(mainCol, 0, mouse.y).y;
                            if (!vCtl.dragging && Math.abs(y - vCtl.pressY) > 8) {
                                vCtl.dragging = true;
                                vbar.dragOrder = ShellLayout.barItems.slice();
                            }
                            if (vCtl.dragging) vbar.dragModuleTo("control", y);
                        }
                        onReleased: {
                            if (!vCtl.dragging) return;
                            vCtl.dragging = false;
                            const order = vbar.dragOrder;
                            vbar.dragOrder = null;
                            ShellLayout.setBarItems(order);
                        }
                        onClicked: mouse => {
                            if (vCtl.editable) return;
                            vbar.controlClicked();
                        }
                        onWheel: w => {
                            if (!vbar.sink || !vbar.sink.audio) return;
                            const step = w.angleDelta.y > 0 ? 0.02 : -0.02;
                            vbar.sink.audio.volume = Math.max(0, Math.min(1, vbar.sink.audio.volume + step));
                        }
                    }
                }

                BarButton {
                    id: vUpd
                    editKey: "updates"
                    visible: ShellLayout.barHas("updates")
                    icon: Theme.icons.update
                    iconColor: vbar.energy && vbar.energy.updateCount > 0 ? Theme.primary : Theme.textColor
                    badge: vbar.energy && vbar.energy.updateCount > 0
                        ? (vbar.energy.updateCount > 99 ? "99+" : String(vbar.energy.updateCount)) : ""
                    onActivated: if (vbar.energy) vbar.energy.runUpdate()
                }
                BarButton {
                    id: vNight
                    editKey: "night"
                    visible: ShellLayout.barHas("night")
                    icon: Theme.icons.night
                    iconColor: vbar.energy && vbar.energy.nightLight ? Theme.primary : Theme.textColor
                    onActivated: if (vbar.energy) vbar.energy.toggleNight()
                }
                BarButton {
                    id: vCaf
                    editKey: "caffeine"
                    visible: ShellLayout.barHas("caffeine")
                    icon: vbar.energy && vbar.energy.caffeine ? Theme.icons.coffee : Theme.icons.coffeeOff
                    iconColor: vbar.energy && vbar.energy.caffeine ? Theme.primary : Theme.textColor
                    onActivated: if (vbar.energy) vbar.energy.toggleCaffeine()
                }
                BarButton {
                    id: vRec
                    editKey: "record"
                    visible: ShellLayout.barHas("record")
                    icon: Theme.icons.record
                    iconColor: vbar.energy && vbar.energy.recording ? Theme.critical : Theme.textColor
                    onActivated: {
                        if (vbar.energy && vbar.energy.recording) vbar.energy.stopRecording();
                        else Quickshell.execDetached(["rice-record", "full"]);
                    }
                }
                BarButton {
                    id: vShot
                    editKey: "screenshot"
                    visible: ShellLayout.barHas("screenshot")
                    icon: Theme.icons.camera
                    onActivated: Quickshell.execDetached(["rice-screenshot", "region"])
                    onSecondary: Quickshell.execDetached(["rice-screenshot", "output"])
                }
                BarButton {
                    id: vClip
                    editKey: "clipboard"
                    visible: ShellLayout.barHas("clipboard")
                    icon: Theme.icons.clipboard
                    onActivated: Quickshell.execDetached(["quickshell", "ipc", "call", "clipboard", "open"])
                }
                BarButton {
                    id: vPick
                    editKey: "picker"
                    visible: ShellLayout.barHas("picker")
                    icon: Theme.icons.eyedropper
                    iconColor: ColorPick.picking ? Theme.primary : Theme.textColor
                    onActivated: ColorPick.pick()
                }
                // Privacidade: só enquanto microfone, câmera ou tela estão em uso.
                BarButton {
                    id: vPriv
                    visible: ShellLayout.barPrivacy && Privacy.active
                    icon: Privacy.screenApps.length > 0 ? Theme.icons.screenShare
                        : Privacy.camApps.length > 0 ? Theme.icons.webcam : Theme.icons.mic
                    iconColor: Theme.critical
                }
                BarButton {
                    id: vGpu
                    editKey: "gpu"
                    visible: ShellLayout.barHas("gpu")
                    icon: Theme.icons.gpu
                    iconColor: vbar.energy && vbar.energy.nvidiaState === "active" ? Theme.primary : Theme.subtext
                    onActivated: Quickshell.execDetached(["quickshell", "ipc", "call", "sidebar", "toggle"])
                }
                BarButton {
                    id: vLock
                    editKey: "lock"
                    visible: ShellLayout.barHas("lock")
                    icon: Theme.icons.lock
                    onActivated: Quickshell.execDetached(["rice-session-action", "lock"])
                }
                BarButton {
                    id: vSet
                    editKey: "settings"
                    visible: ShellLayout.barHas("settings")
                    icon: Theme.icons.tune
                    onActivated: vbar.visualConfigClicked()
                }
                BarButton {
                    id: vPower
                    editKey: "power"
                    visible: ShellLayout.barHas("power")
                    icon: Theme.icons.power
                    iconColor: Theme.secondary
                    onActivated: Quickshell.execDetached(["quickshell", "ipc", "call", "sidebar", "toggle"])
                }
            }
        }
    }

    // ================= popup lateral =================
    Rectangle {
        id: popBox
        readonly property bool busy: mediaVol.dragging
        readonly property real gap: 10
        // Largura fixa: medir pelo implicitWidth do ColumnLayout (que conta ~0
        // para linhas com fillWidth) deixava o conteúdo vazar da caixa.
        width: vbar.popMaxW - 30
        height: popCol.implicitHeight + 24
        x: vbar.onLeft ? vbar.stripW + gap - (vbar.pop !== "" ? 0 : 8)
                       : vbar.width - vbar.stripW - gap - width + (vbar.pop !== "" ? 0 : 8)
        y: Math.max(10, Math.min(vbar.height - height - 10, vbar.popAnchorY - height / 2))
        radius: Theme.frameRadius
        color: Theme.surface
        border.color: Theme.withAlpha(Theme.outline, 0.35)
        border.width: 1
        opacity: vbar.pop !== "" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.ms(150) } }
        Behavior on x { NumberAnimation { duration: Theme.ms(180); easing.type: Easing.OutCubic } }
        Behavior on y { enabled: popBox.opacity > 0.5; NumberAnimation { duration: Theme.ms(180); easing.type: Easing.OutCubic } }

        HoverHandler {
            onHoveredChanged: hovered ? popHide.stop() : vbar.leavePop()
        }

        ColumnLayout {
            id: popCol
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 12
            anchors.leftMargin: 14
            width: popBox.width - 28
            spacing: 6

            // ---- mídia ----
            RowLayout {
                visible: vbar.pop === "media" && vbar.player !== null
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: 10
                    color: Theme.tileHigh
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: vbar.player && vbar.player.trackArtUrl ? vbar.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(128, 128)
                        asynchronous: true
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: vbar.player ? (vbar.player.trackTitle || vbar.player.identity || "") : ""
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.textColor
                    }
                    Text {
                        Layout.fillWidth: true
                        text: vbar.player ? (vbar.player.trackArtist || vbar.player.identity || "") : ""
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                    Row {
                        spacing: 4
                        Repeater {
                            model: [
                                { icon: Theme.icons.prev, act: "prev" },
                                { icon: MediaState.playing ? Theme.icons.pause : Theme.icons.play, act: "toggle" },
                                { icon: Theme.icons.next, act: "next" }
                            ]
                            delegate: Rectangle {
                                id: mBtn
                                required property var modelData
                                width: 32
                                height: 28
                                radius: 8
                                color: mBtnArea.containsMouse ? Theme.tileHigh : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: mBtn.modelData.icon
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 16
                                    color: Theme.textColor
                                }
                                MouseArea {
                                    id: mBtnArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (mBtn.modelData.act === "prev") MediaState.previous();
                                        else if (mBtn.modelData.act === "next") MediaState.next();
                                        else MediaState.toggle();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            PopSlider {
                id: mediaVol
                visible: vbar.pop === "media" && MediaState.hasVolume
                Layout.fillWidth: true
                icon: MediaState.muted ? Theme.icons.volOff : Theme.icons.music
                value: MediaState.shownVolume
                dimmed: MediaState.muted
                onMoved: v => MediaState.setVolume(v)
                onIconClicked: MediaState.toggleMute()
            }

            // ---- bandeja: o menu do próprio app ----
            TrayMenu {
                visible: vbar.pop === "tray"
                Layout.fillWidth: true
                item: vbar.pop === "tray" ? vbar.popTray : null
                maxWidth: popBox.width - 28
                onTriggered: vbar.pop = ""
            }

            // ---- rede ----
            PopTitle {
                visible: vbar.pop === "wifi"
                text: !Networking.wifiEnabled ? Theme.t("topbar.wifi_off", "Wi-Fi desligado")
                    : vbar.activeNetwork ? vbar.activeNetwork.name : Theme.t("vbar.no_network", "Sem conexão")
            }
            PopText {
                visible: vbar.pop === "wifi" && vbar.activeNetwork !== null
                text: vbar.activeNetwork ? Theme.t("vbar.signal", "Sinal") + " " + Math.round(vbar.activeNetwork.signalStrength * 100) + "%" : ""
            }

            PopText {
                visible: vbar.pop === "wifi"
                Layout.topMargin: 4
                text: Theme.t("vbar.click_hint", "Clique no ícone para mais opções")
                font.pixelSize: 10
                opacity: 0.8
            }
        }
    }
}
