import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Tela de boas-vindas do primeiro login.
//
// Pensada para quem está vindo do Windows e abre o computador pela primeira vez
// sem barra de tarefas, sem botão Iniciar e sem ícones na área de trabalho: em
// vez de descobrir sozinho, a pessoa vê de cara o que substitui cada coisa.
//
// Aparece uma única vez (marca ~/.config/quickshell/.welcome-done) e pode ser
// reaberta a qualquer momento com `qs ipc call welcome open` ou pelo Painel Rice.
PanelWindow {
    id: welcomeWindow

    property bool open: false
    property bool checked: false

    // Cada passo é um "e no Windows era assim" → "aqui é assim".
    readonly property var steps: [
        {
            icon: Theme.icons.arch,
            keys: ["Super"],
            title: Theme.t("welcome.step_launcher_title", "A tecla Windows abre o menu de aplicativos"),
            desc: Theme.t("welcome.step_launcher_desc", "É o seu Menu Iniciar. Aperte e comece a digitar o nome do programa.")
        },
        {
            icon: Theme.icons.console,
            keys: ["Super", "Q"],
            title: Theme.t("welcome.step_terminal_title", "Terminal"),
            desc: Theme.t("welcome.step_terminal_desc", "Abre o terminal Kitty. Super + ' abre um terminal suspenso por cima de tudo.")
        },
        {
            icon: Theme.icons.disk,
            keys: ["Super", "E"],
            title: Theme.t("welcome.step_files_title", "Gerenciador de arquivos"),
            desc: Theme.t("welcome.step_files_desc", "O mesmo Super + E do Windows abre a pasta pessoal no Dolphin.")
        },
        {
            icon: Theme.icons.close,
            keys: ["Super", "C"],
            title: Theme.t("welcome.step_close_title", "Fechar a janela atual"),
            desc: Theme.t("welcome.step_close_desc", "Alt + F4 também funciona. As janelas se organizam sozinhas na tela, sem precisar arrastar.")
        },
        {
            icon: Theme.icons.workspaces,
            keys: ["Super", "1..9"],
            title: Theme.t("welcome.step_workspaces_title", "Áreas de trabalho"),
            desc: Theme.t("welcome.step_workspaces_desc", "Cada número é uma área separada. A roda do mouse com Super pressionado também troca.")
        },
        {
            icon: Theme.icons.history,
            keys: ["Super", "V"],
            title: Theme.t("welcome.step_clipboard_title", "Tudo que você copiou"),
            desc: Theme.t("welcome.step_clipboard_desc", "Histórico da área de transferência, com busca e favoritos (Super + Ctrl + V).")
        },
        {
            icon: Theme.icons.camera,
            keys: ["Print"],
            title: Theme.t("welcome.step_screenshot_title", "Captura de tela"),
            desc: Theme.t("welcome.step_screenshot_desc", "Selecione uma área — ou aperte Esc para capturar a tela inteira. Sempre salva e copia.")
        },
        {
            icon: Theme.icons.workspaces,
            keys: ["Super", "Tab"],
            title: Theme.t("welcome.step_overview_title", "Ver tudo que está aberto"),
            desc: Theme.t("welcome.step_overview_desc", "Mostra as áreas de trabalho num carrossel, com os apps de cada uma. Clique numa janela para ir até ela.")
        },
        {
            icon: Theme.icons.performance,
            keys: ["Super", "Esc"],
            title: Theme.t("welcome.step_taskmgr_title", "Gerenciador de tarefas"),
            desc: Theme.t("welcome.step_taskmgr_desc", "Algum programa travou? Abre o monitor do sistema para fechá-lo. Ctrl + Shift + Esc também funciona.")
        },
        {
            icon: Theme.icons.cursor,
            keys: ["Botão direito"],
            title: Theme.t("welcome.step_rightclick_title", "Clique direito na área de trabalho"),
            desc: Theme.t("welcome.step_rightclick_desc", "Atalhos para configurações, tela, terminal, papel de parede e widgets.")
        },
        {
            icon: Theme.icons.power,
            keys: ["Ctrl", "Alt", "Del"],
            title: Theme.t("welcome.step_power_title", "Desligar, reiniciar, suspender"),
            desc: Theme.t("welcome.step_power_desc", "Abre a barra lateral de energia. Encostar o mouse na borda direita faz o mesmo.")
        }
    ]

    property bool tipsOn: true
    Process {
        id: tipsStatus
        command: ["rice-tips", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { welcomeWindow.tipsOn = JSON.parse(text).enabled !== false; } catch (e) {}
            }
        }
    }

    function markDone() {
        doneFile.setText("1\n");
    }

    FileView {
        id: doneFile
        path: Quickshell.env("HOME") + "/.config/quickshell/.welcome-done"
        onLoaded: welcomeWindow.checked = true
        onLoadFailed: {
            // Arquivo não existe = primeiro login desta instalação.
            welcomeWindow.checked = true;
            welcomeWindow.open = true;
        }
    }

    visible: true
    color: "transparent"
    focusable: true

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
        width: welcomeWindow.open ? welcomeWindow.width : 0
        height: welcomeWindow.open ? welcomeWindow.height : 0
    }

    WlrLayershell.namespace: "quickshell-welcome"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: welcomeWindow.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (open) tipsStatus.running = true;
        if (!open) welcomeWindow.markDone();
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)
        opacity: welcomeWindow.open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220 } }

        MouseArea {
            anchors.fill: parent
            onClicked: welcomeWindow.open = false
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 780
        height: 680
        radius: Theme.radius
        color: Theme.surface
        border.color: Theme.withAlpha(Theme.outline, 0.35)
        border.width: 1

        scale: welcomeWindow.open ? 1 : 0.94
        opacity: welcomeWindow.open ? 1 : 0
        visible: opacity > 0

        Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 26
            spacing: 16

            // ------------------------------------------------- cabeçalho
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46
                    radius: 23
                    color: Theme.withAlpha(Theme.primary, 0.18)

                    Text {
                        anchors.centerIn: parent
                        text: Theme.icons.arch
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 24
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: Theme.t("welcome.title", "Bem-vindo ao seu novo desktop")
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        color: Theme.textColor
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Theme.t("welcome.subtitle", "Alguns atalhos e você já está em casa. Dá pra rever tudo isso quando quiser com Super + F1.")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.subtext
                        wrapMode: Text.WordWrap
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: closeArea.containsMouse ? Theme.tileHigh : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: Theme.icons.close
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 15
                        color: closeArea.containsMouse ? Theme.primary : Theme.subtext
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: welcomeWindow.open = false
                    }
                }
            }

            // ------------------------------------------------- passos
            ListView {
                id: stepList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: welcomeWindow.steps
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    id: stepScroll
                    policy: stepList.contentHeight > stepList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                    width: 8
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: stepScroll.pressed ? Theme.primary : Theme.withAlpha(Theme.outline, 0.55)
                    }
                }

                delegate: Rectangle {
                    id: stepCard
                    required property var modelData
                    required property int index

                    width: stepList.width - (stepScroll.visible ? 16 : 4)
                    height: 74
                    radius: 12
                    color: Theme.tile
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outline, 0.18)

                    // Entrada escalonada: os cards vão aparecendo um a um, de cima
                    // pra baixo, em vez de a lista inteira piscar de uma vez.
                    opacity: 0
                    x: 18
                    SequentialAnimation {
                        running: welcomeWindow.open
                        PauseAnimation { duration: 60 + stepCard.index * 55 }
                        ParallelAnimation {
                            NumberAnimation { target: stepCard; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                            NumberAnimation { target: stepCard; property: "x"; to: 0; duration: 320; easing.type: Easing.OutCubic }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 14

                        Text {
                            text: modelData.icon
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 22
                            color: Theme.primary
                            Layout.preferredWidth: 26
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                text: modelData.title
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: Theme.textColor
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.desc
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.subtext
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Teclas do atalho
                        Row {
                            spacing: 4
                            Layout.alignment: Qt.AlignVCenter

                            Repeater {
                                model: modelData.keys
                                delegate: Rectangle {
                                    required property var modelData
                                    height: 24
                                    width: keyLabel.implicitWidth + 16
                                    radius: 6
                                    color: Theme.withAlpha(Theme.primary, 0.16)
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.primary, 0.35)

                                    Text {
                                        id: keyLabel
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.family: Theme.monoFamily
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: Theme.primary
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------- dicas
            // Liga/desliga as dicas em notificação (rice-tips). Mesma chave do
            // painel Rice > Guia de Atalhos.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                radius: 14
                color: Theme.tile
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.22)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    Text {
                        text: Theme.icons.info
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 18
                        color: Theme.primary
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: Theme.t("welcome.tips_title", "Dicas enquanto você usa")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Theme.textColor
                        }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Theme.t("welcome.tips_desc", "De vez em quando uma notificação ensina um atalho. Cada dica aparece no máximo 2 vezes.")
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.subtext
                        }
                    }
                    Rectangle {
                        implicitWidth: 42
                        implicitHeight: 22
                        radius: 11
                        color: welcomeWindow.tipsOn ? Theme.primary : Theme.tileHigh
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Rectangle {
                            width: 16; height: 16; radius: 8
                            anchors.verticalCenter: parent.verticalCenter
                            x: welcomeWindow.tipsOn ? parent.width - width - 3 : 3
                            color: Theme.textColor
                            Behavior on x { NumberAnimation { duration: 140 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                welcomeWindow.tipsOn = !welcomeWindow.tipsOn;
                                Quickshell.execDetached(["rice-tips", welcomeWindow.tipsOn ? "on" : "off"]);
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------- ações
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: [
                        { label: Theme.t("welcome.btn_shortcuts", "Ver todos os atalhos"), icon: Theme.icons.info, action: "cheatsheet" },
                        { label: Theme.t("welcome.btn_settings", "Configurações"), icon: Theme.icons.tune, action: "settings" },
                        { label: Theme.t("welcome.btn_wallpaper", "Papel de parede"), icon: Theme.icons.palette, action: "wallpaper" }
                    ]

                    delegate: Rectangle {
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 19
                        color: actArea.containsMouse ? Theme.tileHigh : Theme.tile
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.outline, 0.22)

                        Behavior on color { ColorAnimation { duration: 130 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.icon
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 14
                                color: Theme.primary
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.textColor
                            }
                        }

                        MouseArea {
                            id: actArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                welcomeWindow.open = false;
                                if (modelData.action === "cheatsheet")
                                    Quickshell.execDetached(["quickshell", "ipc", "call", "cheatsheet", "toggle"]);
                                else if (modelData.action === "settings")
                                    Quickshell.execDetached(["quickshell", "ipc", "call", "visualconfig", "toggle"]);
                                else if (modelData.action === "wallpaper")
                                    Quickshell.execDetached(["sh", "-c", "if flatpak info org.waywallen.waywallen >/dev/null 2>&1; then exec waywallen-switcher; else exec rice-wallpaper-set; fi"]);
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 150
                    Layout.preferredHeight: 38
                    radius: 19
                    color: startArea.containsMouse ? Theme.primary : Theme.withAlpha(Theme.primary, 0.85)

                    Behavior on color { ColorAnimation { duration: 130 } }

                    Text {
                        anchors.centerIn: parent
                        text: Theme.t("welcome.btn_start", "Começar a usar")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Theme.background
                    }

                    MouseArea {
                        id: startArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: welcomeWindow.open = false
                    }
                }
            }
        }

        Keys.onEscapePressed: welcomeWindow.open = false
    }

    IpcHandler {
        target: "welcome"

        function open(): void { welcomeWindow.open = true; }
        function hide(): void { welcomeWindow.open = false; }
        function toggle(): void { welcomeWindow.open = !welcomeWindow.open; }
        // Faz a tela voltar a aparecer no próximo login (útil pra testar).
        function reset(): void { doneFile.setText(""); welcomeWindow.open = true; }
    }
}
