import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import "."

// Lista de redes Wi-Fi com senha na própria linha (sem abrir terminal).
// Usada no popup de rede da barra e no painel de controle.
//   - rede conectada: clique mostra "Desconectar";
//   - rede salva: conecta direto (troca de rede mesmo já conectado);
//   - rede nova com senha: a linha abre um campo de senha; Enter conecta;
//   - senha errada / falha: a linha volta a pedir a senha com o motivo.
ColumnLayout {
    id: wl
    property var device: null          // WifiDevice
    property int maxItems: 8
    // Rede com a linha aberta (senha ou ações) e erro da última tentativa.
    property var openNet: null
    property string error: ""
    property var pending: null         // rede que está conectando agora

    spacing: 4

    readonly property var nets: !device || !Networking.wifiEnabled ? []
        : device.networks.values.slice()
            .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
            .slice(0, maxItems)

    function secured(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }
    function signalIcon(n) {
        const s = n.signalStrength;
        return s > 0.75 ? Theme.icons.wifi4 : s > 0.5 ? Theme.icons.wifi3 : s > 0.25 ? Theme.icons.wifi2 : Theme.icons.wifi1;
    }
    function activate(n) {
        error = "";
        if (n.connected || n.known || !secured(n)) {
            // Conectada: a linha abre para mostrar "Desconectar".
            if (n.connected) { openNet = openNet === n ? null : n; return; }
            openNet = null;
            pending = n;
            n.connect();
        } else {
            openNet = openNet === n ? null : n;
        }
    }
    function submit(n, psk) {
        if (psk.length < 8) { error = Theme.t("wifi.psk_short", "A senha tem pelo menos 8 caracteres"); return; }
        error = "";
        pending = n;
        n.connectWithPsk(psk);
    }

    Connections {
        target: wl.pending
        ignoreUnknownSignals: true
        function onConnectedChanged() {
            if (wl.pending && wl.pending.connected) { wl.pending = null; wl.openNet = null; }
        }
        function onConnectionFailed(reason) {
            const n = wl.pending;
            wl.pending = null;
            wl.error = reason === ConnectionFailReason.NoSecrets
                ? Theme.t("wifi.wrong_psk", "Senha incorreta")
                : Theme.t("wifi.failed", "Não foi possível conectar");
            if (n && wl.secured(n)) wl.openNet = n;
        }
    }
    // A rede pede senha (salva com senha antiga, por exemplo): abre o campo.
    Repeater {
        model: wl.nets
        delegate: Item {
            required property var modelData
            Connections {
                target: modelData
                function onRequestConnectWithPsk() { wl.pending = null; wl.openNet = modelData; }
            }
        }
    }

    Repeater {
        model: wl.nets
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool isOpen: wl.openNet === modelData
            readonly property bool busy: wl.pending === modelData || modelData.stateChanging
            Layout.fillWidth: true
            implicitHeight: 32 + (isOpen ? extra.implicitHeight + 8 : 0)
            radius: 9
            clip: true
            color: rowArea.containsMouse || isOpen ? Theme.tileHigh
                 : modelData.connected ? Theme.withAlpha(Theme.primary, 0.22) : Theme.tile
            Behavior on color { ColorAnimation { duration: Theme.ms(120) } }
            Behavior on implicitHeight { NumberAnimation { duration: Theme.ms(160); easing.type: Easing.OutCubic } }

            MouseArea {
                id: rowArea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 32
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: wl.activate(row.modelData)
            }

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                height: 32
                spacing: 8
                Text {
                    text: wl.signalIcon(row.modelData)
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 16
                    color: row.modelData.connected ? Theme.primary : Theme.subtext
                }
                Text {
                    Layout.fillWidth: true
                    text: row.modelData.name
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: row.modelData.connected ? Font.DemiBold : Font.Normal
                    color: Theme.textColor
                }
                Text {
                    text: row.busy ? Theme.t("wifi.connecting", "conectando…")
                        : row.modelData.connected ? Theme.t("cc.connected", "conectado")
                        : row.modelData.known ? Theme.t("wifi.saved", "salva") : ""
                    visible: text !== ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: row.busy ? Theme.primary : Theme.subtext
                }
                Text {
                    visible: wl.secured(row.modelData) && !row.modelData.known
                    text: Theme.icons.lock
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 12
                    color: Theme.subtext
                }
            }

            // Parte que abre: senha (rede nova) ou desconectar (rede atual).
            ColumnLayout {
                id: extra
                visible: row.isOpen
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 34
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 6

                RowLayout {
                    visible: !row.modelData.connected
                    Layout.fillWidth: true
                    spacing: 6
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 7
                        color: Theme.tile
                        border.width: 1
                        border.color: psk.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.3)
                        TextInput {
                            id: psk
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 30
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: showPsk.checked ? TextInput.Normal : TextInput.Password
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.textColor
                            selectByMouse: true
                            clip: true
                            onAccepted: wl.submit(row.modelData, text)
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: psk.text === ""
                                text: Theme.t("wifi.psk", "Senha")
                                font: psk.font
                                color: Theme.subtext
                            }
                        }
                        // Mostrar/esconder a senha.
                        Text {
                            id: showPsk
                            property bool checked: false
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: checked ? Theme.icons.eyeOff : Theme.icons.eye
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 14
                            color: Theme.subtext
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: showPsk.checked = !showPsk.checked
                            }
                        }
                    }
                    Rectangle {
                        implicitWidth: goText.implicitWidth + 20
                        implicitHeight: 30
                        radius: 7
                        color: goArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.8) : Theme.primary
                        Text {
                            id: goText
                            anchors.centerIn: parent
                            text: Theme.t("wifi.connect", "Conectar")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Theme.background
                        }
                        MouseArea {
                            id: goArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wl.submit(row.modelData, psk.text)
                        }
                    }
                }
                Text {
                    visible: !row.modelData.connected && wl.error !== ""
                    text: wl.error
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.critical
                }
                PopAction {
                    visible: row.modelData.connected
                    icon: Theme.icons.wifiOff
                    label: Theme.t("wifi.disconnect", "Desconectar")
                    onActivated: { wl.openNet = null; row.modelData.disconnect(); }
                }
                PopAction {
                    visible: row.modelData.known
                    icon: Theme.icons.trash
                    label: Theme.t("wifi.forget", "Esquecer rede")
                    needsConfirm: true
                    onActivated: { wl.openNet = null; row.modelData.forget(); }
                }

                onVisibleChanged: if (visible && !row.modelData.connected) psk.forceActiveFocus()
            }
        }
    }
}
