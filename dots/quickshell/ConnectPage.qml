import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import "."

// Página de Wi-Fi / Bluetooth do painel de controle (abre pela seta dos
// blocos). Centro = conexão atual; em volta, as ações; "Buscar" (ou clique no
// centro) mostra as redes/aparelhos orbitando. Rede com senha abre uma folha
// com o campo embaixo.
Item {
    id: pg

    property string mode: "wifi"        // "wifi" | "bt"
    signal back()

    // ---------- Wi-Fi ----------
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var activeNet: wifiDevice ? wifiDevice.networks.values.find(n => n.connected) || null : null
    property var netInfo: ({})
    Process {
        id: infoProc
        command: ["rice-network", "status"]
        stdout: StdioCollector { onStreamFinished: { try { pg.netInfo = JSON.parse(text) || {}; } catch (e) {} } }
    }
    onActiveNetChanged: if (!infoProc.running) infoProc.running = true
    Binding {
        target: pg.wifiDevice
        property: "scannerEnabled"
        value: true
        when: pg.visible && pg.mode === "wifi" && pg.wifiDevice !== null
    }

    function secured(n) { return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe; }
    function sigIcon(s) { return s > 0.75 ? Theme.icons.wifi4 : s > 0.5 ? Theme.icons.wifi3 : s > 0.25 ? Theme.icons.wifi2 : Theme.icons.wifi1; }
    readonly property var wifiNets: !wifiDevice || !Networking.wifiEnabled ? []
        : wifiDevice.networks.values.slice().sort((a, b) => (b.known - a.known) || (b.signalStrength - a.signalStrength)).slice(0, 14)

    // ---------- Bluetooth ----------
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property var btDevs: bt ? bt.devices.values.slice().sort((a, b) =>
        (b.connected - a.connected) || (b.paired - a.paired) || (a.name || "").localeCompare(b.name || "")) : []
    readonly property var btDev: btDevs.find(d => d.connected) || null
    function btIcon(d) {
        const i = (d && d.icon) || "";
        return i.includes("headset") || i.includes("headphone") || i.includes("audio") ? Theme.icons.headphones
             : Theme.icons.bt;
    }

    // ---------- estado da página ----------
    property bool orbitMode: false
    property var pskNet: null
    property string status: ""
    onModeChanged: { orbitMode = false; pskNet = null; status = ""; }
    onVisibleChanged: {
        if (!visible) { orbitMode = false; pskNet = null; status = ""; if (bt) bt.discovering = false; }
        else if (!infoProc.running) infoProc.running = true;
    }

    readonly property bool powered: mode === "wifi" ? Networking.wifiEnabled : (bt !== null && bt.enabled)
    function togglePower() {
        if (mode === "wifi") Networking.wifiEnabled = !Networking.wifiEnabled;
        else if (bt) bt.enabled = !bt.enabled;
    }

    // Sem conexão, já abre na órbita (é o que a pessoa veio procurar).
    readonly property bool showOrbit: powered && (orbitMode || (mode === "wifi" ? activeNet === null : btDev === null))

    function connectNet(n) {
        status = "";
        if (n.connected) { orbitMode = false; return; }
        if (n.known || !secured(n)) { n.connect(); status = Theme.t("wifi.connecting", "conectando…"); orbitMode = false; }
        else pskNet = n;
    }
    Connections {
        target: pg.pskNet
        ignoreUnknownSignals: true
        function onConnectedChanged() { if (pg.pskNet && pg.pskNet.connected) { pg.pskNet = null; pg.status = ""; } }
        function onConnectionFailed(reason) {
            pg.status = reason === ConnectionFailReason.NoSecrets ? Theme.t("wifi.wrong_psk", "Senha incorreta") : Theme.t("wifi.failed", "Não foi possível conectar");
        }
    }
    Connections {
        target: pg.activeNet
        ignoreUnknownSignals: true
        function onConnectedChanged() { pg.status = ""; }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // topo: voltar, título, liga/desliga
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                implicitWidth: 30; implicitHeight: 30; radius: 15
                color: backArea.containsMouse ? Theme.tileHigh : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: Theme.icons.chevronRight
                    rotation: 180
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 18
                    color: Theme.textColor
                }
                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pg.back() }
            }
            Text {
                Layout.fillWidth: true
                text: pg.mode === "wifi" ? "Wi‑Fi" : "Bluetooth"
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Theme.textColor
            }
            Text {
                visible: pg.status !== ""
                text: pg.status
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: pg.status === Theme.t("wifi.connecting", "conectando…") ? Theme.primary : Theme.critical
            }
            Rectangle {
                implicitWidth: 40; implicitHeight: 22; radius: 11
                color: pg.powered ? Theme.primary : Theme.tileHigh
                Behavior on color { ColorAnimation { duration: Theme.ms(140) } }
                Rectangle {
                    width: 16; height: 16; radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    x: pg.powered ? parent.width - width - 3 : 3
                    color: Theme.textColor
                    Behavior on x { NumberAnimation { duration: Theme.ms(140) } }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pg.togglePower() }
            }
        }

        RadialHub {
            id: scene
            Layout.fillWidth: true
            Layout.fillHeight: true
            orbitMode: pg.showOrbit

            centerActive: pg.powered && (pg.mode === "wifi" ? pg.activeNet !== null : pg.btDev !== null)
            centerIcon: pg.mode === "wifi"
                ? (!pg.powered ? Theme.icons.wifiOff : pg.activeNet ? pg.sigIcon(pg.activeNet.signalStrength) : Theme.icons.wifi1)
                : (!pg.powered ? Theme.icons.btOff : pg.btDev ? pg.btIcon(pg.btDev) : Theme.icons.bt)
            centerTitle: pg.mode === "wifi"
                ? (!pg.powered ? Theme.t("cc.off", "Desligado") : pg.activeNet ? pg.activeNet.name : Theme.t("cc.not_connected", "Sem conexão"))
                : (!pg.powered ? Theme.t("cc.off", "Desligado") : pg.btDev ? (pg.btDev.name || pg.btDev.address) : Theme.t("cc.not_connected", "Sem conexão"))
            centerSub: !pg.powered ? Theme.t("conn.tap_on", "clique para ligar")
                : (pg.mode === "wifi" ? (pg.activeNet ? Theme.t("cc.connected", "conectado") : "")
                                      : (pg.btDev ? Theme.t("cc.connected", "conectado") : (pg.bt && pg.bt.discovering ? Theme.t("conn.searching", "procurando…") : Theme.t("conn.tap_scan", "clique para buscar"))))
            readonly property bool connected: pg.mode === "wifi" ? pg.activeNet !== null : pg.btDev !== null
            orbitHint: (pg.mode === "wifi" ? Theme.t("conn.wifi_pick", "Clique numa rede para conectar") : Theme.t("conn.bt_pick", "Clique num aparelho para conectar"))
                + (connected ? " · " + Theme.t("conn.center_back", "no centro para voltar")
                   : (pg.mode === "bt" ? " · " + Theme.t("conn.center_scan", "no centro para buscar mais") : ""))

            nodes: {
                if (!pg.powered) return [];
                if (pg.mode === "wifi") {
                    if (!pg.activeNet) return [];
                    const i = pg.netInfo;
                    const out = [{ key: "scan", icon: Theme.icons.magnify, label: Theme.t("conn.scan", "Buscar") }];
                    if (i.ip) out.push({ key: "ip", icon: Theme.icons.ethernet, label: i.ip });
                    out.push({ key: "signal", icon: pg.sigIcon(pg.activeNet.signalStrength), label: Math.round(pg.activeNet.signalStrength * 100) + "%" });
                    if (i.freq) out.push({ key: "band", icon: Theme.icons.speed, label: (i.is_5g ? "5 GHz" : "2,4 GHz") });
                    if (i.security) out.push({ key: "sec", icon: Theme.icons.lock, label: String(i.security).split(" ").pop() });
                    out.push({ key: "disconnect", icon: Theme.icons.wifiOff, label: Theme.t("wifi.disconnect", "Desconectar"), danger: true });
                    return out;
                }
                if (!pg.btDev) return [];
                const d = pg.btDev;
                const o = [{ key: "scan", icon: Theme.icons.magnify, label: Theme.t("conn.scan", "Buscar") }];
                if (d.batteryAvailable) o.push({ key: "bat", icon: Theme.icons.bat, label: Math.round(d.battery * 100) + "%" });
                o.push({ key: "addr", icon: Theme.icons.info || Theme.icons.bt, label: d.address });
                o.push({ key: "disconnect", icon: Theme.icons.btOff, label: Theme.t("wifi.disconnect", "Desconectar") });
                o.push({ key: "forget", icon: Theme.icons.trash, label: Theme.t("conn.forget", "Esquecer"), danger: true });
                return o;
            }

            orbit: {
                // Ordem fixa (conectada, salvas, depois por nome) e sem o ícone de
                // sinal: o scanner muda o sinal o tempo todo, e reordenar por ele
                // fazia as redes pularem de lugar na órbita.
                if (pg.mode === "wifi")
                    return pg.wifiNets.slice()
                        .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || a.name.localeCompare(b.name))
                        .map(n => ({
                            key: n.name, strong: n.connected || n.known,
                            icon: n.connected ? Theme.icons.check : (pg.secured(n) && !n.known ? Theme.icons.lock : Theme.icons.wifi3),
                            label: n.name
                        }));
                return pg.btDevs.filter(d => d.name || d.paired).slice(0, 14).map(d => ({
                    key: d.address, strong: d.connected || d.paired,
                    icon: d.connected ? Theme.icons.check : pg.btIcon(d),
                    label: d.name || d.address
                }));
            }

            onCenterClicked: {
                if (!pg.powered) { pg.togglePower(); return; }
                if (!scene.connected) {
                    // Sem conexão a órbita já está aberta: o centro busca aparelhos.
                    if (pg.mode === "bt" && pg.bt) pg.bt.discovering = !pg.bt.discovering;
                    return;
                }
                pg.orbitMode = !pg.orbitMode;
                if (pg.mode === "bt" && pg.bt) pg.bt.discovering = pg.orbitMode;
            }
            onNodeClicked: key => {
                if (key === "scan") {
                    pg.orbitMode = true;
                    if (pg.mode === "bt" && pg.bt) pg.bt.discovering = true;
                } else if (key === "ip" && pg.netInfo.ip) {
                    Quickshell.execDetached(["wl-copy", pg.netInfo.ip]);
                    pg.status = "";
                } else if (key === "disconnect") {
                    if (pg.mode === "wifi" && pg.activeNet) pg.activeNet.disconnect();
                    else if (pg.btDev) pg.btDev.disconnect();
                } else if (key === "forget" && pg.btDev) {
                    pg.btDev.forget();
                }
            }
            onOrbitClicked: key => {
                if (pg.mode === "wifi") {
                    const n = pg.wifiNets.find(x => x.name === key);
                    if (n) pg.connectNet(n);
                } else {
                    const d = pg.btDevs.find(x => x.address === key);
                    if (!d) return;
                    if (d.connected) { pg.orbitMode = false; return; }
                    if (d.paired) d.connect(); else d.pair();
                    pg.orbitMode = false;
                    if (pg.bt) pg.bt.discovering = false;
                }
            }
        }
        // Wi-Fi | Bluetooth
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: segRow.implicitWidth + 8
            implicitHeight: 34
            radius: 10
            color: Theme.tile
            RowLayout {
                id: segRow
                anchors.centerIn: parent
                spacing: 4
                Repeater {
                    model: [{ k: "wifi", icon: Theme.icons.wifi4, label: "Wi‑Fi" }, { k: "bt", icon: Theme.icons.bt, label: "Bluetooth" }]
                    delegate: Rectangle {
                        id: seg
                        required property var modelData
                        readonly property bool on: pg.mode === modelData.k
                        implicitWidth: segIn.implicitWidth + 24
                        implicitHeight: 28
                        radius: 8
                        color: on ? Theme.primary : (segA.containsMouse ? Theme.tileHigh : "transparent")
                        Behavior on color { ColorAnimation { duration: Theme.ms(140) } }
                        RowLayout {
                            id: segIn
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: seg.modelData.icon; font.family: Theme.iconFontFamily; font.pixelSize: 13; color: seg.on ? Theme.background : Theme.subtext }
                            Text { text: seg.modelData.label; font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: seg.on ? Font.DemiBold : Font.Normal; color: seg.on ? Theme.background : Theme.textColor }
                        }
                        MouseArea { id: segA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pg.mode = seg.modelData.k }
                    }
                }
            }
        }
    }

    // ---------- folha de senha ----------
    Rectangle {
        id: sheet
        visible: pg.pskNet !== null
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: sheetCol.implicitHeight + 24
        radius: 14
        color: Theme.tileHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.3)
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.ms(140) } }
        onVisibleChanged: if (visible) { pskField.text = ""; pskField.forceActiveFocus(); }
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: sheetCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: Theme.icons.lock
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 14
                    color: Theme.primary
                }
                Text {
                    Layout.fillWidth: true
                    text: pg.pskNet ? pg.pskNet.name : ""
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.textColor
                }
                Text {
                    text: Theme.icons.close
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 14
                    color: Theme.subtext
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { pg.pskNet = null; pg.status = ""; } }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 8
                    color: Theme.tile
                    border.width: 1
                    border.color: pskField.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.3)
                    TextInput {
                        id: pskField
                        property bool show: false
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 32
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: show ? TextInput.Normal : TextInput.Password
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textColor
                        clip: true
                        selectByMouse: true
                        onAccepted: sheet.submit()
                        Keys.onEscapePressed: pg.pskNet = null
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: pskField.text === ""
                            text: Theme.t("wifi.psk", "Senha")
                            font: pskField.font
                            color: Theme.subtext
                        }
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        text: pskField.show ? Theme.icons.eyeOff : Theme.icons.eye
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 15
                        color: Theme.subtext
                        MouseArea { anchors.fill: parent; anchors.margins: -5; cursorShape: Qt.PointingHandCursor; onClicked: pskField.show = !pskField.show }
                    }
                }
                Rectangle {
                    implicitWidth: goLbl.implicitWidth + 22
                    implicitHeight: 34
                    radius: 8
                    color: goA.containsMouse ? Theme.withAlpha(Theme.primary, 0.85) : Theme.primary
                    Text { id: goLbl; anchors.centerIn: parent; text: Theme.t("wifi.connect", "Conectar"); font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold; color: Theme.background }
                    MouseArea { id: goA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sheet.submit() }
                }
            }
        }
        function submit() {
            if (!pg.pskNet) return;
            if (pskField.text.length < 8) { pg.status = Theme.t("wifi.psk_short", "A senha tem pelo menos 8 caracteres"); return; }
            pg.status = Theme.t("wifi.connecting", "conectando…");
            pg.pskNet.connectWithPsk(pskField.text);
        }
    }
}
