import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Hyprland
import "."

// Barra lateral direita: avatar, updates, trays e energia.
//
// COMO ABRE: a faixa da moldura direita (Theme.frameThickness) é o gatilho.
// Mouse chega na borda → a barra "cresce" de dentro da moldura; mouse sai
// da barra → ela recolhe de volta. Fechada não aparece nada além da moldura.
//
// POPUPS: passar o mouse num ícone da barra faz sair um popup da lateral
// esquerda dela, na altura do ícone (menu do tray, detalhes do update,
// rótulo dos botões de energia). É um popup só: ao trocar de ícone ele
// desliza e muda de tamanho em vez de fechar e abrir outro.
//
// FORMA: barra + popup são desenhados num único Canvas como um contorno só,
// com cantos invertidos onde a barra encosta na moldura e onde o popup
// encosta na barra — é isso que dá o efeito de "a borda esticou".
PanelWindow {
    id: sidebar
    visible: ShellLayout.sidebarEnabled
    focusable: false
    color: "transparent"

    anchors { top: true; bottom: true; right: true }
    margins.top: Theme.waybarHeight
    implicitWidth: Theme.frameThickness + Theme.sidebarWidth + Theme.popoutMaxWidth + 40

    WlrLayershell.namespace: "quickshell-sidebar"
    WlrLayershell.layer: launcherOpen ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Fixa, ela reserva espaço como uma central de ações sempre aberta;
    // no modo normal continua invisível para as janelas.
    exclusionMode: sidebar.pinned ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: sidebar.pinned ? Theme.frameThickness + Theme.sidebarWidth : 0

    signal avatarClicked()

    // ================= estado =================
    property bool open: false
    property bool launcherOpen: false
    readonly property bool hasFullscreen: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen) || false
    readonly property bool allowHover: !hasFullscreen || launcherOpen

    // "Sempre visível" em vez de aparecer no hover. As ações internas continuam
    // chamando sidebar.open = false; com a barra fixa isso simplesmente não
    // tem efeito visual, então nenhuma delas precisou mudar.
    readonly property bool pinned: ShellLayout.sidebarEnabled && !ShellLayout.sidebarAutohide
    // sidebarPeek: o modo edição abre a sidebar enquanto se escolhe o que ela mostra.
    readonly property bool effectiveOpen: ShellLayout.sidebarPeek || (sidebar.pinned ? !hasFullscreen : sidebar.open)

    onHasFullscreenChanged: {
        if (hasFullscreen && !launcherOpen && open) {
            openDelay.stop();
            sidebar.open = false;
        }
    }
    onLauncherOpenChanged: {
        if (hasFullscreen && !launcherOpen && open) {
            openDelay.stop();
            sidebar.open = false;
        }
    }

    property string pop: ""          // "" | avatar | update | logout | reboot | power | tray
    property var popTray: null       // SystemTrayItem do popup de tray
    property real popAnchorY: 0      // centro do ícone que abriu o popup

    readonly property real edgeX: width - Theme.frameThickness   // borda interna da moldura

    // Região que recebe mouse: sempre a faixa da moldura; aberta, também
    // barra e popup. O resto da janela (transparente) deixa o clique passar.
    // Em tela cheia sem launcher, a máscara fica vazia para não roubar cliques de jogos/vídeos.
    mask: (allowHover || sidebar.effectiveOpen) ? fullMask : emptyMask

    Region { id: emptyMask }
    Region {
        id: fullMask
        x: sidebar.edgeX
        y: 0
        width: Theme.frameThickness
        height: sidebar.height
        Region { item: bodyArea }
        Region { item: popArea }
    }

    Timer {
        id: openDelay
        interval: 90
        onTriggered: sidebar.open = true
    }
    Timer {
        id: closeDelay
        interval: 400
        onTriggered: sidebar.open = false
    }
    Timer {
        id: popHide
        interval: 220
        onTriggered: sidebar.pop = ""
    }

    function showPop(kind: string, anchorItem: Item, tray: var): void {
        popHide.stop();
        popTray = tray;
        popAnchorY = anchorItem.mapToItem(root, 0, anchorItem.height / 2).y;
        pop = kind;
    }
    function leavePop(): void { popHide.restart(); }

    onOpenChanged: {
        if (open) {
            nightCheck.running = true;
            gpuStateProc.running = true;
            rebootCheckProc.running = true;
        } else {
            pop = "";
            logoutBtn.armed = false;
            rebootBtn.armed = false;
            powerBtn.armed = false;
        }
    }

    // ================= updates pendentes =================
    property int repoUpdates: 0
    property int aurUpdates: 0
    property int riceUpdates: 0
    readonly property int updateCount: repoUpdates + aurUpdates + riceUpdates

    function checkUpdates() {
        repoUpdatesProc.running = true;
        aurUpdatesProc.running = true;
        riceUpdatesProc.running = true;
    }
    Timer {
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: sidebar.checkUpdates()
    }
    Process {
        id: repoUpdatesProc
        // checkupdates sai com erro quando não há updates; conta linhas.
        command: ["bash", "-c", "checkupdates 2>/dev/null | grep -c '.'"]
        stdout: StdioCollector { onStreamFinished: sidebar.repoUpdates = parseInt(text.trim()) || 0 }
    }
    Process {
        id: aurUpdatesProc
        command: ["bash", "-c", "yay -Qu --aur 2>/dev/null | grep -c '.'"]
        stdout: StdioCollector { onStreamFinished: sidebar.aurUpdates = parseInt(text.trim()) || 0 }
    }
    Process {
        id: riceUpdatesProc
        command: ["bash", "-c", "rice-update check 2>/dev/null | jq -r '.count // 0' 2>/dev/null || echo 0"]
        stdout: StdioCollector { onStreamFinished: sidebar.riceUpdates = parseInt(text.trim()) || 0 }
    }

    // ================= ações =================
    Process { id: logoutProc; command: ["hyprctl", "dispatch", "exit"] }
    Process {
        id: rebootProc
        command: ["systemctl", "reboot"]
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.log("EnergySidebar: reboot falhou:", text.trim())
        }
    }
    Process {
        id: powerProc
        command: ["systemctl", "poweroff"]
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.log("EnergySidebar: shutdown falhou:", text.trim())
        }
    }
    // cachy-update é interativo (Terminal=true no .desktop) — precisa de
    // terminal, senão morre sem mostrar nada. Reconta ao fechar o kitty.
    Process {
        id: cachyUpdateProc
        command: ["kitty", "--class", "cachy-update", "--title", "cachy-update", "-e", "cachy-update"]
        onExited: sidebar.checkUpdates()
    }

    // Ações usadas também pelos itens das barras (catálogo do modo edição), para
    // não duplicar a checagem de estado.
    function toggleNight() { if (!nightToggle.running) nightToggle.running = true; }
    function toggleCaffeine() { if (!caffeineToggle.running) caffeineToggle.running = true; }
    function runUpdate() { if (!cachyUpdateProc.running) cachyUpdateProc.running = true; }
    function stopRecording() { recStopProc.running = true; }
    function refreshGpu() { if (!gpuStateProc.running) gpuStateProc.running = true; }
    // GPU na barra: lê o estado da NVIDIA a cada 5 s só se o item estiver lá.
    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: ShellLayout.barHas("gpu")
        onTriggered: sidebar.refreshGpu()
    }

    // ================= QoL: gravação, café, luz noturna, GPU, reboot, cache =================
    // Gravando? (rice-record grava o pid em $XDG_RUNTIME_DIR/rice-record.pid)
    property bool recording: false
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: recProc.running = true
    }
    Process {
        id: recProc
        command: ["bash", "-c", "f=$XDG_RUNTIME_DIR/rice-record.pid; [ -f $f ] && kill -0 $(cat $f) 2>/dev/null && echo 1 || echo 0"]
        stdout: StdioCollector { onStreamFinished: sidebar.recording = text.trim() === "1" }
    }
    Process { id: recStopProc; command: ["rice-record", "stop"]; onExited: recProc.running = true }

    // Luz noturna (wlsunset, sobe no autostart do hyprland.lua).
    property bool nightLight: false
    Process {
        id: nightCheck
        // A sidebar usava `wlsunset` com a latitude/longitude do autor fixas no
        // código, enquanto o painel usava `hyprsunset` pelo rice-nightlight: os
        // dois discordavam sobre o estado e o repositório carregava a
        // localização de uma pessoa. Agora os dois falam com o mesmo programa.
        command: ["pgrep", "-x", "hyprsunset"]
        onExited: code => sidebar.nightLight = code === 0
    }
    Process {
        id: nightToggle
        command: ["rice-nightlight", "toggle"]
        onExited: nightRecheck.restart()
    }

    // ---------- manter acordado ----------
    property bool caffeine: false
    Process {
        id: caffeineCheck
        command: ["rice-caffeine", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { sidebar.caffeine = !!JSON.parse(text).active; } catch (e) {}
            }
        }
    }
    Process {
        id: caffeineToggle
        command: ["rice-caffeine", "toggle"]
        onExited: caffeineRecheck.restart()
    }
    Timer { id: caffeineRecheck; interval: 400; onTriggered: caffeineCheck.running = true }
    Timer {
        interval: 20000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: caffeineCheck.running = true
    }
    Timer { id: nightRecheck; interval: 400; onTriggered: nightCheck.running = true }

    // GPU: estado de energia da NVIDIA lido do sysfs (NÃO usa nvidia-smi,
    // que acordaria a placa só pra perguntar) + apps com /dev/nvidia* aberto.
    property string nvidiaState: ""     // active | suspended
    property var nvidiaApps: []
    Process {
        id: gpuStateProc
        command: ["cat", "/sys/bus/pci/devices/0000:01:00.0/power/runtime_status"]
        stdout: StdioCollector { onStreamFinished: sidebar.nvidiaState = text.trim() }
    }
    Process {
        id: gpuAppsProc
        command: ["bash", "-c", "for p in $(fuser /dev/nvidia* 2>/dev/null); do cat /proc/$p/comm 2>/dev/null; done | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: sidebar.nvidiaApps = text.trim() === "" ? [] : text.trim().split("\n")
        }
    }

    // Reboot necessário (kernel ou driver NVIDIA atualizados sem reiniciar).
    property string rebootReason: ""
    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: rebootCheckProc.running = true
    }
    Process {
        id: rebootCheckProc
        command: ["rice-reboot-needed"]
        stdout: StdioCollector { onStreamFinished: sidebar.rebootReason = text.trim() }
    }

    // Tamanho do cache de pacotes (popup do update).
    property string cacheSize: ""
    Process {
        id: cacheSizeProc
        command: ["bash", "-c", "du -scb /var/cache/pacman/pkg $HOME/.cache/yay 2>/dev/null | tail -1 | cut -f1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const b = parseFloat(text.trim()) || 0;
                sidebar.cacheSize = b > 1073741824 ? (b / 1073741824).toFixed(1) + " GB" : Math.round(b / 1048576) + " MB";
            }
        }
    }
    Process { id: cleanCacheProc; command: ["kitty", "--class", "rice-clean-cache", "-e", "rice-clean-cache"]; onExited: cacheSizeProc.running = true }
    Process { id: lockProc; command: ["rice-lock"] }

    property string uptimeText: ""
    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = Math.floor(parseFloat(text.split(" ")[0]));
                const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
                sidebar.uptimeText = d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + m + "min" : m + " min";
            }
        }
    }

    // ================= componentes =================
    component SideButton: Item {
        id: btn
        required property string kind
        property string icon: ""
        property bool needsConfirm: false
        property color tint: Theme.textColor
        property bool armed: false
        default property alias extra: btnBg.data
        signal activated()

        visible: ShellLayout.sidebarHas(btn.kind)
        Layout.preferredWidth: Theme.sidebarButtonSize
        Layout.preferredHeight: Theme.sidebarButtonSize
        Layout.alignment: Qt.AlignHCenter

        Rectangle {
            id: btnBg
            anchors.fill: parent
            radius: width / 2
            color: btn.armed ? Theme.critical
                : (area.containsMouse || sidebar.pop === btn.kind) ? Theme.tileHigh : "transparent"
            scale: area.pressed ? 0.9 : 1
            Behavior on color { ColorAnimation { duration: Theme.ms(140) } }
            Behavior on scale { NumberAnimation { duration: Theme.ms(90) } }

            Text {
                anchors.centerIn: parent
                visible: btn.icon !== ""
                text: btn.armed ? Theme.icons.confirm : btn.icon
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.sidebarIconSize
                color: btn.armed ? Theme.textColor : btn.tint
            }
        }

        Timer {
            id: disarm
            interval: 3000
            onTriggered: btn.armed = false
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: {
                if (btn.kind === "gpu") { gpuStateProc.running = true; gpuAppsProc.running = true; }
                if (btn.kind === "update") cacheSizeProc.running = true;
                sidebar.showPop(btn.kind, btn, null);
            }
            onExited: sidebar.leavePop()
            onClicked: {
                if (!btn.needsConfirm || btn.armed) {
                    disarm.stop();
                    btn.armed = false;
                    btn.activated();
                } else {
                    btn.armed = true;
                    disarm.restart();
                }
            }
            onDoubleClicked: {
                if (btn.needsConfirm) {
                    disarm.stop();
                    btn.armed = false;
                    btn.activated();
                }
            }
        }
    }

    component Sep: Rectangle {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 26
        Layout.preferredHeight: 1
        Layout.topMargin: 2
        Layout.bottomMargin: 2
        color: Theme.withAlpha(Theme.outline, 0.45)
    }

    // ================= conteúdo =================
    Item {
        id: root
        anchors.fill: parent

        HoverHandler {
            enabled: sidebar.allowHover
            onHoveredChanged: {
                if (!enabled) return;
                if (hovered) {
                    closeDelay.stop();
                    if (!sidebar.open)
                        openDelay.restart();
                } else {
                    openDelay.stop();
                    if (sidebar.open)
                        closeDelay.restart();
                }
            }
        }

        // ---------- geometria animada ----------
        readonly property real radius: Theme.frameRadius
        property real bodyW: sidebar.effectiveOpen ? Theme.sidebarWidth : 0
        Behavior on bodyW { NumberAnimation { duration: Theme.ms(280); easing.type: Easing.OutCubic } }
        readonly property real bodyH: column.implicitHeight + Theme.gap * 4
        readonly property real bodyTop: Math.round((height - bodyH) / 2)
        readonly property real bodyBottom: bodyTop + bodyH

        readonly property real popTargetW: sidebar.pop !== "" && sidebar.effectiveOpen
            ? Math.min(Theme.popoutMaxWidth, popContent.implicitWidth + 32) : 0
        readonly property real popTargetH: Math.max(52, popContent.implicitHeight + 28)
        property real popW: popTargetW
        property real popH: popTargetH
        property real popTop: Math.max(radius, Math.min(height - popTargetH - radius, sidebar.popAnchorY - popTargetH / 2))
        Behavior on popW { NumberAnimation { duration: Theme.ms(260); easing.type: Easing.OutCubic } }
        Behavior on popH { NumberAnimation { duration: Theme.ms(260); easing.type: Easing.OutCubic } }
        // Só desliza entre ícones com o popup já aberto; abrindo do zero
        // ele nasce direto na altura certa.
        Behavior on popTop {
            enabled: root.popW > 4
            NumberAnimation { duration: Theme.ms(260); easing.type: Easing.OutCubic }
        }

        onBodyWChanged: shape.requestPaint()
        onBodyHChanged: shape.requestPaint()
        onPopWChanged: shape.requestPaint()
        onPopHChanged: shape.requestPaint()
        onPopTopChanged: shape.requestPaint()
        onHeightChanged: shape.requestPaint()
        Connections {
            target: Theme
            function onBackgroundChanged() { shape.requestPaint(); }
        }
        Connections {
            target: ShellCustomization
            function onUpdated() { shape.requestPaint(); }
        }

        Canvas {
            id: shape
            anchors.fill: parent

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const E = sidebar.edgeX;
                const bw = root.bodyW;
                if (bw < 0.5)
                    return;
                const R = root.radius;
                const T = root.bodyTop, B = root.bodyBottom;
                const f1 = Math.min(R, bw);                    // canto invertido barra↔moldura
                const c1 = Math.min(R, bw / 2, (B - T) / 2);   // canto convexo da barra
                const L = E - bw;                              // lateral esquerda da barra
                const pw = root.popW;

                ctx.fillStyle = ShellCustomization.getBgColor("sidebar");
                ctx.beginPath();
                ctx.moveTo(E, T - f1);
                ctx.arc(E - f1, T - f1, f1, 0, Math.PI / 2, false);
                ctx.lineTo(L + c1, T);
                ctx.arc(L + c1, T + c1, c1, -Math.PI / 2, Math.PI, true);

                if (pw > 0.5) {
                    const PT = root.popTop, PB = root.popTop + root.popH;
                    const P = L - pw;
                    const cp = Math.min(R * 0.8, pw / 2, (PB - PT) / 2);
                    // canto invertido popup↔barra, só onde a barra existe
                    const ft = Math.max(0, Math.min(R * 0.7, pw, PT - (T + c1)));
                    const fb = Math.max(0, Math.min(R * 0.7, pw, (B - c1) - PB));
                    ctx.lineTo(L, PT - ft);
                    if (ft > 0)
                        ctx.arc(L - ft, PT - ft, ft, 0, Math.PI / 2, false);
                    ctx.lineTo(P + cp, PT);
                    ctx.arc(P + cp, PT + cp, cp, -Math.PI / 2, Math.PI, true);
                    ctx.lineTo(P, PB - cp);
                    ctx.arc(P + cp, PB - cp, cp, Math.PI, Math.PI / 2, true);
                    ctx.lineTo(L - fb, PB);
                    if (fb > 0)
                        ctx.arc(L - fb, PB + fb, fb, -Math.PI / 2, 0, false);
                }

                ctx.lineTo(L, B - c1);
                ctx.arc(L + c1, B - c1, c1, Math.PI, Math.PI / 2, true);
                ctx.lineTo(E - f1, B);
                ctx.arc(E - f1, B + f1, f1, -Math.PI / 2, 0, false);
                ctx.closePath();
                ctx.fill();

                if (ShellCustomization.getStyle("sidebar") === "glow") {
                    ctx.strokeStyle = ShellCustomization.getAccent("sidebar");
                    ctx.lineWidth = 2;
                    ctx.stroke();
                } else if (ShellCustomization.getStyle("sidebar") === "solid") {
                    ctx.strokeStyle = Theme.withAlpha(Theme.outline, 0.25);
                    ctx.lineWidth = 1;
                    ctx.stroke();
                } else if (ShellCustomization.getStyle("sidebar") === "glass") {
                    ctx.strokeStyle = Theme.withAlpha(ShellCustomization.getAccent("sidebar"), 0.35);
                    ctx.lineWidth = 1;
                    ctx.stroke();
                }
            }
        }

        // ---------- indicador de gravação na moldura ----------
        Rectangle {
            visible: sidebar.recording
            x: sidebar.edgeX
            y: root.bodyTop
            width: Theme.frameThickness
            height: root.bodyH
            color: Theme.critical
            SequentialAnimation on opacity {
                running: sidebar.recording
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 700 }
                NumberAnimation { to: 1; duration: 700 }
            }
        }

        // ---------- barra ----------
        Item {
            id: bodyArea
            x: sidebar.edgeX - root.bodyW
            y: root.bodyTop
            width: root.bodyW
            height: root.bodyH
            scale: ShellCustomization.getScale("sidebar")
            transformOrigin: Item.Right
            clip: true

            ColumnLayout {
                id: column
                // Presa à borda direita: ao crescer, a barra "revela" os
                // ícones em vez de espremê-los.
                x: root.bodyW - Theme.sidebarWidth + (Theme.sidebarWidth - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.sidebarButtonSize
                spacing: 6
                opacity: root.bodyW / Theme.sidebarWidth

                // avatar (~/.face)
                Item {
                    id: avatarBtn
                    visible: ShellLayout.sidebarHas("avatar")
                    Layout.preferredWidth: Theme.sidebarButtonSize
                    Layout.preferredHeight: Theme.sidebarButtonSize
                    Layout.alignment: Qt.AlignHCenter

                    ClippingRectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Theme.tileHigh
                        border.width: sidebar.pop === "avatar" ? 2 : 0
                        border.color: Theme.primary

                        AnimatedImage {
                            id: face
                            anchors.fill: parent
                            source: "file://" + Quickshell.env("HOME") + "/.face.webp"
                            playing: visible
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: face.status !== Image.Ready
                            text: Theme.icons.account
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 30
                            color: Theme.subtext
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sidebar.avatarClicked()
                        onEntered: {
                            uptimeProc.running = true;
                            sidebar.showPop("avatar", avatarBtn, null);
                        }
                        onExited: sidebar.leavePop()
                    }
                }

                Sep {}

                SideButton {
                    kind: "update"
                    icon: Theme.icons.update
                    tint: sidebar.updateCount > 0 ? Theme.primary : Theme.textColor
                    onActivated: {
                        if (!cachyUpdateProc.running)
                            cachyUpdateProc.running = true;
                        sidebar.open = false;
                    }

                    Rectangle {
                        visible: sidebar.updateCount > 0
                        width: Math.max(18, badgeText.implicitWidth + 8)
                        height: 18
                        radius: 9
                        color: Theme.primary
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -2
                        anchors.rightMargin: -4

                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: sidebar.updateCount > 99 ? "99+" : sidebar.updateCount
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            color: Theme.background
                        }
                    }
                }

                // gravação em andamento (só aparece gravando) — clique para parar
                SideButton {
                    id: recBtn
                    kind: "record"
                    visible: sidebar.recording && ShellLayout.sidebarHas("record")
                    icon: Theme.icons.record
                    tint: Theme.critical
                    onActivated: recStopProc.running = true
                }

                Sep {}

                // atalhos rápidos
                SideButton {
                    kind: "night"
                    icon: Theme.icons.night
                    tint: sidebar.nightLight ? Theme.primary : Theme.textColor
                    onActivated: nightToggle.running = true
                }
                SideButton {
                    kind: "caffeine"
                    icon: sidebar.caffeine ? Theme.icons.coffee : Theme.icons.coffeeOff
                    tint: sidebar.caffeine ? Theme.primary : Theme.textColor
                    onActivated: caffeineToggle.running = true
                }
                SideButton {
                    kind: "gpu"
                    icon: Theme.icons.gpu
                    tint: sidebar.nvidiaState === "active" ? Theme.primary : Theme.textColor
                    onActivated: {}
                }

                Sep { visible: SystemTray.items.values.length > 0 && ShellLayout.sidebarHas("tray") }

                // trays
                Repeater {
                    id: trayRepeater
                    model: SystemTray.items
                    delegate: Item {
                        id: trayBtn
                        required property SystemTrayItem modelData
                        visible: ShellLayout.sidebarHas("tray")
                        Layout.preferredWidth: Theme.sidebarButtonSize
                        Layout.preferredHeight: Theme.sidebarButtonSize - 6
                        Layout.alignment: Qt.AlignHCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: (trayArea.containsMouse || (sidebar.pop === "tray" && sidebar.popTray === trayBtn.modelData))
                                ? Theme.tileHigh : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.ms(140) } }
                        }
                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 20
                            source: trayBtn.modelData.icon
                            opacity: trayBtn.modelData.status === Status.Passive ? 0.6 : 1
                        }
                        MouseArea {
                            id: trayArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onEntered: sidebar.showPop("tray", trayBtn, trayBtn.modelData)
                            onExited: sidebar.leavePop()
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton)
                                    trayBtn.modelData.secondaryActivate();
                                else if (!trayBtn.modelData.onlyMenu)
                                    trayBtn.modelData.activate();
                            }
                            onWheel: wheel => trayBtn.modelData.scroll(wheel.angleDelta.y, false)
                        }
                    }
                }

                Sep {}

                SideButton {
                    kind: "lock"
                    icon: Theme.icons.lock
                    onActivated: {
                        sidebar.open = false;
                        lockProc.running = true;
                    }
                }
                // Suspender: o equivalente ao "Suspensão" do Windows, que faltava
                // no menu de energia (só havia bloquear, sair, reiniciar e desligar).
                SideButton {
                    id: suspendBtn
                    kind: "suspend"
                    icon: Theme.icons.sleep
                    onActivated: {
                        sidebar.open = false;
                        Quickshell.execDetached(["rice-session-action", "suspend"]);
                    }
                }
                // Ir para a tela de login NÃO fecha o que está aberto: o SDDM
                // abre um greeter num VT novo e a sessão continua atrás dele.
                // Fechar tudo de verdade virou uma ação separada, dentro do
                // popup — é o que se usa para trocar de ambiente gráfico.
                SideButton {
                    id: logoutBtn
                    kind: "logout"
                    icon: Theme.icons.logout
                    onActivated: {
                        sidebar.open = false;
                        Quickshell.execDetached(["rice-session-action", "switch-user"]);
                    }
                }
                SideButton {
                    id: rebootBtn
                    kind: "reboot"
                    icon: Theme.icons.restart
                    tint: sidebar.rebootReason !== "" ? Theme.primary : Theme.textColor
                    needsConfirm: true
                    onActivated: {
                        sidebar.open = false;
                        Quickshell.execDetached(["rice-session-action", "reboot"]);
                    }

                    Rectangle {
                        visible: sidebar.rebootReason !== ""
                        width: 12
                        height: 12
                        radius: 6
                        color: Theme.primary
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 2
                        anchors.rightMargin: 2
                    }
                }
                SideButton {
                    id: powerBtn
                    kind: "power"
                    icon: Theme.icons.power
                    tint: Theme.primary
                    needsConfirm: true
                    onActivated: {
                        sidebar.open = false;
                        Quickshell.execDetached(["rice-session-action", "poweroff"]);
                    }
                }
            }
        }

        // ---------- popup ----------
        Item {
            id: popArea
            x: sidebar.edgeX - root.bodyW - root.popW
            y: root.popTop
            width: root.popW
            height: root.popH
            clip: true

            HoverHandler {
                onHoveredChanged: hovered ? popHide.stop() : sidebar.leavePop()
            }

            Item {
                id: popContent
                x: 16
                y: 14
                width: implicitWidth
                height: implicitHeight
                implicitWidth: current ? Math.min(Theme.popoutMaxWidth - 32, current.implicitWidth) : 0
                implicitHeight: current ? current.implicitHeight : 0
                readonly property Item current: {
                    switch (sidebar.pop) {
                    case "avatar": return avatarPop;
                    case "update": return updatePop;
                    case "record": return recordPop;
                    case "night": return nightPop;
                    case "caffeine": return caffeinePop;
                    case "gpu": return gpuPop;
                    case "lock": return lockPop;
                    case "suspend": return suspendPop;
                    case "logout": return logoutPop;
                    case "reboot": case "power": return powerPop;
                    case "tray": return trayPop;
                    }
                    return null;
                }
                // Some enquanto o popup ainda está esticando/trocando de
                // tamanho e volta quando assenta — a troca de conteúdo vira
                // um fade em vez de corte seco.
                opacity: root.popTargetW > 0 && Math.abs(root.popW - root.popTargetW) < 24 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.ms(140) } }

                ColumnLayout {
                    id: suspendPop
                    visible: popContent.current === suspendPop
                    spacing: 2
                    PopTitle { text: Theme.t("sidebar.suspend", "Suspender") }
                    PopText { text: Theme.t("sidebar.suspend_hint", "Bloqueia a tela e coloca o PC para dormir") }
                }

                ColumnLayout {
                    id: avatarPop
                    visible: popContent.current === avatarPop
                    spacing: 2
                    PopTitle { text: (Quickshell.env("USER") || "") }
                    PopText { text: sidebar.uptimeText !== "" ? Theme.t("sidebar.uptime", "Ligado há ") + sidebar.uptimeText : "..." }
                    PopText { text: Theme.t("sidebar.pc_specs", "Clique para ver as especificações do PC") }
                }

                ColumnLayout {
                    id: updatePop
                    visible: popContent.current === updatePop
                    spacing: 2
                    PopTitle {
                        text: sidebar.updateCount === 0 ? Theme.t("sidebar.updates_none", "Sistema atualizado")
                            : sidebar.updateCount + " " + Theme.t("sidebar.updates_available", "atualizações")
                    }
                    PopText {
                        visible: sidebar.updateCount > 0
                        text: sidebar.repoUpdates + " repositório · " + sidebar.aurUpdates + " AUR" + (sidebar.riceUpdates > 0 ? " · " + sidebar.riceUpdates + " dotfiles" : "")
                    }
                    // Antes esta ação só aparecia quando havia commits novos.
                    // Como o rice-update também conserta o que ficou pela
                    // metade numa atualização anterior, ela fica sempre à mão.
                    PopAction {
                        Layout.topMargin: 4
                        icon: Theme.icons.palette
                        label: sidebar.riceUpdates > 0
                            ? Theme.t("sidebar.rice_update_n", "Atualizar o rice (") + sidebar.riceUpdates + Theme.t("sidebar.rice_update_n_end", " novidades)")
                            : Theme.t("sidebar.rice_update", "Atualizar o rice (hollow-wired)")
                        onActivated: {
                            Quickshell.execDetached(["rice-update", "gui"]);
                            sidebar.open = false;
                        }
                    }
                    // Reinicia só a interface (barra, dock, hub, widgets): o
                    // conserto rápido quando algo do shell trava ou some, sem
                    // fechar os programas. Mesmo que Super + Ctrl + R. Pedido
                    // pelo compositor para o processo novo não morrer junto
                    // com o shell que está sendo encerrado.
                    PopAction {
                        icon: Theme.icons.restart
                        label: Theme.t("sidebar.restart_shell", "Reiniciar a interface (barra, dock, widgets)")
                        onActivated: {
                            sidebar.open = false;
                            Hyprland.dispatch('hl.dsp.exec_cmd("' + Quickshell.env("HOME") + '/.local/bin/rice-restart")');
                        }
                    }
                    PopAction {
                        icon: Theme.icons.health
                        label: Theme.t("sidebar.rice_fix", "Procurar e consertar problemas")
                        onActivated: {
                            Quickshell.execDetached(["rice-update", "fix-gui"]);
                            sidebar.open = false;
                        }
                    }
                    PopAction {
                        Layout.topMargin: 4
                        icon: Theme.icons.update
                        label: "Abrir cachy-update"
                        onActivated: {
                            if (!cachyUpdateProc.running)
                                cachyUpdateProc.running = true;
                            sidebar.open = false;
                        }
                    }
                    PopAction {
                        icon: Theme.icons.broom
                        label: "Limpar cache de pacotes" + (sidebar.cacheSize !== "" ? " (" + sidebar.cacheSize + ")" : "")
                        needsConfirm: true
                        onActivated: {
                            if (!cleanCacheProc.running)
                                cleanCacheProc.running = true;
                            sidebar.open = false;
                        }
                    }
                }

                ColumnLayout {
                    id: recordPop
                    visible: popContent.current === recordPop
                    spacing: 2
                    PopTitle { text: Theme.t("topbar.recording_active", "Gravando a tela"); color: Theme.critical }
                    PopText { text: Theme.t("sidebar.recording_hint", "Clique para parar e salvar em ~/Vídeos/Gravações") }
                }

                ColumnLayout {
                    id: nightPop
                    visible: popContent.current === nightPop
                    spacing: 2
                    PopTitle { text: sidebar.nightLight ? Theme.t("sidebar.night_light_on", "Luz noturna ligada") : Theme.t("sidebar.night_light_off", "Luz noturna desligada") }
                    PopText { text: Theme.t("sidebar.night_light_desc", "Deixa a tela mais quente. O horário automático fica no painel.") }
                    PopText { text: Theme.t("sidebar.night_light_action", "Clique para alternar") }
                }

                ColumnLayout {
                    id: caffeinePop
                    visible: popContent.current === caffeinePop
                    spacing: 2
                    PopTitle {
                        text: sidebar.caffeine ? Theme.t("sidebar.caffeine_on", "A tela não vai apagar")
                                               : Theme.t("sidebar.caffeine_off", "A tela apaga sozinha")
                    }
                    PopText {
                        text: sidebar.caffeine
                            ? Theme.t("sidebar.caffeine_on_desc", "Bloqueio automático e suspensão pausados. Fechar a tampa ainda suspende.")
                            : Theme.t("sidebar.caffeine_off_desc", "Para assistir um filme sem a tela bloquear no meio.")
                    }
                    PopText { text: Theme.t("sidebar.caffeine_action", "Clique para alternar") }
                }

                ColumnLayout {
                    id: gpuPop
                    visible: popContent.current === gpuPop
                    spacing: 2
                    PopTitle {
                        text: sidebar.nvidiaState === "active" ? Theme.t("sidebar.nvidia_active", "NVIDIA acordada") : sidebar.nvidiaState === "suspended" ? Theme.t("sidebar.nvidia_sleeping", "NVIDIA dormindo") : "NVIDIA"
                    }
                    PopText {
                        text: sidebar.nvidiaState === "suspended" ? Theme.t("sidebar.nvidia_sleeping", "Tudo rodando na Intel (economiza bateria)")
                            : sidebar.nvidiaApps.length > 0 ? "Usando: " + sidebar.nvidiaApps.join(", ")
                            : "Nenhum app usando agora"
                        wrapMode: Text.Wrap
                        Layout.maximumWidth: Theme.popoutMaxWidth - 40
                    }
                    PopText { text: Theme.t("sidebar.nvidia_hybrid_desc", "Tela desenhada pela Intel · jogos vão pra NVIDIA (prime-run)") }
                }

                ColumnLayout {
                    id: lockPop
                    visible: popContent.current === lockPop
                    spacing: 2
                    PopTitle { text: Theme.t("sidebar.lock_screen", "Bloquear tela") }
                    PopText { text: Theme.t("sidebar.lock_hint", "Clique para bloquear (Super+L)") }
                }

                ColumnLayout {
                    id: logoutPop
                    visible: popContent.current === logoutPop
                    spacing: 2
                    PopTitle { text: Theme.t("sidebar.switch_user", "Ir para a tela de login") }
                    PopText {
                        text: Theme.t("sidebar.switch_user_desc", "Seus programas continuam abertos. Ao entrar de novo, tudo volta como estava.")
                        wrapMode: Text.Wrap
                        Layout.maximumWidth: Theme.popoutMaxWidth - 40
                    }
                    PopAction {
                        Layout.topMargin: 4
                        icon: Theme.icons.lock
                        label: Theme.t("sidebar.switch_user_btn", "Ir para a tela de login")
                        onActivated: {
                            sidebar.open = false;
                            Quickshell.execDetached(["rice-session-action", "switch-user"]);
                        }
                    }
                    PopAction {
                        icon: Theme.icons.logout
                        label: Theme.t("sidebar.logout_full", "Fechar tudo e sair da sessão")
                        needsConfirm: true
                        onActivated: {
                            sidebar.open = false;
                            Quickshell.execDetached(["rice-session-action", "logout"]);
                        }
                    }
                    PopText {
                        text: Theme.t("sidebar.logout_full_desc", "Fecha todos os programas. Use para trocar de ambiente gráfico.")
                        wrapMode: Text.Wrap
                        Layout.maximumWidth: Theme.popoutMaxWidth - 40
                    }
                }

                ColumnLayout {
                    id: powerPop
                    visible: popContent.current === powerPop
                    spacing: 6
                    readonly property var btn: sidebar.pop === "reboot" ? rebootBtn : powerBtn
                    PopTitle {
                        text: sidebar.pop === "reboot" ? Theme.t("sidebar.reboot", "Reiniciar") : Theme.t("sidebar.shutdown", "Desligar")
                    }
                    PopText {
                        visible: sidebar.pop === "reboot" && sidebar.rebootReason !== ""
                        text: Theme.t("sidebar.reboot_recommended", "Reboot recomendado: ") + sidebar.rebootReason.split(";").join(", ")
                        color: Theme.primary
                    }
                    PopText {
                        text: powerPop.btn.armed ? Theme.t("sidebar.confirm_click_again", "Clique de novo ou confirme abaixo:") : Theme.t("sidebar.confirm_click_twice", "Clique duas vezes ou confirme abaixo:")
                        color: powerPop.btn.armed ? Theme.primary : Theme.subtext
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 6
                        color: powerPop.btn && powerPop.btn.armed ? Theme.critical : Theme.tile
                        border.color: powerPop.btn && powerPop.btn.armed ? Theme.critical : Theme.outline
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: sidebar.pop === "reboot" ? Theme.t("sidebar.confirm_reboot", "Confirmar Reinício") : Theme.t("sidebar.confirm_shutdown", "Confirmar Desligar")
                            color: powerPop.btn && powerPop.btn.armed ? "#ffffff" : Theme.primary
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (powerPop.btn) {
                                    powerPop.btn.armed = false;
                                    powerPop.btn.activated();
                                }
                            }
                        }
                    }
                }

                TrayMenu {
                    id: trayPop
                    visible: popContent.current === trayPop
                    item: sidebar.pop === "tray" ? sidebar.popTray : null
                    maxWidth: Theme.popoutMaxWidth - 32
                    onTriggered: sidebar.pop = ""
                }
            }
        }
    }

    // IPC: `qs ipc call sidebar toggle|open|hide|check|popup <kind>|trayPopup <n>`
    IpcHandler {
        target: "sidebar"
        function toggle(): void { sidebar.open = !sidebar.open; }
        function open(): void { sidebar.open = true; }
        function hide(): void { sidebar.open = false; }
        function close(): void { sidebar.open = false; }
        function check(): void { sidebar.checkUpdates(); }
        function trayPopup(index: string): void {
            const i = parseInt(index) || 0;
            const btn = trayRepeater.itemAt(i);
            if (!btn) return;
            sidebar.open = true;
            sidebar.showPop("tray", btn, SystemTray.items.values[i]);
            popHide.stop();
        }
        function popup(kind: string): void {
            const anchors = { avatar: avatarBtn, update: logoutBtn, logout: logoutBtn, reboot: rebootBtn, power: powerBtn };
            sidebar.open = true;
            sidebar.showPop(kind, anchors[kind] || logoutBtn, null);
            popHide.stop();
        }
    }

    IpcHandler {
        target: "energy"
        function toggle(): void { sidebar.open = !sidebar.open; }
        function open(): void { sidebar.open = true; }
        function hide(): void { sidebar.open = false; }
        function close(): void { sidebar.open = false; }
    }
}
