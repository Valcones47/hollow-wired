import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "."

// Tela de gerenciamento de sessão e confirmação de desligamento (Ctrl + Alt + Del).
// Layout minimalista e centralizado inspirado na tela de segurança / power dialog.
PanelWindow {
    id: sessionDialog

    property bool open: false
    property string selectedAction: "logout"
    property int countdown: 10
    property bool countdownActive: false

    visible: open
    color: "transparent"
    focusable: true

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell-session"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var actions: [
        { key: "suspend",  icon: "󰒲", label: Theme.t("session.suspend", "Suspender"),  desc: Theme.t("session.desc_suspend", "Dormir") },
        { key: "reboot",   icon: "󰜉", label: Theme.t("session.reboot", "Reiniciar"),   desc: Theme.t("session.desc_reboot", "Reiniciar sistema") },
        { key: "poweroff", icon: "󰐥", label: Theme.t("session.shutdown", "Desligar"),  desc: Theme.t("session.desc_shutdown", "Desligar o PC") },
        { key: "logout",   icon: "󰍃", label: Theme.t("session.logout", "Sair"),        desc: Theme.t("session.desc_logout", "Encerrar sessão") }
    ]

    function openDialog(defaultAction) {
        selectedAction = defaultAction || "logout";
        countdown = 10;
        countdownActive = true;
        open = true;
        sessionScope.forceActiveFocus();
    }

    function closeDialog() {
        countdownTimer.stop();
        countdownActive = false;
        open = false;
    }

    function executeAction() {
        const act = selectedAction;
        closeDialog();
        // Dispara o script seguro do rice que já trata término limpo da sessão e bloqueio pré-suspend
        Quickshell.execDetached(["rice-session-action", act]);
    }

    function selectByIndex(delta) {
        let idx = 0;
        for (let i = 0; i < actions.length; i++) {
            if (actions[i].key === selectedAction) { idx = i; break; }
        }
        idx = (idx + delta + actions.length) % actions.length;
        selectedAction = actions[idx].key;
        countdown = 10;
        countdownActive = true;
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        running: sessionDialog.open && sessionDialog.countdownActive
        onTriggered: {
            if (sessionDialog.countdown > 1) {
                sessionDialog.countdown--;
            } else {
                stop();
                sessionDialog.executeAction();
            }
        }
    }

    Item {
        id: sessionScope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: sessionDialog.closeDialog()
        Keys.onLeftPressed: sessionDialog.selectByIndex(-1)
        Keys.onRightPressed: sessionDialog.selectByIndex(1)
        Keys.onReturnPressed: sessionDialog.executeAction()
        Keys.onEnterPressed: sessionDialog.executeAction()

        // Fundo escuro com desfoque condicional (respeita o perfil de desempenho leve)
        Rectangle {
            anchors.fill: parent
            color: Theme.perfMode === "light"
                ? "#e00a0a0f"
                : Theme.withAlpha(Theme.background, 0.88)

            // Clicar fora do card fecha/cancela a tela
            MouseArea {
                anchors.fill: parent
                onClicked: sessionDialog.closeDialog()
            }
        }

        // Card Central de Controle
        MouseArea {
            // Impede cliques no modal de fecharem o diálogo
            anchors.centerIn: parent
            width: 460
            height: 380
            onClicked: {}

            ColumnLayout {
                anchors.fill: parent
                spacing: 16

                // ---------------- Avatar do Usuário ----------------
                Item {
                    Layout.preferredWidth: 84
                    Layout.preferredHeight: 84
                    Layout.alignment: Qt.AlignHCenter

                    ClippingRectangle {
                        anchors.fill: parent
                        radius: 42
                        color: Theme.tile
                        border.width: 2
                        border.color: Theme.withAlpha(Theme.primary, 0.80)

                        AnimatedImage {
                            id: face
                            anchors.fill: parent
                            source: "file://" + Quickshell.env("HOME") + "/.face.webp"
                            playing: sessionDialog.open
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                        }

                        Image {
                            anchors.fill: parent
                            source: "file://" + Quickshell.env("HOME") + "/.face"
                            fillMode: Image.PreserveAspectCrop
                            visible: face.status !== Image.Ready && status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: face.status !== Image.Ready
                            text: Theme.icons.account
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 38
                            color: Theme.textColor
                        }
                    }
                }

                // Nome do usuário
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Quickshell.env("USER") || "Usuário"
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    color: Theme.textColor
                }

                Item { Layout.preferredHeight: 8 }

                // ---------------- 4 Ações Circulares ----------------
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 24

                    Repeater {
                        model: sessionDialog.actions

                        Item {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 82

                            readonly property bool isSelected: sessionDialog.selectedAction === modelData.key

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 54
                                    Layout.preferredHeight: 54
                                    Layout.alignment: Qt.AlignHCenter
                                    radius: 27
                                    color: isSelected
                                        ? Theme.withAlpha(Theme.primary, 0.25)
                                        : (btnArea.containsMouse ? Theme.withAlpha(Theme.tileHigh, 0.8) : Theme.withAlpha(Theme.tile, 0.6))
                                    border.width: isSelected ? 2 : 1
                                    border.color: isSelected
                                        ? Theme.primary
                                        : (btnArea.containsMouse ? Theme.withAlpha(Theme.textColor, 0.6) : Theme.withAlpha(Theme.outline, 0.35))

                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.icon
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 22
                                        color: isSelected ? Theme.primary : Theme.textColor
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: isSelected ? Font.DemiBold : Font.Normal
                                    color: isSelected ? Theme.primary : Theme.subtext
                                }
                            }

                            MouseArea {
                                id: btnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (sessionDialog.selectedAction === modelData.key) {
                                        sessionDialog.executeAction();
                                    } else {
                                        sessionDialog.selectedAction = modelData.key;
                                        sessionDialog.countdown = 10;
                                        sessionDialog.countdownActive = true;
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 12 }

                // ---------------- Texto de Contagem Regressiva ----------------
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        let actName = "";
                        for (let i = 0; i < sessionDialog.actions.length; i++) {
                            if (sessionDialog.actions[i].key === sessionDialog.selectedAction) {
                                actName = sessionDialog.actions[i].label;
                                break;
                            }
                        }
                        return Theme.t("session.action_in", "Executando ") + actName.toLowerCase() + " " +
                               Theme.t("session.seconds", "em %1 segundos...").replace("%1", sessionDialog.countdown);
                    }
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.subtext
                }

                // ---------------- Botões OK e Cancelar ----------------
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 16

                    // Botão Confirmar
                    Rectangle {
                        Layout.preferredWidth: 90
                        Layout.preferredHeight: 32
                        radius: 16
                        color: okArea.containsMouse ? Theme.primary : Theme.withAlpha(Theme.primary, 0.85)

                        Text {
                            anchors.centerIn: parent
                            text: Theme.t("session.ok", "OK")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Theme.background
                        }

                        MouseArea {
                            id: okArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sessionDialog.executeAction()
                        }
                    }

                    // Botão Cancelar
                    Rectangle {
                        Layout.preferredWidth: 90
                        Layout.preferredHeight: 32
                        radius: 16
                        color: cancelArea.containsMouse ? Theme.withAlpha(Theme.tileHigh, 0.9) : Theme.withAlpha(Theme.tile, 0.6)
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.outline, 0.3)

                        Text {
                            anchors.centerIn: parent
                            text: Theme.t("session.cancel", "Cancelar")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.textColor
                        }

                        MouseArea {
                            id: cancelArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sessionDialog.closeDialog()
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "session"

        function open(): void {
            sessionDialog.openDialog("logout");
        }

        function suspend(): void {
            sessionDialog.openDialog("suspend");
        }

        function reboot(): void {
            sessionDialog.openDialog("reboot");
        }

        function poweroff(): void {
            sessionDialog.openDialog("poweroff");
        }

        function logout(): void {
            sessionDialog.openDialog("logout");
        }

        function hide(): void {
            sessionDialog.closeDialog();
        }

        function toggle(): void {
            if (sessionDialog.open) sessionDialog.closeDialog();
            else sessionDialog.openDialog("logout");
        }
    }
}
