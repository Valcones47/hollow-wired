import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Menu do botão direito na área de trabalho — o primeiro lugar em que quem vem
// do Windows clica procurando "Personalizar" ou "Configurações de exibição".
//
// Aberto pelo DesktopWidgets (clique direito num ponto vazio do desktop).
// Fica no layer Overlay com uma camada transparente por baixo: clicar fora
// fecha, e o menu pode passar por cima de janelas quando abre perto delas.
PanelWindow {
    id: menu

    property bool open: false
    property real mx: 0
    property real my: 0
    property bool hasWaywallen: false

    visible: false
    color: "transparent"
    focusable: true
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell-desktop-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function popup(x, y) {
        menu.mx = x;
        menu.my = y;
        waywallenCheck.running = true;
        closeTimer.stop();
        menu.visible = true;
        menu.open = true;
        focusTimer.restart();
    }
    function close() {
        menu.open = false;
        closeTimer.restart();
    }
    function run(item) {
        if (!item.enabled) return;
        menu.close();
        item.action();
    }

    Timer { id: closeTimer; interval: 160; onTriggered: menu.visible = false }
    Timer { id: focusTimer; interval: 1; onTriggered: box.forceActiveFocus() }

    // O "Trocar wallpaper" só funciona com o Waywallen instalado; sem ele o
    // item fica cinza em vez de sumir, para a pessoa saber que existe.
    Process {
        id: waywallenCheck
        running: true
        command: ["flatpak", "info", "org.waywallen.waywallen"]
        onExited: (code, status) => menu.hasWaywallen = code === 0
    }

    readonly property var items: [
        { icon: Theme.icons.settings, label: Theme.t("dmenu.settings", "Configurações"), keys: "Super + I", enabled: true,
          action: () => Quickshell.execDetached(["quickshell", "ipc", "call", "visualconfig", "open"]) },
        { icon: Theme.icons.monitor, label: Theme.t("dmenu.display", "Tela"), keys: "", enabled: true,
          action: () => Quickshell.execDetached(["quickshell", "ipc", "call", "visualconfig", "tab", "3"]) },
        { icon: Theme.icons.console, label: Theme.t("dmenu.terminal", "Terminal"), keys: "Super + Q", enabled: true,
          action: () => Quickshell.execDetached(["kitty"]) },
        { icon: Theme.icons.palette, label: Theme.t("dmenu.wallpaper", "Trocar wallpaper"), keys: "Super + S",
          enabled: menu.hasWaywallen,
          hint: menu.hasWaywallen ? "" : Theme.t("dmenu.wallpaper_missing", "Waywallen não instalado"),
          action: () => Quickshell.execDetached(["waywallen-switcher"]) },
        { icon: Theme.icons.dashboard, label: Theme.t("dmenu.widgets", "Editar widgets"), keys: "Super + W", enabled: true,
          action: () => Quickshell.execDetached(["quickshell", "ipc", "call", "desktopwidgets", "toggleEdit"]) },
        { separator: true },
        { icon: Theme.icons.disk, label: Theme.t("dmenu.files", "Arquivos"), keys: "Super + E", enabled: true,
          action: () => Quickshell.execDetached(["dolphin"]) },
        { icon: Theme.icons.workspaces, label: Theme.t("dmenu.overview", "Visão geral"), keys: "Super + Tab", enabled: true,
          action: () => Quickshell.execDetached(["quickshell", "ipc", "call", "overview", "open"]) },
        { icon: Theme.icons.magnify, label: Theme.t("dmenu.shortcuts", "Atalhos do teclado"), keys: "Super + F1", enabled: true,
          action: () => Quickshell.execDetached(["quickshell", "ipc", "call", "cheatsheet", "toggle"]) }
    ]

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: menu.close()
    }

    Rectangle {
        id: box
        focus: true
        // Abre para o lado que cabe na tela.
        x: Math.min(menu.mx, menu.width - width - 8)
        y: Math.min(menu.my, menu.height - height - 8)
        width: 264
        height: col.implicitHeight + 12
        radius: 16
        color: Theme.mix(Theme.background, "#000000", 0.15)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.35)
        transformOrigin: menu.mx > menu.width - width - 8 ? Item.TopRight : Item.TopLeft
        opacity: menu.open ? 1 : 0
        scale: menu.open ? 1 : 0.9
        Behavior on opacity { NumberAnimation { duration: 130 } }
        Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

        Keys.onEscapePressed: menu.close()

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Column {
            id: col
            x: 6
            y: 6
            width: parent.width - 12

            Repeater {
                model: menu.items
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: col.width
                    height: modelData.separator ? 11 : 40

                    Rectangle {
                        visible: !!row.modelData.separator
                        anchors.centerIn: parent
                        width: parent.width - 16
                        height: 1
                        color: Theme.withAlpha(Theme.outline, 0.3)
                    }

                    Rectangle {
                        visible: !row.modelData.separator
                        anchors.fill: parent
                        radius: 10
                        color: rowArea.containsMouse && row.modelData.enabled
                            ? Theme.withAlpha(Theme.primary, 0.18) : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12
                            opacity: row.modelData.enabled ? 1 : 0.4

                            Text {
                                text: row.modelData.icon || ""
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 16
                                color: rowArea.containsMouse && row.modelData.enabled ? Theme.primary : Theme.textColor
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.label || ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    color: Theme.textColor
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: !!row.modelData.hint
                                    text: row.modelData.hint || ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.subtext
                                }
                            }
                            Text {
                                visible: !!row.modelData.keys
                                text: row.modelData.keys || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.subtext
                            }
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: row.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: menu.run(row.modelData)
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "desktopmenu"
        function close(): void { menu.close(); }
        function popupAt(x: string, y: string): void { menu.popup(parseFloat(x) || 0, parseFloat(y) || 0); }
    }
}
