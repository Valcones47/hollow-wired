import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Services.Polkit
import Quickshell.Io
import "."

// PolkitDialog: Agente de autenticação Polkit nativo do Quickshell.
// Mantido DESLIGADO por padrão para segurança, com o polkit-kde-agent
// como fallback principal. Pode ser habilitado nas configurações.
PanelWindow {
    id: root

    // Monitora a preferência do usuário em ~/.config/hollow-wired/polkit.json
    property bool enabledByPref: false

    property FileView prefFile: FileView {
        path: Quickshell.env("HOME") + "/.config/hollow-wired/polkit.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.enabledByPref = !!d.enabled;
            } catch (e) {
                root.enabledByPref = false;
            }
        }
        onLoadFailed: root.enabledByPref = false
    }

    // Instancia o PolkitAgent apenas se habilitado pelo usuário
    property PolkitAgent agent: PolkitAgent {
        id: polkitAgent
        // Não registra se desligado nas preferências
        Component.onCompleted: {
            if (!root.enabledByPref) {
                console.log("PolkitDialog: agente nativo desativado (usando polkit-kde-agent padrão)");
            }
        }
    }

    readonly property bool active: root.enabledByPref && agent.isActive && agent.flow !== null
    readonly property var currentFlow: agent.flow

    // Dimensões de tela cheia para modal overlay
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    WlrLayershell.namespace: "quickshell-polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: root.active ? Theme.withAlpha(Theme.background, 0.65) : "transparent"
    visible: root.active

    onActiveChanged: {
        if (active) {
            passInput.text = "";
            focusTimer.restart();
        }
    }

    Timer {
        id: focusTimer
        interval: 50
        onTriggered: passInput.forceActiveFocus()
    }

    // Atalhos de teclado no modal
    Shortcut {
        enabled: root.active
        sequence: "Escape"
        onActivated: root.cancelAuth()
    }

    Shortcut {
        enabled: root.active
        sequence: "Return"
        onActivated: root.submitAuth()
    }

    function submitAuth() {
        if (root.currentFlow && root.currentFlow.isResponseRequired) {
            root.currentFlow.submit(passInput.text);
            passInput.text = "";
        }
    }

    function cancelAuth() {
        if (root.currentFlow) {
            try {
                root.currentFlow.cancelAuthenticationRequest();
            } catch (e) {}
        }
    }

    // Caixa de diálogo centralizada
    Rectangle {
        id: dialogBox
        anchors.centerIn: parent
        width: 440
        implicitHeight: contentCol.implicitHeight + 36
        radius: Theme.tileRadius
        color: Theme.tile
        border.width: 1
        border.color: Theme.border

        ColumnLayout {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            spacing: 14

            // Cabeçalho: Ícone + Título
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: 10
                    color: Theme.tileHigh

                    Text {
                        anchors.centerIn: parent
                        text: "󰌾"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 22
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: Theme.t("polkit.title", "Autenticação Administrativa")
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                        color: Theme.textColor
                    }

                    Text {
                        text: root.currentFlow ? (root.currentFlow.actionId || "org.freedesktop.policykit.exec") : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            // Mensagem da ação que requer privilégio
            Text {
                Layout.fillWidth: true
                text: root.currentFlow ? (root.currentFlow.message || Theme.t("polkit.desc_default", "Uma aplicação está solicitando permissão para executar uma tarefa administrativa.")) : ""
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.subtext
                wrapMode: Text.WordWrap
            }

            // Mensagem de erro / aviso suplementar (ex: senha errada)
            RowLayout {
                Layout.fillWidth: true
                visible: root.currentFlow && (root.currentFlow.supplementaryIsError || root.currentFlow.failed || (root.currentFlow.supplementaryMessage && root.currentFlow.supplementaryMessage.length > 0))
                spacing: 6

                Text {
                    text: "󰅖"
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 14
                    color: Theme.critical
                }

                Text {
                    Layout.fillWidth: true
                    text: (root.currentFlow && root.currentFlow.supplementaryMessage) ? root.currentFlow.supplementaryMessage : Theme.t("polkit.wrong_pass", "Senha incorreta. Tente novamente.")
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    color: Theme.critical
                    wrapMode: Text.WordWrap
                }
            }

            // Campo de Entrada de Senha
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: 8
                color: Theme.tileHigh
                border.width: 1
                border.color: passInput.activeFocus ? Theme.primary : (root.currentFlow && root.currentFlow.supplementaryIsError ? Theme.critical : Theme.border)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "󰌋"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 14
                        color: passInput.activeFocus ? Theme.primary : Theme.subtext
                    }

                    TextInput {
                        id: passInput
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textColor
                        echoMode: (root.currentFlow && root.currentFlow.responseVisible) ? TextInput.Normal : TextInput.Password
                        inputMethodHints: Qt.ImhHiddenText | Qt.ImhNoAutoUppercase
                        clip: true

                        Text {
                            anchors.fill: parent
                            text: (root.currentFlow && root.currentFlow.inputPrompt) ? root.currentFlow.inputPrompt : Theme.t("polkit.prompt_pass", "Digite sua senha de administrador...")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.withAlpha(Theme.subtext, 0.5)
                            visible: passInput.text.length === 0
                        }
                    }
                }
            }

            // Botões de Ação
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 10

                Item { Layout.fillWidth: true }

                // Cancelar
                Rectangle {
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: 34
                    radius: 7
                    color: cancelMouse.containsMouse ? Theme.tileHigh : "transparent"
                    border.width: 1
                    border.color: Theme.border

                    Text {
                        anchors.centerIn: parent
                        text: Theme.t("polkit.btn_cancel", "Cancelar")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textColor
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelAuth()
                    }
                }

                // Autenticar
                Rectangle {
                    Layout.preferredWidth: 110
                    Layout.preferredHeight: 34
                    radius: 7
                    color: authMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.85) : Theme.primary

                    Text {
                        anchors.centerIn: parent
                        text: Theme.t("polkit.btn_auth", "Autenticar")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        color: Theme.background
                    }

                    MouseArea {
                        id: authMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.submitAuth()
                    }
                }
            }
        }
    }
}
