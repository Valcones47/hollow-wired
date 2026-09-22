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

    // Setas das áreas de trabalho mudam no modo vertical (rice-workspace-layout).
    property bool wsVertical: false
    FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/workspace-layout"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: sheetWindow.wsVertical = text().trim() === "vertical"
        onLoadFailed: sheetWindow.wsVertical = false
    }

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
                        text: Theme.t("cheatsheet.title", "Atalhos do Teclado")
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
                                text: Theme.t("cheatsheet.search_placeholder", "Filtrar atalhos...")
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
                            category: Theme.t("cheatsheet.cat_nav", "Navegação & Janelas"),
                            items: [
                                { keys: ["Super"], desc: Theme.t("cheatsheet.desc_launcher", "Abrir / fechar Launcher") },
                                { keys: ["Super", "Q"], desc: Theme.t("cheatsheet.desc_terminal", "Terminal Kitty") },
                                { keys: ["Super", "E"], desc: Theme.t("cheatsheet.desc_dolphin", "Gerenciador Dolphin") },
                                { keys: ["Alt", "Tab"], desc: Theme.t("cheatsheet.desc_alttab", "Alternar janelas com miniaturas") },
                                { keys: ["Super", "Tab"], desc: Theme.t("cheatsheet.desc_overview", "Visão geral das áreas de trabalho") },
                                { keys: ["Super", sheetWindow.wsVertical ? "↑ / ↓" : "← / →"], desc: Theme.t("cheatsheet.desc_ws_switch", "Área de trabalho anterior / próxima") },
                                { keys: ["Super", "Shift", sheetWindow.wsVertical ? "↑ / ↓" : "← / →"], desc: Theme.t("cheatsheet.desc_ws_move", "Levar a janela para a área vizinha") },
                                { keys: ["Super", sheetWindow.wsVertical ? "← / →" : "↑ / ↓"], desc: Theme.t("cheatsheet.desc_focus", "Trocar o foco entre janelas") },
                                { keys: ["Super", "Esc"], desc: Theme.t("cheatsheet.desc_taskmgr", "Gerenciador de tarefas") },
                                { keys: ["Super", "'"], desc: Theme.t("cheatsheet.desc_dropterm", "Terminal drop-down suspenso") },
                                { keys: ["Super", "Shift", "X"], desc: Theme.t("cheatsheet.desc_kill", "Encerrar janela travada (Kill)") },
                                { keys: ["Super", "L"], desc: Theme.t("cheatsheet.desc_lock", "Bloquear sessão") },
                                { keys: ["Super", "M"], desc: Theme.t("cheatsheet.desc_exit", "Sair do Hyprland") }
                            ]
                        },
                        {
                            category: Theme.t("cheatsheet.cat_ricing", "Ricing & Customização"),
                            items: [
                                { keys: ["Super", "I"], desc: Theme.t("cheatsheet.desc_settings", "Painel de Configurações do Rice") },
                                { keys: ["Super", "F1"], desc: Theme.t("cheatsheet.desc_cheatsheet", "Cheatsheet de atalhos") },
                                { keys: ["Super", "W"], desc: Theme.t("cheatsheet.desc_widgets", "Editor de Widgets de Desktop") },
                                { keys: ["Super", "N"], desc: Theme.t("cheatsheet.desc_notif", "Painel de Notificações") },
                                { keys: ["Super", "Shift", "N"], desc: Theme.t("cheatsheet.desc_dnd", "Alternar Não Perturbe (DND)") },
                                { keys: ["Super", "S"], desc: Theme.t("cheatsheet.desc_wallpaper", "Seletor de Wallpapers Waywallen") },
                                { keys: ["Super", "B"], desc: Theme.t("cheatsheet.desc_blur", "Alternar Blur (Desfoque)") },
                                { keys: ["Super", "Shift", "B"], desc: Theme.t("cheatsheet.desc_perf", "Modo Ultra-Desempenho (0% iGPU)") },
                                { keys: ["Super", "Ctrl", "R"], desc: Theme.t("cheatsheet.desc_restart", "Reiniciar interface Quickshell") }
                            ]
                        },
                        {
                            category: Theme.t("cheatsheet.cat_media", "Captura & Multimídia"),
                            items: [
                                { keys: ["Print", "/", "Super", "Shift", "S"], desc: Theme.t("cheatsheet.desc_screenshot", "Captura de região (salva e copia)") },
                                { keys: ["Super", "Alt", "S"], desc: Theme.t("cheatsheet.desc_screenshot_edit", "Captura com editor de anotações (Swappy)") },
                                { keys: ["Super", "Shift", "R"], desc: Theme.t("cheatsheet.desc_record_region", "Gravar a tela inteira (de novo para parar)") },
                                { keys: ["Super", "Ctrl", "Shift", "R"], desc: Theme.t("cheatsheet.desc_record_screen", "Gravar tela inteira") },
                                { keys: ["Super", "Shift", "C"], desc: Theme.t("cheatsheet.desc_picker", "Conta-gotas de cores") },
                                { keys: ["Super", "V"], desc: Theme.t("cheatsheet.desc_clipboard", "Histórico da área de transferência") },
                                { keys: ["Super", "Ctrl", "V"], desc: Theme.t("cheatsheet.desc_clipboard_fav", "Favoritos da área de transferência") },
                                { keys: ["Num Lock"], desc: Theme.t("cheatsheet.desc_mic", "Mute / Unmute do microfone") },
                                { keys: ["Vol + / -"], desc: Theme.t("cheatsheet.desc_vol", "Ajustar volume no OSD flutuante") },
                                { keys: ["Brilho + / -"], desc: Theme.t("cheatsheet.desc_bright", "Ajustar brilho no OSD flutuante") }
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
