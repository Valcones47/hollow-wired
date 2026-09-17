import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "."

// Painel de Configurações Visuais do Rice:
// - Fastfetch (Logos em ~/Imagens/FastFetch, dimensões, módulos, preview no terminal)
// - Kitty Terminal (Opacidade, fonte, padding, blur, cursor, áudio)
// - Mako Notificações (Posição 3x2, timeout, bordas, raio, teste)
// - Tela & Monitor (Detecção eDP-1, 144Hz vs 60Hz, VRR FreeSync, slider de brilho)
// - Teclado & Mouse (ABNT2 vs US Intl, sensibilidade, aceleração Flat vs Adaptativa, NumLock)
// - Cores & Wallust (Paleta completa de 16 cores com cópia HEX, regenerar cores, switcher)
// - Efeitos & Janelas (Luz noturna, dim inativo, arredondamento, gaps, animações, SDDM/Limine)
// - Sistema & Reparo (Reiniciar PipeWire, destravar pacman db.lck, limpar cache, Rice Doctor)
PanelWindow {
    id: win

    property bool open: false
    visible: false
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: true

    WlrLayershell.namespace: "quickshell-visualconfig"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (open) {
            closeTimer.stop();
            visible = true;
            win.refreshAll();
        } else {
            closeTimer.restart();
        }
    }
    Timer { id: closeTimer; interval: 220; onTriggered: win.visible = false }

    // ================= DADOS & ESTADO =================
    property int currentTab: 0 // 0..7

    // Fastfetch
    property var ffConfig: ({})
    property var ffImages: []
    property string ffCurrentLogo: ""
    property int ffWidth: 32
    property int ffHeight: 14
    property var ffActiveModules: []

    // Kitty
    property real kittyOpacity: 0.85
    property real kittyFontSize: 11.0
    property int kittyPadding: 12
    property bool kittyBlur: false
    property string kittyCursor: "beam"
    property bool kittyBell: false

    // Mako
    property string makoAnchor: "top-right"
    property int makoTimeout: 5
    property int makoRadius: 8
    property int makoBorder: 2

    // Tela & Monitores
    property string monitorName: "eDP-1"
    property string monitorModel: "AU Optronics 144Hz IPS"
    property string monitorRes: "1920x1080"
    property int monitorHz: 144
    property bool vrrEnabled: true
    property int screenBrightness: 40

    // Teclado & Mouse
    property string kbLayout: "br"
    property real mouseSensitivity: 0.0
    property string mouseAccel: "flat"
    property bool numlock: true

    // Cores & Wallust
    property var wallustColors: ({})

    // Efeitos / Hyprland
    property bool nightlightActive: false
    property int nightlightTemp: 4500
    property bool dimInactive: false
    property real dimStrength: 0.2
    property int rounding: 8
    property int gapsIn: 6
    property string animPreset: "smooth"

    // Toast de notificação interna (ex: "Copiado para o clipboard")
    property string toastMsg: ""
    Timer {
        id: toastTimer
        interval: 2200
        onTriggered: win.toastMsg = ""
    }
    function showToast(msg) {
        win.toastMsg = msg;
        toastTimer.restart();
    }

    // Processos de Leitura
    Process {
        id: loadFFProc
        command: ["rice-fastfetch-apply", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    win.ffConfig = data;
                    win.ffCurrentLogo = data.source || "";
                    win.ffWidth = data.width || 32;
                    win.ffHeight = data.height || 14;
                    win.ffActiveModules = data.modules || [];
                } catch (e) {}
            }
        }
    }

    Process {
        id: listImagesProc
        command: ["rice-fastfetch-apply", "list-images"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.ffImages = JSON.parse(text) || [];
                } catch (e) {
                    win.ffImages = [];
                }
            }
        }
    }

    Process {
        id: loadKittyProc
        command: ["rice-kitty-apply", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    win.kittyOpacity = d.opacity !== undefined ? d.opacity : 0.85;
                    win.kittyFontSize = d.font_size !== undefined ? d.font_size : 11.0;
                    win.kittyPadding = d.padding !== undefined ? d.padding : 12;
                    win.kittyBlur = !!d.blur;
                    win.kittyCursor = d.cursor || "beam";
                    win.kittyBell = !!d.bell;
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadMakoProc
        command: ["rice-mako-apply", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    win.makoAnchor = d.anchor || "top-right";
                    win.makoTimeout = d.timeout || 5;
                    win.makoRadius = d.radius || 8;
                    win.makoBorder = d.border_size !== undefined ? d.border_size : 2;
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadNightlightProc
        command: ["rice-nightlight", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    win.nightlightActive = !!d.active;
                    win.nightlightTemp = d.temp || 4500;
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadHyprPrefsProc
        command: ["rice-hypr-prefs", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d.dim_inactive !== undefined) win.dimInactive = !!d.dim_inactive;
                    if (d.dim_strength !== undefined) win.dimStrength = d.dim_strength;
                    if (d.rounding !== undefined) win.rounding = d.rounding;
                    if (d.gaps_in !== undefined) win.gapsIn = d.gaps_in;
                    if (d.anim_preset !== undefined) win.animPreset = d.anim_preset;
                    if (d.monitor_hz !== undefined) win.monitorHz = parseInt(d.monitor_hz) || 144;
                    if (d.vrr !== undefined) win.vrrEnabled = (d.vrr === 1 || d.vrr === true);
                    if (d.kb_layout !== undefined) win.kbLayout = d.kb_layout;
                    if (d.mouse_sensitivity !== undefined) win.mouseSensitivity = d.mouse_sensitivity;
                    if (d.mouse_accel !== undefined) win.mouseAccel = d.mouse_accel;
                    if (d.numlock !== undefined) win.numlock = !!d.numlock;
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadMonitorsProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(text);
                    if (arr && arr.length > 0) {
                        win.monitorName = arr[0].name || "eDP-1";
                        win.monitorRes = arr[0].width + "x" + arr[0].height;
                        win.monitorModel = (arr[0].make ? arr[0].make + " " : "") + (arr[0].model || "Display IPS");
                        if (arr[0].refreshRate) win.monitorHz = Math.round(arr[0].refreshRate);
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadBrightnessProc
        command: ["sh", "-c", "brightnessctl -m 2>/dev/null | awk -F, '{print $4}' | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const b = parseInt(text.trim());
                if (!isNaN(b) && b > 0) win.screenBrightness = b;
            }
        }
    }

    Process {
        id: loadWallustColorsProc
        command: ["sh", "-c", "cat ~/.cache/wallust/colors-quickshell.json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.wallustColors = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    function refreshAll() {
        loadFFProc.running = true;
        listImagesProc.running = true;
        loadKittyProc.running = true;
        loadMakoProc.running = true;
        loadNightlightProc.running = true;
        loadHyprPrefsProc.running = true;
        loadMonitorsProc.running = true;
        loadBrightnessProc.running = true;
        loadWallustColorsProc.running = true;
    }

    // Debounce genérico para sliders
    Timer {
        id: debounceTimer
        interval: 70
        property var fn: null
        onTriggered: {
            if (fn) fn();
        }
        function exec(action) {
            fn = action;
            restart();
        }
    }

    // ================= COMPONENTES VISUAIS REUTILIZÁVEIS =================
    component CfgSlider: ColumnLayout {
        id: csld
        property string title: ""
        property real minVal: 0
        property real maxVal: 100
        property real value: 0
        property string unit: ""
        property int decimals: 0
        signal changed(real newVal)

        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: csld.title
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textColor
            }
            Item { Layout.fillWidth: true }
            Text {
                text: csld.decimals > 0 ? csld.value.toFixed(csld.decimals) + csld.unit : Math.round(csld.value) + csld.unit
                font.family: Theme.monoFamily
                font.pixelSize: 11
                color: Theme.primary
            }
        }

        Item {
            id: ctrack
            Layout.fillWidth: true
            implicitHeight: 22

            readonly property real fraction: Math.max(0, Math.min(1, (csld.value - csld.minVal) / (csld.maxVal - csld.minVal)))

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: Theme.withAlpha(Theme.primary, 0.2)

                Rectangle {
                    width: parent.width * ctrack.fraction
                    height: parent.height
                    radius: 3
                    color: Theme.primary
                }
            }

            Rectangle {
                x: (ctrack.width - width) * ctrack.fraction
                anchors.verticalCenter: parent.verticalCenter
                width: csldArea.pressed || csldArea.containsMouse ? 16 : 12
                height: width
                radius: width / 2
                color: Theme.textColor
                Behavior on width { NumberAnimation { duration: 100 } }
            }

            MouseArea {
                id: csldArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                preventStealing: true

                function updateVal(mx) {
                    const frac = Math.max(0, Math.min(1, mx / ctrack.width));
                    const raw = csld.minVal + frac * (csld.maxVal - csld.minVal);
                    const finalVal = csld.decimals > 0 ? parseFloat(raw.toFixed(csld.decimals)) : Math.round(raw);
                    csld.changed(finalVal);
                }

                onPressed: mouse => updateVal(mouse.x)
                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x); }
                onWheel: wheel => {
                    const step = (csld.maxVal - csld.minVal) / 20;
                    const delta = wheel.angleDelta.y > 0 ? step : -step;
                    const raw = Math.max(csld.minVal, Math.min(csld.maxVal, csld.value + delta));
                    const finalVal = csld.decimals > 0 ? parseFloat(raw.toFixed(csld.decimals)) : Math.round(raw);
                    csld.changed(finalVal);
                }
            }
        }
    }

    component CfgToggle: RowLayout {
        id: csw
        property string title: ""
        property string subtitle: ""
        property bool checked: false
        signal toggled(bool nextVal)

        Layout.fillWidth: true
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                text: csw.title
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textColor
            }
            Text {
                visible: csw.subtitle !== ""
                text: csw.subtitle
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.subtext
            }
        }

        Rectangle {
            implicitWidth: 38
            implicitHeight: 20
            radius: 10
            color: csw.checked ? Theme.primary : Theme.tileHigh

            Rectangle {
                width: 14; height: 14; radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: csw.checked ? parent.width - width - 3 : 3
                color: Theme.textColor
                Behavior on x { NumberAnimation { duration: 140 } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: csw.toggled(!csw.checked)
            }
        }
    }

    component SectionHeader: ColumnLayout {
        property string title: ""
        property string subtitle: ""
        Layout.fillWidth: true
        spacing: 2

        Text {
            text: parent.title
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Theme.textColor
        }
        Text {
            visible: parent.subtitle !== ""
            text: parent.subtitle
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.subtext
        }
    }

    component ActionBtn: Rectangle {
        id: abtn
        property string icon: ""
        property string text: ""
        property bool primary: false
        signal clicked()

        implicitHeight: 34
        implicitWidth: btnRow.implicitWidth + 24
        radius: 8
        color: abtn.primary ? (abtnArea.pressed ? Theme.withAlpha(Theme.primary, 0.7) : Theme.primary)
                            : (abtnArea.pressed ? Theme.tileHigh : (abtnArea.containsMouse ? Theme.tileHigh : Theme.tile))
        border.width: 1
        border.color: abtn.primary ? Theme.primary : Theme.withAlpha(Theme.outline, 0.25)

        RowLayout {
            id: btnRow
            anchors.centerIn: parent
            spacing: 8

            Text {
                visible: abtn.icon !== ""
                text: abtn.icon
                font.family: Theme.iconFontFamily
                font.pixelSize: 14
                color: abtn.primary ? Theme.background : Theme.textColor
            }
            Text {
                text: abtn.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.Medium
                color: abtn.primary ? Theme.background : Theme.textColor
            }
        }

        MouseArea {
            id: abtnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: abtn.clicked()
        }
    }

    // ================= FUNDO ESCURECIDO =================
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, win.open ? 0.45 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea {
            anchors.fill: parent
            onClicked: win.open = false
        }
    }

    // ================= CARTÃO PRINCIPAL (SIDEBAR + CONTEÚDO) =================
    Rectangle {
        id: card
        width: 960
        height: 630
        anchors.centerIn: parent
        radius: 22
        color: Theme.surface
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.3)
        focus: win.open
        Keys.onEscapePressed: win.open = false

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent } // não fechar ao clicar dentro

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ==================== LADO ESQUERDO: BARRA LATERAL ====================
            Rectangle {
                Layout.preferredWidth: 230
                Layout.fillHeight: true
                topLeftRadius: 22
                bottomLeftRadius: 22
                color: Theme.withAlpha(Theme.background, 0.5)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    // Cabeçalho do Painel
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 10
                            color: Theme.withAlpha(Theme.primary, 0.2)

                            Text {
                                anchors.centerIn: parent
                                text: Theme.icons.tune
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 18
                                color: Theme.primary
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: "Painel Rice"
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                color: Theme.textColor
                            }
                            Text {
                                text: "Configurações Gráficas"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.subtext
                            }
                        }
                    }

                    // Divisor
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Theme.withAlpha(Theme.outline, 0.15)
                    }

                    // Lista de Categorias
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: navCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: navCol
                            width: parent.width
                            spacing: 4

                            readonly property var navItems: [
                                { name: "Fastfetch", icon: Theme.icons.packages, desc: "Logo & Módulos" },
                                { name: "Kitty Terminal", icon: Theme.icons.console, desc: "Fonte & Opacidade" },
                                { name: "Notificações", icon: Theme.icons.bell, desc: "Posição & Estilo" },
                                { name: "Tela & Monitores", icon: Theme.icons.monitor, desc: "144Hz & Brilho" },
                                { name: "Teclado & Mouse", icon: Theme.icons.tune, desc: "Layout & Sensibilidade" },
                                { name: "Cores & Wallust", icon: Theme.icons.palette, desc: "Paleta Dinâmica" },
                                { name: "Efeitos & Janelas", icon: Theme.icons.laptop, desc: "Bordas & SDDM" },
                                { name: "Sistema & Reparo", icon: Theme.icons.health, desc: "Auto-reparo & Áudio" }
                            ]

                            Repeater {
                                model: navCol.navItems
                                delegate: Rectangle {
                                    id: navDelegate
                                    required property var modelData
                                    required property int index

                                    Layout.fillWidth: true
                                    implicitHeight: 46
                                    radius: 10
                                    color: win.currentTab === index
                                        ? Theme.withAlpha(Theme.primary, 0.22)
                                        : (navItemArea.containsMouse ? Theme.tileHigh : "transparent")
                                    border.width: win.currentTab === index ? 1 : 0
                                    border.color: Theme.primary

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        Text {
                                            text: navDelegate.modelData.icon
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 17
                                            color: win.currentTab === navDelegate.index ? Theme.primary : Theme.subtext
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            Text {
                                                text: navDelegate.modelData.name
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.weight: win.currentTab === navDelegate.index ? Font.DemiBold : Font.Normal
                                                color: win.currentTab === navDelegate.index ? Theme.textColor : Theme.textColor
                                            }

                                            Text {
                                                text: navDelegate.modelData.desc
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 9
                                                color: win.currentTab === navDelegate.index ? Theme.primary : Theme.subtext
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: navItemArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.currentTab = navDelegate.index
                                    }
                                }
                            }
                        }
                    }

                    // Rodapé da Sidebar
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 6
                        color: Theme.tile
                        Text {
                            anchors.centerIn: parent
                            text: "Hyprland Lua · Quickshell"
                            font.family: Theme.monoFamily
                            font.pixelSize: 10
                            color: Theme.subtext
                        }
                    }
                }
            }

            // Divisor Vertical
            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Theme.withAlpha(Theme.outline, 0.2)
            }

            // ==================== LADO DIREITO: ÁREA DE CONTEÚDO ====================
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    // Cabeçalho da Aba Ativa + Botão Fechar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: [
                                    "Fastfetch & Terminal Fetch",
                                    "Kitty Terminal & Tipografia",
                                    "Mako Notificações",
                                    "Monitores & Exibição",
                                    "Teclado, Mouse & Entradas",
                                    "Cores & Wallust Dinâmico",
                                    "Efeitos Visuais, Bordas & SDDM",
                                    "Sistema & Manutenção Rápida"
                                ][win.currentTab] || "Configurações"
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: Theme.textColor
                            }

                            Text {
                                text: [
                                    "Personalize o logo, dimensões e informações mostradas no terminal.",
                                    "Ajuste opacidade, tamanho de texto, espaçamento interno e cursor.",
                                    "Escolha a posição na tela, tempo de exibição e bordas das notificações.",
                                    "Controle taxa de atualização (144Hz/60Hz), FreeSync/VRR e brilho.",
                                    "Seletor de layout ABNT2/US, sensibilidade do mouse e perfil de aceleração.",
                                    "Visualize a paleta de 16 cores ativas do wallpaper e copie códigos HEX.",
                                    "Luz noturna, transparência inativa, cantos arredondados, animações e login.",
                                    "Auto-reparo com 1 clique: reiniciar áudio, destravar pacman e limpar caches."
                                ][win.currentTab] || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.subtext
                            }
                        }

                        // Toast de aviso se ativo
                        Rectangle {
                            visible: win.toastMsg !== ""
                            implicitHeight: 28
                            implicitWidth: toastLabel.implicitWidth + 20
                            radius: 14
                            color: Theme.primary

                            Text {
                                id: toastLabel
                                anchors.centerIn: parent
                                text: win.toastMsg
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: Theme.background
                            }
                        }

                        // Botão Fechar
                        Rectangle {
                            implicitWidth: 32
                            implicitHeight: 32
                            radius: 16
                            color: closeArea.containsMouse ? Theme.tileHigh : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: Theme.icons.close
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 16
                                color: Theme.textColor
                            }

                            MouseArea {
                                id: closeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.open = false
                            }
                        }
                    }

                    // Divisor
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Theme.withAlpha(Theme.outline, 0.15)
                    }

                    // Container dos Conteúdos
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // ==================== ABA 0: FASTFETCH ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 0
                            contentHeight: ffContentCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: ffContentCol
                                width: parent.width
                                spacing: 16

                                RowLayout {
                                    Layout.fillWidth: true
                                    SectionHeader {
                                        title: "Logo & Imagens do Fastfetch"
                                        subtitle: "Imagens detectadas em ~/Imagens/FastFetch"
                                    }
                                    Item { Layout.fillWidth: true }
                                    ActionBtn {
                                        icon: Theme.icons.laptop
                                        text: "Abrir Pasta"
                                        onClicked: Quickshell.execDetached(["dolphin", "/home/val47/Imagens/FastFetch"])
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        Layout.preferredWidth: 130
                                        Layout.preferredHeight: 110
                                        radius: Theme.tileRadius
                                        color: win.ffCurrentLogo === "" || win.ffCurrentLogo === "arch"
                                            ? Theme.withAlpha(Theme.primary, 0.25)
                                            : (archArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                        border.width: win.ffCurrentLogo === "" || win.ffCurrentLogo === "arch" ? 1.5 : 0
                                        border.color: Theme.primary

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: Theme.icons.arch
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 38
                                                color: win.ffCurrentLogo === "" || win.ffCurrentLogo === "arch" ? Theme.primary : Theme.subtext
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: "Arch Padrão"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                color: Theme.textColor
                                            }
                                        }

                                        MouseArea {
                                            id: archArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                win.ffCurrentLogo = "arch";
                                                Quickshell.execDetached(["rice-fastfetch-apply", "set-logo", "arch"]);
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: win.ffImages
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.preferredWidth: 130
                                            Layout.preferredHeight: 110
                                            radius: Theme.tileRadius
                                            color: win.ffCurrentLogo === modelData.path
                                                ? Theme.withAlpha(Theme.primary, 0.25)
                                                : (imgArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: win.ffCurrentLogo === modelData.path ? 1.5 : 0
                                            border.color: Theme.primary

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 4
                                                Item {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    Image {
                                                        anchors.fill: parent
                                                        source: "file://" + parent.parent.parent.modelData.path
                                                        fillMode: Image.PreserveAspectFit
                                                        mipmap: true
                                                        asynchronous: true
                                                    }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: parent.parent.modelData.name
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideMiddle
                                                    color: win.ffCurrentLogo === parent.parent.modelData.path ? Theme.primary : Theme.subtext
                                                }
                                            }

                                            MouseArea {
                                                id: imgArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.ffCurrentLogo = parent.modelData.path;
                                                    Quickshell.execDetached(["rice-fastfetch-apply", "set-logo", parent.modelData.path]);
                                                }
                                            }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20
                                    CfgSlider {
                                        title: "Largura do Logo (Colunas)"
                                        minVal: 15; maxVal: 50; value: win.ffWidth; unit: " col"
                                        onChanged: newVal => {
                                            win.ffWidth = Math.round(newVal);
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-fastfetch-apply", "set-size", String(win.ffWidth), String(win.ffHeight)]);
                                            });
                                        }
                                    }
                                    CfgSlider {
                                        title: "Altura do Logo (Linhas)"
                                        minVal: 8; maxVal: 32; value: win.ffHeight; unit: " lin"
                                        onChanged: newVal => {
                                            win.ffHeight = Math.round(newVal);
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-fastfetch-apply", "set-size", String(win.ffWidth), String(win.ffHeight)]);
                                            });
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Módulos de Sistema Exibidos"
                                    subtitle: "Clique para ativar ou ocultar cada informação no Fastfetch"
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Repeater {
                                        model: [
                                            { key: "os", label: "Sistema (OS)", icon: Theme.icons.arch },
                                            { key: "host", label: "Máquina", icon: Theme.icons.laptop },
                                            { key: "kernel", label: "Kernel", icon: Theme.icons.chip },
                                            { key: "uptime", label: "Tempo de Atividade", icon: Theme.icons.clock },
                                            { key: "packages", label: "Pacotes", icon: Theme.icons.packages },
                                            { key: "shell", label: "Shell", icon: Theme.icons.console },
                                            { key: "display", label: "Tela & Resolução", icon: Theme.icons.monitor },
                                            { key: "de", label: "Ambiente (DE)", icon: Theme.icons.dashboard },
                                            { key: "wm", label: "Compositor (WM)", icon: Theme.icons.workspaces },
                                            { key: "theme", label: "Tema & Cores", icon: Theme.icons.palette },
                                            { key: "icons", label: "Ícones", icon: Theme.icons.tune },
                                            { key: "terminal", label: "Terminal", icon: Theme.icons.console },
                                            { key: "cpu", label: "Processador (CPU)", icon: Theme.icons.cpu },
                                            { key: "gpu", label: "Placa de Vídeo (GPU)", icon: Theme.icons.gpu },
                                            { key: "memory", label: "Memória RAM", icon: Theme.icons.memory },
                                            { key: "swap", label: "Swap / zRAM", icon: Theme.icons.disk },
                                            { key: "disk", label: "Armazenamento", icon: Theme.icons.disk }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool active: win.ffActiveModules.indexOf(modelData.key) !== -1
                                            implicitHeight: 30
                                            implicitWidth: modRow.implicitWidth + 18
                                            radius: 8
                                            color: active ? Theme.withAlpha(Theme.primary, 0.22) : Theme.tile
                                            border.width: active ? 1 : 0
                                            border.color: Theme.primary

                                            RowLayout {
                                                id: modRow
                                                anchors.centerIn: parent
                                                spacing: 6
                                                Text {
                                                    text: parent.parent.modelData.icon
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 12
                                                    color: parent.parent.active ? Theme.primary : Theme.subtext
                                                }
                                                Text {
                                                    text: parent.parent.modelData.label
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    color: parent.parent.active ? Theme.textColor : Theme.subtext
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-fastfetch-apply", "toggle-module", parent.modelData.key]);
                                                    const idx = win.ffActiveModules.indexOf(parent.modelData.key);
                                                    if (idx !== -1) win.ffActiveModules.splice(idx, 1);
                                                    else win.ffActiveModules.push(parent.modelData.key);
                                                    win.ffActiveModules = [].concat(win.ffActiveModules);
                                                }
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    ActionBtn {
                                        icon: Theme.icons.console
                                        text: "Visualizar no Terminal (Kitty)"
                                        primary: true
                                        onClicked: Quickshell.execDetached(["rice-fastfetch-apply", "run"])
                                    }
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: "Restaurar Padrões"
                                        onClicked: {
                                            Quickshell.execDetached(["rice-fastfetch-apply", "reset"]);
                                            loadFFProc.running = true;
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }

                        // ==================== ABA 1: KITTY TERMINAL ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 1
                            contentHeight: kittyCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: kittyCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Aparência & Tipografia"
                                    subtitle: "Ajuste em tempo real da opacidade e legibilidade do terminal Kitty"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20
                                    CfgSlider {
                                        title: "Opacidade de Fundo"
                                        minVal: 0.3; maxVal: 1.0; value: win.kittyOpacity; decimals: 2
                                        onChanged: newVal => {
                                            win.kittyOpacity = newVal;
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-kitty-apply", "set", "opacity", String(win.kittyOpacity)]);
                                            });
                                        }
                                    }
                                    CfgSlider {
                                        title: "Tamanho da Fonte"
                                        minVal: 8; maxVal: 20; value: win.kittyFontSize; decimals: 1; unit: " pt"
                                        onChanged: newVal => {
                                            win.kittyFontSize = newVal;
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-kitty-apply", "set", "font_size", String(win.kittyFontSize)]);
                                            });
                                        }
                                    }
                                }

                                CfgSlider {
                                    title: "Espaçamento Interno (Margem / Padding)"
                                    minVal: 0; maxVal: 32; value: win.kittyPadding; unit: " px"
                                    onChanged: newVal => {
                                        win.kittyPadding = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-kitty-apply", "set", "padding", String(win.kittyPadding)]);
                                        });
                                    }
                                }

                                SectionHeader {
                                    title: "Estilo do Cursor & Efeitos"
                                    subtitle: "Formato do ponteiro e comportamento de áudio"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    Repeater {
                                        model: [
                                            { id: "beam", name: "Linha Vertical (Beam)", icon: Theme.icons.cursor },
                                            { id: "block", name: "Bloco Sólido (Block)", icon: Theme.icons.dashboard },
                                            { id: "underline", name: "Sublinhado (Underline)", icon: Theme.icons.timer }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool active: win.kittyCursor === modelData.id
                                            Layout.fillWidth: true
                                            implicitHeight: 38
                                            radius: 10
                                            color: active ? Theme.withAlpha(Theme.primary, 0.22) : (curArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: active ? 1.5 : 0
                                            border.color: Theme.primary

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 6
                                                Text {
                                                    text: parent.parent.modelData.icon
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 13
                                                    color: parent.parent.active ? Theme.primary : Theme.subtext
                                                }
                                                Text {
                                                    text: parent.parent.modelData.name
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    font.weight: parent.parent.active ? Font.DemiBold : Font.Normal
                                                    color: parent.parent.active ? Theme.textColor : Theme.subtext
                                                }
                                            }

                                            MouseArea {
                                                id: curArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.kittyCursor = parent.modelData.id;
                                                    Quickshell.execDetached(["rice-kitty-apply", "set", "cursor", parent.modelData.id]);
                                                }
                                            }
                                        }
                                    }
                                }

                                CfgToggle {
                                    title: "Desfoque de Fundo (Background Blur)"
                                    subtitle: "Ativa efeito de vidro fosco atrás do terminal (Hyprland)"
                                    checked: win.kittyBlur
                                    onToggled: nv => {
                                        win.kittyBlur = nv;
                                        Quickshell.execDetached(["rice-kitty-apply", "set", "blur", nv ? "1" : "0"]);
                                    }
                                }

                                CfgToggle {
                                    title: "Sino Sonoro (Audio Bell)"
                                    subtitle: "Toca bipe do sistema ao atingir o limite ou cometer erro"
                                    checked: win.kittyBell
                                    onToggled: nv => {
                                        win.kittyBell = nv;
                                        Quickshell.execDetached(["rice-kitty-apply", "set", "bell", nv ? "1" : "0"]);
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    ActionBtn {
                                        icon: Theme.icons.console
                                        text: "Abrir Novo Terminal Kitty"
                                        primary: true
                                        onClicked: Quickshell.execDetached(["kitty"])
                                    }
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: "Restaurar Padrões"
                                        onClicked: {
                                            Quickshell.execDetached(["rice-kitty-apply", "reset"]);
                                            loadKittyProc.running = true;
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }

                        // ==================== ABA 2: NOTIFICAÇÕES (MAKO) ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 2
                            contentHeight: makoCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: makoCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Posição na Tela"
                                    subtitle: "Escolha onde os banners de notificação devem surgir"
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 3
                                    rowSpacing: 8
                                    columnSpacing: 8

                                    Repeater {
                                        model: [
                                            { id: "top-left", name: "Canto Superior Esquerdo" },
                                            { id: "top-center", name: "Superior Centro" },
                                            { id: "top-right", name: "Canto Superior Direito (Padrão)" },
                                            { id: "bottom-left", name: "Canto Inferior Esquerdo" },
                                            { id: "bottom-center", name: "Inferior Centro" },
                                            { id: "bottom-right", name: "Canto Inferior Direito" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool active: win.makoAnchor === modelData.id
                                            Layout.fillWidth: true
                                            implicitHeight: 38
                                            radius: 10
                                            color: active ? Theme.withAlpha(Theme.primary, 0.22) : (posArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: active ? 1.5 : 0
                                            border.color: Theme.primary

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 6
                                                Text {
                                                    text: Theme.icons.bell
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 13
                                                    color: parent.parent.active ? Theme.primary : Theme.subtext
                                                }
                                                Text {
                                                    text: parent.parent.modelData.name
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    font.weight: parent.parent.active ? Font.DemiBold : Font.Normal
                                                    color: parent.parent.active ? Theme.textColor : Theme.subtext
                                                }
                                            }

                                            MouseArea {
                                                id: posArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.makoAnchor = parent.modelData.id;
                                                    Quickshell.execDetached(["rice-mako-apply", "set", "anchor", parent.modelData.id]);
                                                }
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Comportamento & Geometria"
                                    subtitle: "Tempo de exibição, bordas e arredondamento dos banners"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20
                                    CfgSlider {
                                        title: "Tempo em Tela (Timeout)"
                                        minVal: 2; maxVal: 20; value: win.makoTimeout; unit: " s"
                                        onChanged: newVal => {
                                            win.makoTimeout = Math.round(newVal);
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-mako-apply", "set", "timeout", String(win.makoTimeout)]);
                                            });
                                        }
                                    }
                                    CfgSlider {
                                        title: "Arredondamento dos Cantos"
                                        minVal: 0; maxVal: 20; value: win.makoRadius; unit: " px"
                                        onChanged: newVal => {
                                            win.makoRadius = Math.round(newVal);
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-mako-apply", "set", "radius", String(win.makoRadius)]);
                                            });
                                        }
                                    }
                                }

                                CfgSlider {
                                    title: "Espessura da Borda"
                                    minVal: 0; maxVal: 6; value: win.makoBorder; unit: " px"
                                    onChanged: newVal => {
                                        win.makoBorder = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-mako-apply", "set", "border_size", String(win.makoBorder)]);
                                        });
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    ActionBtn {
                                        icon: Theme.icons.bell
                                        text: "Enviar Notificação de Teste"
                                        primary: true
                                        onClicked: Quickshell.execDetached(["rice-mako-apply", "test"])
                                    }
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: "Restaurar Padrões"
                                        onClicked: {
                                            Quickshell.execDetached(["rice-mako-apply", "reset"]);
                                            loadMakoProc.running = true;
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }

                        // ==================== ABA 3: TELA & MONITORES ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 3
                            contentHeight: displayCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: displayCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Monitor Principal Detectado"
                                    subtitle: "Informações de hardware e resolução da tela ativa"
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 70
                                    radius: 12
                                    color: Theme.tile
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.outline, 0.2)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 14

                                        Rectangle {
                                            implicitWidth: 42
                                            implicitHeight: 42
                                            radius: 10
                                            color: Theme.withAlpha(Theme.primary, 0.2)
                                            Text {
                                                anchors.centerIn: parent
                                                text: Theme.icons.monitor
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 22
                                                color: Theme.primary
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            RowLayout {
                                                spacing: 8
                                                Text {
                                                    text: win.monitorName + " · " + win.monitorRes
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 14
                                                    font.weight: Font.Bold
                                                    color: Theme.textColor
                                                }
                                                Rectangle {
                                                    implicitHeight: 20
                                                    implicitWidth: hzBadge.implicitWidth + 12
                                                    radius: 10
                                                    color: Theme.primary
                                                    Text {
                                                        id: hzBadge
                                                        anchors.centerIn: parent
                                                        text: win.monitorHz + " Hz Ativo"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        font.weight: Font.Bold
                                                        color: Theme.background
                                                    }
                                                }
                                            }
                                            Text {
                                                text: win.monitorModel
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.subtext
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Taxa de Atualização da Tela (Frequência)"
                                    subtitle: "Alterne instantaneamente entre máxima fluidez para jogos ou economia de energia"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    // Card 144Hz
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 72
                                        radius: 12
                                        color: win.monitorHz === 144 ? Theme.withAlpha(Theme.primary, 0.22) : (hz144Area.containsMouse ? Theme.tileHigh : Theme.tile)
                                        border.width: win.monitorHz === 144 ? 1.5 : 0
                                        border.color: Theme.primary

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12
                                            Text {
                                                text: Theme.icons.lightning
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 22
                                                color: win.monitorHz === 144 ? Theme.primary : Theme.subtext
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: "144 Hz (Ultra Suave & Jogos)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Máxima fluidez de animações e menor latência de entrada."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: hz144Area
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                win.monitorHz = 144;
                                                Quickshell.execDetached(["rice-hypr-prefs", "set", "monitor_hz", "144"]);
                                                win.showToast("Taxa ajustada para 144 Hz");
                                            }
                                        }
                                    }

                                    // Card 60Hz
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 72
                                        radius: 12
                                        color: win.monitorHz === 60 ? Theme.withAlpha(Theme.primary, 0.22) : (hz60Area.containsMouse ? Theme.tileHigh : Theme.tile)
                                        border.width: win.monitorHz === 60 ? 1.5 : 0
                                        border.color: Theme.primary

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12
                                            Text {
                                                text: Theme.icons.saver
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 22
                                                color: win.monitorHz === 60 ? Theme.primary : Theme.subtext
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: "60 Hz (Economia de Energia)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Reduz o consumo da GPU integrada e poupa bateria."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: hz60Area
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                win.monitorHz = 60;
                                                Quickshell.execDetached(["rice-hypr-prefs", "set", "monitor_hz", "60"]);
                                                win.showToast("Taxa ajustada para 60 Hz");
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Sincronização & Tearing"
                                    subtitle: "Elimina cortes visuais (tearing) adaptando os frames à taxa do monitor"
                                }

                                CfgToggle {
                                    title: "VRR / FreeSync Adaptativo (Variable Refresh Rate)"
                                    subtitle: "Ajusta dinamicamente a taxa de atualização do monitor conforme os FPS dos jogos."
                                    checked: win.vrrEnabled
                                    onToggled: nv => {
                                        win.vrrEnabled = nv;
                                        Quickshell.execDetached(["rice-hypr-prefs", "set", "vrr", nv ? "1" : "0"]);
                                        win.showToast(nv ? "VRR ativado" : "VRR desativado");
                                    }
                                }

                                SectionHeader {
                                    title: "Brilho do Painel"
                                    subtitle: "Ajuste suave de iluminação da tela interna (backlight)"
                                }

                                CfgSlider {
                                    title: "Nível de Brilho da Tela"
                                    minVal: 5; maxVal: 100; value: win.screenBrightness; unit: "%"
                                    onChanged: newVal => {
                                        win.screenBrightness = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["brightnessctl", "set", win.screenBrightness + "%"]);
                                        });
                                    }
                                }
                            }
                        }

                        // ==================== ABA 4: TECLADO & MOUSE ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 4
                            contentHeight: inputCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: inputCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Layout do Teclado"
                                    subtitle: "Alterne instantaneamente o mapa de teclas sem precisar reiniciar a sessão"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    // ABNT2
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 64
                                        radius: 12
                                        color: win.kbLayout === "br" ? Theme.withAlpha(Theme.primary, 0.22) : (abntArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                        border.width: win.kbLayout === "br" ? 1.5 : 0
                                        border.color: Theme.primary

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12
                                            Text {
                                                text: "🇧🇷"
                                                font.pixelSize: 24
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: "Português Brasil (ABNT2)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Teclado padrão com tecla 'Ç' física dedicada."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: abntArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                win.kbLayout = "br";
                                                Quickshell.execDetached(["rice-hypr-prefs", "set", "kb_layout", "br"]);
                                                win.showToast("Teclado definido para ABNT2 (Brasil)");
                                            }
                                        }
                                    }

                                    // US Intl
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 64
                                        radius: 12
                                        color: win.kbLayout === "us" ? Theme.withAlpha(Theme.primary, 0.22) : (usArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                        border.width: win.kbLayout === "us" ? 1.5 : 0
                                        border.color: Theme.primary

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12
                                            Text {
                                                text: "🇺🇸"
                                                font.pixelSize: 24
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: "Inglês Internacional (US Intl)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Padrão americano com dead keys (' + c = ç, ~ + a = ã)."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: usArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                win.kbLayout = "us";
                                                Quickshell.execDetached(["rice-hypr-prefs", "set", "kb_layout", "us"]);
                                                win.showToast("Teclado definido para US Internacional");
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Sensibilidade & Velocidade do Mouse"
                                    subtitle: "Ajuste preciso de -1.0 a +1.0 (0.0 = velocidade nativa do sensor)"
                                }

                                CfgSlider {
                                    title: "Velocidade do Ponteiro"
                                    minVal: -1.0; maxVal: 1.0; value: win.mouseSensitivity; decimals: 2
                                    onChanged: newVal => {
                                        win.mouseSensitivity = newVal;
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-hypr-prefs", "set", "mouse_sensitivity", String(win.mouseSensitivity)]);
                                        });
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: "Redefinir Sensibilidade Neutra (0.0)"
                                        onClicked: {
                                            win.mouseSensitivity = 0.0;
                                            Quickshell.execDetached(["rice-hypr-prefs", "set", "mouse_sensitivity", "0.0"]);
                                            win.showToast("Sensibilidade redefinida para 0.0");
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                SectionHeader {
                                    title: "Perfil de Aceleração do Mouse"
                                    subtitle: "Flat elimina aceleração (ideal para mira em jogos); Adaptativo acelera com movimentos rápidos"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    // Flat
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 64
                                        radius: 12
                                        color: win.mouseAccel === "flat" ? Theme.withAlpha(Theme.primary, 0.22) : (flatArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                        border.width: win.mouseAccel === "flat" ? 1.5 : 0
                                        border.color: Theme.primary

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12
                                            Text {
                                                text: Theme.icons.gamepad
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 22
                                                color: win.mouseAccel === "flat" ? Theme.primary : Theme.subtext
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: "Flat (Sem Aceleração - 1:1)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Movimento previsível e consistente. Essencial para jogos (FPS)."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: flatArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                win.mouseAccel = "flat";
                                                Quickshell.execDetached(["rice-hypr-prefs", "set", "mouse_accel", "flat"]);
                                                win.showToast("Perfil de mouse: Flat (Sem aceleração)");
                                            }
                                        }
                                    }

                                    // Adaptive
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 64
                                        radius: 12
                                        color: win.mouseAccel === "adaptive" ? Theme.withAlpha(Theme.primary, 0.22) : (adaptArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                        border.width: win.mouseAccel === "adaptive" ? 1.5 : 0
                                        border.color: Theme.primary

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12
                                            Text {
                                                text: Theme.icons.cursor
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 22
                                                color: win.mouseAccel === "adaptive" ? Theme.primary : Theme.subtext
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: "Adaptativo (Com Aceleração)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Aumenta a velocidade em gestos rápidos. Padrão confortável."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: adaptArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                win.mouseAccel = "adaptive";
                                                Quickshell.execDetached(["rice-hypr-prefs", "set", "mouse_accel", "adaptive"]);
                                                win.showToast("Perfil de mouse: Adaptativo");
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Comportamento de Inicialização"
                                    subtitle: "Opções de inicialização automática de hardware"
                                }

                                CfgToggle {
                                    title: "NumLock Ativado no Boot"
                                    subtitle: "Habilita o teclado numérico automaticamente assim que a sessão do Hyprland inicia."
                                    checked: win.numlock
                                    onToggled: nv => {
                                        win.numlock = nv;
                                        Quickshell.execDetached(["rice-hypr-prefs", "set", "numlock", String(nv)]);
                                        win.showToast(nv ? "NumLock ativado por padrão" : "NumLock desativado por padrão");
                                    }
                                }
                            }
                        }

                        // ==================== ABA 5: CORES & WALLUST ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 5
                            contentHeight: colorsCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: colorsCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Paleta Dinâmica Extraída do Wallpaper"
                                    subtitle: "Todas as cores da interface e terminal são geradas pelo Wallust a partir do papel de parede ativo"
                                }

                                // Destaques Principais
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Repeater {
                                        model: [
                                            { label: "Fundo", hex: win.wallustColors.background || "#170D0C" },
                                            { label: "Texto", hex: win.wallustColors.foreground || "#C2A6A5" },
                                            { label: "Destaque 1", hex: win.wallustColors.color4 || "#5D1D1D" },
                                            { label: "Destaque 2", hex: win.wallustColors.color10 || "#A62727" }
                                        ]
                                        delegate: Rectangle {
                                            id: colorCard
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 60
                                            radius: 10
                                            color: Theme.tile
                                            border.width: 1
                                            border.color: Theme.withAlpha(Theme.outline, 0.2)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 10
                                                Rectangle {
                                                    implicitWidth: 36
                                                    implicitHeight: 36
                                                    radius: 18
                                                    color: colorCard.modelData.hex
                                                    border.width: 1
                                                    border.color: Theme.withAlpha(Theme.outline, 0.3)
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    Text {
                                                        text: colorCard.modelData.label
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        color: Theme.subtext
                                                    }
                                                    Text {
                                                        text: colorCard.modelData.hex
                                                        font.family: Theme.monoFamily
                                                        font.pixelSize: 12
                                                        font.weight: Font.DemiBold
                                                        color: Theme.textColor
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Quickshell.execDetached(["wl-copy", colorCard.modelData.hex]);
                                                    win.showToast("Copiado: " + colorCard.modelData.hex);
                                                }
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Paleta Completa de 16 Cores ANSI"
                                    subtitle: "Clique em qualquer cor para copiar o código HEX para a área de transferência"
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 8
                                    rowSpacing: 10
                                    columnSpacing: 10

                                    Repeater {
                                        model: 16
                                        delegate: Rectangle {
                                            required property int modelData
                                            readonly property string hex: win.wallustColors["color" + modelData] || "#333333"
                                            Layout.fillWidth: true
                                            implicitHeight: 52
                                            radius: 8
                                            color: colorChipArea.containsMouse ? Theme.tileHigh : Theme.tile
                                            border.width: 1
                                            border.color: colorChipArea.containsMouse ? Theme.primary : Theme.withAlpha(Theme.outline, 0.15)

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 4

                                                Rectangle {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    radius: 11
                                                    color: parent.parent.hex
                                                    border.width: 1
                                                    border.color: Theme.withAlpha(Theme.outline, 0.3)
                                                }

                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: "c" + parent.parent.modelData
                                                    font.family: Theme.monoFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }

                                            MouseArea {
                                                id: colorChipArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Quickshell.execDetached(["wl-copy", parent.hex]);
                                                    win.showToast("Copiado c" + parent.modelData + ": " + parent.hex);
                                                }
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Ações de Wallpaper & Sincronização"
                                    subtitle: "Alterne papéis de parede animados ou regenere a paleta do sistema"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ActionBtn {
                                        icon: Theme.icons.palette
                                        text: "Regenerar Cores do Wallpaper Atual"
                                        primary: true
                                        onClicked: {
                                            Quickshell.execDetached(["rice-wallust-refresh"]);
                                            refreshColorsTimer.restart();
                                            win.showToast("Regenerando cores do Wallust...");
                                        }
                                    }

                                    ActionBtn {
                                        icon: Theme.icons.dashboard
                                        text: "Abrir Seletor de Wallpapers (Super + S)"
                                        onClicked: {
                                            win.open = false;
                                            Quickshell.execDetached(["waywallen-switcher"]);
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }
                                Timer {
                                    id: refreshColorsTimer
                                    interval: 1200
                                    onTriggered: loadWallustColorsProc.running = true
                                }
                            }
                        }

                        // ==================== ABA 6: EFEITOS VISUAIS & JANELAS ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 6
                            contentHeight: effCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: effCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Luz Noturna (Filtro de Luz Azul)"
                                    subtitle: "Reduz o cansaço visual ajustando a temperatura de cor da tela"
                                }

                                CfgToggle {
                                    title: "Ativar Luz Noturna"
                                    subtitle: "Aplica filtro quente instantaneamente via hyprsunset"
                                    checked: win.nightlightActive
                                    onToggled: nv => {
                                        win.nightlightActive = nv;
                                        Quickshell.execDetached(["rice-nightlight", "toggle"]);
                                    }
                                }

                                CfgSlider {
                                    title: "Temperatura de Cor"
                                    minVal: 2500; maxVal: 6500; value: win.nightlightTemp; unit: " K"
                                    onChanged: newVal => {
                                        win.nightlightTemp = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-nightlight", "set", String(win.nightlightTemp)]);
                                        });
                                    }
                                }

                                SectionHeader {
                                    title: "Foco & Janelas Inativas"
                                    subtitle: "Escurece as janelas que não estão recebendo comandos no momento"
                                }

                                CfgToggle {
                                    title: "Escurecer Janelas Inativas (Dim Inactive)"
                                    subtitle: "Destaca a janela atualmente em uso escurecendo as janelas de fundo"
                                    checked: win.dimInactive
                                    onToggled: nv => {
                                        win.dimInactive = nv;
                                        Quickshell.execDetached(["rice-hypr-prefs", "set", "dim_inactive", nv ? "true" : "false"]);
                                    }
                                }

                                CfgSlider {
                                    title: "Intensidade do Escurecimento (Dim Strength)"
                                    minVal: 0.05; maxVal: 0.50; value: win.dimStrength; decimals: 2
                                    onChanged: newVal => {
                                        win.dimStrength = newVal;
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-hypr-prefs", "set", "dim_strength", String(win.dimStrength)]);
                                        });
                                    }
                                }

                                SectionHeader {
                                    title: "Geometria do Hyprland"
                                    subtitle: "Curvatura dos cantos e espaçamento entre janelas"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20
                                    CfgSlider {
                                        title: "Arredondamento dos Cantos (Rounding)"
                                        minVal: 0; maxVal: 20; value: win.rounding; unit: " px"
                                        onChanged: newVal => {
                                            win.rounding = Math.round(newVal);
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-hypr-prefs", "set", "rounding", String(win.rounding)]);
                                            });
                                        }
                                    }
                                    CfgSlider {
                                        title: "Espaçamento Interno (Gaps In)"
                                        minVal: 0; maxVal: 18; value: win.gapsIn; unit: " px"
                                        onChanged: newVal => {
                                            win.gapsIn = Math.round(newVal);
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-hypr-prefs", "set", "gaps_in", String(win.gapsIn)]);
                                            });
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Estilo de Animação"
                                    subtitle: "Curvas de Bézier e velocidade para abertura, fechamento e workspaces"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    Repeater {
                                        model: [
                                            { id: "smooth", name: "Suave (Padrão)", desc: "Fluido e equilibrado" },
                                            { id: "bouncy", name: "Elástico (Bouncy)", desc: "Com leve overshoot" },
                                            { id: "snappy", name: "Rápido (Snappy)", desc: "Imediato e seco" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool active: win.animPreset === modelData.id
                                            Layout.fillWidth: true
                                            implicitHeight: 52
                                            radius: 10
                                            color: active ? Theme.withAlpha(Theme.primary, 0.22) : (animArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: active ? 1.5 : 0
                                            border.color: Theme.primary

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 2
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: parent.parent.modelData.name
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: parent.parent.active ? Font.DemiBold : Font.Normal
                                                    color: parent.parent.active ? Theme.textColor : Theme.textColor
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: parent.parent.modelData.desc
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: parent.parent.active ? Theme.primary : Theme.subtext
                                                }
                                            }

                                            MouseArea {
                                                id: animArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.animPreset = parent.modelData.id;
                                                    Quickshell.execDetached(["rice-hypr-prefs", "set", "anim_preset", parent.modelData.id]);
                                                    win.showToast("Estilo de animação: " + parent.modelData.name);
                                                }
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Inicialização & Tela de Login (SDDM & Limine)"
                                    subtitle: "Aplica o tema SilentSDDM e wallpaper suavizado no bootloader do sistema"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ActionBtn {
                                        icon: Theme.icons.verified
                                        text: "Aplicar SDDM e Bootloader Limine"
                                        primary: true
                                        onClicked: {
                                            Quickshell.execDetached([
                                                "kitty", "--title", "Configuração de Login & Bootloader",
                                                "bash", "-c", "echo '==> Digite sua senha para configurar o SDDM e Limine:'; sudo /home/val47/.local/bin/rice-apply-boot-login; echo; read -n 1 -s -r -p '✔ Concluído! Pressione qualquer tecla para fechar...'"
                                            ]);
                                        }
                                    }

                                    ActionBtn {
                                        icon: Theme.icons.laptop
                                        text: "Testar Tela do SDDM em Janela"
                                        onClicked: {
                                            Quickshell.execDetached(["bash", "-c", "sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/SilentSDDM 2>/dev/null || sddm-greeter --test-mode --theme /usr/share/sddm/themes/SilentSDDM"]);
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }

                        // ==================== ABA 7: SISTEMA & REPARO ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 7
                            contentHeight: sysCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: sysCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Auto-Reparo & Soluções Rápidas de Um Clique"
                                    subtitle: "Ferramentas práticas para resolver problemas comuns sem abrir o terminal ou digitar comandos"
                                }

                                // 4 Cartões de Solução Rápida
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    // Card 1: Áudio PipeWire
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 68
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 14

                                            Rectangle {
                                                implicitWidth: 40
                                                implicitHeight: 40
                                                radius: 10
                                                color: Theme.withAlpha(Theme.primary, 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Theme.icons.volHigh
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 20
                                                    color: Theme.primary
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: "Reiniciar Sistema de Áudio (PipeWire)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Se o som parou ou o microfone não responde após conectar um fone/headset."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }

                                            ActionBtn {
                                                icon: Theme.icons.refresh
                                                text: "Reiniciar Áudio"
                                                primary: true
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-maintenance", "audio"]);
                                                    win.showToast("Reiniciando PipeWire e WirePlumber...");
                                                }
                                            }
                                        }
                                    }

                                    // Card 2: Destravar Pacman (db.lck)
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 68
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 14

                                            Rectangle {
                                                implicitWidth: 40
                                                implicitHeight: 40
                                                radius: 10
                                                color: Theme.withAlpha(Theme.primary, 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Theme.icons.lock
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 20
                                                    color: Theme.primary
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: "Destravar Pacman (Remover db.lck)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Resolve o erro 'banco de dados está bloqueado' se o terminal fechou durante um update."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }

                                            ActionBtn {
                                                icon: Theme.icons.verified
                                                text: "Destravar Pacman"
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-maintenance", "unlockpacman"]);
                                                }
                                            }
                                        }
                                    }

                                    // Card 3: Limpeza de Cache & Disco
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 68
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 14

                                            Rectangle {
                                                implicitWidth: 40
                                                implicitHeight: 40
                                                radius: 10
                                                color: Theme.withAlpha(Theme.primary, 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Theme.icons.broom
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 20
                                                    color: Theme.primary
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: "Limpeza de Disco & Caches Antigos"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Remove versões antigas de pacotes do pacman e miniaturas expiradas com segurança."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }

                                            ActionBtn {
                                                icon: Theme.icons.disk
                                                text: "Limpar Caches"
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-maintenance", "cleancache"]);
                                                    win.showToast("Limpando caches do sistema...");
                                                }
                                            }
                                        }
                                    }

                                    // Card 4: Rice Doctor
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 68
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 14

                                            Rectangle {
                                                implicitWidth: 40
                                                implicitHeight: 40
                                                radius: 10
                                                color: Theme.withAlpha(Theme.primary, 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Theme.icons.health
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 20
                                                    color: Theme.primary
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: "Assistente de Diagnóstico (Rice Doctor)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Varredura completa de integridade de áudio, GPU, Waywallen, SDDM e zRAM."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }

                                            ActionBtn {
                                                icon: Theme.icons.console
                                                text: "Executar Rice Doctor"
                                                primary: true
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-maintenance", "doctor"]);
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
        }
    }

    // ================= IPC =================
    IpcHandler {
        target: "visualconfig"
        function toggle(): void { win.open = !win.open; }
        function open(): void { win.open = true; }
        function close(): void { win.open = false; }
        function tab(index: string): void {
            win.currentTab = parseInt(index) || 0;
            win.open = true;
        }
    }
}
