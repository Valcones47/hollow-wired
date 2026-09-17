import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

ShellRoot {
    // Pollers de CPU/GPU/RAM/disco só rodam com o hub aberto ou quando o workspace ativo possui widget de stats.
    Binding {
        target: SysStats
        property: "active"
        value: hub.visible || dw.hasStatsWidget
    }

    // ---------- fechar o hub clicando fora ----------
    // Camada transparente cobrindo a tela inteira no layer "Top" (abaixo do
    // hub, que fica em "Overlay"). Só existe enquanto o hub está aberto.
    // A sidebar não usa isso: ela fecha sozinha quando o mouse sai dela.
    PanelWindow {
        id: clickCatcher
        visible: hub.open
        color: "transparent"
        focusable: false

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "quickshell-hub-catcher"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        MouseArea {
            anchors.fill: parent
            onClicked: hub.open = false
        }
    }

    DesktopWidgets { id: dw }
    Frame {}

    TopBar {
        recording: sidebar.recording
        onClockClicked: hub.open = !hub.open
        onNotifClicked: {
            card.currentTab = 5;
            hub.open = true;
        }
        onVisualConfigClicked: visualConfig.open = !visualConfig.open
        onStopRecording: Quickshell.execDetached(["rice-record"])
    }

    EnergySidebar {
        id: sidebar
        onAvatarClicked: {
            sidebar.open = false;
            sysinfo.open = true;
        }
    }

    SystemInfo {
        id: sysinfo
    }

    VisualConfigPanel {
        id: visualConfig
    }

    Launcher {
        id: launcher
    }

    Dock {
        suppressed: launcher.open
    }

    AltTab {}
    OSD {}
    Cheatsheet {}
    Clipboard {}

    PanelWindow {
        id: hub
        visible: false
        focusable: true
        color: "transparent"

        // Colado logo abaixo da waybar, sem vão: o card tem o mesmo fundo da
        // barra (background alpha 0.85 + blur) e cantos invertidos em cima,
        // então parece que desce DE DENTRO da barra, como na Caelestia.
        anchors.top: true
        margins.top: Theme.waybarHeight

        implicitWidth: Theme.panelWidth + Theme.radius * 2
        implicitHeight: Theme.panelHeight

        WlrLayershell.namespace: "quickshell-hub"
        WlrLayershell.layer: WlrLayer.Overlay
        // Sem isso o Hyprland encolhe as janelas tiled pra abrir espaço — o
        // painel deve só SOBREPOR.
        exclusionMode: ExclusionMode.Ignore

        // `open` é o estado lógico; `visible` só desliga depois que a
        // animação de recolher termina.
        property bool open: false
        onOpenChanged: {
            if (open) {
                closeTimer.stop();
                hub.visible = true;
            } else {
                closeTimer.restart();
            }
        }
        Timer {
            id: closeTimer
            interval: 260
            onTriggered: hub.visible = false
        }

        Item {
            id: slide
            width: parent.width
            height: parent.height
            y: hub.open ? 0 : -height
            opacity: hub.open ? 1 : 0
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200 } }

            // ---------- cantos invertidos (junção com a waybar) ----------
            Canvas {
                id: cornerLeft
                x: 0
                width: Theme.radius
                height: Theme.radius
                onPaint: {
                    const ctx = getContext("2d");
                    const r = width;
                    ctx.reset();
                    ctx.fillStyle = Theme.surface;
                    ctx.beginPath();
                    ctx.moveTo(0, 0);
                    ctx.lineTo(r, 0);
                    ctx.lineTo(r, r);
                    ctx.arc(0, r, r, 0, -Math.PI / 2, true);
                    ctx.closePath();
                    ctx.fill();
                }
            }
            Canvas {
                id: cornerRight
                x: parent.width - width
                width: Theme.radius
                height: Theme.radius
                onPaint: {
                    const ctx = getContext("2d");
                    const r = width;
                    ctx.reset();
                    ctx.fillStyle = Theme.surface;
                    ctx.beginPath();
                    ctx.moveTo(r, 0);
                    ctx.lineTo(0, 0);
                    ctx.lineTo(0, r);
                    ctx.arc(r, r, r, Math.PI, 3 * Math.PI / 2, false);
                    ctx.closePath();
                    ctx.fill();
                }
            }
            Connections {
                target: Theme
                function onBackgroundChanged() {
                    cornerLeft.requestPaint();
                    cornerRight.requestPaint();
                }
            }

            Rectangle {
                id: card
                x: Theme.radius
                width: Theme.panelWidth
                height: parent.height
                color: Theme.surface
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: Theme.radius
                bottomRightRadius: Theme.radius

                property int currentTab: 0
                readonly property var tabs: [
                    { icon: Theme.icons.dashboard, label: "Dashboard" },
                    { icon: Theme.icons.media, label: "Mídia" },
                    { icon: Theme.icons.performance, label: "Performance" },
                    { icon: Theme.icons.workspaces, label: "Workspaces" },
                    { icon: Theme.icons.tune, label: "Aparência" },
                    { icon: Theme.icons.bell, label: "Notificações" },
                    { icon: Theme.icons.record, label: "Gravação" }
                ]

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.gap * 2
                    anchors.rightMargin: Theme.gap * 2
                    anchors.bottomMargin: Theme.gap * 2
                    anchors.topMargin: Theme.gap
                    spacing: Theme.gap + 4

                    // ---------- abas: ícone em cima, rótulo embaixo, indicador deslizante ----------
                    Item {
                        id: tabBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: 54

                        Row {
                            id: tabRow
                            anchors.fill: parent
                            anchors.bottomMargin: 1

                            Repeater {
                                id: tabRepeater
                                model: card.tabs
                                delegate: Item {
                                    id: tabDelegate
                                    required property var modelData
                                    required property int index
                                    readonly property bool active: card.currentTab === index
                                    readonly property real labelWidth: tabLabel.implicitWidth

                                    width: tabRow.width / card.tabs.length
                                    height: tabRow.height

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        anchors.bottomMargin: 4
                                        radius: Theme.tileRadius
                                        color: tabArea.containsMouse && !tabDelegate.active
                                            ? Theme.withAlpha(Theme.textColor, 0.06) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -2
                                        spacing: 1
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: tabDelegate.modelData.icon
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 20
                                            color: tabDelegate.active ? Theme.primary : Theme.subtext
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }
                                        Text {
                                            id: tabLabel
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: tabDelegate.modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: tabDelegate.active ? Font.DemiBold : Font.Normal
                                            color: tabDelegate.active ? Theme.primary : Theme.subtext
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }
                                    }

                                    MouseArea {
                                        id: tabArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: card.currentTab = tabDelegate.index
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: Theme.withAlpha(Theme.outline, 0.35)
                        }

                        Rectangle {
                            id: indicator
                            readonly property real tabWidth: tabBar.width / card.tabs.length
                            readonly property Item activeTab: tabRepeater.itemAt(card.currentTab)
                            width: activeTab ? activeTab.labelWidth + 12 : 60
                            height: 3
                            radius: 1.5
                            anchors.bottom: parent.bottom
                            x: tabWidth * card.currentTab + (tabWidth - width) / 2
                            color: Theme.primary
                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Dashboard {
                            anchors.fill: parent
                            opacity: card.currentTab === 0 ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }
                        Media {
                            anchors.fill: parent
                            opacity: card.currentTab === 1 ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }
                        Monitoring {
                            anchors.fill: parent
                            opacity: card.currentTab === 2 ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }
                        Workspaces {
                            anchors.fill: parent
                            opacity: card.currentTab === 3 ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }
                        Appearance {
                            anchors.fill: parent
                            opacity: card.currentTab === 4 ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }
                        Notifications {
                            anchors.fill: parent
                            opacity: card.currentTab === 5 && hub.visible ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }
                        Recording {
                            anchors.fill: parent
                            opacity: card.currentTab === 6 && hub.visible ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }
                    }
                }
            }
        }

        // IPC: `qs ipc call hub toggle|show|hide|tab N` — toggle é usado pelo
        // on-click do módulo clock na waybar (ver config.jsonc).
        IpcHandler {
            target: "hub"

            function toggle(): void { hub.open = !hub.open; }
            function show(): void { hub.open = true; }
            function hide(): void { hub.open = false; }
            function tab(index: string): void { card.currentTab = parseInt(index) || 0; }
        }

        IpcHandler {
            target: "notif"

            function toggleDnd(): void { NotifService.toggleDnd(); }
            function refresh(): void { NotifService.refresh(); }
            function clear(): void { NotifService.setCleared(NotifService.maxId); }
            function open(): void {
                card.currentTab = 5;
                hub.open = true;
            }
        }
    }
}
