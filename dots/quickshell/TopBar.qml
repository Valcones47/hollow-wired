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
    property bool recording: false
    signal stopRecording()

    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.waybarHeight + 460
    exclusiveZone: Theme.waybarHeight
    color: "transparent"
    focusable: false

    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property int barH: Theme.waybarHeight

    mask: Region {
        x: 0
        y: 0
        width: bar.width
        height: bar.barH
        Region { item: popArea }
    }

    // ================= estado do popup =================
    property string pop: ""
    property real popAnchorX: 0
    onPopChanged: {
        if (pop === "battery") {
            if (!blurCheck.running) blurCheck.running = true;
            if (!perfCheck.running) perfCheck.running = true;
        }
    }

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
        && (n.properties["media.class"] || "") === "Stream/Output/Audio")
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
            brCur.reload();
            bar.brightness = (parseFloat(brCur.text()) || 0) / (parseFloat(brMax.text()) || 1);
        }
    }
    Process { id: brSet; property int pct: 0; command: ["brightnessctl", "-q", "set", pct + "%"] }
    function setBrightness(v) {
        brightness = Math.max(0.01, v);
        brSet.pct = Math.max(1, Math.round(v * 100));
        brSet.running = true;
    }

    // --- bateria ---
    readonly property var battery: UPower.displayDevice
    property int batteryCycles: 0
    FileView { id: cycles; path: "/sys/class/power_supply/BAT1/cycle_count"; blockLoading: true
        onLoaded: bar.batteryCycles = parseInt(text()) || 0 }
    // Saúde: o UPower não expõe nesse notebook, mas o kernel tem a
    // capacidade atual (charge_full) e a de fábrica (charge_full_design).
    FileView { id: chFull; path: "/sys/class/power_supply/BAT1/charge_full"; blockLoading: true }
    FileView { id: chDesign; path: "/sys/class/power_supply/BAT1/charge_full_design"; blockLoading: true }
    readonly property real batteryHealth: (parseFloat(chFull.text()) || 0) / (parseFloat(chDesign.text()) || 1)
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
    readonly property var activeNetwork: wifiDevice ? wifiDevice.networks.values.find(n => n.connected) || null : null
    function wifiIcon() {
        if (!Networking.wifiEnabled) return Theme.icons.wifiOff;
        if (!activeNetwork) return Theme.icons.wifiOff;
        const s = activeNetwork.signalStrength;
        return s > 0.75 ? Theme.icons.wifi4 : s > 0.5 ? Theme.icons.wifi3 : s > 0.25 ? Theme.icons.wifi2 : Theme.icons.wifi1;
    }
    Process { id: nmtuiProc; property string ssid: ""; command: ["kitty", "--class", "rice-nmtui", "-e", "nmtui-connect", ssid] }
    Process { id: netRestart; command: ["bash", "-c", "nmcli networking off && sleep 2 && nmcli networking on"] }

    // --- bluetooth ---
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btDevices: btAdapter ? btAdapter.devices.values.slice().sort((a, b) =>
        (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name)) : []
    readonly property int btConnected: btDevices.filter(d => d.connected).length

    // --- otimizações / modos de desempenho ---
    property bool blurEnabled: true
    Process {
        id: blurCheck
        command: ["rice-blur-toggle", "status"]
        stdout: StdioCollector {
            onStreamFinished: bar.blurEnabled = text.trim() === "1"
        }
    }
    Process {
        id: blurToggleProc
        command: ["rice-blur-toggle"]
        onExited: {
            blurRecheck.restart();
            perfRecheck.restart();
        }
    }
    Timer { id: blurRecheck; interval: 300; onTriggered: blurCheck.running = true }

    property bool perfModeEnabled: false
    Process {
        id: perfCheck
        command: ["rice-perf-mode", "status"]
        stdout: StdioCollector {
            onStreamFinished: bar.perfModeEnabled = text.trim() === "1"
        }
    }
    Process {
        id: perfToggleProc
        command: ["rice-perf-mode"]
        onExited: {
            perfRecheck.restart();
            blurRecheck.restart();
        }
    }
    Timer { id: perfRecheck; interval: 300; onTriggered: perfCheck.running = true }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!blurCheck.running) blurCheck.running = true;
            if (!perfCheck.running) perfCheck.running = true;
        }
    }

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
        default property alias content: modRow.data
        signal clicked()
        signal rightClicked()
        signal wheel(int delta)

        implicitWidth: modRow.implicitWidth + 18
        implicitHeight: bar.barH - 8
        radius: height / 2
        color: modArea.containsMouse || bar.pop === kind ? Theme.tileHigh : "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }

        RowLayout {
            id: modRow
            anchors.centerIn: parent
            spacing: 5
        }
        MouseArea {
            id: modArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: if (mod.kind !== "") bar.showPop(mod.kind, mod)
            onExited: bar.leavePop()
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    mod.rightClicked();
                } else {
                    mod.clicked();
                }
            }
            onWheel: w => mod.wheel(w.angleDelta.y)
        }
    }

    // ================= conteúdo =================
    Item {
        id: root
        anchors.fill: parent

        // ---------- geometria animada do popup ----------
        readonly property real radius: Theme.frameRadius
        readonly property real popTargetW: bar.pop !== "" ? popContent.implicitWidth + 32 : 0
        readonly property real popTargetH: bar.pop !== "" ? popContent.implicitHeight + 28 : 0
        property real popW: popTargetW
        property real popH: popTargetH
        property real popX: Math.max(Theme.frameThickness + radius,
            Math.min(width - Theme.frameThickness - radius - Math.max(popTargetW, 1), bar.popAnchorX - popTargetW / 2))
        Behavior on popW { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on popH { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on popX {
            enabled: root.popH > 4
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
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

            // ---------- esquerda: workspaces + janela ativa ----------
            RowLayout {
                anchors.left: parent.left
                anchors.leftMargin: Theme.frameThickness + 6
                anchors.verticalCenter: parent.verticalCenter
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
                            model: Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id)
                            delegate: Rectangle {
                                id: wsDot
                                required property var modelData
                                readonly property bool active: Hyprland.focusedWorkspace === modelData
                                anchors.verticalCenter: parent.verticalCenter
                                width: active ? 26 : 10
                                height: 10
                                radius: 5
                                color: active ? Theme.primary
                                    : modelData.urgent ? Theme.critical
                                    : wsArea.containsMouse ? Theme.textColor : Theme.withAlpha(Theme.subtext, 0.55)
                                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 160 } }
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

                BarText {
                    Layout.maximumWidth: 420
                    text: Hyprland.activeToplevel && Hyprland.activeToplevel.workspace === Hyprland.focusedWorkspace
                        ? Hyprland.activeToplevel.title : ""
                    elide: Text.ElideRight
                    color: Theme.subtext
                    font.pixelSize: 12
                }
            }

            // ---------- centro: relógio ----------
            Module {
                id: clockMod
                kind: ""
                anchors.centerIn: parent
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

            // ---------- direita ----------
            RowLayout {
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
                    visible: bar.recording
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
                    id: notifMod
                    kind: ""
                    onClicked: bar.notifClicked()
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
                    BarIcon { text: bar.wifiIcon() }
                }

                Module {
                    id: btMod
                    kind: "bt"
                    BarIcon {
                        text: !bar.btAdapter || !bar.btAdapter.enabled ? Theme.icons.btOff
                            : bar.btConnected > 0 ? Theme.icons.btConnected : Theme.icons.bt
                        color: bar.btConnected > 0 ? Theme.primary : Theme.textColor
                    }
                }

                Module {
                    id: audioMod
                    kind: "audio"
                    onClicked: if (bar.sink) bar.sink.audio.muted = !bar.sink.audio.muted
                    onWheel: d => { if (bar.sink) bar.sink.audio.volume = Math.max(0, Math.min(1, bar.sink.audio.volume + (d > 0 ? 0.05 : -0.05))); }
                    BarIcon { text: bar.volIcon(bar.sink) }
                    BarText { text: bar.sink && bar.sink.audio ? Math.round(bar.sink.audio.volume * 100) + "%" : "--" }
                }

                Module {
                    id: brMod
                    kind: "brightness"
                    onWheel: d => bar.setBrightness(bar.brightness + (d > 0 ? 0.05 : -0.05))
                    BarIcon { text: Theme.icons.brightness }
                    BarText { text: Math.round(bar.brightness * 100) + "%" }
                }

                Module {
                    id: batMod
                    kind: "battery"
                    visible: bar.battery && bar.battery.isLaptopBattery
                    BarIcon {
                        text: bar.batIcon()
                        color: bar.battery && bar.battery.percentage <= 0.15 && bar.battery.state !== UPowerDeviceState.Charging
                            ? Theme.critical : Theme.textColor
                    }
                    BarText { text: bar.battery ? Math.round(bar.battery.percentage * 100) + "%" : "" }
                    BarIcon {
                        font.pixelSize: 14
                        color: Theme.primary
                        text: PowerProfiles.profile === PowerProfile.Performance ? Theme.icons.perf
                            : PowerProfiles.profile === PowerProfile.PowerSaver ? Theme.icons.saver : Theme.icons.balanced
                    }
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
                readonly property bool busy: audioPop.dragging || brightnessPop.dragging
                readonly property Item current: {
                    switch (bar.pop) {
                    case "audio": return audioPop;
                    case "brightness": return brightnessPop;
                    case "battery": return batteryPop;
                    case "wifi": return wifiPop;
                    case "bt": return btPop;
                    case "record": return recordPop;
                    }
                    return null;
                }
                opacity: root.popTargetW > 0 && Math.abs(root.popW - root.popTargetW) < 30
                    && Math.abs(root.popH - root.popTargetH) < 30 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }

                // ---------- gravação ----------
                ColumnLayout {
                    id: recordPop
                    visible: popContent.current === recordPop
                    spacing: 2
                    PopTitle { text: "Gravando a tela"; color: Theme.critical }
                    PopText { text: "Clique no ícone para parar (ou Super+Shift+R)" }
                }

                // ---------- áudio ----------
                ColumnLayout {
                    id: audioPop
                    visible: popContent.current === audioPop
                    width: 320
                    spacing: 6
                    readonly property bool dragging: outSlider.dragging || inSlider.dragging

                    PopTitle { text: "Saída" }
                    PopSlider {
                        id: outSlider
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

                    PopTitle { text: "Microfone"; Layout.topMargin: 6 }
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

                    PopTitle { text: "Aplicativos"; Layout.topMargin: 6; visible: bar.streams.length > 0 }
                    Repeater {
                        model: bar.streams
                        delegate: PopSlider {
                            required property var modelData
                            icon: bar.volIcon(modelData)
                            label: bar.nodeName(modelData)
                            value: modelData.audio ? modelData.audio.volume : 0
                            dimmed: modelData.audio ? modelData.audio.muted : true
                            onMoved: v => { if (modelData.audio) modelData.audio.volume = v; }
                            onIconClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                        }
                    }
                }

                // ---------- brilho ----------
                ColumnLayout {
                    id: brightnessPop
                    visible: popContent.current === brightnessPop
                    width: 280
                    spacing: 6
                    readonly property bool dragging: brSlider.dragging
                    PopTitle { text: "Brilho da tela" }
                    PopSlider {
                        id: brSlider
                        icon: Theme.icons.brightness
                        value: bar.brightness
                        onMoved: v => bar.setBrightness(v)
                    }
                }

                // ---------- bateria ----------
                ColumnLayout {
                    id: batteryPop
                    visible: popContent.current === batteryPop
                    width: 290
                    spacing: 4
                    PopTitle {
                        text: !bar.battery ? "" : Math.round(bar.battery.percentage * 100) + "% · " + (
                            bar.battery.state === UPowerDeviceState.Charging ? "carregando"
                            : bar.battery.state === UPowerDeviceState.FullyCharged ? "carregada"
                            : bar.battery.state === UPowerDeviceState.PendingCharge ? "na tomada, sem carregar" : "na bateria")
                    }
                    PopText {
                        visible: text !== ""
                        text: !bar.battery ? "" : bar.battery.state === UPowerDeviceState.Charging
                            ? (bar.fmtTime(bar.battery.timeToFull) ? "Cheia em " + bar.fmtTime(bar.battery.timeToFull) : "")
                            : (bar.fmtTime(bar.battery.timeToEmpty) ? "Resta " + bar.fmtTime(bar.battery.timeToEmpty) : "")
                    }
                    PopText {
                        visible: text !== ""
                        text: [
                            bar.batteryHealth > 0 ? "Saúde " + Math.round(bar.batteryHealth * 100) + "%" : "",
                            bar.batteryCycles > 0 ? bar.batteryCycles + " ciclos de carga" : ""
                        ].filter(t => t !== "").join(" · ")
                    }
                    PopText {
                        visible: bar.battery && Math.abs(bar.battery.changeRate) > 0.1
                        text: bar.battery ? "Consumo " + Math.abs(bar.battery.changeRate).toFixed(1) + " W" : ""
                    }

                    PopTitle { text: "Perfil de energia"; Layout.topMargin: 8 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [
                                { p: PowerProfile.PowerSaver, icon: Theme.icons.saver, label: "Economia" },
                                { p: PowerProfile.Balanced, icon: Theme.icons.balanced, label: "Equilíbrio" },
                                { p: PowerProfile.Performance, icon: Theme.icons.perf, label: "Desempenho" }
                            ]
                            delegate: Rectangle {
                                id: prof
                                required property var modelData
                                readonly property bool active: PowerProfiles.profile === modelData.p
                                Layout.fillWidth: true
                                implicitHeight: 54
                                radius: 12
                                color: active ? Theme.primary : profArea.containsMouse ? Theme.tileHigh : Theme.tile
                                Behavior on color { ColorAnimation { duration: 140 } }
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 0
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: prof.modelData.icon
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 18
                                        color: prof.active ? Theme.background : Theme.textColor
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: prof.modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        color: prof.active ? Theme.background : Theme.subtext
                                    }
                                }
                                MouseArea {
                                    id: profArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: PowerProfiles.profile = prof.modelData.p
                                }
                            }
                        }
                    }

                    PopTitle { text: "Otimizações de GPU & Tela"; Layout.topMargin: 8 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        // Modo Jogo
                        Rectangle {
                            id: gameTile
                            readonly property bool active: GameMode.active
                            Layout.fillWidth: true
                            implicitHeight: 54
                            radius: 12
                            color: active ? Theme.primary : gameArea.containsMouse ? Theme.tileHigh : Theme.tile
                            Behavior on color { ColorAnimation { duration: 140 } }
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Theme.icons.gamepad
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 18
                                    color: gameTile.active ? Theme.background : Theme.textColor
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: gameTile.active ? "Jogo: On" : "Modo Jogo"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: gameTile.active ? Theme.background : Theme.subtext
                                }
                            }
                            MouseArea {
                                id: gameArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: GameMode.manual = !GameMode.manual
                            }
                        }

                        // Toggle de Blur
                        Rectangle {
                            id: blurTile
                            readonly property bool active: bar.blurEnabled
                            Layout.fillWidth: true
                            implicitHeight: 54
                            radius: 12
                            color: active ? Theme.primary : blurArea.containsMouse ? Theme.tileHigh : Theme.tile
                            Behavior on color { ColorAnimation { duration: 140 } }
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: bar.blurEnabled ? Theme.icons.blur : Theme.icons.blurOff
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 18
                                    color: blurTile.active ? Theme.background : Theme.textColor
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: bar.blurEnabled ? "Blur: On" : "Blur: Off"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: blurTile.active ? Theme.background : Theme.subtext
                                }
                            }
                            MouseArea {
                                id: blurArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    bar.blurEnabled = !bar.blurEnabled;
                                    blurToggleProc.running = true;
                                }
                            }
                        }

                        // Toggle de Super Desempenho
                        Rectangle {
                            id: perfTile
                            readonly property bool active: bar.perfModeEnabled
                            Layout.fillWidth: true
                            implicitHeight: 54
                            radius: 12
                            color: active ? Theme.primary : perfArea.containsMouse ? Theme.tileHigh : Theme.tile
                            Behavior on color { ColorAnimation { duration: 140 } }
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Theme.icons.lightning
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 18
                                    color: perfTile.active ? Theme.background : Theme.textColor
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: perfTile.active ? "Ultra: On" : "Ultra Perf"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: perfTile.active ? Theme.background : Theme.subtext
                                }
                            }
                            MouseArea {
                                id: perfArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    bar.perfModeEnabled = !bar.perfModeEnabled;
                                    perfToggleProc.running = true;
                                }
                            }
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
                            text: !Networking.wifiEnabled ? "Wi-Fi desligado"
                                : bar.activeNetwork ? bar.activeNetwork.name : "Wi-Fi sem conexão"
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
                                Behavior on x { NumberAnimation { duration: 140 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                            }
                        }
                    }
                    PopText { text: "Clique numa rede para conectar"; visible: Networking.wifiEnabled }

                    Repeater {
                        model: !bar.wifiDevice || !Networking.wifiEnabled ? [] : bar.wifiDevice.networks.values
                            .slice().sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
                            .slice(0, 8)
                        delegate: PopAction {
                            required property var modelData
                            icon: modelData.signalStrength > 0.75 ? Theme.icons.wifi4 : modelData.signalStrength > 0.5 ? Theme.icons.wifi3
                                : modelData.signalStrength > 0.25 ? Theme.icons.wifi2 : Theme.icons.wifi1
                            label: modelData.name
                            detail: modelData.connected ? "conectado" : modelData.stateChanging ? "..." : modelData.known ? "salva" : ""
                            selected: modelData.connected
                            onActivated: {
                                if (modelData.connected) return;
                                if (modelData.known) {
                                    modelData.connect();
                                } else {
                                    nmtuiProc.ssid = modelData.name;
                                    nmtuiProc.running = true;
                                    bar.pop = "";
                                }
                            }
                        }
                    }

                    PopAction {
                        Layout.topMargin: 6
                        icon: Theme.icons.refresh
                        label: "Reiniciar rede"
                        needsConfirm: true
                        onActivated: netRestart.running = true
                    }
                }

                // ---------- bluetooth ----------
                ColumnLayout {
                    id: btPop
                    visible: popContent.current === btPop
                    width: 290
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        PopTitle {
                            Layout.fillWidth: true
                            text: !bar.btAdapter ? "Sem adaptador" : bar.btAdapter.enabled ? "Bluetooth" : "Bluetooth desligado"
                        }
                        Rectangle {
                            visible: bar.btAdapter !== null
                            implicitWidth: 40
                            implicitHeight: 22
                            radius: 11
                            color: bar.btAdapter && bar.btAdapter.enabled ? Theme.primary : Theme.tileHigh
                            Rectangle {
                                width: 16; height: 16; radius: 8
                                anchors.verticalCenter: parent.verticalCenter
                                x: bar.btAdapter && bar.btAdapter.enabled ? parent.width - width - 3 : 3
                                color: Theme.textColor
                                Behavior on x { NumberAnimation { duration: 140 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bar.btAdapter.enabled = !bar.btAdapter.enabled
                            }
                        }
                    }

                    PopText {
                        visible: bar.btAdapter && bar.btAdapter.enabled && bar.btDevices.length === 0
                        text: "Nenhum dispositivo"
                    }

                    Repeater {
                        model: bar.btAdapter && bar.btAdapter.enabled ? bar.btDevices.filter(d => d.paired || d.connected || bar.btAdapter.discovering).slice(0, 8) : []
                        delegate: PopAction {
                            required property var modelData
                            icon: modelData.connected ? Theme.icons.btConnected : Theme.icons.bt
                            label: modelData.name || modelData.address
                            detail: modelData.pairing ? "pareando..." : modelData.connected
                                ? (modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : "conectado")
                                : modelData.paired ? "" : "novo"
                            selected: modelData.connected
                            onActivated: {
                                if (modelData.connected) modelData.disconnect();
                                else if (modelData.paired) modelData.connect();
                                else modelData.pair();
                            }
                        }
                    }

                    PopAction {
                        visible: bar.btAdapter && bar.btAdapter.enabled
                        Layout.topMargin: 6
                        icon: Theme.icons.magnify
                        label: bar.btAdapter && bar.btAdapter.discovering ? "Procurando... (clique para parar)" : "Procurar dispositivos"
                        selected: bar.btAdapter && bar.btAdapter.discovering
                        onActivated: bar.btAdapter.discovering = !bar.btAdapter.discovering
                    }
                }
            }
        }
    }

    // IPC de teste: `qs ipc call bar popup <audio|brightness|battery|wifi|bt>` / `hide`
    IpcHandler {
        target: "bar"
        function popup(kind: string): void {
            const m = { audio: audioMod, brightness: brMod, battery: batMod, wifi: wifiMod, bt: btMod }[kind];
            if (m) bar.showPopNow(kind, m);
        }
        function hide(): void { bar.pop = ""; }
        function setBarVisible(v: bool): void { bar.visible = v; }
    }
}
