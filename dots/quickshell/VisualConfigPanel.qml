import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "."

// Painel de Configurações Visuais para ferramentas sem GUI nativa:
// - Fastfetch (Logos em ~/Imagens/FastFetch, dimensões, módulos)
// - Kitty Terminal (Opacidade, fonte, padding, blur, cursor, áudio)
// - Mako Notificações (Posição na tela, timeout, bordas, raio, teste)
// - Efeitos & Hyprland (Luz noturna hyprsunset, dim inactive, rounding, gaps, animações)
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
    property int currentTab: 0 // 0: Fastfetch, 1: Kitty, 2: Mako, 3: Efeitos

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

    // Efeitos / Hyprland
    property bool nightlightActive: false
    property int nightlightTemp: 4500
    property bool dimInactive: false
    property real dimStrength: 0.2
    property int rounding: 8
    property int gapsIn: 6
    property string animPreset: "bouncy"

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

    // ================= CARTÃO CENTRAL =================
    Rectangle {
        id: card
        width: 860
        height: 590
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // ---------- CABEÇALHO ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: 10
                    color: Theme.withAlpha(Theme.primary, 0.15)

                    Text {
                        anchors.centerIn: parent
                        text: Theme.icons.tune
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 20
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Configurações Visuais"
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: Theme.textColor
                    }
                    Text {
                        text: "Ajuste gráfico e em tempo real para Fastfetch, Kitty, Notificações e Efeitos"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
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

            // ---------- ABAS / TABS ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { name: "Fastfetch", icon: Theme.icons.packages },
                        { name: "Kitty Terminal", icon: Theme.icons.monitor },
                        { name: "Notificações (Mako)", icon: Theme.icons.bell },
                        { name: "Efeitos & Hyprland", icon: Theme.icons.palette }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 10
                        color: win.currentTab === index ? Theme.withAlpha(Theme.primary, 0.22)
                                                        : (tabArea.containsMouse ? Theme.tileHigh : Theme.tile)
                        border.width: win.currentTab === index ? 1 : 0
                        border.color: Theme.primary

                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: parent.parent.modelData.icon
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 15
                                color: win.currentTab === parent.parent.index ? Theme.primary : Theme.subtext
                            }
                            Text {
                                text: parent.parent.modelData.name
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: win.currentTab === parent.parent.index ? Font.DemiBold : Font.Normal
                                color: win.currentTab === parent.parent.index ? Theme.textColor : Theme.subtext
                            }
                        }

                        MouseArea {
                            id: tabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.currentTab = parent.index
                        }
                    }
                }
            }

            // Divisor
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.withAlpha(Theme.outline, 0.15)
            }

            // ---------- CONTEÚDO DAS ABAS ----------
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

                        // Header da seção
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

                        // Galeria de logos
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            // Card Distro Padrão
                            Rectangle {
                                Layout.preferredWidth: 140
                                Layout.preferredHeight: 120
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
                                        font.pixelSize: 42
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

                            // Lista de imagens em ~/Imagens/FastFetch
                            Repeater {
                                model: win.ffImages
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.preferredWidth: 140
                                    Layout.preferredHeight: 120
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

                        // Sliders de Dimensões
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 20

                            CfgSlider {
                                title: "Largura do Logo (Colunas)"
                                minVal: 15
                                maxVal: 50
                                value: win.ffWidth
                                unit: " col"
                                onChanged: newVal => {
                                    win.ffWidth = Math.round(newVal);
                                    debounceTimer.exec(() => {
                                        Quickshell.execDetached(["rice-fastfetch-apply", "set-size", String(win.ffWidth), String(win.ffHeight)]);
                                    });
                                }
                            }

                            CfgSlider {
                                title: "Altura do Logo (Linhas)"
                                minVal: 8
                                maxVal: 32
                                value: win.ffHeight
                                unit: " lin"
                                onChanged: newVal => {
                                    win.ffHeight = Math.round(newVal);
                                    debounceTimer.exec(() => {
                                        Quickshell.execDetached(["rice-fastfetch-apply", "set-size", String(win.ffWidth), String(win.ffHeight)]);
                                    });
                                }
                            }
                        }

                        // Seção de Módulos
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
                                    { key: "host", label: "Host / PC", icon: Theme.icons.laptop },
                                    { key: "kernel", label: "Kernel", icon: Theme.icons.chip },
                                    { key: "uptime", label: "Tempo de Atividade", icon: Theme.icons.timer },
                                    { key: "packages", label: "Pacotes", icon: Theme.icons.packages },
                                    { key: "shell", label: "Shell", icon: Theme.icons.console },
                                    { key: "display", label: "Tela / Resolução", icon: Theme.icons.monitor },
                                    { key: "wm", label: "Window Manager", icon: Theme.icons.workspaces },
                                    { key: "cpu", label: "Processador (CPU)", icon: Theme.icons.cpu },
                                    { key: "gpu", label: "Placa de Vídeo (GPU)", icon: Theme.icons.gpu },
                                    { key: "memory", label: "Memória RAM", icon: Theme.icons.memory },
                                    { key: "disk", label: "Disco", icon: Theme.icons.disk },
                                    { key: "colors", label: "Paleta de Cores", icon: Theme.icons.palette }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool active: win.ffActiveModules.indexOf(modelData.key) !== -1

                                    implicitWidth: modRow.implicitWidth + 20
                                    implicitHeight: 30
                                    radius: 15
                                    color: active ? Theme.withAlpha(Theme.primary, 0.22)
                                                  : (chipArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                    border.width: 1
                                    border.color: active ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                    RowLayout {
                                        id: modRow
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Text {
                                            text: parent.parent.modelData.icon
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 13
                                            color: parent.parent.active ? Theme.primary : Theme.subtext
                                        }
                                        Text {
                                            text: parent.parent.modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: parent.parent.active ? Font.DemiBold : Font.Normal
                                            color: parent.parent.active ? Theme.textColor : Theme.subtext
                                        }
                                    }

                                    MouseArea {
                                        id: chipArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const idx = win.ffActiveModules.indexOf(parent.modelData.key);
                                            const copy = win.ffActiveModules.slice();
                                            if (idx === -1) {
                                                copy.push(parent.modelData.key);
                                            } else {
                                                copy.splice(idx, 1);
                                            }
                                            win.ffActiveModules = copy;
                                            Quickshell.execDetached(["rice-fastfetch-apply", "toggle-module", parent.modelData.key]);
                                        }
                                    }
                                }
                            }
                        }

                        // Botão Testar Fastfetch
                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            ActionBtn {
                                icon: Theme.icons.play
                                text: "Visualizar Fastfetch no Terminal"
                                primary: true
                                onClicked: Quickshell.execDetached(["rice-fastfetch-apply", "run"])
                            }
                        }
                    }
                }

                // ==================== ABA 1: KITTY TERMINAL ====================
                Flickable {
                    anchors.fill: parent
                    visible: win.currentTab === 1
                    contentHeight: kittyContentCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: kittyContentCol
                        width: parent.width
                        spacing: 16

                        SectionHeader {
                            title: "Aparência & Geometria do Terminal Kitty"
                            subtitle: "As mudanças são aplicadas instantaneamente sem reiniciar sessões abertas"
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 20

                            CfgSlider {
                                title: "Opacidade do Fundo (Transparência)"
                                minVal: 0.40
                                maxVal: 1.00
                                value: win.kittyOpacity
                                decimals: 2
                                unit: ""
                                onChanged: newVal => {
                                    win.kittyOpacity = newVal;
                                    debounceTimer.exec(() => {
                                        Quickshell.execDetached(["rice-kitty-apply", "set", "opacity", newVal.toFixed(2)]);
                                    });
                                }
                            }

                            CfgSlider {
                                title: "Tamanho da Fonte"
                                minVal: 8.0
                                maxVal: 18.0
                                value: win.kittyFontSize
                                decimals: 1
                                unit: " pt"
                                onChanged: newVal => {
                                    win.kittyFontSize = newVal;
                                    debounceTimer.exec(() => {
                                        Quickshell.execDetached(["rice-kitty-apply", "set", "font_size", newVal.toFixed(1)]);
                                    });
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 20

                            CfgSlider {
                                title: "Margem Interna (Window Padding)"
                                minVal: 0
                                maxVal: 32
                                value: win.kittyPadding
                                unit: " px"
                                onChanged: newVal => {
                                    win.kittyPadding = Math.round(newVal);
                                    debounceTimer.exec(() => {
                                        Quickshell.execDetached(["rice-kitty-apply", "set", "padding", String(win.kittyPadding)]);
                                    });
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "Formato do Cursor"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.textColor
                                }

                                RowLayout {
                                    spacing: 8

                                    Repeater {
                                        model: [
                                            { id: "beam", label: "Barra ( | )" },
                                            { id: "block", label: "Bloco ( █ )" },
                                            { id: "underline", label: "Sublinhado ( _ )" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            implicitWidth: 110
                                            implicitHeight: 28
                                            radius: 6
                                            color: win.kittyCursor === modelData.id ? Theme.primary
                                                                                   : (cursorArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: 1
                                            border.color: win.kittyCursor === modelData.id ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                            Text {
                                                anchors.centerIn: parent
                                                text: parent.modelData.label
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: win.kittyCursor === parent.modelData.id ? Font.DemiBold : Font.Normal
                                                color: win.kittyCursor === parent.modelData.id ? Theme.background : Theme.textColor
                                            }

                                            MouseArea {
                                                id: cursorArea
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
                            }
                        }

                        // Toggles adicionais do Kitty
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 30

                            CfgToggle {
                                title: "Desfoque de Fundo (Blur)"
                                subtitle: "Ativa blur sob o terminal semitransparente"
                                checked: win.kittyBlur
                                onToggled: nextVal => {
                                    win.kittyBlur = nextVal;
                                    Quickshell.execDetached(["rice-kitty-apply", "set", "blur", nextVal ? "1" : "0"]);
                                }
                            }

                            CfgToggle {
                                title: "Campainha Sonora (Audio Bell)"
                                subtitle: "Toca bipe sonoro em alertas do terminal"
                                checked: win.kittyBell
                                onToggled: nextVal => {
                                    win.kittyBell = nextVal;
                                    Quickshell.execDetached(["rice-kitty-apply", "set", "bell", nextVal ? "true" : "false"]);
                                }
                            }
                        }

                        // Ações Kitty
                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            ActionBtn {
                                icon: Theme.icons.console
                                text: "Abrir Novo Terminal"
                                primary: true
                                onClicked: Quickshell.execDetached(["kitty"])
                            }
                        }
                    }
                }

                // ==================== ABA 2: MAKO NOTIFICAÇÕES ====================
                Flickable {
                    anchors.fill: parent
                    visible: win.currentTab === 2
                    contentHeight: makoContentCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: makoContentCol
                        width: parent.width
                        spacing: 16

                        SectionHeader {
                            title: "Posição das Notificações na Tela (Anchor)"
                            subtitle: "Selecione o quadrante em que as mensagens do sistema aparecem"
                        }

                        // Grid 3x2 elegante para ancoragem
                        GridLayout {
                            columns: 3
                            rowSpacing: 8
                            columnSpacing: 12

                            Repeater {
                                model: [
                                    { id: "top-left", label: "Superior Esquerdo" },
                                    { id: "top-center", label: "Superior Centro" },
                                    { id: "top-right", label: "Superior Direito" },
                                    { id: "bottom-left", label: "Inferior Esquerdo" },
                                    { id: "bottom-center", label: "Inferior Centro" },
                                    { id: "bottom-right", label: "Inferior Direito" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    implicitWidth: 230
                                    implicitHeight: 38
                                    radius: 8
                                    color: win.makoAnchor === modelData.id ? Theme.withAlpha(Theme.primary, 0.22)
                                                                          : (posArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                    border.width: win.makoAnchor === modelData.id ? 1.5 : 1
                                    border.color: win.makoAnchor === modelData.id ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Rectangle {
                                            implicitWidth: 8
                                            implicitHeight: 8
                                            radius: 4
                                            color: win.makoAnchor === parent.parent.modelData.id ? Theme.primary : Theme.subtext
                                        }
                                        Text {
                                            text: parent.parent.modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: win.makoAnchor === parent.parent.modelData.id ? Font.DemiBold : Font.Normal
                                            color: win.makoAnchor === parent.parent.modelData.id ? Theme.textColor : Theme.subtext
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

                        // Sliders de Notificação
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 20

                            CfgSlider {
                                title: "Tempo de Exibição (Duração)"
                                minVal: 2
                                maxVal: 15
                                value: win.makoTimeout
                                unit: " s"
                                onChanged: newVal => {
                                    win.makoTimeout = Math.round(newVal);
                                    debounceTimer.exec(() => {
                                        Quickshell.execDetached(["rice-mako-apply", "set", "timeout", String(win.makoTimeout)]);
                                    });
                                }
                            }

                            CfgSlider {
                                title: "Arredondamento dos Cantos (Raio)"
                                minVal: 0
                                maxVal: 24
                                value: win.makoRadius
                                unit: " px"
                                onChanged: newVal => {
                                    win.makoRadius = Math.round(newVal);
                                    debounceTimer.exec(() => {
                                        Quickshell.execDetached(["rice-mako-apply", "set", "radius", String(win.makoRadius)]);
                                    });
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 20

                            CfgSlider {
                                title: "Espessura da Borda"
                                minVal: 0
                                maxVal: 6
                                value: win.makoBorder
                                unit: " px"
                                onChanged: newVal => {
                                    win.makoBorder = Math.round(newVal);
                                    debounceTimer.exec(() => {
                                        Quickshell.execDetached(["rice-mako-apply", "set", "border_size", String(win.makoBorder)]);
                                    });
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // Ações Mako
                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            ActionBtn {
                                icon: Theme.icons.bell
                                text: "Disparar Notificação de Teste"
                                primary: true
                                onClicked: Quickshell.execDetached(["rice-mako-apply", "test"])
                            }
                        }
                    }
                }

                // ==================== ABA 3: EFEITOS & HYPRLAND ====================
                Flickable {
                    anchors.fill: parent
                    visible: win.currentTab === 3
                    contentHeight: fxContentCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: fxContentCol
                        width: parent.width
                        spacing: 16

                        SectionHeader {
                            title: "Luz Noturna (Hyprsunset) & Conforto Visual"
                            subtitle: "Ajuste de temperatura de cor para descanso ocular em horários noturnos"
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 30

                            CfgToggle {
                                title: "Luz Noturna Ativa"
                                subtitle: win.nightlightActive ? "Filtro de luz azul ligado" : "Filtro desligado"
                                checked: win.nightlightActive
                                onToggled: nextVal => {
                                    win.nightlightActive = nextVal;
                                    Quickshell.execDetached(["rice-nightlight", "toggle"]);
                                }
                            }

                            CfgSlider {
                                title: "Temperatura de Cor"
                                minVal: 2500
                                maxVal: 6500
                                value: win.nightlightTemp
                                unit: " K"
                                onChanged: newVal => {
                                    win.nightlightTemp = Math.round(newVal);
                                    debounceTimer.exec(() => {
                                        Quickshell.execDetached(["rice-nightlight", "set", String(win.nightlightTemp)]);
                                    });
                                }
                            }
                        }

                        SectionHeader {
                            title: "Foco de Janelas & Geometria"
                            subtitle: "Efeitos de sombreamento e formato das bordas no Hyprland"
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 30

                            CfgToggle {
                                title: "Escurecer Janelas Inativas (Dim)"
                                subtitle: "Diminui o brilho de janelas em segundo plano"
                                checked: win.dimInactive
                                onToggled: nextVal => {
                                    win.dimInactive = nextVal;
                                    Quickshell.execDetached(["rice-hypr-prefs", "set", "dim_inactive", nextVal ? "true" : "false"]);
                                }
                            }

                            CfgSlider {
                                title: "Intensidade do Escurecimento"
                                minVal: 0.05
                                maxVal: 0.50
                                value: win.dimStrength
                                decimals: 2
                                unit: ""
                                onChanged: newVal => {
                                    win.dimStrength = newVal;
                                    debounceTimer.exec(() => {
                                        Quickshell.execDetached(["rice-hypr-prefs", "set", "dim_strength", newVal.toFixed(2)]);
                                    });
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 20

                            CfgSlider {
                                title: "Arredondamento dos Cantos (Rounding)"
                                minVal: 0
                                maxVal: 20
                                value: win.rounding
                                unit: " px"
                                onChanged: newVal => {
                                    win.rounding = Math.round(newVal);
                                    debounceTimer.exec(() => {
                                        Quickshell.execDetached(["rice-hypr-prefs", "set", "rounding", String(win.rounding)]);
                                    });
                                }
                            }

                            CfgSlider {
                                title: "Espaçamento Interno (Gaps In)"
                                minVal: 0
                                maxVal: 20
                                value: win.gapsIn
                                unit: " px"
                                onChanged: newVal => {
                                    win.gapsIn = Math.round(newVal);
                                    debounceTimer.exec(() => {
                                        Quickshell.execDetached(["rice-hypr-prefs", "set", "gaps_in", String(win.gapsIn)]);
                                    });
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "Preset de Animações do Compositor"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.textColor
                            }

                            RowLayout {
                                spacing: 10

                                Repeater {
                                    model: [
                                        { id: "smooth", label: "Suave (Smooth)" },
                                        { id: "bouncy", label: "Elástico (Bouncy)" },
                                        { id: "snappy", label: "Rápido (Snappy)" },
                                        { id: "off", label: "Desativado (Off)" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        implicitWidth: 150
                                        implicitHeight: 32
                                        radius: 8
                                        color: win.animPreset === modelData.id ? Theme.primary
                                                                              : (animArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                        border.width: 1
                                        border.color: win.animPreset === modelData.id ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: win.animPreset === parent.modelData.id ? Font.DemiBold : Font.Normal
                                            color: win.animPreset === parent.modelData.id ? Theme.background : Theme.textColor
                                        }

                                        MouseArea {
                                            id: animArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                win.animPreset = parent.modelData.id;
                                                Quickshell.execDetached(["rice-hypr-prefs", "set", "anim_preset", parent.modelData.id]);
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
