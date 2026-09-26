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
import Quickshell.Widgets
import "."

// Barra do topo (substitui a waybar). Mesma linguagem da sidebar: passar o
// mouse num módulo faz um popup "escorrer" da borda de baixo da barra, na
// altura do módulo, desenhado junto com a barra num contorno só (cantos
// invertidos na junção). Trocar de módulo desliza/redimensiona o mesmo popup.
//
// Esquerda: workspaces + título da janela ativa
// Centro:   relógio (clique abre o hub)
// Direita:  gravação · microfone mutado · wifi · bluetooth · volume · brilho · bateria
PanelWindow {
    id: bar

    signal clockClicked()
    signal notifClicked()
    signal visualConfigClicked()
    signal controlClicked()
    signal btPageRequested()
    signal controlHovered(bool on)
    // A sidebar (EnergySidebar): estados e ações dos itens do catálogo (updates,
    // luz noturna, café, GPU) moram nela; ligada no shell.qml.
    property var energy: null
    property bool recording: false
    signal stopRecording()

    // Com a barra vertical ligada, esta some por completo.
    visible: ShellLayout.barEnabled && !ShellLayout.barVertical
    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.waybarHeight + 460
    // Barra que some no hover não reserva espaço: as janelas usam a tela toda
    // e ela volta ao encostar o mouse na borda de cima.
    exclusiveZone: (ShellLayout.barAutohide || ShellLayout.barVertical) ? 0 : Theme.waybarHeight
    color: "transparent"
    focusable: false

    property bool launcherOpen: false
    readonly property bool hasFullscreen: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen) || false

    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.layer: launcherOpen ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property int barH: Theme.waybarHeight

    // ---- barra escondida (opção "aparecer só no hover") ----
    property bool barHovered: false
    readonly property bool barShown: !ShellLayout.barAutohide || barHovered
        || bar.pop !== "" || bar.launcherOpen
    Timer { id: barHideDelay; interval: 400; onTriggered: bar.barHovered = false }
    Timer { id: barShowDelay; interval: 60; onTriggered: bar.barHovered = true }

    // Áreas de trabalho mostradas na barra. Com workspaceCount = 0 continua só
    // o que existe (comportamento antigo); com 1..10 os botões ficam sempre
    // lá, mesmo sem nenhuma janela aberta — é assim que dá para pular para uma
    // área vazia sem decorar o atalho.
    readonly property var wsModel: {
        const existing = Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id);
        const n = ShellLayout.workspaceCount;
        if (n <= 0)
            return existing.map(w => ({ id: w.id, ws: w, urgent: w.urgent, occupied: true }));

        const byId = {};
        for (const w of existing) byId[w.id] = w;
        const out = [];
        for (let i = 1; i <= n; i++) {
            const w = byId[i] || null;
            out.push({
                id: i,
                ws: w,
                urgent: w ? w.urgent : false,
                occupied: w ? w.toplevels.values.length > 0 : false
            });
        }
        // Áreas acima do limite só aparecem se realmente existirem.
        for (const w of existing) {
            if (w.id > n) out.push({ id: w.id, ws: w, urgent: w.urgent, occupied: true });
        }
        return out;
    }

    mask: Region {
        x: 0
        y: 0
        width: bar.width
        // Escondida, sobra só uma faixa fina no topo para o mouse encontrar.
        height: bar.barShown ? bar.barH : 4
        Region { item: popArea }
    }

    // ================= estado do popup =================
    property string pop: ""
    // Aba do popup da mídia: "media" ou "eq".
    property string mediaTab: "media"
    property real popAnchorX: 0

    Timer { id: popShow; interval: 110; property string kind; property Item anchor
        onTriggered: bar.showPopNow(kind, anchor) }
    Timer { id: popHide; interval: 260; onTriggered: if (!popContent.busy) bar.pop = "" }

    function showPop(kind: string, anchorItem: Item): void {
        popHide.stop();
        if (pop !== "") {
            showPopNow(kind, anchorItem);   // já aberto: troca na hora (desliza)
        } else {
            popShow.kind = kind;
            popShow.anchor = anchorItem;
            popShow.restart();
        }
    }
    function showPopNow(kind: string, anchorItem: Item): void {
        popAnchorX = anchorItem.mapToItem(root, anchorItem.width / 2, 0).x;
        pop = kind;
    }
    function openNotifs(): void { showPopNow("notifs", notifMod); }
    function leavePop(): void {
        popShow.stop();
        popHide.restart();
    }

    // ================= dados =================
    // --- áudio ---
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && !n.isSink
        && (n.properties["media.class"] || "") === "Audio/Source")
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isStream
        && (n.properties["media.class"] || "") === "Stream/Output/Audio"
        // Fluxos virtuais (loopback, saída do equalizador) não são apps.
        && String(n.properties["node.virtual"] || "") !== "true")
    PwObjectTracker { objects: [bar.sink, bar.source].concat(bar.sinks, bar.sources, bar.streams) }

    function nodeName(n) {
        if (!n) return "";
        return n.properties["application.name"] || n.description || n.nickname || n.name;
    }
    function volIcon(n) {
        if (!n || !n.audio || n.audio.muted) return Theme.icons.volOff;
        const v = n.audio.volume;
        return v > 0.66 ? Theme.icons.volHigh : v > 0.33 ? Theme.icons.volMid : Theme.icons.volLow;
    }

    // --- brilho (sysfs; sysfs não avisa mudança, então relê a cada 2s) ---
    property real brightness: 0
    FileView { id: brCur; path: "/sys/class/backlight/intel_backlight/brightness"; blockLoading: true }
    FileView { id: brMax; path: "/sys/class/backlight/intel_backlight/max_brightness"; blockLoading: true }
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // Logo depois de uma mudança feita aqui, o sysfs ainda pode ter o
            // valor antigo; reler agora desfazia o que o usuário acabou de rolar.
            if (brHold.running || brSet.running) return;
            brCur.reload();
            bar.brightness = Math.max(0, Math.min(1, (parseFloat(brCur.text()) || 0) / (parseFloat(brMax.text()) || 1)));
        }
    }
    Timer { id: brHold; interval: 1500 }
    // Um brightnessctl por vez: com a roda chegam vários pedidos seguidos, e
    // `running = true` num processo que já está rodando é ignorado — o valor
    // final se perdia. O pedido mais recente fica guardado e roda na saída.
    property int brPending: -1
    Process {
        id: brSet
        property int pct: 0
        command: ["brightnessctl", "-q", "set", pct + "%"]
        onExited: {
            if (bar.brPending >= 0) {
                pct = bar.brPending;
                bar.brPending = -1;
                running = true;
            }
        }
    }
    function setBrightness(v) {
        brightness = Math.max(0.01, Math.min(1, v));
        brHold.restart();
        const pct = Math.max(1, Math.round(brightness * 100));
        if (brSet.running) {
            brPending = pct;
        } else {
            brSet.pct = pct;
            brSet.running = true;
        }
    }
    // Roda do mouse nos módulos da barra: acumula o delta e anda 5% por
    // clique inteiro, somando a partir do último valor pedido (o volume do
    // PipeWire demora um pouco para refletir a mudança).
    property real wheelAcc: 0
    property real volTarget: -1
    Timer { id: volSettle; interval: 800; onTriggered: { bar.volTarget = -1; bar.wheelAcc = 0; } }
    function wheelSteps(d) {
        wheelAcc += d;
        const steps = Math.trunc(wheelAcc / 120);
        wheelAcc -= steps * 120;
        return steps;
    }
    function wheelVolume(d) {
        if (!sink || !sink.audio) return;
        const steps = wheelSteps(d);
        if (steps === 0) return;
        const base = volTarget >= 0 ? volTarget : Math.min(AudioPrefs.maxVolume, sink.audio.volume);
        volTarget = Math.max(0, Math.min(AudioPrefs.maxVolume, Math.round((base + steps * 0.05) * 20) / 20));
        volSettle.restart();
        sink.audio.volume = volTarget;
    }
    function wheelBrightness(d) {
        const steps = wheelSteps(d);
        if (steps === 0) return;
        setBrightness(Math.round((brightness + steps * 0.05) * 20) / 20);
    }

    // --- bateria ---
    readonly property var battery: UPower.displayDevice
    function batIcon() {
        if (!battery || !battery.isLaptopBattery) return Theme.icons.bat;
        if (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged)
            return Theme.icons.batCharging;
        const p = Math.round(battery.percentage * 10);
        return p <= 0 ? Theme.icons.batAlert : p >= 10 ? Theme.icons.bat : Theme.icons["bat" + p + "0"];
    }
    function fmtTime(secs) {
        if (!secs || secs <= 0) return "";
        const h = Math.floor(secs / 3600), m = Math.floor(secs % 3600 / 60);
        return h > 0 ? h + "h " + m + "min" : m + " min";
    }

    // --- rede ---
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    // Cabo ligado: o ícone de rede mostra o cabo (o tráfego sai por ele, que
    // tem prioridade no NetworkManager); antes a barra só sabia de Wi-Fi.
    readonly property var wiredDevice: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) || null
    readonly property var activeNetwork: wifiDevice ? wifiDevice.networks.values.find(n => n.connected) || null : null
    function wifiIcon() {
        if (!Networking.wifiEnabled) return Theme.icons.wifiOff;
        if (!activeNetwork) return Theme.icons.wifiOff;
        const s = activeNetwork.signalStrength;
        return s > 0.75 ? Theme.icons.wifi4 : s > 0.5 ? Theme.icons.wifi3 : s > 0.25 ? Theme.icons.wifi2 : Theme.icons.wifi1;
    }
    Process { id: netRestart; command: ["bash", "-c", "nmcli networking off && sleep 2 && nmcli networking on"] }

    // --- bluetooth ---
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btDevices: btAdapter ? btAdapter.devices.values.filter(d => d.paired || d.connected)
        .sort((a, b) => (b.connected - a.connected) || (a.name || "").localeCompare(b.name || "")) : []
    readonly property var btConnected: btDevices.find(d => d.connected) || null

    // ================= componentes =================
    component BarText: Text {
        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: Theme.textColor
    }
    component BarIcon: Text {
        font.family: Theme.iconFontFamily
        font.pixelSize: 17
        color: Theme.textColor
    }

    // Módulo da barra: fundo em pill no hover, abre o popup `kind`.
    component Module: Rectangle {
        id: mod
        required property string kind
        // Chave do módulo. Itens do catálogo (ShellLayout.barCatalog) só se
        // arrastam no modo edição; entram e saem pela aba do modo edição. Os
        // outros (relógio) continuam ligando/desligando no clique.
        property string editKey: ""
        readonly property bool editable: ShellLayout.editing && mod.editKey !== ""
        readonly property bool inCatalog: ShellLayout.barCatalogCurrent.includes(mod.editKey)
        // Deixa cliques chegarem aos filhos (ícones da bandeja) fora do modo edição.
        property bool passClicks: false
        opacity: mod.editKey !== "" && !mod.inCatalog && !ShellLayout.barModule(mod.editKey) ? 0.35 : 1
        border.width: mod.editable ? 1 : 0
        border.color: Theme.withAlpha(Theme.primary, 0.7)
        default property alias content: modRow.data
        signal clicked()
        signal hoverIn()
        signal hoverOut()
        signal rightClicked()
        signal wheel(int delta)

        implicitWidth: modRow.implicitWidth + 18
        implicitHeight: bar.barH - 8
        radius: height / 2
        color: modArea.containsMouse || bar.pop === kind ? Theme.tileHigh : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.ms(140) } }

        RowLayout {
            id: modRow
            anchors.centerIn: parent
            spacing: 5
        }
        // Qualquer item do catálogo muda de lugar (e de zona) arrastando.
        readonly property bool reorderable: mod.editable && mod.inCatalog
        property bool dragging: false
        property real pressX: 0
        z: dragging ? 5 : 0

        MouseArea {
            id: modArea
            anchors.fill: parent
            z: mod.passClicks && !mod.editable ? -1 : 0
            hoverEnabled: true
            preventStealing: true
            cursorShape: mod.dragging ? Qt.ClosedHandCursor : mod.reorderable ? Qt.OpenHandCursor : Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: {
                if (mod.kind !== "" && !mod.editable) bar.showPop(mod.kind, mod);
                if (!mod.editable) mod.hoverIn();
            }
            onExited: {
                bar.leavePop();
                mod.hoverOut();
            }
            onPressed: mouse => mod.pressX = mapToItem(root, mouse.x, 0).x
            onPositionChanged: mouse => {
                if (!pressed || !mod.reorderable) return;
                const x = mapToItem(root, mouse.x, 0).x;
                if (!mod.dragging && Math.abs(x - mod.pressX) > 8) {
                    mod.dragging = true;
                    bar.dragOrder = ShellLayout.barItems.slice();
                    bar.dragItem = mod;
                }
                if (mod.dragging) {
                    bar.dragX = x;
                    bar.dragModuleTo(mod.editKey, x);
                }
            }
            onReleased: {
                if (!mod.dragging) return;
                mod.dragging = false;
                bar.dragItem = null;
                const order = bar.dragOrder;
                bar.dragOrder = null;
                ShellLayout.setBarItems(order);
            }
            onCanceled: {
                if (!mod.dragging) return;
                mod.dragging = false;
                bar.dragItem = null;
                bar.dragOrder = null;
                bar.applyBarOrder();
            }
            onClicked: mouse => {
                if (mod.editable) {
                    if (!mod.inCatalog && mouse.button === Qt.LeftButton && !mod.dragging)
                        ShellLayout.setBarModule(mod.editKey, !ShellLayout.barModule(mod.editKey));
                    return;
                }
                if (mouse.button === Qt.RightButton) {
                    mod.rightClicked();
                } else {
                    mod.clicked();
                }
            }
            onWheel: w => mod.wheel(w.angleDelta.y)
        }
    }

    // ================= ordem dos indicadores =================
    // Os módulos são declarados numa ordem fixa. Para aplicar a ordem salva, cada
    // um sai e volta para o rightRow (reparentar põe o item no fim da lista de
    // filhos, e o RowLayout segue essa lista). stackAfter() não existe no QML.
    // Enquanto arrasta, dragOrder guarda a ordem ao vivo e só é gravada ao soltar.
    property var dragOrder: null
    // Arraste visível: uma cópia do item segue o ponteiro (ShaderEffectSource
    // com hideSource, então o lugar dele vira um espaço vazio que mostra onde
    // vai cair) e as três zonas aparecem enquanto arrasta.
    property Item dragItem: null
    property real dragX: 0
    readonly property int dragZone: dragX < root.width / 3 ? 0 : dragX > root.width * 2 / 3 ? 2 : 1
    function barModuleItems() {
        return { workspaces: wsMod, clock: clockMod, media: mediaMod, mixer: mixerMod, bluetooth: btMod, weather: weatherMod, notifications: notifMod, network: wifiMod, control: ctlMod, tray: trayMod,
                 updates: updMod, night: nightMod, caffeine: cafMod, record: recMod, screenshot: shotMod,
                 clipboard: clipMod, picker: pickMod, gpu: gpuMod, lock: lockMod, settings: setMod, power: powMod };
    }
    function applyBarOrder() {
        const items = bar.barModuleItems();
        let target = leftRow;
        for (const k of (bar.dragOrder || ShellLayout.barItems)) {
            if (k === "::center") { target = centerRow; continue; }
            if (k === "::right") { target = rightRow; continue; }
            const it = items[k];
            if (!it) continue;
            it.parent = orderParking;
            it.parent = target;
        }
    }
    // Arrastar: a zona sai de onde o ponteiro está (terço esquerdo, meio ou
    // terço direito da barra); dentro dela, a posição é contada pelos vizinhos
    // cujo meio fica à esquerda do ponteiro.
    function dragModuleTo(key, x) {
        const items = bar.barModuleItems();
        const cur = bar.dragOrder;
        const order = cur.filter(k => k !== key);
        const zone = x < root.width / 3 ? 0 : x > root.width * 2 / 3 ? 2 : 1;
        const ci = order.indexOf("::center"), ri = order.indexOf("::right");
        const start = zone === 0 ? 0 : zone === 1 ? ci + 1 : ri + 1;
        const end = zone === 0 ? ci : zone === 1 ? ri : order.length;
        let pos = start;
        for (let i = start; i < end; i++) {
            const it = items[order[i]];
            if (!it || !it.visible) { pos = i + 1; continue; }
            const mid = it.mapToItem(root, it.width / 2, 0).x;
            if (mid < x) pos = i + 1;
        }
        order.splice(pos, 0, key);
        if (JSON.stringify(order) === JSON.stringify(cur)) return;
        bar.dragOrder = order;
        bar.applyBarOrder();
    }
    Connections {
        target: ShellLayout
        function onBarItemsChanged() { if (!bar.dragOrder) bar.applyBarOrder(); }
    }
    Item { id: orderParking; visible: false }

    // ================= conteúdo =================
    Item {
        id: root
        anchors.fill: parent
        // Sai por cima da borda quando escondida, em vez de simplesmente
        // sumir: o movimento mostra de onde ela volta.
        y: bar.barShown ? 0 : -bar.barH
        Behavior on y { NumberAnimation { duration: Theme.ms(260); easing.type: Easing.OutCubic } }

        HoverHandler {
            enabled: ShellLayout.barAutohide
            onHoveredChanged: {
                if (!enabled) return;
                if (hovered) {
                    barHideDelay.stop();
                    barShowDelay.restart();
                } else {
                    barShowDelay.stop();
                    barHideDelay.restart();
                }
            }
        }

        // ---------- geometria animada do popup ----------
        readonly property real radius: Theme.frameRadius
        readonly property real popTargetW: bar.pop !== "" ? popContent.implicitWidth + 32 : 0
        readonly property real popTargetH: bar.pop !== "" ? popContent.implicitHeight + 28 : 0
        property real popW: popTargetW
        property real popH: popTargetH
        property real popX: Math.max(Theme.frameThickness + radius,
            Math.min(width - Theme.frameThickness - radius - Math.max(popTargetW, 1), bar.popAnchorX - popTargetW / 2))
        Behavior on popW { NumberAnimation { duration: Theme.ms(260); easing.type: Easing.OutCubic } }
        Behavior on popH { NumberAnimation { duration: Theme.ms(260); easing.type: Easing.OutCubic } }
        Behavior on popX {
            enabled: root.popH > 4
            NumberAnimation { duration: Theme.ms(260); easing.type: Easing.OutCubic }
        }

        onPopWChanged: shape.requestPaint()
        onPopHChanged: shape.requestPaint()
        onPopXChanged: shape.requestPaint()
        onWidthChanged: shape.requestPaint()
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
                const W = width, H = bar.barH, R = root.radius;
                const ph = root.popH, pw = root.popW;
                ctx.fillStyle = Theme.surface;
                ctx.beginPath();
                ctx.moveTo(0, 0);
                ctx.lineTo(W, 0);
                ctx.lineTo(W, H);
                if (ph > 0.5 && pw > 0.5) {
                    // centraliza a largura animada em volta do alvo
                    const PL = root.popX + (root.popTargetW - pw) / 2;
                    const PR = PL + pw, PB = H + ph;
                    const c = Math.min(R, pw / 2, ph / 2);
                    const f = Math.min(R * 0.8, ph);
                    ctx.lineTo(PR + f, H);
                    ctx.arc(PR + f, H + f, f, -Math.PI / 2, Math.PI, true);
                    ctx.lineTo(PR, PB - c);
                    ctx.arc(PR - c, PB - c, c, 0, Math.PI / 2, false);
                    ctx.lineTo(PL + c, PB);
                    ctx.arc(PL + c, PB - c, c, Math.PI / 2, Math.PI, false);
                    ctx.lineTo(PL, H + f);
                    ctx.arc(PL - f, H + f, f, 0, -Math.PI / 2, true);
                }
                ctx.lineTo(0, H);
                ctx.closePath();
                ctx.fill();
            }
        }

        // ================= barra =================
        Item {
            id: barItem
            width: parent.width
            height: bar.barH

            // Botão direito no fundo da barra: modo edição (como no KDE). Fica
            // por baixo dos módulos, que têm o próprio clique.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: ShellLayout.editing = !ShellLayout.editing
            }

            // Zonas destacadas durante o arraste (a do ponteiro fica mais forte).
            Repeater {
                model: 3
                delegate: Rectangle {
                    required property int index
                    visible: bar.dragItem !== null
                    x: root.width * index / 3 + 3
                    width: root.width / 3 - 6
                    anchors.verticalCenter: parent.verticalCenter
                    height: bar.barH - 6
                    radius: height / 2
                    color: Theme.withAlpha(Theme.primary, bar.dragZone === index ? 0.14 : 0.04)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.primary, bar.dragZone === index ? 0.5 : 0.15)
                    Behavior on color { ColorAnimation { duration: Theme.ms(120) } }
                }
            }

            ShaderEffectSource {
                id: dragGhost
                z: 50
                visible: bar.dragItem !== null
                sourceItem: bar.dragItem
                hideSource: true
                live: true
                width: bar.dragItem ? bar.dragItem.width : 0
                height: bar.dragItem ? bar.dragItem.height : 0
                x: bar.dragX - width / 2
                anchors.verticalCenter: parent.verticalCenter
                scale: 1.1
                opacity: 0.92
            }

            // ---------- três zonas: esquerda, centro, direita ----------
            // Os módulos são distribuídos por applyBarOrder() conforme a lista
            // do ShellLayout (com os marcadores ::center e ::right).
            RowLayout {
                id: leftRow
                anchors.left: parent.left
                anchors.leftMargin: Theme.frameThickness + 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                // Workspaces + área especial + título da janela: um bloco só.
                Module {
                    id: wsMod
                    kind: ""
                    editKey: "workspaces"
                    passClicks: true
                    color: "transparent"
                    visible: ShellLayout.barHas("workspaces")
                    RowLayout {
                        spacing: 10

                        Rectangle {
                            implicitWidth: wsRow.implicitWidth + 16
                            implicitHeight: bar.barH - 10
                            radius: height / 2
                            color: Theme.tile

                            Row {
                                id: wsRow
                                anchors.centerIn: parent
                                spacing: 6
                                Repeater {
                                    model: bar.wsModel
                                    delegate: Rectangle {
                                        id: wsDot
                                        required property var modelData
                                        readonly property bool active: Hyprland.focusedWorkspace
                                            && Hyprland.focusedWorkspace.id === modelData.id
                                        // Ícone do app da área (a janela em foco, se estiver
                                        // nela; senão a primeira). Opcional: bar.wsIcons.
                                        readonly property string appIcon: {
                                            if (!ShellLayout.get("bar", "wsIcons", true) || !modelData.ws) return "";
                                            const tops = modelData.ws.toplevels.values;
                                            if (!tops.length) return "";
                                            const at = Hyprland.activeToplevel;
                                            const t = at && tops.includes(at) ? at : tops[0];
                                            const id = (t.wayland && t.wayland.appId) || (t.lastIpcObject && t.lastIpcObject.class) || "";
                                            if (!id) return "";
                                            const e = DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id);
                                            return Quickshell.iconPath(e ? e.icon : id, "application-x-executable");
                                        }
                                        readonly property bool showIcon: appIcon !== ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        // Área vazia fica menor e mais apagada: dá para
                                        // ver que existe sem competir com as ocupadas.
                                        width: showIcon ? (active ? 34 : 22) : active ? 26 : (modelData.occupied ? 10 : 7)
                                        height: showIcon ? 20 : modelData.occupied || active ? 10 : 7
                                        radius: height / 2
                                        color: showIcon ? (active ? Theme.primary : wsArea.containsMouse ? Theme.tileHigh : "transparent")
                                            : active ? Theme.primary
                                            : modelData.urgent ? Theme.critical
                                            : wsArea.containsMouse ? Theme.textColor
                                            : Theme.withAlpha(Theme.subtext, modelData.occupied ? 0.55 : 0.28)
                                        border.width: showIcon && modelData.urgent ? 1.5 : 0
                                        border.color: Theme.critical
                                        Behavior on width { NumberAnimation { duration: Theme.ms(220); easing.type: Easing.OutCubic } }
                                        Behavior on height { NumberAnimation { duration: Theme.ms(220); easing.type: Easing.OutCubic } }
                                        Behavior on color { ColorAnimation { duration: Theme.ms(160) } }
                                        IconImage {
                                            visible: wsDot.showIcon
                                            anchors.centerIn: parent
                                            implicitSize: 14
                                            source: wsDot.appIcon
                                            opacity: wsDot.active ? 1 : 0.8
                                        }
                                        MouseArea {
                                            id: wsArea
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            // activate() usa a sintaxe antiga de dispatch,
                                            // que quebra com o config em Lua.
                                            onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsDot.modelData.id + " })")
                                        }
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                onWheel: w => Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + (w.angleDelta.y > 0 ? "e-1" : "e+1") + "\" })")
                            }
                        }

                        // Área especial (Super + A): um workspace "escondido" que abre
                        // por cima do atual. Colorido enquanto está aberta; o número é
                        // quantas janelas estão guardadas nela.
                        Rectangle {
                            id: specialBtn
                            property bool open: false
                            readonly property var ws: Hyprland.workspaces.values.find(w => w.name === "special:magic") || null
                            readonly property int count: ws && ws.toplevels ? ws.toplevels.values.length : 0
                            implicitWidth: specialRow.implicitWidth + 16
                            implicitHeight: bar.barH - 10
                            radius: height / 2
                            color: open ? Theme.withAlpha(Theme.primary, 0.3)
                                 : specialArea.containsMouse ? Theme.tileHigh : Theme.tile
                            border.width: open ? 1 : 0
                            border.color: Theme.primary
                            Behavior on color { ColorAnimation { duration: Theme.ms(140) } }

                            Row {
                                id: specialRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: specialBtn.open ? Theme.icons.star : Theme.icons.starOutline
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 12
                                    color: specialBtn.open ? Theme.primary : Theme.subtext
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: specialBtn.count > 0
                                    text: specialBtn.count
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: specialBtn.open ? Theme.primary : Theme.subtext
                                }
                            }
                            MouseArea {
                                id: specialArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Hyprland.dispatch('hl.dsp.workspace.toggle_special("magic")')
                            }
                            // Aberta ou fechada: vem do evento do Hyprland, que também
                            // cobre quem usa o atalho em vez do botão.
                            Connections {
                                target: Hyprland
                                function onRawEvent(event) {
                                    if (event.name === "activespecial")
                                        specialBtn.open = String(event.data).split(",")[0] === "special:magic";
                                }
                            }
                            Process {
                                running: true
                                command: ["hyprctl", "monitors", "-j"]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        try {
                                            specialBtn.open = JSON.parse(text).some(m => m.specialWorkspace && m.specialWorkspace.name === "special:magic");
                                        } catch (e) {}
                                    }
                                }
                            }
                        }

                        BarText {
                            Layout.maximumWidth: 420
                            text: Hyprland.activeToplevel && Hyprland.activeToplevel.workspace === Hyprland.focusedWorkspace
                                ? Hyprland.activeToplevel.title : ""
                            elide: Text.ElideRight
                            color: Theme.subtext
                            font.pixelSize: 12
                        }
                    }
                }
            }

            RowLayout {
                id: centerRow
                anchors.centerIn: parent
                spacing: 2
            }

            // O cava leve do disco só roda com o disco à mostra.
            Binding {
                target: MediaState
                property: "levelWanted"
                value: mediaMod.visible && bar.visible
            }

            // ---------- mídia: à esquerda do relógio (fora da ordem da direita) ----------
            // Só ícone: nota musical com um player aberto (tocando ou pausado),
            // equalizador sem nada. O hover abre o popup com a mídia, o volume do
            // app e a aba do equalizador (que antes tinha um ícone próprio).
            Module {
                id: mediaMod
                kind: "media"
                editKey: "media"
                visible: ShellLayout.barHas("media")
                onClicked: {
                    if (MediaState.player) MediaState.toggle();
                    else bar.showPopNow("media", mediaMod);
                }
                onRightClicked: if (MediaState.player) MediaState.next()
                // roda: volume do app que está tocando (MediaState)
                onWheel: d => MediaState.wheel(d)
                onHoverIn: if (!MediaState.player) bar.mediaTab = "eq"
                // Com player (tocando ou pausado): o disco com a capa, girando e
                // ondulando com o som. Sem nada: o ícone do equalizador.
                MediaDisc {
                    visible: MediaState.player !== null
                    size: 28
                }
                BarIcon {
                    visible: MediaState.player === null
                    text: Theme.icons.music
                    color: EqService.enabled ? Theme.primary : Theme.textColor
                }
            }

            // ---------- centro: relógio ----------
            Module {
                id: clockMod
                kind: ""
                editKey: "clock"
                visible: ShellLayout.barHas("clock")
                onClicked: bar.clockClicked()

                property date now: new Date()
                Timer { interval: 1000; running: true; repeat: true; onTriggered: clockMod.now = new Date() }

                BarText {
                    text: Qt.formatDateTime(clockMod.now, "HH:mm")
                    font.weight: Font.DemiBold
                }
                BarText {
                    text: Qt.formatDateTime(clockMod.now, "dd/MM")
                    color: Theme.subtext
                }
            }

            // ---------- mixer: à direita do relógio ----------
            // Volume de cada app que está tocando som (streams do PipeWire).
            Module {
                id: mixerMod
                kind: "mixer"
                editKey: "mixer"
                visible: ShellLayout.barHas("mixer")
                onClicked: bar.showPopNow("mixer", mixerMod)
                BarIcon {
                    text: Theme.icons.mixer
                    color: bar.streams.length > 0 ? Theme.textColor : Theme.subtext
                }
            }

            // Equalizador: ícone pequeno colado no relógio. Ele saiu da aba
            // Mídia do hub, que ficava apertada demais com ele dentro. Fica
            // colorido enquanto o equalizador está ligado.
            // ---------- direita ----------
            RowLayout {
                id: rightRow
                Component.onCompleted: bar.applyBarOrder()
                anchors.right: parent.right
                anchors.rightMargin: Theme.frameThickness + 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Module {
                    kind: ""
                    visible: GameMode.active
                    BarIcon { text: Theme.icons.gamepad; color: Theme.primary }
                }

                Module {
                    kind: "record"
                    // Com o item "Gravar" na barra, ele mesmo mostra a gravação.
                    visible: bar.recording && !ShellLayout.barHas("record")
                    onClicked: bar.stopRecording()
                    BarIcon {
                        text: Theme.icons.record
                        color: Theme.critical
                        SequentialAnimation on opacity {
                            running: bar.recording
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 700 }
                            NumberAnimation { to: 1; duration: 700 }
                        }
                    }
                }

                Module {
                    kind: "audio"
                    visible: bar.source && bar.source.audio && bar.source.audio.muted
                    onClicked: bar.source.audio.muted = false
                    BarIcon { text: Theme.icons.micOff; color: Theme.critical }
                }

                Module {
                    id: pomodoroMod
                    kind: "pomodoro"
                    visible: PomodoroService.active
                    onClicked: bar.clockClicked()
                    RowLayout {
                        spacing: 4
                        Text {
                            text: "󰄉"
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 13
                            color: PomodoroService.paused ? Theme.warning : Theme.primary
                        }
                        BarText {
                            text: PomodoroService.timeString
                            font.weight: Font.DemiBold
                            color: PomodoroService.paused ? Theme.warning : Theme.textColor
                        }
                    }
                }

                // Privacidade: um ponto só enquanto microfone, câmera ou
                // compartilhamento de tela estão em uso; o hover diz quem.
                Module {
                    id: privMod
                    kind: "privacy"
                    visible: ShellLayout.barPrivacy && Privacy.active
                    Rectangle {
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: 4
                        color: Theme.critical
                    }
                    BarIcon {
                        visible: Privacy.camApps.length > 0 || Privacy.screenApps.length > 0
                        text: Privacy.screenApps.length > 0 ? Theme.icons.screenShare : Theme.icons.webcam
                        font.pixelSize: 14
                        color: Theme.critical
                    }
                    BarIcon {
                        visible: Privacy.micApps.length > 0
                        text: Theme.icons.mic
                        font.pixelSize: 14
                        color: Theme.critical
                    }
                }

                Module {
                    id: weatherMod
                    kind: ""
                    editKey: "weather"
                    visible: ShellLayout.barHas("weather")
                    onClicked: bar.clockClicked()
                    RowLayout {
                        spacing: 4
                        BarIcon {
                            text: WeatherService.icon
                            font.pixelSize: 14
                            color: Theme.primary
                        }
                        BarText {
                            text: WeatherService.temp
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Module {
                    id: notifMod
                    kind: ""
                    editKey: "notifications"
                    visible: ShellLayout.barHas("notifications")
                    onClicked: bar.pop === "notifs" ? bar.pop = "" : bar.showPopNow("notifs", notifMod)
                    onRightClicked: NotifService.toggleDnd()

                    BarIcon {
                        text: NotifService.dnd ? Theme.icons.bellOff : Theme.icons.bell
                        color: NotifService.dnd ? Theme.secondary : (NotifService.unreadCount > 0 ? Theme.primary : Theme.textColor)
                        font.pixelSize: 15
                    }

                    Rectangle {
                        visible: NotifService.unreadCount > 0
                        implicitWidth: Math.max(16, notifBadgeText.implicitWidth + 8)
                        implicitHeight: 16
                        radius: 8
                        color: Theme.primary

                        Text {
                            id: notifBadgeText
                            anchors.centerIn: parent
                            text: NotifService.unreadCount > 99 ? "99+" : String(NotifService.unreadCount)
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Theme.background
                        }
                    }
                }

                Module {
                    id: wifiMod
                    kind: "wifi"
                    // Desktop ligado só no cabo não tem placa Wi-Fi: mostrar um
                    // ícone de "Wi-Fi desligado" pra sempre só confundia.
                    editKey: "network"
                    visible: (bar.wifiDevice !== null || bar.wiredDevice !== null) && ShellLayout.barHas("network")
                    BarIcon { text: bar.wiredDevice ? Theme.icons.ethernet : bar.wifiIcon() }
                }

                // Bluetooth na barra (opcional, pelo modo edição): popup com os
                // aparelhos, igual ao da rede. "Mais opções" abre a página do
                // painel de controle.
                Module {
                    id: btMod
                    kind: "bluetooth"
                    editKey: "bluetooth"
                    visible: bar.btAdapter !== null && ShellLayout.barHas("bluetooth")
                    onClicked: bar.btPageRequested()
                    BarIcon {
                        text: !bar.btAdapter || !bar.btAdapter.enabled ? Theme.icons.btOff
                            : bar.btConnected ? Theme.icons.btConnected : Theme.icons.bt
                        color: bar.btConnected ? Theme.primary : Theme.textColor
                    }
                }

                // Brilho, som e bateria num bloco só: o clique abre a central
                // de controle (Bluetooth e Configurações moram lá). A roda
                // continua mudando o volume.
                Module {
                    id: ctlMod
                    kind: ""
                    editKey: "control"
                    visible: ShellLayout.barHas("control")
                    onClicked: bar.controlClicked()
                    onHoverIn: bar.controlHovered(true)
                    onHoverOut: bar.controlHovered(false)
                    onWheel: d => bar.wheelVolume(d)
                    BarIcon {
                        visible: brMax.text().trim() !== ""
                        text: Theme.icons.brightness
                        font.pixelSize: 15
                    }
                    BarIcon { text: bar.volIcon(bar.sink) }
                    BarText { text: bar.sink && bar.sink.audio ? Math.round((bar.volTarget >= 0 ? bar.volTarget : bar.sink.audio.volume) * 100) + "%" : "--" }
                    BarIcon {
                        visible: bar.battery && bar.battery.isLaptopBattery
                        text: bar.batIcon()
                        color: bar.battery && bar.battery.percentage <= 0.15 && bar.battery.state !== UPowerDeviceState.Charging
                            ? Theme.critical : Theme.textColor
                    }
                    BarText {
                        visible: bar.battery && bar.battery.isLaptopBattery
                        text: bar.battery ? Math.round(bar.battery.percentage * 100) + "%" : ""
                    }
                }

                // ---------- itens do catálogo (modo edição) ----------
                Module {
                    id: trayMod
                    kind: ""
                    editKey: "tray"
                    passClicks: true
                    visible: ShellLayout.barHas("tray") && (SystemTray.items.values.length > 0 || ShellLayout.editing)
                    BarIcon {
                        visible: SystemTray.items.values.length === 0
                        text: Theme.icons.apps
                        font.pixelSize: 15
                    }
                    Repeater {
                        model: SystemTray.items
                        delegate: Item {
                            id: tIcon
                            required property SystemTrayItem modelData
                            implicitWidth: 20
                            implicitHeight: 20
                            IconImage {
                                anchors.fill: parent
                                source: tIcon.modelData.icon
                                opacity: tIcon.modelData.status === Status.Passive ? 0.6 : 1
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -3
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: mouse => {
                                    const it = tIcon.modelData;
                                    if (mouse.button === Qt.MiddleButton) it.secondaryActivate();
                                    else if (mouse.button === Qt.RightButton || it.onlyMenu) {
                                        const p = tIcon.mapToItem(null, 0, tIcon.height + 6);
                                        it.display(bar, p.x, p.y);
                                    } else it.activate();
                                }
                                onWheel: w => tIcon.modelData.scroll(w.angleDelta.y, false)
                            }
                        }
                    }
                }

                Module {
                    id: updMod
                    kind: ""
                    editKey: "updates"
                    visible: ShellLayout.barHas("updates")
                    onClicked: if (bar.energy) bar.energy.runUpdate()
                    BarIcon {
                        text: Theme.icons.update
                        font.pixelSize: 15
                        color: bar.energy && bar.energy.updateCount > 0 ? Theme.primary : Theme.textColor
                    }
                    BarText {
                        visible: bar.energy && bar.energy.updateCount > 0
                        text: bar.energy ? (bar.energy.updateCount > 99 ? "99+" : String(bar.energy.updateCount)) : ""
                    }
                }

                Module {
                    id: nightMod
                    kind: ""
                    editKey: "night"
                    visible: ShellLayout.barHas("night")
                    onClicked: if (bar.energy) bar.energy.toggleNight()
                    BarIcon {
                        text: Theme.icons.night
                        font.pixelSize: 15
                        color: bar.energy && bar.energy.nightLight ? Theme.primary : Theme.textColor
                    }
                }

                Module {
                    id: cafMod
                    kind: ""
                    editKey: "caffeine"
                    visible: ShellLayout.barHas("caffeine")
                    onClicked: if (bar.energy) bar.energy.toggleCaffeine()
                    BarIcon {
                        text: bar.energy && bar.energy.caffeine ? Theme.icons.coffee : Theme.icons.coffeeOff
                        font.pixelSize: 15
                        color: bar.energy && bar.energy.caffeine ? Theme.primary : Theme.textColor
                    }
                }

                Module {
                    id: recMod
                    kind: ""
                    editKey: "record"
                    visible: ShellLayout.barHas("record")
                    onClicked: {
                        if (bar.recording) bar.stopRecording();
                        else Quickshell.execDetached(["rice-record", "full"]);
                    }
                    BarIcon {
                        text: Theme.icons.record
                        font.pixelSize: 15
                        color: bar.recording ? Theme.critical : Theme.textColor
                    }
                }

                Module {
                    id: shotMod
                    kind: ""
                    editKey: "screenshot"
                    visible: ShellLayout.barHas("screenshot")
                    onClicked: Quickshell.execDetached(["rice-screenshot", "region"])
                    onRightClicked: Quickshell.execDetached(["rice-screenshot", "output"])
                    BarIcon { text: Theme.icons.camera; font.pixelSize: 15 }
                }

                Module {
                    id: clipMod
                    kind: ""
                    editKey: "clipboard"
                    visible: ShellLayout.barHas("clipboard")
                    onClicked: Quickshell.execDetached(["quickshell", "ipc", "call", "clipboard", "open"])
                    BarIcon { text: Theme.icons.clipboard; font.pixelSize: 15 }
                }

                Module {
                    id: pickMod
                    kind: "picker"
                    editKey: "picker"
                    visible: ShellLayout.barHas("picker")
                    onClicked: { bar.pop = ""; ColorPick.pick(); }
                    BarIcon { text: Theme.icons.eyedropper; font.pixelSize: 15 }
                }

                Module {
                    id: gpuMod
                    kind: ""
                    editKey: "gpu"
                    visible: ShellLayout.barHas("gpu")
                    onClicked: Quickshell.execDetached(["quickshell", "ipc", "call", "sidebar", "toggle"])
                    BarIcon {
                        text: Theme.icons.gpu
                        font.pixelSize: 15
                        color: bar.energy && bar.energy.nvidiaState === "active" ? Theme.primary : Theme.subtext
                    }
                }

                Module {
                    id: lockMod
                    kind: ""
                    editKey: "lock"
                    visible: ShellLayout.barHas("lock")
                    onClicked: Quickshell.execDetached(["rice-session-action", "lock"])
                    BarIcon { text: Theme.icons.lock; font.pixelSize: 15 }
                }

                Module {
                    id: setMod
                    kind: ""
                    editKey: "settings"
                    visible: ShellLayout.barHas("settings")
                    onClicked: bar.visualConfigClicked()
                    BarIcon { text: Theme.icons.tune; font.pixelSize: 15 }
                }

                Module {
                    id: powMod
                    kind: ""
                    editKey: "power"
                    visible: ShellLayout.barHas("power")
                    onClicked: Quickshell.execDetached(["quickshell", "ipc", "call", "sidebar", "toggle"])
                    BarIcon { text: Theme.icons.power; font.pixelSize: 15; color: Theme.secondary }
                }
            }
        }

        // ================= popup =================
        Item {
            id: popArea
            x: root.popX + (root.popTargetW - root.popW) / 2
            y: bar.barH
            width: root.popW
            height: root.popH
            clip: true

            HoverHandler {
                onHoveredChanged: hovered ? popHide.stop() : bar.leavePop()
            }

            Item {
                id: popContent
                x: 16 - (root.popTargetW - root.popW) / 2
                y: 14
                // ColumnLayout recalcula o próprio implicitWidth pelo conteúdo
                // (linhas com fillWidth contam ~0), então os popups de largura
                // fixa declaram `width` e ele vale mais que o implícito.
                implicitWidth: current ? Math.max(current.width, current.implicitWidth) : 0
                implicitHeight: current ? current.implicitHeight : 0
                width: implicitWidth
                height: implicitHeight
                // Arrastando um slider: não fecha nem se o mouse escapar do popup.
                readonly property bool busy: audioPop.dragging || mixerPop.dragging || EqService.dragging || mediaPop.dragging
                readonly property Item current: {
                    switch (bar.pop) {
                    case "audio": return audioPop;
                    case "wifi": return wifiPop;
                    case "record": return recordPop;
                    case "media": return mediaPop;
                    case "picker": return pickerPop;
                    case "privacy": return privacyPop;
                    case "mixer": return mixerPop;
                    case "bluetooth": return btPop;
                    case "notifs": return notifsPop;
                    }
                    return null;
                }
                opacity: root.popTargetW > 0 && Math.abs(root.popW - root.popTargetW) < 30
                    && Math.abs(root.popH - root.popTargetH) < 30 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.ms(140) } }

                // ---------- mídia + equalizador ----------
                ColumnLayout {
                    id: mediaPop
                    visible: popContent.current === mediaPop
                    width: 440
                    spacing: 10
                    readonly property bool dragging: seekArea.pressed || volArea.pressed

                    // abas largas, dividindo a largura
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: [
                                { k: "media", label: Theme.t("topbar.media_tab", "Mídia") },
                                { k: "eq", label: Theme.t("topbar.eq_tab", "Equalizador") }
                            ]
                            delegate: Rectangle {
                                id: mt
                                required property var modelData
                                readonly property bool on: bar.mediaTab === mt.modelData.k
                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: 9
                                color: mt.on ? Theme.tileHigh : (mtArea.containsMouse ? Theme.withAlpha(Theme.tileHigh, 0.5) : Theme.withAlpha(Theme.tile, 0.5))
                                Text {
                                    anchors.centerIn: parent
                                    text: mt.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: mt.on ? Font.DemiBold : Font.Normal
                                    color: mt.on ? Theme.textColor : Theme.subtext
                                }
                                MouseArea {
                                    id: mtArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: bar.mediaTab = mt.modelData.k
                                }
                            }
                        }
                    }

                    // --- mídia ---
                    PopText {
                        visible: bar.mediaTab === "media" && !MediaState.player
                        text: Theme.t("topbar.nothing_playing", "Nada tocando agora.")
                    }
                    RowLayout {
                        visible: bar.mediaTab === "media" && MediaState.player !== null
                        Layout.fillWidth: true
                        spacing: 14

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                Rectangle {
                                    implicitWidth: 72
                                    implicitHeight: 72
                                    radius: 12
                                    color: Theme.tileHigh
                                    clip: true
                                    Image {
                                        id: mediaArt
                                        anchors.fill: parent
                                        source: MediaState.player && MediaState.player.trackArtUrl ? MediaState.player.trackArtUrl : ""
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize: Qt.size(144, 144)
                                        asynchronous: true
                                        visible: status === Image.Ready
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !mediaArt.visible
                                        text: Theme.icons.album
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 24
                                        color: Theme.subtext
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        Layout.fillWidth: true
                                        text: MediaState.player ? (MediaState.player.trackTitle || MediaState.player.identity || "") : ""
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                        color: Theme.textColor
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: MediaState.player ? (MediaState.player.trackArtist || "") : ""
                                        visible: text !== ""
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.subtext
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: MediaState.player ? (MediaState.player.identity || "") : ""
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        color: Theme.withAlpha(Theme.subtext, 0.7)
                                    }
                                    Row {
                                        Layout.topMargin: 4
                                        spacing: 4
                                        Repeater {
                                            model: [
                                                { icon: Theme.icons.prev, act: "prev" },
                                                { icon: MediaState.playing ? Theme.icons.pause : Theme.icons.play, act: "toggle" },
                                                { icon: Theme.icons.next, act: "next" }
                                            ]
                                            delegate: Rectangle {
                                                id: mbtn
                                                required property var modelData
                                                width: 36
                                                height: 30
                                                radius: 9
                                                color: mbtnArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.6)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: mbtn.modelData.icon
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 17
                                                    color: Theme.textColor
                                                }
                                                MouseArea {
                                                    id: mbtnArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (mbtn.modelData.act === "prev") MediaState.previous();
                                                        else if (mbtn.modelData.act === "next") MediaState.next();
                                                        else MediaState.toggle();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // duração: arrastar/clicar busca (se o player deixar)
                            RowLayout {
                                Layout.fillWidth: true
                                visible: MediaState.length > 0
                                spacing: 8
                                readonly property real shownPos: seekArea.pressed ? seekArea.dragPos : MediaState.position
                                Text {
                                    text: MediaState.fmt(parent.shownPos)
                                    font.family: Theme.monoFamily
                                    font.pixelSize: 10
                                    color: Theme.subtext
                                }
                                Item {
                                    id: seekBar
                                    Layout.fillWidth: true
                                    implicitHeight: 16
                                    readonly property real frac: MediaState.length > 0
                                        ? Math.max(0, Math.min(1, parent.shownPos / MediaState.length)) : 0
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        height: 4
                                        radius: 2
                                        color: Theme.withAlpha(Theme.outline, 0.35)
                                        Rectangle {
                                            width: parent.width * seekBar.frac
                                            height: parent.height
                                            radius: 2
                                            color: Theme.primary
                                        }
                                    }
                                    Rectangle {
                                        visible: MediaState.canSeek
                                        x: seekBar.width * seekBar.frac - width / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: seekArea.containsMouse || seekArea.pressed ? 12 : 8
                                        height: width
                                        radius: width / 2
                                        color: Theme.textColor
                                    }
                                    MouseArea {
                                        id: seekArea
                                        anchors.fill: parent
                                        enabled: MediaState.canSeek
                                        hoverEnabled: true
                                        preventStealing: true
                                        cursorShape: Qt.PointingHandCursor
                                        property real dragPos: 0
                                        function at(x) { return Math.max(0, Math.min(1, x / width)) * MediaState.length; }
                                        onPressed: mouse => dragPos = at(mouse.x)
                                        onPositionChanged: mouse => { if (pressed) dragPos = at(mouse.x); }
                                        onReleased: MediaState.seek(dragPos)
                                    }
                                }
                                Text {
                                    text: MediaState.fmt(MediaState.length)
                                    font.family: Theme.monoFamily
                                    font.pixelSize: 10
                                    color: Theme.subtext
                                }
                            }
                        }

                        // volume do app, na vertical à direita
                        ColumnLayout {
                            visible: MediaState.hasVolume
                            Layout.fillHeight: true
                            Layout.preferredWidth: 34
                            spacing: 6
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: Math.round(volCol.shown * 100) + "%"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.subtext
                            }
                            Item {
                                id: volCol
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillHeight: true
                                Layout.minimumHeight: 70
                                implicitWidth: 24
                                // valor local enquanto arrasta (o PipeWire demora a refletir)
                                property real local: -1
                                readonly property real shown: volArea.pressed && local >= 0 ? local : MediaState.shownVolume
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 6
                                    height: parent.height
                                    radius: 3
                                    color: Theme.withAlpha(Theme.outline, 0.35)
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: parent.height * volCol.shown
                                        radius: 3
                                        color: MediaState.muted ? Theme.subtext : Theme.primary
                                    }
                                }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: (parent.height - height) * (1 - volCol.shown)
                                    width: volArea.containsMouse || volArea.pressed ? 14 : 10
                                    height: width
                                    radius: width / 2
                                    color: Theme.textColor
                                }
                                MouseArea {
                                    id: volArea
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor
                                    function at(y) { return Math.max(0, Math.min(1, 1 - (y - 4) / volCol.height)); }
                                    onPressed: mouse => { volCol.local = at(mouse.y); MediaState.setVolume(volCol.local); }
                                    onPositionChanged: mouse => {
                                        if (!pressed) return;
                                        volCol.local = at(mouse.y);
                                        MediaState.setVolume(volCol.local);
                                    }
                                    onWheel: w => MediaState.wheel(w.angleDelta.y)
                                }
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: MediaState.muted ? Theme.icons.volOff : Theme.icons.music
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 15
                                color: MediaState.muted ? Theme.subtext : Theme.textColor
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: MediaState.toggleMute()
                                }
                            }
                        }
                    }

                    // --- equalizador ---
                    Item {
                        visible: bar.mediaTab === "eq"
                        Layout.fillWidth: true
                        implicitHeight: 270
                        Equalizer {
                            anchors.fill: parent
                            compact: true
                        }
                    }
                }

                // ---------- gravação ----------
                ColumnLayout {
                    id: recordPop
                    visible: popContent.current === recordPop
                    spacing: 2
                    PopTitle { text: Theme.t("topbar.recording_active", "Gravando a tela"); color: Theme.critical }
                    PopText { text: Theme.t("topbar.click_to_stop", "Clique no ícone para parar (ou Super+Shift+R)") }
                }

                // ---------- áudio ----------
                ColumnLayout {
                    id: audioPop
                    visible: popContent.current === audioPop
                    width: 320
                    spacing: 6
                    readonly property bool dragging: outSlider.dragging || inSlider.dragging

                    PopTitle { text: Theme.t("topbar.output", "Saída") }
                    PopSlider {
                        id: outSlider
                        max: AudioPrefs.maxVolume
                        icon: bar.volIcon(bar.sink)
                        label: bar.nodeName(bar.sink)
                        value: bar.sink && bar.sink.audio ? bar.sink.audio.volume : 0
                        dimmed: bar.sink && bar.sink.audio ? bar.sink.audio.muted : true
                        onMoved: v => { if (bar.sink) bar.sink.audio.volume = v; }
                        onIconClicked: if (bar.sink) bar.sink.audio.muted = !bar.sink.audio.muted
                    }
                    Repeater {
                        model: bar.sinks.length > 1 ? bar.sinks : []
                        delegate: PopAction {
                            required property var modelData
                            icon: (modelData.properties["device.form-factor"] || "").includes("head") ? Theme.icons.headphones : Theme.icons.speaker
                            label: bar.nodeName(modelData)
                            selected: modelData === bar.sink
                            onActivated: Pipewire.preferredDefaultAudioSink = modelData
                        }
                    }

                    PopTitle { text: Theme.t("topbar.microphone", "Microfone"); Layout.topMargin: 6 }
                    PopSlider {
                        id: inSlider
                        icon: bar.source && bar.source.audio && bar.source.audio.muted ? Theme.icons.micOff : Theme.icons.mic
                        label: bar.nodeName(bar.source)
                        value: bar.source && bar.source.audio ? bar.source.audio.volume : 0
                        dimmed: bar.source && bar.source.audio ? bar.source.audio.muted : true
                        onMoved: v => { if (bar.source) bar.source.audio.volume = v; }
                        onIconClicked: if (bar.source) bar.source.audio.muted = !bar.source.audio.muted
                    }
                    Repeater {
                        model: bar.sources.length > 1 ? bar.sources : []
                        delegate: PopAction {
                            required property var modelData
                            icon: Theme.icons.mic
                            label: bar.nodeName(modelData)
                            selected: modelData === bar.source
                            onActivated: Pipewire.preferredDefaultAudioSource = modelData
                        }
                    }

                    PopTitle { text: Theme.t("topbar.apps", "Aplicativos"); Layout.topMargin: 6; visible: bar.streams.length > 0 }
                    Repeater {
                        model: bar.streams
                        delegate: PopSlider {
                            required property var modelData
                            max: AudioPrefs.maxVolume
                            icon: bar.volIcon(modelData)
                            label: bar.nodeName(modelData)
                            value: modelData.audio ? modelData.audio.volume : 0
                            dimmed: modelData.audio ? modelData.audio.muted : true
                            onMoved: v => { if (modelData.audio) modelData.audio.volume = v; }
                            onIconClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                        }
                    }
                }

                // ---------- bluetooth ----------
                ColumnLayout {
                    id: btPop
                    visible: popContent.current === btPop
                    width: 300
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        PopTitle {
                            Layout.fillWidth: true
                            text: !bar.btAdapter || !bar.btAdapter.enabled ? Theme.t("bt.off", "Bluetooth desligado")
                                : bar.btConnected ? (bar.btConnected.name || bar.btConnected.address) : "Bluetooth"
                        }
                        Rectangle {
                            implicitWidth: 40
                            implicitHeight: 22
                            radius: 11
                            readonly property bool on: bar.btAdapter !== null && bar.btAdapter.enabled
                            color: on ? Theme.primary : Theme.tileHigh
                            Rectangle {
                                width: 16; height: 16; radius: 8
                                anchors.verticalCenter: parent.verticalCenter
                                x: parent.on ? parent.width - width - 3 : 3
                                color: Theme.textColor
                                Behavior on x { NumberAnimation { duration: Theme.ms(140) } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (bar.btAdapter) bar.btAdapter.enabled = !bar.btAdapter.enabled
                            }
                        }
                    }
                    PopText {
                        visible: bar.btAdapter !== null && bar.btAdapter.enabled && bar.btDevices.length === 0
                        text: Theme.t("bt.none_paired", "Nenhum aparelho pareado")
                    }
                    Repeater {
                        model: bar.btAdapter && bar.btAdapter.enabled ? bar.btDevices.slice(0, 8) : []
                        delegate: PopAction {
                            required property var modelData
                            icon: modelData.connected ? Theme.icons.btConnected : Theme.icons.bt
                            label: modelData.name || modelData.address
                            detail: modelData.state === BluetoothDeviceState.Connecting ? Theme.t("wifi.connecting", "conectando…")
                                : modelData.connected ? (modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : Theme.t("cc.connected", "conectado")) : ""
                            selected: modelData.connected
                            onActivated: modelData.connected ? modelData.disconnect() : modelData.connect()
                        }
                    }
                    PopAction {
                        Layout.topMargin: 4
                        icon: Theme.icons.chevronRight
                        label: Theme.t("bt.more", "Buscar e mais opções")
                        onActivated: { bar.pop = ""; bar.btPageRequested(); }
                    }
                }

                // ---------- notificações (histórico, não perturbe) ----------
                Item {
                    id: notifsPop
                    visible: popContent.current === notifsPop
                    width: 400
                    implicitHeight: notifsView.wantedHeight
                    Notifications { id: notifsView; anchors.fill: parent; visible: notifsPop.visible }
                }

                // ---------- mixer (volume por app) ----------
                ColumnLayout {
                    id: mixerPop
                    visible: popContent.current === mixerPop
                    width: 320
                    spacing: 6
                    property bool dragging: false

                    PopTitle { text: Theme.t("mixer.title", "Volume dos apps") }
                    PopText {
                        visible: bar.streams.length === 0
                        text: Theme.t("mixer.empty", "Nenhum app tocando som agora")
                    }
                    Repeater {
                        model: bar.streams
                        delegate: PopSlider {
                            required property var modelData
                            max: AudioPrefs.maxVolume
                            icon: bar.volIcon(modelData)
                            label: bar.nodeName(modelData)
                            value: modelData.audio ? modelData.audio.volume : 0
                            dimmed: modelData.audio ? modelData.audio.muted : true
                            onDraggingChanged: mixerPop.dragging = dragging
                            onMoved: v => { if (modelData.audio) modelData.audio.volume = v; }
                            onIconClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                        }
                    }
                    // Mesmo interruptor da aba Áudio das configurações (AudioPrefs).
                    PopAction {
                        Layout.topMargin: 4
                        icon: Theme.icons.volHigh
                        label: Theme.t("mixer.boost", "Permitir até 150%")
                        detail: Theme.t("mixer.boost_sub", "Pode distorcer o som")
                        selected: AudioPrefs.maxVolume > 1
                        onActivated: {
                            const on = AudioPrefs.maxVolume <= 1;
                            AudioPrefs.setMax(on ? 150 : 100);
                            if (!on) for (const n of bar.streams.concat([bar.sink]))
                                if (n && n.audio && n.audio.volume > 1) n.audio.volume = 1;
                        }
                    }
                }

                // ---------- conta-gotas ----------
                ColumnLayout {
                    id: pickerPop
                    visible: popContent.current === pickerPop
                    width: 300
                    spacing: 6

                    PopTitle { text: Theme.t("picker.title", "Cores recentes") }
                    PopText {
                        visible: ColorPick.history.length === 0
                        text: Theme.t("picker.empty", "Clique no ícone para pegar uma cor da tela")
                    }
                    Repeater {
                        model: ColorPick.history
                        delegate: RowLayout {
                            id: colorRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                implicitWidth: 18
                                implicitHeight: 18
                                radius: 5
                                color: colorRow.modelData
                                border.width: 1
                                border.color: Theme.border
                            }
                            Repeater {
                                model: [colorRow.modelData, ColorPick.rgb(colorRow.modelData), ColorPick.hsl(colorRow.modelData)]
                                delegate: Rectangle {
                                    id: fmt
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: fmt.index > 0
                                    implicitWidth: fmtText.implicitWidth + 12
                                    implicitHeight: 24
                                    radius: 6
                                    color: fmtArea.containsMouse ? Theme.tileHigh : "transparent"
                                    Text {
                                        id: fmtText
                                        anchors.centerIn: parent
                                        text: ColorPick.copied === fmt.modelData ? Theme.t("picker.copied", "copiado") : fmt.modelData
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: ColorPick.copied === fmt.modelData ? Theme.primary : Theme.subtext
                                    }
                                    MouseArea {
                                        id: fmtArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ColorPick.copy(fmt.modelData)
                                    }
                                }
                            }
                        }
                    }
                    PopAction {
                        Layout.topMargin: 4
                        icon: Theme.icons.eyedropper
                        label: Theme.t("picker.pick", "Pegar uma cor da tela")
                        onActivated: { bar.pop = ""; ColorPick.pick(); }
                    }
                }

                // ---------- privacidade ----------
                ColumnLayout {
                    id: privacyPop
                    visible: popContent.current === privacyPop
                    width: 280
                    spacing: 4

                    PopTitle { text: Theme.t("privacy.title", "Em uso agora") }
                    Repeater {
                        model: Privacy.micApps
                        delegate: PopAction {
                            required property var modelData
                            icon: Theme.icons.mic
                            label: modelData
                            detail: Theme.t("privacy.mic", "microfone")
                        }
                    }
                    Repeater {
                        model: Privacy.camApps
                        delegate: PopAction {
                            required property var modelData
                            icon: Theme.icons.webcam
                            label: modelData
                            detail: Theme.t("privacy.cam", "câmera")
                        }
                    }
                    Repeater {
                        model: Privacy.screenApps
                        delegate: PopAction {
                            required property var modelData
                            icon: Theme.icons.screenShare
                            label: modelData
                            detail: Theme.t("privacy.screen", "tela")
                        }
                    }
                }

                // ---------- wifi ----------
                ColumnLayout {
                    id: wifiPop
                    visible: popContent.current === wifiPop
                    width: 300
                    spacing: 4

                    // Escaneia só enquanto o popup está aberto.
                    Binding {
                        target: bar.wifiDevice
                        property: "scannerEnabled"
                        value: bar.pop === "wifi"
                        when: bar.wifiDevice !== null
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PopTitle {
                            Layout.fillWidth: true
                            text: !Networking.wifiEnabled ? Theme.t("topbar.wifi_off", "Wi-Fi desligado")
                                : bar.activeNetwork ? bar.activeNetwork.name : "Wi-Fi"
                        }
                        Rectangle {
                            implicitWidth: 40
                            implicitHeight: 22
                            radius: 11
                            color: Networking.wifiEnabled ? Theme.primary : Theme.tileHigh
                            Rectangle {
                                width: 16; height: 16; radius: 8
                                anchors.verticalCenter: parent.verticalCenter
                                x: Networking.wifiEnabled ? parent.width - width - 3 : 3
                                color: Theme.textColor
                                Behavior on x { NumberAnimation { duration: Theme.ms(140) } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                            }
                        }
                    }
                    
                    WifiList {
                        Layout.fillWidth: true
                        device: bar.wifiDevice
                    }

                    PopAction {
                        Layout.topMargin: 6
                        icon: Theme.icons.refresh
                        label: Theme.t("wifi.restart", "Reiniciar rede")
                        needsConfirm: true
                        onActivated: netRestart.running = true
                    }
                }

            }
        }
    }

    // IPC de teste: `qs ipc call bar popup <audio|wifi|media|eq>` / `hide`
    IpcHandler {
        target: "bar"
        function popup(kind: string): void {
            if (kind === "eq" || kind === "media") {
                bar.mediaTab = kind === "eq" ? "eq" : "media";
                bar.showPopNow("media", mediaMod);
                return;
            }
            const m = { audio: ctlMod, wifi: wifiMod, picker: pickMod, privacy: privMod, mixer: mixerMod }[kind];
            if (m) bar.showPopNow(kind, m);
        }
        function hide(): void { bar.pop = ""; }
        // Posição do popup aberto (para testes recortarem o print certo).
        function geometry(): string {
            return JSON.stringify({ x: Math.round(popArea.x), y: Math.round(popArea.y), w: Math.round(popArea.width), h: Math.round(popArea.height) });
        }
        function setBarVisible(v: bool): void { bar.visible = v; }
    }
}
