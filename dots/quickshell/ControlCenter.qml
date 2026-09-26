pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Quickshell.Networking
import Quickshell.Bluetooth
import "."

// Central de controle (estilo Win11/macOS): abre pelo bloco brilho/som/bateria
// das barras, ou `qs ipc call control toggle`.
//
// Reúne o que antes eram ícones soltos na barra: Bluetooth e o atalho das
// Configurações moram aqui dentro (tem PC sem Bluetooth, e o ícone vazio só
// confundia). Wi‑Fi e notificações continuam com ícone próprio na barra.
//
// A camada cobre a tela para fechar com clique fora; o cartão encosta na barra
// (em cima: canto direito; lateral: embaixo, do lado da barra).
PanelWindow {
    id: cc

    property bool open: false
    signal settingsRequested()

    visible: open || card.opacity > 0
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-controlcenter"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open && !hoverMode ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Aberta por hover (parar o mouse no bloco da barra): a máscara fica só no
    // cartão, para a barra continuar recebendo o mouse, e fecha ao sair do bloco
    // e do cartão. Um clique no bloco a deixa fixa (tela toda, fecha com clique
    // fora ou Esc).
    property bool hoverMode: false
    mask: Region { item: cc.hoverMode ? card : fullArea }
    Item { id: fullArea; anchors.fill: parent }
    function hoverEnter() {
        closeTimer.stop();
        if (!open) openTimer.restart();
    }
    function hoverLeave() {
        openTimer.stop();
        if (open && hoverMode) closeTimer.restart();
    }
    function clickToggle() {
        openTimer.stop();
        closeTimer.stop();
        if (open && hoverMode) { hoverMode = false; return; }
        hoverMode = false;
        open = !open;
    }
    Timer { id: openTimer; interval: 220; onTriggered: { cc.hoverMode = true; cc.open = true; } }
    Timer { id: closeTimer; interval: 350; onTriggered: if (!cardHover.hovered) cc.open = false }

    IpcHandler {
        target: "control"
        function toggle(): void { cc.clickToggle(); }
        function show(): void { cc.open = true; }
        function hide(): void { cc.open = false; }
        // `qs ipc call control page wifi|bt` (atalhos e testes)
        function page(m: string): void { cc.openPage(m); }
        function scan(): void { if (cc.page !== "") connPage.orbitMode = true; }
    }

    onOpenChanged: {
        if (open) {
            card.forceActiveFocus();
            blurCheck.running = true;
            nightCheck.running = true;
            cc.readBrightness();
            cc.refreshNet();
        } else {
            cc.hoverMode = false;
            cc.btOpen = false;
            cc.page = "";
            cc.wifiOpen = false;
            cc.vpnOpen = false;
            cc.audioOpen = false;
            powerRow.disarm();
        }
    }

    // ================= dados =================
    // --- áudio ---
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink)
    // Stream de reprodução = isStream && isSink no Quickshell. Sem o nó vinculado
    // as `properties` vêm vazias, então filtrar por media.class não achava nada.
    // Fora ficam o equalizador e os loopbacks do próprio rice.
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isStream && n.isSink
        && n.name !== "hollow_eq_out" && !String(n.name).startsWith("output.loopback"))
    PwObjectTracker { objects: [cc.sink, cc.source].concat(cc.sinks, cc.streams) }
    function nodeName(n) {
        if (!n) return "";
        return n.properties["application.name"] || n.description || n.nickname || n.name;
    }
    function volIcon(n) {
        if (!n || !n.audio || n.audio.muted) return Theme.icons.volOff;
        const v = n.audio.volume;
        return v > 0.66 ? Theme.icons.volHigh : v > 0.33 ? Theme.icons.volMid : Theme.icons.volLow;
    }

    // --- brilho (sysfs não avisa mudança: lê ao abrir e a cada 2 s aberto) ---
    property real brightness: 0
    readonly property bool hasBacklight: brMax.text().trim() !== ""
    FileView { id: brCur; path: "/sys/class/backlight/intel_backlight/brightness"; blockLoading: true; printErrors: false }
    FileView { id: brMax; path: "/sys/class/backlight/intel_backlight/max_brightness"; blockLoading: true; printErrors: false }
    function readBrightness() {
        if (brHold.running || brSet.running || !cc.hasBacklight) return;
        brCur.reload();
        cc.brightness = Math.max(0, Math.min(1, (parseFloat(brCur.text()) || 0) / (parseFloat(brMax.text()) || 1)));
    }
    Timer { interval: 2000; repeat: true; running: cc.open; onTriggered: cc.readBrightness() }
    Timer { id: brHold; interval: 1500 }
    // Um brightnessctl por vez; o pedido mais recente roda na saída (ver TopBar).
    property int brPending: -1
    Process {
        id: brSet
        property int pct: 0
        command: ["brightnessctl", "-q", "set", pct + "%"]
        onExited: {
            if (cc.brPending >= 0) {
                pct = cc.brPending;
                cc.brPending = -1;
                running = true;
            }
        }
    }
    function setBrightness(v) {
        brightness = Math.max(0.01, Math.min(1, v));
        brHold.restart();
        const pct = Math.max(1, Math.round(brightness * 100));
        if (brSet.running) brPending = pct;
        else { brSet.pct = pct; brSet.running = true; }
    }

    // --- bateria ---
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isLaptopBattery
    function batIcon() {
        if (!hasBattery) return Theme.icons.bat;
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
    function batText() {
        if (!hasBattery) return "";
        const st = battery.state;
        let s = Math.round(battery.percentage * 100) + "%";
        if (st === UPowerDeviceState.Charging) {
            const t = fmtTime(battery.timeToFull);
            s += " · " + (t ? Theme.t("cc.bat_full_in", "cheia em %1").replace("%1", t) : Theme.t("cc.bat_charging", "carregando"));
        } else if (st === UPowerDeviceState.FullyCharged) {
            s += " · " + Theme.t("cc.bat_full", "carregada");
        } else {
            const t = fmtTime(battery.timeToEmpty);
            if (t) s += " · " + Theme.t("cc.bat_left", "resta %1").replace("%1", t);
        }
        return s;
    }

    // --- rede / bluetooth ---
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var activeNetwork: wifiDevice ? wifiDevice.networks.values.find(n => n.connected) || null : null
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btDevices: btAdapter ? btAdapter.devices.values.slice().sort((a, b) =>
        (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name)) : []
    readonly property var btConnectedDev: btDevices.find(d => d.connected) || null

    // --- blur / luz noturna ---
    property bool blurEnabled: true
    Process {
        id: blurCheck
        command: ["rice-blur-toggle", "status"]
        stdout: StdioCollector { onStreamFinished: cc.blurEnabled = text.trim() === "1" }
    }
    Process { id: blurToggle; command: ["rice-blur-toggle"]; onExited: blurCheck.running = true }
    property bool nightLight: false
    Process {
        id: nightCheck
        command: ["pgrep", "-x", "hyprsunset"]
        onExited: code => cc.nightLight = code === 0
    }
    Process { id: nightToggle; command: ["rice-nightlight", "toggle"]; onExited: nightRecheck.restart() }
    Timer { id: nightRecheck; interval: 400; onTriggered: nightCheck.running = true }

    // --- mídia (estado e comandos no MediaState) ---
    readonly property var player: MediaState.player

    function openPage(m) {
        if (m !== "wifi" && m !== "bt") return;
        cc.hoverMode = false;
        cc.open = true;
        connPage.mode = m;
        cc.page = m;
    }

    // --- seções que abrem ---
    property bool btOpen: false
    // Página de Wi-Fi / Bluetooth ("" = tela principal).
    property string page: ""

    // --- VPN e redes salvas (rice-network → nmcli), lidos ao abrir ---
    property bool wifiOpen: false
    property bool vpnOpen: false
    property var vpns: []
    property var savedWifi: []
    readonly property var activeVpn: vpns.find(v => v.active) || null
    function refreshNet() {
        if (!vpnProc.running) vpnProc.running = true;
        if (!savedProc.running) savedProc.running = true;
    }
    Process {
        id: vpnProc
        command: ["rice-network", "vpn-list"]
        stdout: StdioCollector { onStreamFinished: { try { cc.vpns = JSON.parse(text) || []; } catch (e) {} } }
    }
    Process {
        id: savedProc
        command: ["rice-network", "saved-wifi"]
        stdout: StdioCollector { onStreamFinished: { try { cc.savedWifi = JSON.parse(text) || []; } catch (e) {} } }
    }
    // Ligar/desligar VPN ou esquecer rede: um pedido por vez, e relê a lista no fim.
    Process {
        id: netAction
        onExited: cc.refreshNet()
    }
    function runNet(args) {
        if (netAction.running) return;
        netAction.command = ["rice-network"].concat(args);
        netAction.running = true;
    }
    property bool audioOpen: false

    // ================= componentes =================
    // Bloco grande de liga/desliga. `more` mostra a seta que abre detalhes.
    component Tile: Rectangle {
        id: tile
        property string icon: ""
        property string label: ""
        property string sub: ""
        property bool active: false
        property bool more: false
        property bool expanded: false
        signal toggled()
        signal moreClicked()

        Layout.fillWidth: true
        implicitHeight: 58
        radius: 14
        clip: true
        color: tile.active ? Theme.primary : Theme.tile
        Behavior on color { ColorAnimation { duration: Theme.ms(140) } }
        scale: mainArea.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: Theme.ms(90) } }

        // Hover: o bloco "enche" da esquerda para a direita (como nas páginas
        // de Wi-Fi e Bluetooth).
        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            radius: parent.radius
            width: mainArea.containsMouse ? parent.width : 0
            color: tile.active ? Theme.withAlpha(Theme.background, 0.14) : Theme.withAlpha(Theme.primary, 0.22)
            Behavior on width { NumberAnimation { duration: mainArea.containsMouse ? Theme.ms(600) : Theme.ms(160); easing.type: Easing.OutQuad } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: tile.more ? 0 : 10
            spacing: 8
            Text {
                text: tile.icon
                font.family: Theme.iconFontFamily
                font.pixelSize: 18
                color: tile.active ? Theme.background : Theme.textColor
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: tile.label
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: tile.active ? Theme.background : Theme.textColor
                }
                Text {
                    Layout.fillWidth: true
                    visible: tile.sub !== ""
                    text: tile.sub
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: tile.active ? Theme.withAlpha(Theme.background, 0.75) : Theme.subtext
                }
            }
            Item {
                visible: tile.more
                Layout.fillHeight: true
                Layout.preferredWidth: 26
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: parent.height - 20
                    color: tile.active ? Theme.withAlpha(Theme.background, 0.3) : Theme.withAlpha(Theme.outline, 0.3)
                }
                Text {
                    anchors.centerIn: parent
                    text: Theme.icons.chevronRight
                    rotation: tile.expanded ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: Theme.ms(140) } }
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 16
                    color: tile.active ? Theme.background : Theme.subtext
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.moreClicked()
                }
            }
        }
        MouseArea {
            id: mainArea
            anchors.fill: parent
            anchors.rightMargin: tile.more ? 26 : 0
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.toggled()
        }
    }

    component RoundBtn: Rectangle {
        id: rb
        property string icon: ""
        property string tip: ""
        property color tint: Theme.textColor
        property bool armed: false
        signal activated()
        implicitWidth: 36
        implicitHeight: 36
        radius: 18
        color: rb.armed ? Theme.withAlpha(Theme.critical, 0.55) : (rbArea.containsMouse ? Theme.tileHigh : Theme.tile)
        Behavior on color { ColorAnimation { duration: Theme.ms(120) } }
        Text {
            anchors.centerIn: parent
            text: rb.icon
            font.family: Theme.iconFontFamily
            font.pixelSize: 16
            color: rb.armed ? Theme.textColor : rb.tint
        }
        MouseArea {
            id: rbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rb.activated()
        }
        // Dica em cima do botão (só ícone não diz o que faz).
        Rectangle {
            visible: rb.tip !== "" && rbArea.containsMouse
            anchors.bottom: parent.top
            anchors.bottomMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            width: tipText.implicitWidth + 14
            height: 22
            radius: 6
            color: Theme.tileHigh
            Text {
                id: tipText
                anchors.centerIn: parent
                text: rb.tip
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.textColor
            }
        }
    }

    // ================= conteúdo =================
    // clique fora fecha
    MouseArea {
        anchors.fill: parent
        onClicked: cc.open = false
    }

    Rectangle {
        id: card
        readonly property int stripW: 52 + Theme.frameThickness
        readonly property bool onLeft: ShellLayout.barEnabled && ShellLayout.barPosition === "left"
        readonly property bool onRight: ShellLayout.barEnabled && ShellLayout.barPosition === "right"
        readonly property bool side: onLeft || onRight

        width: cc.page !== "" ? 500 : 380
        height: cc.page !== "" ? Math.min(560, cc.height - 20) : Math.min(col.implicitHeight + 28, cc.height - 20)
        Behavior on width { NumberAnimation { duration: Theme.ms(220); easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: Theme.ms(220); easing.type: Easing.OutCubic } }
        x: onLeft ? stripW + 8 : cc.width - width - (onRight ? stripW : Theme.frameThickness) - 8
        y: side ? cc.height - height - 10 : Theme.waybarHeight + 6
        radius: Theme.radius + 4
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.97)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.3)
        clip: true

        opacity: cc.open ? 1 : 0
        scale: cc.open ? 1 : 0.96
        transformOrigin: side ? (onLeft ? Item.BottomLeft : Item.BottomRight) : Item.TopRight
        Behavior on opacity { NumberAnimation { duration: Theme.ms(160) } }
        Behavior on scale { NumberAnimation { duration: Theme.ms(200); easing.type: Easing.OutCubic } }

        focus: true
        Keys.onEscapePressed: cc.page !== "" ? cc.page = "" : cc.open = false

        // engole cliques dentro do cartão (senão o de fora fecha)
        MouseArea { anchors.fill: parent }
        HoverHandler {
            id: cardHover
            onHoveredChanged: hovered ? closeTimer.stop() : (cc.hoverMode ? closeTimer.restart() : undefined)
        }

        // Página de Wi-Fi / Bluetooth: entra deslizando da direita.
        ConnectPage {
            id: connPage
            width: 500 - 28
            height: parent.height - 28
            y: 14
            x: cc.page !== "" ? 14 : parent.width + 20
            opacity: cc.page !== "" ? 1 : 0
            visible: opacity > 0
            Behavior on x { NumberAnimation { duration: Theme.ms(260); easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Theme.ms(180) } }
            onBack: cc.page = ""
            onModeChanged: if (cc.page !== "") cc.page = mode
        }

        Flickable {
            id: mainFlick
            anchors.fill: parent
            anchors.margins: 14
            x: cc.page !== "" ? -card.width : 0
            opacity: cc.page !== "" ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.ms(160) } }
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            ColumnLayout {
                id: col
                width: parent.width
                spacing: 12

                // ---------- blocos ----------
                // Duas colunas: com três, "Não perturbe" e "Luz noturna" cortavam.
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    uniformCellWidths: true
                    columnSpacing: 8
                    rowSpacing: 8

                    Tile {
                        icon: Networking.wifiEnabled ? Theme.icons.wifi4 : Theme.icons.wifiOff
                        label: Theme.t("cc.wifi", "Wi‑Fi")
                        sub: !Networking.wifiEnabled ? Theme.t("cc.off", "Desligado")
                            : cc.activeNetwork ? cc.activeNetwork.name : Theme.t("cc.not_connected", "Sem conexão")
                        active: Networking.wifiEnabled
                        visible: cc.wifiDevice !== null && ShellLayout.ccHas("wifi")
                        more: true
                        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                        onMoreClicked: { connPage.mode = "wifi"; cc.page = "wifi"; }
                    }
                    Tile {
                        icon: Theme.icons.lock
                        label: "VPN"
                        sub: cc.activeVpn ? cc.activeVpn.name : Theme.t("cc.off", "Desligado")
                        active: cc.activeVpn !== null
                        visible: cc.vpns.length > 0 && ShellLayout.ccHas("vpn")
                        more: true
                        expanded: cc.vpnOpen
                        // Com uma VPN só, o bloco liga e desliga ela; com mais, abre a lista.
                        onToggled: {
                            if (cc.vpns.length === 1) cc.runNet([cc.vpns[0].active ? "vpn-down" : "vpn-up", cc.vpns[0].uuid]);
                            else cc.vpnOpen = !cc.vpnOpen;
                        }
                        onMoreClicked: cc.vpnOpen = !cc.vpnOpen
                    }
                    Tile {
                        icon: !cc.btAdapter || !cc.btAdapter.enabled ? Theme.icons.btOff
                            : cc.btConnectedDev ? Theme.icons.btConnected : Theme.icons.bt
                        label: "Bluetooth"
                        sub: !cc.btAdapter || !cc.btAdapter.enabled ? Theme.t("cc.off", "Desligado")
                            : cc.btConnectedDev ? (cc.btConnectedDev.name || cc.btConnectedDev.address) : Theme.t("cc.not_connected", "Sem conexão")
                        active: cc.btAdapter !== null && cc.btAdapter.enabled
                        visible: cc.btAdapter !== null && ShellLayout.ccHas("bluetooth")
                        more: true
                        onToggled: cc.btAdapter.enabled = !cc.btAdapter.enabled
                        onMoreClicked: { connPage.mode = "bt"; cc.page = "bt"; }
                    }
                    Tile {
                        icon: NotifService.dnd ? Theme.icons.bellOff : Theme.icons.bell
                        label: Theme.t("cc.dnd", "Não perturbe")
                        sub: NotifService.dnd ? Theme.t("cc.on", "Ligado") : Theme.t("cc.off", "Desligado")
                        active: NotifService.dnd
                        visible: ShellLayout.ccHas("dnd")
                        onToggled: NotifService.toggleDnd()
                    }
                    Tile {
                        icon: Theme.icons.gamepad
                        label: Theme.t("cc.game", "Modo jogo")
                        sub: GameMode.active ? Theme.t("cc.on", "Ligado") : Theme.t("cc.off", "Desligado")
                        active: GameMode.active
                        visible: ShellLayout.ccHas("game")
                        onToggled: GameMode.manual = !GameMode.manual
                    }
                    Tile {
                        icon: cc.blurEnabled ? Theme.icons.blur : Theme.icons.blurOff
                        label: Theme.t("cc.blur", "Desfoque")
                        sub: cc.blurEnabled ? Theme.t("cc.on", "Ligado") : Theme.t("cc.off", "Desligado")
                        active: cc.blurEnabled
                        visible: ShellLayout.ccHas("blur")
                        onToggled: if (!blurToggle.running) blurToggle.running = true
                    }
                    Tile {
                        icon: Theme.icons.night
                        label: Theme.t("cc.night", "Luz noturna")
                        sub: cc.nightLight ? Theme.t("cc.on", "Ligado") : Theme.t("cc.off", "Desligado")
                        active: cc.nightLight
                        visible: ShellLayout.ccHas("night")
                        onToggled: if (!nightToggle.running) nightToggle.running = true
                    }
                }

                // ---------- VPN ----------
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: cc.vpnOpen && cc.vpns.length > 0
                    spacing: 4
                    Repeater {
                        model: cc.vpnOpen ? cc.vpns : []
                        delegate: PopAction {
                            required property var modelData
                            icon: Theme.icons.lock
                            label: modelData.name
                            detail: netAction.running ? "…" : modelData.active ? Theme.t("cc.connected", "conectado") : ""
                            selected: modelData.active
                            onActivated: cc.runNet([modelData.active ? "vpn-down" : "vpn-up", modelData.uuid])
                        }
                    }
                }

                // ---------- sliders ----------
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    PopSlider {
                        Layout.fillWidth: true
                        visible: cc.hasBacklight
                        icon: Theme.icons.brightness
                        value: cc.brightness
                        onMoved: v => cc.setBrightness(v)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        PopSlider {
                            Layout.fillWidth: true
                            icon: cc.volIcon(cc.sink)
                            max: AudioPrefs.maxVolume
                            value: cc.sink && cc.sink.audio ? cc.sink.audio.volume : 0
                            dimmed: cc.sink && cc.sink.audio ? cc.sink.audio.muted : true
                            onMoved: v => { if (cc.sink) cc.sink.audio.volume = v; }
                            onIconClicked: if (cc.sink) cc.sink.audio.muted = !cc.sink.audio.muted
                        }
                        // saída de áudio e volume por app
                        Rectangle {
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: 14
                            color: moreAudio.containsMouse || cc.audioOpen ? Theme.tileHigh : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: Theme.icons.chevronRight
                                rotation: cc.audioOpen ? 90 : 0
                                Behavior on rotation { NumberAnimation { duration: Theme.ms(140) } }
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 16
                                color: Theme.subtext
                            }
                            MouseArea {
                                id: moreAudio
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: cc.audioOpen = !cc.audioOpen
                            }
                        }
                    }
                    PopSlider {
                        Layout.fillWidth: true
                        icon: cc.source && cc.source.audio && cc.source.audio.muted ? Theme.icons.micOff : Theme.icons.mic
                        value: cc.source && cc.source.audio ? cc.source.audio.volume : 0
                        dimmed: cc.source && cc.source.audio ? cc.source.audio.muted : true
                        onMoved: v => { if (cc.source) cc.source.audio.volume = v; }
                        onIconClicked: if (cc.source) cc.source.audio.muted = !cc.source.audio.muted
                    }
                }

                // ---------- saída e apps ----------
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: cc.audioOpen
                    spacing: 4
                    PopTitle { text: Theme.t("cc.output", "Saída de áudio") }
                    Repeater {
                        model: cc.sinks
                        delegate: PopAction {
                            required property var modelData
                            icon: (modelData.properties["device.form-factor"] || "").includes("head") ? Theme.icons.headphones : Theme.icons.speaker
                            label: cc.nodeName(modelData)
                            selected: modelData === cc.sink
                            onActivated: Pipewire.preferredDefaultAudioSink = modelData
                        }
                    }
                    PopTitle {
                        Layout.topMargin: 4
                        visible: cc.streams.length > 0
                        text: Theme.t("cc.apps", "Volume por app")
                    }
                    Repeater {
                        model: cc.streams
                        delegate: PopSlider {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: cc.volIcon(modelData)
                            max: AudioPrefs.maxVolume
                            label: cc.nodeName(modelData)
                            value: modelData.audio ? modelData.audio.volume : 0
                            dimmed: modelData.audio ? modelData.audio.muted : true
                            onMoved: v => { if (modelData.audio) modelData.audio.volume = v; }
                            onIconClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                        }
                    }
                }

                // ---------- mídia ----------
                Rectangle {
                    Layout.fillWidth: true
                    visible: cc.player !== null
                    implicitHeight: 64
                    radius: 14
                    color: Theme.tile
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10
                        Rectangle {
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                            radius: 10
                            color: Theme.tileHigh
                            clip: true
                            Image {
                                id: ccArt
                                anchors.fill: parent
                                source: cc.player && cc.player.trackArtUrl ? cc.player.trackArtUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(96, 96)
                                asynchronous: true
                                visible: status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !ccArt.visible
                                text: Theme.icons.album
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 20
                                color: Theme.subtext
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: cc.player ? (cc.player.trackTitle || cc.player.identity || "") : ""
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: Theme.textColor
                            }
                            Text {
                                Layout.fillWidth: true
                                text: cc.player ? (cc.player.trackArtist || cc.player.identity || "") : ""
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.subtext
                            }
                        }
                        Repeater {
                            model: [
                                { icon: Theme.icons.prev, cmd: "previous" },
                                { icon: MediaState.playing ? Theme.icons.pause : Theme.icons.play, cmd: "toggle" },
                                { icon: Theme.icons.next, cmd: "next" }
                            ]
                            delegate: Rectangle {
                                id: mb
                                required property var modelData
                                implicitWidth: 30
                                implicitHeight: 30
                                radius: 15
                                color: mbArea.containsMouse ? Theme.tileHigh : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: mb.modelData.icon
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 17
                                    color: Theme.textColor
                                }
                                MouseArea {
                                    id: mbArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (mb.modelData.cmd === "previous") MediaState.previous();
                                        else if (mb.modelData.cmd === "next") MediaState.next();
                                        else MediaState.toggle();
                                    }
                                }
                            }
                        }
                    }
                }

                PopSlider {
                    Layout.fillWidth: true
                    visible: cc.player !== null && MediaState.hasVolume
                    icon: MediaState.muted ? Theme.icons.volOff : Theme.icons.music
                    label: MediaState.player ? (MediaState.player.identity || "") : ""
                    value: MediaState.shownVolume
                    dimmed: MediaState.muted
                    onMoved: v => MediaState.setVolume(v)
                    onIconClicked: MediaState.toggleMute()
                }

                // ---------- bateria e perfil de energia ----------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        visible: cc.hasBattery
                        text: cc.batIcon()
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 17
                        color: cc.hasBattery && cc.battery.percentage <= 0.15 && cc.battery.state !== UPowerDeviceState.Charging
                            ? Theme.critical : Theme.textColor
                    }
                    Text {
                        Layout.fillWidth: true
                        text: cc.hasBattery ? cc.batText() : Theme.t("cc.power_profile", "Perfil de energia")
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textColor
                    }
                    Row {
                        spacing: 2
                        Repeater {
                            model: [
                                { p: PowerProfile.PowerSaver, icon: Theme.icons.saver, tip: Theme.t("sidebar.power_saver", "Economia") },
                                { p: PowerProfile.Balanced, icon: Theme.icons.balanced, tip: Theme.t("sidebar.power_balanced", "Equilíbrio") },
                                { p: PowerProfile.Performance, icon: Theme.icons.perf, tip: Theme.t("sidebar.power_perf", "Desempenho") }
                            ]
                            delegate: Rectangle {
                                id: pp
                                required property var modelData
                                readonly property bool active: PowerProfiles.profile === pp.modelData.p
                                width: 34
                                height: 28
                                radius: 8
                                color: pp.active ? Theme.primary : (ppArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                Text {
                                    anchors.centerIn: parent
                                    text: pp.modelData.icon
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 15
                                    color: pp.active ? Theme.background : Theme.textColor
                                }
                                MouseArea {
                                    id: ppArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: PowerProfiles.profile = pp.modelData.p
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.withAlpha(Theme.outline, 0.25)
                }

                // ---------- configurações e energia ----------
                RowLayout {
                    id: powerRow
                    Layout.fillWidth: true
                    spacing: 6
                    // Reiniciar/desligar pedem um segundo clique (fica vermelho).
                    property string armed: ""
                    function disarm() { armed = ""; }
                    Timer { id: disarmTimer; interval: 3000; onTriggered: powerRow.disarm() }
                    function arm(kind) {
                        if (armed === kind) {
                            armed = "";
                            cc.open = false;
                            Quickshell.execDetached(["rice-session-action", kind]);
                        } else {
                            armed = kind;
                            disarmTimer.restart();
                        }
                    }

                    Rectangle {
                        implicitWidth: setRow.implicitWidth + 24
                        implicitHeight: 36
                        radius: 18
                        color: setArea.containsMouse ? Theme.tileHigh : Theme.tile
                        Row {
                            id: setRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icons.tune
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 15
                                color: Theme.textColor
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.t("cc.settings", "Configurações")
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.textColor
                            }
                        }
                        MouseArea {
                            id: setArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                cc.open = false;
                                cc.settingsRequested();
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: powerRow.armed !== ""
                        text: Theme.t("cc.confirm", "de novo p/ confirmar")
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.subtext
                    }
                    RoundBtn {
                        icon: Theme.icons.lock
                        tip: Theme.t("cc.tip_lock", "Bloquear")
                        onActivated: {
                            cc.open = false;
                            Quickshell.execDetached(["rice-session-action", "lock"]);
                        }
                    }
                    RoundBtn {
                        icon: Theme.icons.sleep
                        tip: Theme.t("cc.tip_sleep", "Suspender")
                        onActivated: {
                            cc.open = false;
                            Quickshell.execDetached(["rice-session-action", "suspend"]);
                        }
                    }
                    RoundBtn {
                        icon: Theme.icons.restart
                        tip: Theme.t("cc.tip_reboot", "Reiniciar")
                        armed: powerRow.armed === "reboot"
                        onActivated: powerRow.arm("reboot")
                    }
                    RoundBtn {
                        icon: Theme.icons.power
                        tip: Theme.t("cc.tip_off", "Desligar")
                        tint: Theme.critical
                        armed: powerRow.armed === "poweroff"
                        onActivated: powerRow.arm("poweroff")
                    }
                }
            }
        }
    }
}
