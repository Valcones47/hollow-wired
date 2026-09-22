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
import "."

// Barra lateral vertical — a alternativa à barra de cima, que é como a maior
// parte dos rices de Hyprland se organiza.
//
// É um componente à parte, e não um modo dentro do TopBar.qml, de propósito: a
// barra de cima desenha os popups num Canvas com cantos invertidos preso à
// borda de baixo dela, e virar aquilo de lado significaria refazer o desenho
// inteiro. Aqui os módulos abrem direto o lugar que já resolve o assunto (o
// hub, o painel, a central de ações), o que numa barra estreita é mais direto
// do que um popup pendurado.
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
    implicitWidth: vbar.barW + Theme.frameThickness
    exclusiveZone: ShellLayout.barAutohide ? 0 : vbar.barW + Theme.frameThickness

    WlrLayershell.namespace: "quickshell-vbar"
    WlrLayershell.layer: vbar.launcherOpen ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // ---- esconder no hover ----
    property bool barHovered: false
    readonly property bool shown: !ShellLayout.barAutohide || barHovered
    Timer { id: hideDelay; interval: 400; onTriggered: vbar.barHovered = false }
    Timer { id: showDelay; interval: 60; onTriggered: vbar.barHovered = true }

    mask: Region {
        x: vbar.onLeft ? 0 : (vbar.shown ? 0 : vbar.width - 4)
        y: 0
        width: vbar.shown ? vbar.width : 4
        height: vbar.height
    }

    // ================= dados =================
    readonly property PwNode sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [vbar.sink] }

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
            onClicked: mouse => mouse.button === Qt.RightButton ? bb.secondary() : bb.activated()
            onWheel: w => bb.wheel(w.angleDelta.y)
        }
    }

    // ================= conteúdo =================
    Item {
        anchors.fill: parent
        // Sai pela lateral quando está escondida.
        x: vbar.shown ? 0 : (vbar.onLeft ? -vbar.barW : vbar.barW)
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
                    visible: ShellLayout.barModule("clock")
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
                        onClicked: vbar.clockClicked()
                    }
                }

                Item { Layout.fillHeight: true }

                // ---- indicadores ----
                BarButton {
                    visible: ShellLayout.barModule("notifications")
                    icon: NotifService.dnd ? Theme.icons.bellOff : Theme.icons.bell
                    iconColor: NotifService.dnd ? Theme.secondary
                        : (NotifService.unreadCount > 0 ? Theme.primary : Theme.textColor)
                    badge: NotifService.unreadCount > 0
                        ? (NotifService.unreadCount > 99 ? "99+" : String(NotifService.unreadCount)) : ""
                    onActivated: vbar.notifClicked()
                    onSecondary: NotifService.toggleDnd()
                }

                BarButton {
                    visible: ShellLayout.barModule("audio")
                    icon: vbar.volIcon()
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
                    visible: ShellLayout.barModule("network")
                    icon: vbar.wifiIcon()
                    iconColor: vbar.activeNetwork ? Theme.textColor : Theme.subtext
                    onActivated: Quickshell.execDetached(["quickshell", "ipc", "call", "visualconfig", "tab", "11"])
                }

                BarButton {
                    visible: vbar.btAdapter !== null && ShellLayout.barModule("bluetooth")
                    icon: !vbar.btAdapter || !vbar.btAdapter.enabled ? Theme.icons.btOff
                        : (vbar.btConnected > 0 ? Theme.icons.btConnected : Theme.icons.bt)
                    iconColor: vbar.btConnected > 0 ? Theme.primary : Theme.textColor
                    onActivated: Quickshell.execDetached(["quickshell", "ipc", "call", "visualconfig", "tab", "10"])
                }

                BarButton {
                    visible: vbar.battery !== null && vbar.battery.isLaptopBattery && ShellLayout.barModule("battery")
                    icon: vbar.batIcon()
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
                    visible: ShellLayout.barModule("settings")
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
}
