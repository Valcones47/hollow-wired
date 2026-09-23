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
    onPopChanged: if (vbar.pop === "battery") { blurCheck.running = true; perfCheck.running = true; }

    // Mesmos atalhos de desempenho do popup da bateria da barra de cima.
    property bool blurEnabled: true
    property bool perfModeEnabled: false
    Process {
        id: blurCheck
        command: ["rice-blur-toggle", "status"]
        stdout: StdioCollector { onStreamFinished: vbar.blurEnabled = text.trim() === "1" }
    }
    Process {
        id: blurToggleProc
        command: ["rice-blur-toggle"]
        onExited: { blurCheck.running = true; perfCheck.running = true; }
    }
    Process {
        id: perfCheck
        command: ["rice-perf-mode", "status"]
        stdout: StdioCollector { onStreamFinished: vbar.perfModeEnabled = text.trim() === "1" }
    }
    Process {
        id: perfToggleProc
        command: ["rice-perf-mode"]
        onExited: { blurCheck.running = true; perfCheck.running = true; }
    }
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

    // Mídia: o primeiro player que estiver tocando, senão o primeiro que houver.
    // Depois de um clique o player fica preso (mediaLock): senão, ao pausar, a
    // barra podia pular para outro player e o segundo clique ia para ele.
    readonly property var player: {
        const ps = Mpris.players.values;
        if (mediaLock && ps.indexOf(mediaLock) >= 0) return mediaLock;
        return ps.find(p => p.isPlaying) || (ps.length > 0 ? ps[0] : null);
    }

    // Estado mostrado. Alguns players (o Sonora, players web) levam até ~1,5 s para
    // confirmar play/pause e às vezes mandam um estado atrasado pelo Mpris, o que
    // deixava o ícone "pausado" com a música tocando. Após o clique vale o estado
    // pedido; depois o playerctl diz o real (até 4 conferências) e o override sai
    // quando o Mpris concordar.
    property var mediaOverride: null
    property var mediaLock: null
    property int mediaSyncTries: 0
    readonly property bool mediaPlaying: mediaOverride !== null ? mediaOverride
        : (player !== null && player.isPlaying)

    function mediaToggle() {
        const pl = player;
        if (!pl) return;
        const want = !mediaPlaying;
        mediaLock = pl;
        mediaOverride = want;
        if (want && pl.canPlay) pl.play();
        else if (!want && pl.canPause) pl.pause();
        else if (pl.canTogglePlaying) pl.togglePlaying();
        mediaSyncTries = 0;
        mediaSyncTimer.restart();
    }
    function mediaRelease() {
        mediaSyncTimer.stop();
        mediaOverride = null;
        mediaLock = null;
    }
    Timer {
        id: mediaSyncTimer
        interval: 1200
        onTriggered: {
            if (!vbar.mediaLock || mediaSyncProc.running) return;
            mediaSyncProc.command = ["playerctl", "-p",
                String(vbar.mediaLock.dbusName).replace("org.mpris.MediaPlayer2.", ""), "status"];
            mediaSyncProc.running = true;
        }
    }
    Process {
        id: mediaSyncProc
        stdout: StdioCollector {
            onStreamFinished: {
                const st = text.trim();
                if (st === "Playing" || st === "Paused" || st === "Stopped")
                    vbar.mediaOverride = st === "Playing";
                vbar.mediaSyncTries++;
                if (!vbar.mediaLock || vbar.mediaLock.isPlaying === vbar.mediaOverride
                        || vbar.mediaSyncTries >= 4)
                    vbar.mediaRelease();
                else
                    mediaSyncTimer.restart();
            }
        }
    }

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

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property int btConnected: vbar.btAdapter
        ? vbar.btAdapter.devices.values.filter(d => d.connected).length : 0

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
        opacity: bb.editKey !== "" && !ShellLayout.barModule(bb.editKey) ? 0.35 : 1
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
        Behavior on color { ColorAnimation { duration: 130 } }

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

        MouseArea {
            id: bbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: if (bb.popKind !== "" && !bb.editable) vbar.showPop(bb.popKind, bb)
            onExited: if (bb.popKind !== "") vbar.leavePop()
            onClicked: mouse => {
                if (bb.editable) {
                    ShellLayout.setBarModule(bb.editKey, !ShellLayout.barModule(bb.editKey));
                    return;
                }
                mouse.button === Qt.RightButton ? bb.secondary() : bb.activated();
            }
            onWheel: w => bb.wheel(w.angleDelta.y)
        }
    }

    // ================= conteúdo =================
    Item {
        width: vbar.stripW
        height: parent.height
        // Sai pela lateral quando está escondida.
        x: (vbar.onLeft ? 0 : parent.width - width) + (vbar.shown ? 0 : (vbar.onLeft ? -vbar.barW : vbar.barW))
        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

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
                anchors.fill: parent
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 6

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
                            Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 160 } }

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
                    visible: vbar.player !== null
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
                        opacity: vbar.mediaPlaying ? 1 : 0.55
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
                        onClicked: vbar.mediaToggle()
                    }
                }

                Item { Layout.fillHeight: true }

                // ---- bandeja (apps em segundo plano) ----
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

                Rectangle {
                    visible: SystemTray.items.values.length > 0
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 1
                    color: Theme.withAlpha(Theme.outline, 0.35)
                }

                // ---- indicadores ----
                BarButton {
                    editKey: "notifications"
                    visible: ShellLayout.showModule("notifications")
                    icon: NotifService.dnd ? Theme.icons.bellOff : Theme.icons.bell
                    iconColor: NotifService.dnd ? Theme.secondary
                        : (NotifService.unreadCount > 0 ? Theme.primary : Theme.textColor)
                    badge: NotifService.unreadCount > 0
                        ? (NotifService.unreadCount > 99 ? "99+" : String(NotifService.unreadCount)) : ""
                    onActivated: vbar.notifClicked()
                    onSecondary: NotifService.toggleDnd()
                }

                BarButton {
                    editKey: "audio"
                    visible: ShellLayout.showModule("audio")
                    icon: vbar.volIcon()
                    popKind: "audio"
                    iconColor: (vbar.sink && vbar.sink.audio && vbar.sink.audio.muted) ? Theme.subtext : Theme.textColor
                    onActivated: {
                        if (vbar.sink && vbar.sink.audio) vbar.sink.audio.muted = !vbar.sink.audio.muted;
                    }
                    onSecondary: Quickshell.execDetached(["quickshell", "ipc", "call", "visualconfig", "tab", "4"])
                    onWheel: delta => {
                        if (!vbar.sink || !vbar.sink.audio) return;
                        const step = delta > 0 ? 0.02 : -0.02;
                        vbar.sink.audio.volume = Math.max(0, Math.min(1, vbar.sink.audio.volume + step));
                    }
                }

                BarButton {
                    editKey: "network"
                    visible: ShellLayout.showModule("network")
                    icon: vbar.wifiIcon()
                    popKind: "wifi"
                    iconColor: vbar.activeNetwork ? Theme.textColor : Theme.subtext
                    onActivated: Quickshell.execDetached(["quickshell", "ipc", "call", "visualconfig", "tab", "11"])
                }

                BarButton {
                    editKey: "bluetooth"
                    visible: vbar.btAdapter !== null && ShellLayout.showModule("bluetooth")
                    icon: !vbar.btAdapter || !vbar.btAdapter.enabled ? Theme.icons.btOff
                        : (vbar.btConnected > 0 ? Theme.icons.btConnected : Theme.icons.bt)
                    iconColor: vbar.btConnected > 0 ? Theme.primary : Theme.textColor
                    popKind: "bt"
                    onActivated: Quickshell.execDetached(["quickshell", "ipc", "call", "visualconfig", "tab", "10"])
                }

                BarButton {
                    editKey: "battery"
                    visible: vbar.battery !== null && vbar.battery.isLaptopBattery && ShellLayout.showModule("battery")
                    icon: vbar.batIcon()
                    popKind: "battery"
                    iconColor: vbar.battery && vbar.battery.percentage < 0.15 ? Theme.critical : Theme.textColor
                    onActivated: Quickshell.execDetached(["quickshell", "ipc", "call", "visualconfig", "tab", "6"])
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 1
                    color: Theme.withAlpha(Theme.outline, 0.35)
                }

                BarButton {
                    editKey: "settings"
                    visible: ShellLayout.showModule("settings")
                    icon: Theme.icons.tune
                    onActivated: vbar.visualConfigClicked()
                }

                BarButton {
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
        readonly property bool busy: outSlider.dragging || inSlider.dragging
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
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: popBox.opacity > 0.5; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

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

            // ---- áudio ----
            PopTitle { visible: vbar.pop === "audio"; text: Theme.t("topbar.output", "Saída") }
            PopSlider {
                id: outSlider
                visible: vbar.pop === "audio"
                Layout.fillWidth: true
                icon: vbar.volIcon()
                value: vbar.sink && vbar.sink.audio ? vbar.sink.audio.volume : 0
                dimmed: vbar.sink && vbar.sink.audio ? vbar.sink.audio.muted : true
                onMoved: v => { if (vbar.sink && vbar.sink.audio) vbar.sink.audio.volume = v; }
                onIconClicked: if (vbar.sink && vbar.sink.audio) vbar.sink.audio.muted = !vbar.sink.audio.muted
            }
            PopTitle { visible: vbar.pop === "audio"; text: Theme.t("topbar.microphone", "Microfone"); Layout.topMargin: 4 }
            PopSlider {
                id: inSlider
                visible: vbar.pop === "audio"
                Layout.fillWidth: true
                icon: vbar.source && vbar.source.audio && vbar.source.audio.muted ? Theme.icons.micOff : Theme.icons.mic
                value: vbar.source && vbar.source.audio ? vbar.source.audio.volume : 0
                dimmed: vbar.source && vbar.source.audio ? vbar.source.audio.muted : true
                onMoved: v => { if (vbar.source && vbar.source.audio) vbar.source.audio.volume = v; }
                onIconClicked: if (vbar.source && vbar.source.audio) vbar.source.audio.muted = !vbar.source.audio.muted
            }

            // ---- bateria ----
            PopTitle {
                visible: vbar.pop === "battery"
                text: !vbar.battery ? "" : Math.round(vbar.battery.percentage * 100) + "% · " + (
                    vbar.battery.state === UPowerDeviceState.Charging ? Theme.t("vbar.charging", "carregando")
                    : vbar.battery.state === UPowerDeviceState.FullyCharged ? Theme.t("vbar.charged", "carregada")
                    : Theme.t("vbar.on_battery", "na bateria"))
            }
            PopText {
                visible: vbar.pop === "battery" && text !== ""
                text: !vbar.battery ? "" : vbar.battery.state === UPowerDeviceState.Charging
                    ? (vbar.fmtTime(vbar.battery.timeToFull) ? Theme.t("vbar.full_in", "Cheia em") + " " + vbar.fmtTime(vbar.battery.timeToFull) : "")
                    : (vbar.fmtTime(vbar.battery.timeToEmpty) ? Theme.t("vbar.remaining", "Resta") + " " + vbar.fmtTime(vbar.battery.timeToEmpty) : "")
            }
            PopTitle { visible: vbar.pop === "battery"; text: Theme.t("topbar.power_profile", "Perfil de energia"); Layout.topMargin: 6 }
            Repeater {
                model: vbar.pop === "battery" ? [
                    { p: PowerProfile.PowerSaver, icon: Theme.icons.saver, label: Theme.t("sidebar.power_saver", "Economia") },
                    { p: PowerProfile.Balanced, icon: Theme.icons.balanced, label: Theme.t("sidebar.power_balanced", "Equilíbrio") },
                    { p: PowerProfile.Performance, icon: Theme.icons.perf, label: Theme.t("sidebar.power_perf", "Desempenho") }
                ] : []
                delegate: PopAction {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: modelData.icon
                    label: modelData.label
                    selected: PowerProfiles.profile === modelData.p
                    onActivated: PowerProfiles.profile = modelData.p
                }
            }

            PopTitle { visible: vbar.pop === "battery"; text: Theme.t("topbar.optimizations", "Otimizações de GPU & Tela"); Layout.topMargin: 6 }
            PopAction {
                visible: vbar.pop === "battery"
                Layout.fillWidth: true
                icon: Theme.icons.gamepad
                label: Theme.t("vbar.game_mode", "Modo jogo")
                selected: GameMode.active
                onActivated: GameMode.manual = !GameMode.manual
            }
            PopAction {
                visible: vbar.pop === "battery"
                Layout.fillWidth: true
                icon: vbar.blurEnabled ? Theme.icons.blur : Theme.icons.blurOff
                label: Theme.t("vbar.blur", "Desfoque")
                selected: vbar.blurEnabled
                onActivated: {
                    vbar.blurEnabled = !vbar.blurEnabled;
                    blurToggleProc.running = true;
                }
            }
            PopAction {
                visible: vbar.pop === "battery"
                Layout.fillWidth: true
                icon: Theme.icons.lightning
                label: Theme.t("vbar.ultra_perf", "Ultra desempenho")
                selected: vbar.perfModeEnabled
                onActivated: {
                    vbar.perfModeEnabled = !vbar.perfModeEnabled;
                    perfToggleProc.running = true;
                }
            }

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
                                { icon: vbar.mediaPlaying ? Theme.icons.pause : Theme.icons.play, act: "toggle" },
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
                                        const pl = vbar.player;
                                        if (!pl) return;
                                        if (mBtn.modelData.act === "prev" && pl.canGoPrevious) { vbar.mediaRelease(); pl.previous(); }
                                        else if (mBtn.modelData.act === "next" && pl.canGoNext) { vbar.mediaRelease(); pl.next(); }
                                        else if (mBtn.modelData.act === "toggle") vbar.mediaToggle();
                                    }
                                }
                            }
                        }
                    }
                }
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

            // ---- bluetooth ----
            PopTitle {
                visible: vbar.pop === "bt"
                text: !vbar.btAdapter ? Theme.t("topbar.no_bt_adapter", "Sem adaptador")
                    : vbar.btAdapter.enabled ? "Bluetooth" : Theme.t("topbar.bt_off", "Bluetooth desligado")
            }
            Repeater {
                model: vbar.pop === "bt" && vbar.btAdapter ? vbar.btAdapter.devices.values.filter(d => d.connected) : []
                delegate: PopText {
                    required property var modelData
                    text: "• " + (modelData.name || modelData.address)
                }
            }
            PopText {
                visible: vbar.pop === "bt" && vbar.btAdapter !== null && vbar.btAdapter.enabled && vbar.btConnected === 0
                text: Theme.t("vbar.no_bt_devices", "Nenhum aparelho conectado")
            }

            PopText {
                visible: vbar.pop === "wifi" || vbar.pop === "bt" || vbar.pop === "battery"
                Layout.topMargin: 4
                text: Theme.t("vbar.click_hint", "Clique no ícone para mais opções")
                font.pixelSize: 10
                opacity: 0.8
            }
        }
    }
}
