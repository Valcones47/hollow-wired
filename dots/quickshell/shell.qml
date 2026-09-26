import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "."

ShellRoot {
    id: shellRoot
    readonly property bool hasFullscreen: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen) || false
    readonly property bool launcherOpen: launcher.open
    // Pollers de CPU/GPU/RAM/disco só rodam com o hub aberto ou quando o workspace ativo possui widget de stats.
    Binding {
        target: SysStats
        property: "active"
        value: hub.visible || dw.hasStatsWidget || lockScreen.active
    }

    // Tela de bloqueio (Super + L, inatividade, "Ir para a tela de login").
    LockScreen { id: lockScreen }

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

    DesktopWidgets {
        id: dw
        onDesktopRightClicked: (x, y) => desktopMenu.popup(x, y)
    }
    DesktopMenu { id: desktopMenu }
    Frame { id: frameScope }
    WallpaperFade { id: wallFade }

    // Área especial (Super + A) reaparecendo sozinha ao clicar fora de um
    // painel. Quando um painel do shell fecha, o Hyprland devolve o foco à
    // última janela usada; se ela é a da área especial (escondida com
    // Super + A, sobretudo com o workspace atual vazio), focar nela reabre a
    // área especial — e a pessoa "é mandada" para o app. Se a área especial
    // abrir logo depois de uma camada do shell fechar, sem ter sido aberta
    // antes, ela é escondida de novo. Abrir pelo atalho continua normal: aí
    // não há camada fechando no mesmo instante.
    Item {
        id: specialGuard
        property real layerClosedAt: 0
        // Área especial aberta em cada monitor. Começa lida do Hyprland: sem
        // isso o shell nasceria achando que tudo está fechado e esconderia uma
        // área especial que a pessoa tinha aberto de propósito.
        property var openSpecial: ({})

        Process {
            running: true
            command: ["hyprctl", "monitors", "-j"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const m = {};
                        for (const mon of JSON.parse(text))
                            m[mon.name] = (mon.specialWorkspace && mon.specialWorkspace.name) || "";
                        specialGuard.openSpecial = m;
                    } catch (e) {}
                }
            }
        }

        Connections {
            target: Hyprland
            function onRawEvent(event) {
                const n = event.name;
                const data = String(event.data);
                if (n === "closelayer") {
                    if (data.startsWith("quickshell") || data.startsWith("hollow"))
                        specialGuard.layerClosedAt = Date.now();
                } else if (n === "activespecial") {
                    const parts = data.split(",");
                    const name = parts[0];
                    const mon = parts[1] || "";
                    const wasOpen = specialGuard.openSpecial[mon] || "";
                    const m = Object.assign({}, specialGuard.openSpecial);
                    m[mon] = name;
                    if (name !== "" && wasOpen === "" && Date.now() - specialGuard.layerClosedAt < 500) {
                        Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + name.replace(/^special:/, "") + '")');
                        m[mon] = "";
                    }
                    specialGuard.openSpecial = m;
                }
            }
        }
    }

    // Link aberto no navegador que está em outra área de trabalho: o
    // Hyprland só marca a janela como "urgente" (não pula para ela), então o
    // rice-browser-notice avisa com uma notificação que leva até a aba. O
    // evento chega duas vezes por link (uma por troca de título); o intervalo
    // por janela evita notificação dobrada.
    Item {
        id: browserNotice
        property var lastAt: ({})
        Connections {
            target: Hyprland
            function onRawEvent(event) {
                if (event.name !== "urgent") return;
                const addr = String(event.data);
                const now = Date.now();
                if (now - (browserNotice.lastAt[addr] || 0) < 4000) return;
                const m = Object.assign({}, browserNotice.lastAt);
                m[addr] = now;
                browserNotice.lastAt = m;
                Quickshell.execDetached(["rice-browser-notice", addr]);
            }
        }
    }

    // Dicas de uso (rice-tips): uma de cada vez, a primeira 4 minutos depois
    // de entrar e depois a cada 20. Cada dica aparece no máximo duas vezes e o
    // script não faz nada quando elas estão desligadas ou já se esgotaram.
    // Com jogo ou vídeo em tela cheia, espera a próxima rodada.
    Timer {
        interval: 4 * 60 * 1000
        running: true
        repeat: true
        onTriggered: {
            interval = 20 * 60 * 1000;
            if (!shellRoot.hasFullscreen)
                Quickshell.execDetached(["rice-tips", "random"]);
        }
    }

    // Luz noturna agendada. O `rice-nightlight auto` decide sozinho se o filtro
    // deve estar ligado no horário atual e não faz nada quando o agendamento
    // está desligado — por isso dá para chamar sempre, sem daemon novo nem
    // serviço que o usuário precise habilitar.
    Timer {
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: Quickshell.execDetached(["rice-nightlight", "auto"])
    }

    // ---------- modo de captura limpa ----------
    // `qs ipc call capture hide` esconde tudo que o Quickshell desenha por cima
    // do wallpaper (barra, moldura, dock e widgets) para que o
    // rice-sddm-sync-wallpaper capture o papel de parede puro, sem nenhum
    // pedaço da interface nem conteúdo de janelas na foto da tela de login.
    // `qs ipc call capture restore` devolve tudo ao estado anterior.
    property bool captureMode: false

    Binding { target: topbar; property: "visible"; value: false; when: shellRoot.captureMode; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: dock;   property: "visible"; value: false; when: shellRoot.captureMode; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: dw;     property: "visible"; value: false; when: shellRoot.captureMode; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: frameScope; property: "hidden"; value: true; when: shellRoot.captureMode; restoreMode: Binding.RestoreBindingOrValue }

    IpcHandler {
        target: "capture"

        // "show" não pode ser usado como nome aqui: `qs ipc call <alvo> show`
        // é engolido pelo próprio CLI do Quickshell e só lista as funções.
        function hide(): void { shellRoot.captureMode = true; }
        function restore(): void { shellRoot.captureMode = false; }
        function state(): string { return shellRoot.captureMode ? "hidden" : "shown"; }
    }

    Launcher {
        id: launcher
        // Sem isso o launcher engole os cliques destinados à dock e à sidebar.
        dockShown: dock.shown
        sidebarOpen: sidebar.open
        barPopupOpen: topbar.pop !== ""
    }

    TopBar {
        id: topbar
        energy: sidebar
        launcherOpen: shellRoot.launcherOpen
        recording: sidebar.recording
        onClockClicked: hub.open = !hub.open
        onVisualConfigClicked: visualConfig.open = !visualConfig.open
        onControlClicked: controlCenter.clickToggle()
        onControlHovered: on => on ? controlCenter.hoverEnter() : controlCenter.hoverLeave()
        onStopRecording: Quickshell.execDetached(["rice-record", "stop"])
    }

    // Alternativa vertical à barra de cima. As duas nunca aparecem juntas: o
    // arranjo escolhe uma (ShellLayout.barVertical).
    VerticalBar {
        id: vbar
        energy: sidebar
        launcherOpen: shellRoot.launcherOpen
        onClockClicked: hub.open = !hub.open
        onVisualConfigClicked: visualConfig.open = !visualConfig.open
        onControlClicked: controlCenter.clickToggle()
        onControlHovered: on => on ? controlCenter.hoverEnter() : controlCenter.hoverLeave()
    }

    EnergySidebar {
        id: sidebar
        launcherOpen: shellRoot.launcherOpen
        onAvatarClicked: {
            sidebar.open = false;
            sysinfo.open = true;
        }
    }

    Dock {
        id: dock
        energy: sidebar
        launcherOpen: shellRoot.launcherOpen
    }


    SystemInfo {
        id: sysinfo
    }

    VisualConfigPanel {
        id: visualConfig
    }

    AltTab {}
    Overview {}
    OSD {}
    Cheatsheet {}
    Clipboard {}
    Welcome {}
    QuickNotes {}
    StickyNote {}
    SessionDialog {}
    // Assistente de IA (Super + Ctrl + A): conversa e tradução pelo rice-ai.
    AiSidebar {}
    NotifToasts {}
    PolkitDialog {}
    EditMode {}
    ControlCenter {
        id: controlCenter
        onSettingsRequested: visualConfig.open = true
    }

    PanelWindow {
        id: hub
        visible: false
        focusable: true
        color: "transparent"

        // Colado logo abaixo da waybar, sem vão: o card tem o mesmo fundo da
        // barra (background alpha 0.85 + blur) e cantos invertidos em cima,
        // então parece que desce DE DENTRO da barra, como na Caelestia.
        anchors.top: true
        margins.top: sideMode ? Theme.frameThickness + Theme.gap : Theme.waybarHeight
        // Barra na lateral: o hub sai do lado dela, em vez de descer de cima
        // (onde não tem barra nenhuma).
        readonly property bool sideMode: ShellLayout.barEnabled && ShellLayout.barVertical
        readonly property bool sideLeft: ShellLayout.barPosition === "left"
        anchors.left: sideMode && sideLeft
        anchors.right: sideMode && !sideLeft
        margins.left: sideMode ? 52 + Theme.frameThickness + Theme.gap : 0
        margins.right: sideMode ? 52 + Theme.frameThickness + Theme.gap : 0

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

        // Barra em cima: o hub "cresce" do relógio, como na Caelestia. O
        // `slide` é uma janela de recorte que começa estreita e baixa no
        // centro da barra e abre até o tamanho cheio; o conteúdo fica parado
        // dentro dela (x compensado), então nada escorrega, só aparece.
        // Barra na lateral: continua deslizando do lado dela.
        Item {
            id: slide
            readonly property real closedW: 240
            width: hub.sideMode || hub.open ? parent.width : Math.min(closedW, parent.width)
            height: hub.sideMode || hub.open ? parent.height : 0
            y: 0
            x: hub.sideMode
                ? (hub.open ? 0 : (hub.sideLeft ? -parent.width : parent.width))
                : (parent.width - width) / 2
            clip: !hub.sideMode
            opacity: hub.open ? 1 : 0
            Behavior on height { NumberAnimation { duration: Theme.ms(300); easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Theme.ms(260); easing.type: Easing.OutQuart } }
            // Em cima o x só acompanha a largura (centraliza); animar o x também
            // atrasava a posição e a abertura saía torta para a direita.
            Behavior on x { enabled: hub.sideMode; NumberAnimation { duration: Theme.ms(260); easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Theme.ms(hub.open ? 120 : 220) } }

            Item {
            id: slideContent
            x: hub.sideMode ? 0 : -slide.x
            width: hub.width
            height: hub.height

            // ---------- cantos invertidos (junção com a waybar) ----------
            Canvas {
                id: cornerLeft
                visible: !hub.sideMode
                x: 0
                width: Theme.radius
                height: Theme.radius
                onPaint: {
                    const ctx = getContext("2d");
                    const r = width;
                    ctx.reset();
                    ctx.fillStyle = ShellCustomization.getBgColor("hub");
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
                visible: !hub.sideMode
                x: parent.width - width
                width: Theme.radius
                height: Theme.radius
                onPaint: {
                    const ctx = getContext("2d");
                    const r = width;
                    ctx.reset();
                    ctx.fillStyle = ShellCustomization.getBgColor("hub");
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
            Connections {
                target: ShellCustomization
                function onUpdated() {
                    cornerLeft.requestPaint();
                    cornerRight.requestPaint();
                }
            }

            Rectangle {
                id: card
                x: Theme.radius
                width: Theme.panelWidth
                height: parent.height
                scale: ShellCustomization.getScale("hub")
                transformOrigin: Item.Top
                color: ShellCustomization.getBgColor("hub")
                border.width: ShellCustomization.getBorderWidth("hub")
                border.color: ShellCustomization.getBorderColor("hub")
                topLeftRadius: hub.sideMode ? Theme.radius : 0
                topRightRadius: hub.sideMode ? Theme.radius : 0
                bottomLeftRadius: Theme.radius
                bottomRightRadius: Theme.radius

                Rectangle {
                    visible: ShellCustomization.getStyle("hub") === "glow"
                    anchors.fill: parent
                    anchors.margins: -3
                    bottomLeftRadius: card.bottomLeftRadius + 3
                    bottomRightRadius: card.bottomRightRadius + 3
                    color: "transparent"
                    border.color: Theme.withAlpha(ShellCustomization.getAccent("hub"), 0.4)
                    border.width: 1
                    z: -1
                }

                property int currentTab: 0
                readonly property var tabs: [
                    { icon: Theme.icons.dashboard, label: Theme.t("hub.tab_dashboard", "Dashboard") },
                    { icon: Theme.icons.media, label: Theme.t("hub.tab_media", "Mídia") },
                    { icon: Theme.icons.performance, label: Theme.t("hub.tab_performance", "Performance") },
                    { icon: Theme.icons.record, label: Theme.t("hub.tab_recording", "Gravação") }
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
                                        Behavior on color { ColorAnimation { duration: Theme.ms(120) } }
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
                                            Behavior on color { ColorAnimation { duration: Theme.ms(150) } }
                                        }
                                        Text {
                                            id: tabLabel
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: tabDelegate.modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: tabDelegate.active ? Font.DemiBold : Font.Normal
                                            color: tabDelegate.active ? Theme.primary : Theme.subtext
                                            Behavior on color { ColorAnimation { duration: Theme.ms(150) } }
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
                            Behavior on x { NumberAnimation { duration: Theme.ms(220); easing.type: Easing.OutCubic } }
                            Behavior on width { NumberAnimation { duration: Theme.ms(220); easing.type: Easing.OutCubic } }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Dashboard {
                            anchors.fill: parent
                            opacity: card.currentTab === 0 ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: Theme.ms(140) } }
                        }
                        Media {
                            anchors.fill: parent
                            opacity: card.currentTab === 1 ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: Theme.ms(140) } }
                        }
                        Monitoring {
                            anchors.fill: parent
                            opacity: card.currentTab === 2 ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: Theme.ms(140) } }
                        }
                        Recording {
                            anchors.fill: parent
                            opacity: card.currentTab === 3 && hub.visible ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: Theme.ms(140) } }
                        }
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
            // Lido pelo rice-lock-info (linha de notificações do hyprlock, que
            // é a tela de bloqueio de reserva).
            function count(): string { return String(NotifService.unreadCount); }
            function clear(): void { NotifService.setCleared(NotifService.maxId); }
            function open(): void {
                if (ShellLayout.barVertical) vbar.openNotifs();
                else topbar.openNotifs();
            }
        }
    }
}
