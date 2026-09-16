import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Modal de Cheatsheet de Atalhos (Super + F1) estilo Caelestia.
// Exibe os principais atalhos organizados por categoria com barra de pesquisa instantânea.
PanelWindow {
    id: sheetWindow

    property bool open: false

    visible: true
    color: "transparent"
    focusable: true

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
        width: sheetWindow.open ? sheetWindow.width : 0
        height: sheetWindow.open ? sheetWindow.height : 0
    }

    WlrLayershell.namespace: "quickshell-cheatsheet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: sheetWindow.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (open) {
            searchField.text = "";
            searchField.forceActiveFocus();
        }
    }

    // Fundo escurecido clicável para fechar
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: sheetWindow.open ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: sheetWindow.open = false
        }
    }

    // Janela Central
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 820
        height: 540
        radius: Theme.radius
        color: Theme.surface
        border.color: Theme.withAlpha(Theme.outline, 0.35)
        border.width: 1

        scale: sheetWindow.open ? 1 : 0.94
        opacity: sheetWindow.open ? 1 : 0
        visible: opacity > 0

        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Impede cliques no card de propagarem para o fundo
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            // Header: Título + Campo de Busca + Botão Fechar
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Row {
                    spacing: 10
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{F018D}"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 22
                        color: Theme.primary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Atalhos do Teclado"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        color: Theme.textColor
                    }
                }

                Item { Layout.fillWidth: true }

                // Campo de Busca
                Rectangle {
                    Layout.preferredWidth: 260
                    Layout.preferredHeight: 36
                    radius: 18
                    color: Theme.tile
                    border.color: searchField.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Text {
                            text: Theme.icons.magnify
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 14
                            color: Theme.subtext
                        }

                        TextInput {
                            id: searchField
                            Layout.fillWidth: true
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.textColor
                            clip: true

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    sheetWindow.open = false;
                                    event.accepted = true;
                                }
                            }

                            Text {
                                text: "Filtrar atalhos..."
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: Theme.withAlpha(Theme.subtext, 0.6)
                                visible: !searchField.text && !searchField.activeFocus
                            }
                        }
                    }
                }

                // Botão Fechar (Esc)
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: closeArea.containsMouse ? Theme.tileHigh : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\u{F0156}"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 16
                        color: closeArea.containsMouse ? Theme.primary : Theme.subtext
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sheetWindow.open = false
                    }
                }
            }

            // Separador
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.withAlpha(Theme.outline, 0.2)
            }

            // Lista de Atalhos com Categorias
            ScrollView {
                id: scrollView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ScrollBar.vertical: ScrollBar {
                    active: true
                    width: 4
                }

                Flow {
                    width: card.width - 48
                    spacing: 16

                    readonly property var allCategories: [
                        {
                            category: "Navegação & Janelas",
                            items: [
                                { keys: ["Super"], desc: "Abrir / fechar Launcher" },
                                { keys: ["Super", "Q"], desc: "Terminal Kitty" },
                                { keys: ["Super", "E"], desc: "Gerenciador Dolphin" },
                                { keys: ["Alt", "Tab"], desc: "Alternar janelas com miniaturas" },
                                { keys: ["Super", "'"], desc: "Terminal drop-down suspenso" },
                                { keys: ["Super", "Shift", "X"], desc: "Encerrar janela travada (Kill)" },
                                { keys: ["Super", "L"], desc: "Bloquear sessão (hyprlock)" },
                                { keys: ["Super", "M"], desc: "Sair do Hyprland" }
                            ]
                        },
                        {
                            category: "Ricing & Customização",
                            items: [
                                { keys: ["Super", "F1"], desc: "Cheatsheet de atalhos" },
                                { keys: ["Super", "W"], desc: "Editor de Widgets de Desktop" },
                                { keys: ["Super", "N"], desc: "Painel de Notificações" },
                                { keys: ["Super", "Shift", "N"], desc: "Alternar Não Perturbe (DND)" },
                                { keys: ["Super", "S"], desc: "Seletor de Wallpapers Waywallen" },
                                { keys: ["Super", "B"], desc: "Alternar Blur (Desfoque)" },
                                { keys: ["Super", "Shift", "B"], desc: "Modo Ultra-Desempenho (0% iGPU)" },
                                { keys: ["Super", "Ctrl", "R"], desc: "Reiniciar interface Quickshell" }
                            ]
                        },
                        {
                            category: "Captura & Multimídia",
                            items: [
                                { keys: ["Super", "Shift", "S"], desc: "Screenshot da tela com anotação" },
                                { keys: ["Super", "Shift", "R"], desc: "Gravar região da tela" },
                                { keys: ["Super", "Ctrl", "Shift", "R"], desc: "Gravar tela inteira" },
                                { keys: ["Super", "Shift", "C"], desc: "Conta-gotas de cores" },
                                { keys: ["Super", "V"], desc: "Histórico da área de transferência" },
                                { keys: ["Num Lock"], desc: "Mute / Unmute do microfone" },
                                { keys: ["Vol + / -"], desc: "Ajustar volume no OSD flutuante" },
                                { keys: ["Brilho + / -"], desc: "Ajustar brilho no OSD flutuante" }
                            ]
                        }
                    ]

                    Repeater {
                        model: {
                            const query = searchField.text.trim().toLowerCase();
                            if (!query) return parent.allCategories;

                            return parent.allCategories.map(cat => {
                                const filtered = cat.items.filter(it =>
                                    it.desc.toLowerCase().includes(query) ||
                                    it.keys.some(k => k.toLowerCase().includes(query))
                                );
                                return { category: cat.category, items: filtered };
                            }).filter(cat => cat.items.length > 0);
                        }

                        delegate: Rectangle {
                            id: catBox
                            required property var modelData
                            width: (card.width - 48 - 16) / 2
                            implicitHeight: catCol.implicitHeight + 24
                            radius: Theme.radius - 4
                            color: Theme.tile
                            border.color: Theme.withAlpha(Theme.outline, 0.15)
                            border.width: 1

                            ColumnLayout {
                                id: catCol
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                Text {
                                    text: catBox.modelData.category
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: Theme.primary
                                }

                                Repeater {
                                    model: catBox.modelData.items
                                    delegate: RowLayout {
                                        id: itemRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 8

                                        // Teclas
                                        Row {
                                            spacing: 4
                                            Layout.alignment: Qt.AlignVCenter

                                            Repeater {
                                                model: itemRow.modelData.keys
                                                delegate: Rectangle {
                                                    required property string modelData
                                                    implicitWidth: keyText.implicitWidth + 12
                                                    implicitHeight: 22
                                                    radius: 5
                                                    color: Theme.surface
                                                    border.color: Theme.withAlpha(Theme.outline, 0.3)
                                                    border.width: 1

                                                    Text {
                                                        id: keyText
                                                        anchors.centerIn: parent
                                                        text: parent.modelData
                                                        font.family: Theme.monoFamily
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                        color: Theme.textColor
                                                    }
                                                }
                                            }
                                        }

                                        // Descrição
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            text: itemRow.modelData.desc
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            color: Theme.subtext
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            sheetWindow.open = !sheetWindow.open;
        }

        function show(): void {
            sheetWindow.open = true;
        }

        function hide(): void {
            sheetWindow.open = false;
        }
    }
}
