import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Widgets
import Quickshell.Services.UPower
import "."

// Motor Avançado de Widgets de Desktop Nativos
// Suporta 13 tipos de widgets, customização visual completa (estilo de card, escala,
// opacidade de fundo, cores de destaque), grade magnética (snap to grid 20px),
// duplicação rápida e persistência por workspace em ~/.config/quickshell/desktop-widgets.json.
// Atalho para entrar/sair do modo de edição: Super + W (ou clique direito no desktop).
PanelWindow {
    id: dwWindow

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    focusable: editMode

    WlrLayershell.namespace: "quickshell-desktop-widgets"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: editMode ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property bool editMode: false
    property bool snapToGrid: true
    readonly property int gridSize: 20

    property string selectedWidgetId: ""
    property bool configLoaded: false
    property var allConfig: ({})
    readonly property int currentWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    property var currentList: allConfig[String(currentWs)] || []

    readonly property bool hasStatsWidget: {
        if (!currentList || !Array.isArray(currentList)) return false;
        for (let i = 0; i < currentList.length; i++) {
            const t = currentList[i].type;
            if (t === "sysinfo" || t === "top" || t === "storage" || t === "netspeed") return true;
        }
        return false;
    }

    readonly property var selectedWidgetData: {
        if (!selectedWidgetId || !currentList) return null;
        for (let i = 0; i < currentList.length; i++) {
            if (currentList[i].id === selectedWidgetId) return currentList[i];
        }
        return null;
    }

    FileView {
        id: configFile
        path: Quickshell.env("HOME") + "/.config/quickshell/desktop-widgets.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (parsed && typeof parsed === "object") {
                    dwWindow.allConfig = parsed;
                    dwWindow.currentList = dwWindow.allConfig[String(dwWindow.currentWs)] || [];
                    dwWindow.configLoaded = true;
                }
            } catch (e) {
                console.warn("Erro ao parsear desktop-widgets.json:", e);
            }
        }
    }

    onCurrentWsChanged: {
        selectedWidgetId = "";
        currentList = allConfig[String(currentWs)] || [];
    }

    Process {
        id: saveProc
        property string jsonPayload: ""
        command: ["bash", "-c", "printf '%s' \"$JSON\" | rice-desktop-widgets save"]
        environment: ({ JSON: jsonPayload })
    }

    function saveCurrentConfig() {
        if (!configLoaded) return;
        const payload = JSON.stringify(allConfig, null, 2);
        saveProc.jsonPayload = payload;
        saveProc.running = true;
    }

    function snapVal(val) {
        return snapToGrid ? Math.round(val / gridSize) * gridSize : Math.round(val);
    }

    function addWidget(type) {
        const wsKey = String(currentWs);
        if (!allConfig[wsKey]) allConfig[wsKey] = [];
        const newId = type + "-" + Date.now();
        const newWidget = {
            id: newId,
            type: type,
            x: snapVal(120 + Math.floor(Math.random() * 80)),
            y: snapVal(120 + Math.floor(Math.random() * 80)),
            scale: 1.0,
            style: "glass",
            opacity: 0.85,
            accent: "",
            noteText: type === "notes" ? "Minhas anotações aqui..." : ""
        };
        allConfig[wsKey].push(newWidget);
        currentList = allConfig[wsKey].slice();
        selectedWidgetId = newId;
        saveCurrentConfig();
    }

    function removeWidget(id) {
        const wsKey = String(currentWs);
        if (!allConfig[wsKey]) return;
        allConfig[wsKey] = allConfig[wsKey].filter(w => w.id !== id);
        currentList = allConfig[wsKey].slice();
        if (selectedWidgetId === id) selectedWidgetId = "";
        saveCurrentConfig();
    }

    function duplicateWidget(id) {
        const wsKey = String(currentWs);
        if (!allConfig[wsKey]) return;
        const source = allConfig[wsKey].find(w => w.id === id);
        if (!source) return;
        const cloned = Object.assign({}, source, {
            id: source.type + "-" + Date.now(),
            x: snapVal(source.x + 30),
            y: snapVal(source.y + 30)
        });
        allConfig[wsKey].push(cloned);
        currentList = allConfig[wsKey].slice();
        selectedWidgetId = cloned.id;
        saveCurrentConfig();
    }

    function clearCurrentWorkspace() {
        const wsKey = String(currentWs);
        allConfig[wsKey] = [];
        currentList = [];
        selectedWidgetId = "";
        saveCurrentConfig();
    }

    function updateWidgetPos(id, newX, newY) {
        const wsKey = String(currentWs);
        if (!allConfig[wsKey]) return;
        const w = allConfig[wsKey].find(item => item.id === id);
        if (w) {
            w.x = snapVal(Math.max(20, Math.min(dwWindow.width - 160, newX)));
            w.y = snapVal(Math.max(40, Math.min(dwWindow.height - 100, newY)));
            saveCurrentConfig();
        }
    }

    function updateWidgetProp(id, key, val) {
        const wsKey = String(currentWs);
        if (!allConfig[wsKey]) return;
        const w = allConfig[wsKey].find(item => item.id === id);
        if (w) {
            w[key] = val;
            currentList = allConfig[wsKey].slice();
            saveCurrentConfig();
        }
    }

    // Clique direito no desktop vazio abre/fecha modo de edição
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                dwWindow.editMode = !dwWindow.editMode;
                if (!dwWindow.editMode) dwWindow.selectedWidgetId = "";
            }
        }
    }

    // ================= CONTAINER BASE DE CADA WIDGET (WIDGETBASE) =================
    component WidgetBase: Rectangle {
        id: base
        property var modelData: null
        default property alias content: baseContent.data

        readonly property real wScale: (modelData && modelData.scale) ? modelData.scale : 1.0
        readonly property string wStyle: (modelData && modelData.style) ? modelData.style : "glass"
        readonly property real wOpacity: (modelData && modelData.opacity !== undefined) ? modelData.opacity : 0.85
        readonly property color wAccent: (modelData && modelData.accent && modelData.accent !== "") ? modelData.accent : Theme.primary

        radius: Theme.radius
        color: {
            if (wStyle === "borderless") return "transparent";
            if (wStyle === "solid") return Theme.surface;
            if (wStyle === "glow") return Theme.withAlpha(Theme.surface, Math.max(0.75, wOpacity));
            // glass:
            return Theme.withAlpha(Theme.surface, wOpacity);
        }
        border.width: wStyle === "borderless" ? 0 : (wStyle === "glow" ? 2 : 1)
        border.color: {
            if (wStyle === "borderless") return "transparent";
            if (wStyle === "glow") return wAccent;
            if (wStyle === "solid") return Theme.withAlpha(Theme.outline, 0.25);
            // glass:
            return Theme.withAlpha(wAccent, 0.35);
        }

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        // Brilho de vidro no topo para o estilo Glass
        Rectangle {
            visible: base.wStyle === "glass"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.withAlpha("#ffffff", 0.16)
            radius: base.radius
        }

        // Borda difusa externa para o estilo Glow
        Rectangle {
            visible: base.wStyle === "glow"
            anchors.fill: parent
            anchors.margins: -3
            radius: base.radius + 3
            color: "transparent"
            border.color: Theme.withAlpha(base.wAccent, 0.4)
            border.width: 1
            z: -1
        }

        Item {
            id: baseContent
            anchors.fill: parent
        }
    }

    // ================= CONTAINER DE WIDGETS DO WORKSPACE =================
    Item {
        anchors.fill: parent

        Repeater {
            model: dwWindow.currentList
            delegate: Item {
                id: widgetContainer
                required property var modelData
                required property int index

                readonly property real sScale: modelData.scale || 1.0
                readonly property bool isSelected: dwWindow.editMode && dwWindow.selectedWidgetId === modelData.id

                x: modelData.x || 100
                y: modelData.y || 100
                width: (widgetLoader.item ? widgetLoader.item.width : 280) * sScale
                height: (widgetLoader.item ? widgetLoader.item.height : 140) * sScale

                Item {
                    id: scaledWrapper
                    width: widgetLoader.item ? widgetLoader.item.width : 280
                    height: widgetLoader.item ? widgetLoader.item.height : 140
                    scale: widgetContainer.sScale
                    transformOrigin: Item.TopLeft

                    // Carregador dinâmico do tipo de widget
                    Loader {
                        id: widgetLoader
                        anchors.fill: parent
                        sourceComponent: {
                            switch (widgetContainer.modelData.type) {
                                case "clock": return compClock;
                                case "analog":
                                case "analogclock": return compAnalogClock;
                                case "media": return compMedia;
                                case "sysinfo": return compSys;
                                case "top": return compTop;
                                case "netspeed": return compNet;
                                case "calendar": return compCalendar;
                                case "battery": return compBattery;
                                case "storage": return compStorage;
                                case "pomodoro": return compPomodoro;
                                case "notes": return compNotes;
                                case "weather": return compWeather;
                                case "quotes": return compQuotes;
                                default: return compClock;
                            }
                        }
                        property var widgetModel: widgetContainer.modelData
                    }
                }

                // Área de Arraste e Seleção em Modo de Edição
                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    enabled: dwWindow.editMode
                    drag.target: widgetContainer
                    drag.minimumX: 10
                    drag.maximumX: dwWindow.width - widgetContainer.width - 10
                    drag.minimumY: Theme.waybarHeight + 6
                    drag.maximumY: dwWindow.height - widgetContainer.height - 10
                    cursorShape: dwWindow.editMode ? Qt.SizeAllCursor : Qt.ArrowCursor

                    onClicked: {
                        if (dwWindow.editMode) {
                            dwWindow.selectedWidgetId = widgetContainer.modelData.id;
                        }
                    }

                    onReleased: {
                        if (dwWindow.editMode) {
                            dwWindow.updateWidgetPos(widgetContainer.modelData.id, widgetContainer.x, widgetContainer.y);
                        }
                    }
                }

                // Moldura de Seleção e Ações Rápidas (Modo de Edição)
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: Theme.radius + 4
                    color: "transparent"
                    border.color: widgetContainer.isSelected ? Theme.primary : Theme.withAlpha(Theme.primary, 0.4)
                    border.width: widgetContainer.isSelected ? 2 : 1
                    visible: dwWindow.editMode

                    // Botões de ação no topo da moldura
                    Row {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -12
                        anchors.rightMargin: -6
                        spacing: 4

                        // Botão Inspector / Configurar Aparência (⚙)
                        Rectangle {
                            width: 24
                            height: 24
                            radius: 12
                            color: Theme.surface
                            border.color: Theme.primary
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: Theme.icons.tune
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 12
                                color: Theme.primary
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dwWindow.selectedWidgetId = widgetContainer.modelData.id
                            }
                        }

                        // Botão Duplicar (⧉)
                        Rectangle {
                            width: 24
                            height: 24
                            radius: 12
                            color: Theme.surface
                            border.color: Theme.secondary
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: Theme.icons.fileCompare
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 11
                                color: Theme.secondary
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dwWindow.duplicateWidget(widgetContainer.modelData.id)
                            }
                        }

                        // Botão Excluir (X)
                        Rectangle {
                            width: 24
                            height: 24
                            radius: 12
                            color: Theme.critical

                            Text {
                                anchors.centerIn: parent
                                text: Theme.icons.close
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 11
                                color: "#ffffff"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dwWindow.removeWidget(widgetContainer.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // ================= WIDGET 1: RELÓGIO DIGITAL & SAUDAÇÃO =================
    Component {
        id: compClock
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 340
            height: 140

            property var now: new Date()
            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: w.now = new Date()
            }

            function greeting(h) {
                var u = (Quickshell.env("USER") || Quickshell.env("LOGNAME") || "User");
                var uname = u.charAt(0).toUpperCase() + u.slice(1);
                if (h >= 5 && h < 12) return Theme.t("greeting.morning", "Bom dia") + ", " + uname;
                if (h >= 12 && h < 18) return Theme.t("greeting.afternoon", "Boa tarde") + ", " + uname;
                return Theme.t("greeting.evening", "Boa noite") + ", " + uname;
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 2

                Text {
                    text: w.greeting(w.now.getHours())
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: w.wAccent
                }

                Text {
                    text: Qt.formatTime(w.now, "hh:mm")
                    font.family: Theme.monoFamily
                    font.pixelSize: 46
                    font.weight: Font.Bold
                    color: Theme.textColor
                }

                Text {
                    text: Qt.formatDate(w.now, Theme.t("clock.date_format", "dddd, d 'de' MMMM"))
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.subtext
                }
            }
        }
    }

    // ================= WIDGET 2: RELÓGIO ANALÓGICO MINIMALISTA =================
    Component {
        id: compAnalogClock
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 200
            height: 200

            property var now: new Date()
            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: {
                    w.now = new Date();
                    clockCanvas.requestPaint();
                }
            }

            Canvas {
                id: clockCanvas
                anchors.centerIn: parent
                width: 170
                height: 170

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const cx = width / 2;
                    const cy = height / 2;
                    const r = width / 2 - 4;

                    // Mostrador
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                    ctx.fillStyle = Theme.withAlpha(Theme.background, 0.35);
                    ctx.fill();
                    ctx.lineWidth = 1.5;
                    ctx.strokeStyle = Theme.withAlpha(w.wAccent, 0.4);
                    ctx.stroke();

                    // Marcadores das 12 horas
                    for (let i = 0; i < 12; i++) {
                        const angle = i * Math.PI / 6;
                        const isMain = (i % 3 === 0);
                        const len = isMain ? 9 : 5;
                        const x1 = cx + Math.sin(angle) * (r - len);
                        const y1 = cy - Math.cos(angle) * (r - len);
                        const x2 = cx + Math.sin(angle) * (r - 2);
                        const y2 = cy - Math.cos(angle) * (r - 2);

                        ctx.beginPath();
                        ctx.moveTo(x1, y1);
                        ctx.lineTo(x2, y2);
                        ctx.lineWidth = isMain ? 2.5 : 1.2;
                        ctx.strokeStyle = isMain ? w.wAccent : Theme.withAlpha(Theme.textColor, 0.4);
                        ctx.stroke();
                    }

                    const h = w.now.getHours();
                    const m = w.now.getMinutes();
                    const s = w.now.getSeconds();

                    // Ponteiro das Horas
                    const hAngle = (h % 12 + m / 60) * Math.PI / 6;
                    ctx.beginPath();
                    ctx.moveTo(cx, cy);
                    ctx.lineTo(cx + Math.sin(hAngle) * (r * 0.5), cy - Math.cos(hAngle) * (r * 0.5));
                    ctx.lineWidth = 4;
                    ctx.lineCap = "round";
                    ctx.strokeStyle = Theme.textColor;
                    ctx.stroke();

                    // Ponteiro dos Minutos
                    const mAngle = (m + s / 60) * Math.PI / 30;
                    ctx.beginPath();
                    ctx.moveTo(cx, cy);
                    ctx.lineTo(cx + Math.sin(mAngle) * (r * 0.72), cy - Math.cos(mAngle) * (r * 0.72));
                    ctx.lineWidth = 2.5;
                    ctx.lineCap = "round";
                    ctx.strokeStyle = Theme.textColor;
                    ctx.stroke();

                    // Ponteiro dos Segundos
                    const sAngle = s * Math.PI / 30;
                    ctx.beginPath();
                    ctx.moveTo(cx - Math.sin(sAngle) * 12, cy + Math.cos(sAngle) * 12);
                    ctx.lineTo(cx + Math.sin(sAngle) * (r * 0.82), cy - Math.cos(sAngle) * (r * 0.82));
                    ctx.lineWidth = 1.5;
                    ctx.lineCap = "round";
                    ctx.strokeStyle = w.wAccent;
                    ctx.stroke();

                    // Pino Central
                    ctx.beginPath();
                    ctx.arc(cx, cy, 4, 0, 2 * Math.PI);
                    ctx.fillStyle = w.wAccent;
                    ctx.fill();
                }
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(w.now, "dd MMM").toUpperCase()
                font.family: Theme.monoFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.subtext
            }
        }
    }

    // ================= WIDGET 3: PLAYER DE MÍDIA COM DISCO DE VINIL =================
    Component {
        id: compMedia
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 360
            height: 160

            // O que está tocando de fato; sem nenhum tocando, o primeiro. Fixar
            // em values[0] mostrava o navegador parado com o Spotify tocando.
            readonly property var player: {
                const list = Mpris.players.values;
                for (let i = 0; i < list.length; i++)
                    if (list[i].isPlaying)
                        return list[i];
                return list.length > 0 ? list[0] : null;
            }
            readonly property bool playing: player ? player.isPlaying : false
            readonly property string artUrl: player && player.trackArtUrl ? player.trackArtUrl : ""

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 16

                // Disco de Vinil com rotação animada
                Rectangle {
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: 100
                    radius: 50
                    color: "#111215"
                    border.color: Theme.withAlpha(Theme.outline, 0.4)
                    border.width: 2

                    RotationAnimation on rotation {
                        loops: Animation.Infinite
                        from: 0; to: 360; duration: 6000
                        running: w.playing
                    }

                    // Capa da música tocando, recortada no círculo do disco e
                    // girando com ele. Sem capa (ou sem player) fica o vinil
                    // liso com o selo colorido no meio, como antes.
                    ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: width / 2
                        color: "transparent"
                        visible: discArt.status === Image.Ready

                        Image {
                            id: discArt
                            anchors.fill: parent
                            source: w.artUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                        }
                    }

                    Rectangle { anchors.centerIn: parent; width: 70; height: 70; radius: 35; color: "transparent"; border.color: discArt.status === Image.Ready ? Qt.rgba(0, 0, 0, 0.25) : "#25272c"; border.width: 1 }
                    Rectangle { anchors.centerIn: parent; width: 46; height: 46; radius: 23; color: "transparent"; border.color: discArt.status === Image.Ready ? Qt.rgba(0, 0, 0, 0.25) : "#25272c"; border.width: 1 }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 28; height: 28; radius: 14
                        // Com capa, o selo vira o furo do vinil.
                        color: discArt.status === Image.Ready ? "#111215" : w.wAccent
                        border.width: discArt.status === Image.Ready ? 2 : 0
                        border.color: w.wAccent

                        Text {
                            anchors.centerIn: parent
                            visible: discArt.status !== Image.Ready
                            text: Theme.icons.music
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 13
                            color: Theme.background
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            visible: discArt.status === Image.Ready
                            width: 6; height: 6; radius: 3
                            color: Theme.withAlpha(Theme.foreground, 0.8)
                        }
                    }
                }

                // Info da Música & Controles
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: w.player ? (w.player.trackTitle || "Sem título") : "Nenhuma mídia ativa"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: Theme.textColor
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: w.player ? (w.player.trackArtist || "Artista desconhecido") : "Player ocioso"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
                        elide: Text.ElideRight
                    }

                    // Barra de progresso
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 4
                        radius: 2
                        color: Theme.withAlpha(Theme.outline, 0.3)

                        Rectangle {
                            height: parent.height
                            radius: 2
                            width: (w.player && w.player.length > 0) ? (parent.width * (w.player.position / w.player.length)) : 0
                            color: w.wAccent
                        }
                    }

                    // Botões multimídia
                    Row {
                        spacing: 12
                        Layout.alignment: Qt.AlignHCenter

                        Text {
                            text: Theme.icons.prev
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 18
                            color: Theme.textColor
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (w.player && w.player.canGoPrevious) w.player.previous()
                            }
                        }

                        Rectangle {
                            width: 32; height: 32; radius: 16
                            color: w.wAccent

                            Text {
                                anchors.centerIn: parent
                                text: w.playing ? Theme.icons.pause : Theme.icons.play
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 16
                                color: Theme.background
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (w.player && w.player.canTogglePlaying) w.player.togglePlaying()
                            }
                        }

                        Text {
                            text: Theme.icons.next
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 18
                            color: Theme.textColor
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (w.player && w.player.canGoNext) w.player.next()
                            }
                        }
                    }
                }
            }
        }
    }

    // ================= WIDGET 4: RECURSOS DO SISTEMA (CPU/GPU/RAM) =================
    Component {
        id: compSys
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 340
            height: 140

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                // CPU
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: "CPU"
                        font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold
                        color: w.wAccent; Layout.alignment: Qt.AlignHCenter
                    }
                    Gauge {
                        Layout.preferredWidth: 64; Layout.preferredHeight: 64
                        Layout.alignment: Qt.AlignHCenter
                        value: SysStats.cpuUsage
                        color: w.wAccent
                    }
                    Text {
                        text: Math.round(SysStats.cpuUsage * 100) + "%"
                        font.family: Theme.monoFamily; font.pixelSize: 11
                        color: Theme.textColor; Layout.alignment: Qt.AlignHCenter
                    }
                }

                // GPU (RTX 3050)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: SysStats.gpuName
                        font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold
                        color: Theme.secondary; Layout.alignment: Qt.AlignHCenter
                    }
                    Gauge {
                        Layout.preferredWidth: 64; Layout.preferredHeight: 64
                        Layout.alignment: Qt.AlignHCenter
                        value: SysStats.gpuUsage
                        color: Theme.secondary
                    }
                    Text {
                        text: Math.round(SysStats.gpuUsage * 100) + "%"
                        font.family: Theme.monoFamily; font.pixelSize: 11
                        color: Theme.textColor; Layout.alignment: Qt.AlignHCenter
                    }
                }

                // RAM REAL
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: "RAM REAL"
                        font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold
                        color: Theme.accent1; Layout.alignment: Qt.AlignHCenter
                    }
                    Gauge {
                        Layout.preferredWidth: 64; Layout.preferredHeight: 64
                        Layout.alignment: Qt.AlignHCenter
                        value: SysStats.ramRealFrac
                        color: Theme.accent1
                    }
                    Text {
                        text: SysStats.ramRealGiB.toFixed(1) + "G"
                        font.family: Theme.monoFamily; font.pixelSize: 11
                        color: Theme.textColor; Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }
    }

    // ================= WIDGET 5: TOP PROCESSOS (CPU & RAM) =================
    Component {
        id: compTop
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 320
            height: 165

            property bool sortByCpu: true
            property var procs: []

            Process {
                id: topProc
                command: ["bash", "-c", w.sortByCpu
                    ? "ps -eo comm,%cpu,%mem --sort=-%cpu | head -n 4 | tail -n +2"
                    : "ps -eo comm,%cpu,%mem --sort=-%mem | head -n 4 | tail -n +2"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const lines = text.trim().split("\n");
                        const list = [];
                        for (let line of lines) {
                            const p = line.trim().split(/\s+/);
                            if (p.length >= 3) {
                                list.push({ name: p[0], cpu: parseFloat(p[1]) || 0, mem: parseFloat(p[2]) || 0 });
                            }
                        }
                        w.procs = list;
                    }
                }
            }

            Timer {
                interval: 3500; running: true; repeat: true; triggeredOnStart: true
                onTriggered: topProc.running = true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: w.sortByCpu ? "Top Processos (CPU)" : "Top Processos (RAM)"
                        font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.Bold
                        color: w.wAccent; Layout.fillWidth: true
                    }

                    Rectangle {
                        implicitWidth: modeText.implicitWidth + 12
                        implicitHeight: 20
                        radius: 10
                        color: Theme.tile
                        border.color: Theme.withAlpha(w.wAccent, 0.4); border.width: 1

                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: w.sortByCpu ? "Ver RAM" : "Ver CPU"
                            font.family: Theme.fontFamily; font.pixelSize: 10
                            color: Theme.textColor
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                w.sortByCpu = !w.sortByCpu;
                                topProc.running = true;
                            }
                        }
                    }
                }

                Repeater {
                    model: w.procs
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: modelData.name
                                font.family: Theme.monoFamily; font.pixelSize: 11
                                color: Theme.textColor; Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: w.sortByCpu ? (modelData.cpu.toFixed(1) + "% CPU") : (modelData.mem.toFixed(1) + "% RAM")
                                font.family: Theme.monoFamily; font.pixelSize: 11
                                color: w.wAccent
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 3
                            radius: 1.5; color: Theme.withAlpha(Theme.outline, 0.25)
                            Rectangle {
                                height: parent.height; radius: 1.5
                                width: Math.min(parent.width, parent.width * ((w.sortByCpu ? modelData.cpu : modelData.mem * 5) / 100))
                                color: w.wAccent
                            }
                        }
                    }
                }
            }
        }
    }

    // ================= WIDGET 6: MONITOR DE REDE (DOWNLOAD / UPLOAD) =================
    Component {
        id: compNet
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 280
            height: 130

            property real rxBytes: 0
            property real txBytes: 0
            property real downSpeed: 0
            property real upSpeed: 0

            Process {
                id: netProc
                command: ["bash", "-c", "awk '$1 ~ /^(wlan|enp|eth)/ { rx += $2; tx += $10 } END { print rx, tx }' /proc/net/dev"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const parts = text.trim().split(/\s+/);
                        if (parts.length >= 2) {
                            const newRx = parseFloat(parts[0]) || 0;
                            const newTx = parseFloat(parts[1]) || 0;
                            if (w.rxBytes > 0) {
                                w.downSpeed = Math.max(0, (newRx - w.rxBytes) / 2);
                                w.upSpeed = Math.max(0, (newTx - w.txBytes) / 2);
                            }
                            w.rxBytes = newRx;
                            w.txBytes = newTx;
                        }
                    }
                }
            }

            Timer {
                interval: 2000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: netProc.running = true
            }

            function fmtSpeed(bytes) {
                if (bytes >= 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB/s";
                if (bytes >= 1024) return (bytes / 1024).toFixed(0) + " KB/s";
                return bytes.toFixed(0) + " B/s";
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: Theme.icons.network
                        font.family: Theme.iconFontFamily; font.pixelSize: 14; color: w.wAccent
                    }
                    Text {
                        text: "Tráfego de Rede"
                        font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.Bold
                        color: Theme.textColor; Layout.fillWidth: true
                    }
                    Text {
                        text: "wlan0"
                        font.family: Theme.monoFamily; font.pixelSize: 10; color: Theme.subtext
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Row {
                            spacing: 4
                            Text { text: "↓"; font.pixelSize: 14; color: Theme.accent1; font.weight: Font.Bold }
                            Text { text: "Download"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.subtext }
                        }
                        Text {
                            text: w.fmtSpeed(w.downSpeed)
                            font.family: Theme.monoFamily; font.pixelSize: 15; font.weight: Font.Bold
                            color: Theme.textColor
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Row {
                            spacing: 4
                            Text { text: "↑"; font.pixelSize: 14; color: w.wAccent; font.weight: Font.Bold }
                            Text { text: "Upload"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.subtext }
                        }
                        Text {
                            text: w.fmtSpeed(w.upSpeed)
                            font.family: Theme.monoFamily; font.pixelSize: 15; font.weight: Font.Bold
                            color: Theme.textColor
                        }
                    }
                }
            }
        }
    }

    // ================= WIDGET 7: CALENDÁRIO MENSAL =================
    Component {
        id: compCalendar
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 320
            height: 230

            property var today: new Date()
            property int currentMonth: today.getMonth()
            property int currentYear: today.getFullYear()

            readonly property var monthNames: [
                "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
                "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
            ]

            readonly property var calendarDays: {
                const firstDay = new Date(currentYear, currentMonth, 1).getDay();
                const totalDays = new Date(currentYear, currentMonth + 1, 0).getDate();
                const days = [];
                for (let i = 0; i < firstDay; i++) days.push({ day: 0, isToday: false });
                for (let d = 1; d <= totalDays; d++) {
                    const isTod = (d === today.getDate() && currentMonth === today.getMonth() && currentYear === today.getFullYear());
                    days.push({ day: d, isToday: isTod });
                }
                while (days.length % 7 !== 0) days.push({ day: 0, isToday: false });
                return days;
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                // Cabeçalho
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: w.monthNames[w.currentMonth].toUpperCase() + " " + w.currentYear
                        font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Bold
                        color: w.wAccent; Layout.fillWidth: true
                    }
                    Text {
                        text: Theme.icons.calendar
                        font.family: Theme.iconFontFamily; font.pixelSize: 14; color: Theme.subtext
                    }
                }

                // Dias da semana
                Row {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: ["D", "S", "T", "Q", "Q", "S", "S"]
                        delegate: Item {
                            width: (w.width - 28) / 7; height: 18
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold
                                color: Theme.subtext
                            }
                        }
                    }
                }

                // Grade de dias
                Grid {
                    Layout.fillWidth: true
                    columns: 7
                    rowSpacing: 4
                    columnSpacing: 0

                    Repeater {
                        model: w.calendarDays
                        delegate: Item {
                            width: (w.width - 28) / 7; height: 22

                            Rectangle {
                                anchors.centerIn: parent
                                width: 22; height: 22; radius: 11
                                color: modelData.isToday ? w.wAccent : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.day > 0 ? String(modelData.day) : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: modelData.isToday ? Font.Bold : Font.Normal
                                    color: modelData.isToday ? Theme.background : (modelData.day > 0 ? Theme.textColor : "transparent")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ================= WIDGET 8: BATERIA & SAÚDE DE ENERGIA =================
    Component {
        id: compBattery
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 300
            height: 140

            readonly property var bat: UPower.displayDevice

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: Theme.icons.bat
                        font.family: Theme.iconFontFamily; font.pixelSize: 16
                        color: (w.bat && w.bat.percentage <= 0.2) ? Theme.critical : w.wAccent
                    }
                    Text {
                        text: "Bateria & Energia"
                        font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.Bold
                        color: Theme.textColor; Layout.fillWidth: true
                    }
                    Text {
                        text: w.bat ? (Math.round(w.bat.percentage * 100) + "%") : "--"
                        font.family: Theme.monoFamily; font.pixelSize: 14; font.weight: Font.Bold
                        color: w.wAccent
                    }
                }

                // Barra de Bateria
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 8; radius: 4
                    color: Theme.tile
                    Rectangle {
                        height: parent.height; radius: 4
                        width: w.bat ? (parent.width * Math.max(0, Math.min(1, w.bat.percentage))) : 0
                        color: (w.bat && w.bat.percentage <= 0.2) ? Theme.critical : w.wAccent
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: !w.bat ? "Sem bateria"
                            : w.bat.state === UPowerDeviceState.Charging ? "⚡ Carregando"
                            : w.bat.state === UPowerDeviceState.FullyCharged ? "✓ Bateria cheia"
                            : "🔋 Descarregando"
                        font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.textColor
                        Layout.fillWidth: true
                    }
                    Text {
                        visible: w.bat && Math.abs(w.bat.changeRate) > 0.1
                        text: w.bat ? (Math.abs(w.bat.changeRate).toFixed(1) + " W") : ""
                        font.family: Theme.monoFamily; font.pixelSize: 11; color: Theme.subtext
                    }
                }
            }
        }
    }

    // ================= WIDGET 9: ARMAZENAMENTO & PARTIÇÕES =================
    Component {
        id: compStorage
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 320
            height: 135

            property string totalStr: ""
            property string usedStr: ""
            property string availStr: ""
            property real usedFrac: 0

            Process {
                id: dfProc
                command: ["bash", "-c", "df -h / | tail -n 1"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const parts = text.trim().split(/\s+/);
                        if (parts.length >= 5) {
                            w.totalStr = parts[1];
                            w.usedStr = parts[2];
                            w.availStr = parts[3];
                            w.usedFrac = (parseFloat(parts[4]) || 0) / 100;
                        }
                    }
                }
            }

            Timer {
                interval: 10000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: dfProc.running = true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: Theme.icons.disk
                        font.family: Theme.iconFontFamily; font.pixelSize: 16; color: w.wAccent
                    }
                    Text {
                        text: "Armazenamento (Btrfs)"
                        font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.Bold
                        color: Theme.textColor; Layout.fillWidth: true
                    }
                    Text {
                        text: Math.round(w.usedFrac * 100) + "%"
                        font.family: Theme.monoFamily; font.pixelSize: 13; font.weight: Font.Bold
                        color: w.wAccent
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 8; radius: 4
                    color: Theme.tile
                    Rectangle {
                        height: parent.height; radius: 4
                        width: parent.width * Math.min(1, Math.max(0, w.usedFrac))
                        color: w.usedFrac > 0.9 ? Theme.critical : w.wAccent
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: w.usedStr + " usado de " + w.totalStr
                        font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.subtext
                        Layout.fillWidth: true
                    }
                    Text {
                        text: w.availStr + " livre"
                        font.family: Theme.monoFamily; font.pixelSize: 11; font.weight: Font.Medium
                        color: Theme.textColor
                    }
                }
            }
        }
    }

    // ================= WIDGET 10: TIMER / POMODORO DE FOCO =================
    Component {
        id: compPomodoro
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 290
            height: 150

            property int remainingSeconds: 25 * 60
            property int totalSeconds: 25 * 60
            property bool isRunning: false

            Timer {
                interval: 1000; running: w.isRunning; repeat: true
                onTriggered: {
                    if (w.remainingSeconds > 0) {
                        w.remainingSeconds--;
                    } else {
                        w.isRunning = false;
                        Quickshell.execDetached(["notify-send", "-a", "Pomodoro", "⏰ Tempo Esgotado!", "Hora de fazer uma pausa."]);
                    }
                }
            }

            function setTime(mins) {
                w.isRunning = false;
                w.totalSeconds = mins * 60;
                w.remainingSeconds = mins * 60;
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: Theme.icons.timer
                        font.family: Theme.iconFontFamily; font.pixelSize: 14; color: w.wAccent
                    }
                    Text {
                        text: "Timer de Foco"
                        font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.Bold
                        color: Theme.textColor; Layout.fillWidth: true
                    }

                    // Seletor 25m / 5m
                    Row {
                        spacing: 4
                        Rectangle {
                            implicitWidth: 36; implicitHeight: 20; radius: 10
                            color: w.totalSeconds === 1500 ? w.wAccent : Theme.tile
                            Text {
                                anchors.centerIn: parent; text: "25m"
                                font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold
                                color: w.totalSeconds === 1500 ? Theme.background : Theme.textColor
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.setTime(25) }
                        }
                        Rectangle {
                            implicitWidth: 32; implicitHeight: 20; radius: 10
                            color: w.totalSeconds === 300 ? w.wAccent : Theme.tile
                            Text {
                                anchors.centerIn: parent; text: "5m"
                                font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold
                                color: w.totalSeconds === 300 ? Theme.background : Theme.textColor
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: w.setTime(5) }
                        }
                    }
                }

                // Display do Timer
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        const m = Math.floor(w.remainingSeconds / 60);
                        const s = w.remainingSeconds % 60;
                        return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
                    }
                    font.family: Theme.monoFamily; font.pixelSize: 34; font.weight: Font.Bold
                    color: Theme.textColor
                }

                // Controles Play/Pause e Reset
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12

                    Rectangle {
                        width: 30; height: 30; radius: 15
                        color: w.wAccent
                        Text {
                            anchors.centerIn: parent
                            text: w.isRunning ? Theme.icons.pause : Theme.icons.play
                            font.family: Theme.iconFontFamily; font.pixelSize: 14
                            color: Theme.background
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: w.isRunning = !w.isRunning
                        }
                    }

                    Rectangle {
                        width: 30; height: 30; radius: 15
                        color: Theme.tile
                        border.color: Theme.withAlpha(Theme.outline, 0.3); border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icons.refresh
                            font.family: Theme.iconFontFamily; font.pixelSize: 13
                            color: Theme.textColor
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                w.isRunning = false;
                                w.remainingSeconds = w.totalSeconds;
                            }
                        }
                    }
                }
            }
        }
    }

    // ================= WIDGET 11: BLOCO DE NOTAS RÁPIDAS =================
    Component {
        id: compNotes
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 320
            height: 180

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: Theme.icons.pencil
                        font.family: Theme.iconFontFamily; font.pixelSize: 13; color: w.wAccent
                    }
                    Text {
                        text: "Notas Rápidas (WS " + dwWindow.currentWs + ")"
                        font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold
                        color: Theme.textColor; Layout.fillWidth: true
                    }
                    Text {
                        text: Theme.icons.trash
                        font.family: Theme.iconFontFamily; font.pixelSize: 12; color: Theme.subtext
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                noteArea.text = "";
                                dwWindow.updateWidgetProp(widgetModel.id, "noteText", "");
                            }
                        }
                    }
                }

                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    TextArea {
                        id: noteArea
                        text: widgetModel.noteText || ""
                        placeholderText: "Clique para digitar notas..."
                        placeholderTextColor: Theme.subtext
                        color: Theme.textColor
                        font.family: Theme.fontFamily; font.pixelSize: 12
                        wrapMode: TextEdit.Wrap
                        background: null

                        onTextChanged: {
                            if (focus) {
                                dwWindow.updateWidgetProp(widgetModel.id, "noteText", text);
                            }
                        }
                    }
                }
            }
        }
    }

    // ================= WIDGET 12: CLIMA & PREVISÃO =================
    Component {
        id: compWeather
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 300
            height: 140

            property string temp: "--"
            property string desc: "Carregando..."
            property string city: "Mandaguaçu"

            Process {
                id: wProc
                command: ["bash", "-c", "curl -s 'wttr.in/?format=j1' --max-time 4 2>/dev/null"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const data = JSON.parse(text);
                            const cur = data.current_condition[0];
                            w.temp = cur.temp_C + "°C";
                            w.desc = cur.lang_pt ? cur.lang_pt[0].value : cur.weatherDesc[0].value;
                            if (data.nearest_area && data.nearest_area[0].areaName) {
                                w.city = data.nearest_area[0].areaName[0].value;
                            }
                        } catch (e) {
                            w.desc = "Previsão indisponível";
                        }
                    }
                }
            }

            Timer {
                interval: 300000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: wProc.running = true
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                Text {
                    text: Theme.icons.sunny
                    font.family: Theme.iconFontFamily; font.pixelSize: 42
                    color: w.wAccent
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2

                    Text {
                        text: w.temp
                        font.family: Theme.monoFamily; font.pixelSize: 30; font.weight: Font.Bold
                        color: Theme.textColor
                    }

                    Text {
                        text: w.desc
                        font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.subtext
                        elide: Text.ElideRight; Layout.fillWidth: true
                    }

                    Text {
                        text: w.city
                        font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.withAlpha(Theme.subtext, 0.7)
                    }
                }
            }
        }
    }

    // ================= WIDGET 13: CITAÇÕES INSPIRADORAS =================
    Component {
        id: compQuotes
        WidgetBase {
            id: w
            modelData: widgetModel
            width: 360
            height: 140

            property int quoteIndex: 0
            readonly property var quoteList: [
                { quote: "A simplicidade é o último grau da sofisticação.", author: "Leonardo da Vinci" },
                { quote: "Primeiro faça funcionar, depois faça certo, depois faça rápido.", author: "Kent Beck" },
                { quote: "Linux is only free if your time has no value.", author: "Jamie Zawinski" },
                { quote: "Talk is cheap. Show me the code.", author: "Linus Torvalds" },
                { quote: "O ricing não é apenas estética; é tornar seu sistema verdadeiramente seu.", author: "Comunidade Unix" }
            ]

            function nextQuote() {
                w.quoteIndex = (w.quoteIndex + 1) % w.quoteList.length;
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: Theme.icons.quote
                        font.family: Theme.iconFontFamily; font.pixelSize: 14; color: w.wAccent
                    }
                    Text {
                        text: "Frase do Dia"
                        font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold
                        color: Theme.subtext; Layout.fillWidth: true
                    }
                    Text {
                        text: Theme.icons.refresh
                        font.family: Theme.iconFontFamily; font.pixelSize: 13; color: Theme.subtext
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: w.nextQuote()
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    text: "\"" + w.quoteList[w.quoteIndex].quote + "\""
                    font.family: Theme.fontFamily; font.pixelSize: 12; font.italic: true
                    color: Theme.textColor; wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: "— " + w.quoteList[w.quoteIndex].author
                    font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.DemiBold
                    color: w.wAccent
                }
            }
        }
    }

    // ================= BARRA DE FERRAMENTAS DO MODO DE EDIÇÃO =================
    Rectangle {
        id: editBar
        anchors.horizontalCenter: parent.horizontalCenter
        y: dwWindow.editMode ? (Theme.waybarHeight + 12) : -100
        opacity: dwWindow.editMode ? 1 : 0
        visible: opacity > 0

        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        implicitWidth: Math.min(dwWindow.width - 40, editRow.implicitWidth + 32)
        implicitHeight: 50
        radius: 25
        color: Theme.surface
        border.color: Theme.primary
        border.width: 1

        RowLayout {
            id: editRow
            anchors.centerIn: parent
            spacing: 10

            Text {
                text: "✏️ WS " + dwWindow.currentWs
                font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.Bold
                color: Theme.primary
            }

            Rectangle { width: 1; height: 22; color: Theme.withAlpha(Theme.outline, 0.3) }

            // Botão Toggle Grade Magnética (Snap 20px)
            Rectangle {
                implicitWidth: snapText.implicitWidth + 14
                implicitHeight: 28
                radius: 14
                color: dwWindow.snapToGrid ? Theme.primary : Theme.tile
                border.color: Theme.withAlpha(Theme.primary, 0.4); border.width: 1

                Text {
                    id: snapText
                    anchors.centerIn: parent
                    text: dwWindow.snapToGrid ? "# Grade: 20px" : "# Grade: Livre"
                    font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Medium
                    color: dwWindow.snapToGrid ? Theme.background : Theme.textColor
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: dwWindow.snapToGrid = !dwWindow.snapToGrid
                }
            }

            Rectangle { width: 1; height: 22; color: Theme.withAlpha(Theme.outline, 0.3) }

            // Scroll de Adição de Widgets
            ScrollView {
                Layout.preferredWidth: Math.min(720, addRow.implicitWidth)
                Layout.preferredHeight: 32
                clip: true

                Row {
                    id: addRow
                    spacing: 6

                    readonly property var widgetTypes: [
                        { label: "+ Relógio", type: "clock" },
                        { label: "+ Analógico", type: "analog" },
                        { label: "+ Mídia", type: "media" },
                        { label: "+ Sistema", type: "sysinfo" },
                        { label: "+ Top Apps", type: "top" },
                        { label: "+ Rede", type: "netspeed" },
                        { label: "+ Calendário", type: "calendar" },
                        { label: "+ Bateria", type: "battery" },
                        { label: "+ Disco", type: "storage" },
                        { label: "+ Pomodoro", type: "pomodoro" },
                        { label: "+ Notas", type: "notes" },
                        { label: "+ Clima", type: "weather" },
                        { label: "+ Citação", type: "quotes" }
                    ]

                    Repeater {
                        model: addRow.widgetTypes
                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: addBtnText.implicitWidth + 14
                            implicitHeight: 28
                            radius: 14
                            color: addArea.containsMouse ? Theme.primary : Theme.tile
                            border.color: Theme.withAlpha(Theme.primary, 0.3); border.width: 1

                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                id: addBtnText
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Medium
                                color: addArea.containsMouse ? Theme.background : Theme.textColor
                            }

                            MouseArea {
                                id: addArea
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dwWindow.addWidget(parent.modelData.type)
                            }
                        }
                    }
                }
            }

            Rectangle { width: 1; height: 22; color: Theme.withAlpha(Theme.outline, 0.3) }

            // Limpar Workspace
            Rectangle {
                implicitWidth: clearText.implicitWidth + 14
                implicitHeight: 28
                radius: 14
                color: clearArea.containsMouse ? Theme.critical : Theme.tile
                border.color: Theme.withAlpha(Theme.critical, 0.4); border.width: 1

                Text {
                    id: clearText
                    anchors.centerIn: parent
                    text: Theme.t("common.clear", "Limpar")
                    font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Medium
                    color: clearArea.containsMouse ? "#ffffff" : Theme.textColor
                }
                MouseArea {
                    id: clearArea
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dwWindow.clearCurrentWorkspace()
                }
            }

            // Concluir
            Rectangle {
                implicitWidth: doneText.implicitWidth + 18
                implicitHeight: 28
                radius: 14
                color: doneArea.containsMouse ? Theme.accent1 : Theme.primary

                Text {
                    id: doneText
                    anchors.centerIn: parent
                    text: "✓ " + Theme.t("widgets.done", "Concluir")
                    font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold
                    color: Theme.background
                }

                MouseArea {
                    id: doneArea
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        dwWindow.editMode = false;
                        dwWindow.selectedWidgetId = "";
                    }
                }
            }
        }
    }

    // ================= INSPECTOR / CUSTOMIZADOR VISUAL DE WIDGET =================
    Rectangle {
        id: inspectorCard
        property real customX: -1
        property real customY: -1

        // Se o usuário ainda não moveu manualmente, posiciona do lado oposto do widget selecionado
        x: customX !== -1 ? customX : (
            (dwWindow.selectedWidgetData && dwWindow.selectedWidgetData.x > ((dwWindow.width || 1920) / 2 - 160))
                ? 24
                : ((dwWindow.width || 1920) - width - 24)
        )
        y: customY !== -1 ? customY : Math.max(Theme.waybarHeight + 10, (dwWindow.height || 1080) - implicitHeight - 48)
        width: 320
        implicitHeight: inspCol.implicitHeight + 28
        radius: Theme.radius
        color: Theme.surface
        border.color: Theme.primary
        border.width: 1
        visible: dwWindow.editMode && dwWindow.selectedWidgetData !== null
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        ColumnLayout {
            id: inspCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            // Header do Inspector (Arrastável)
            Item {
                id: inspHeaderItem
                Layout.fillWidth: true
                implicitHeight: 28

                RowLayout {
                    anchors.fill: parent
                    spacing: 8

                    Text {
                        text: Theme.icons.tune
                        font.family: Theme.iconFontFamily; font.pixelSize: 15; color: Theme.primary
                    }
                    Text {
                        text: Theme.t("widgets.style_title", "Estilizar Widget")
                        font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Bold
                        color: Theme.textColor; Layout.fillWidth: true
                    }
                    Text {
                        text: "⠿"
                        font.pixelSize: 14; color: Theme.subtext
                    }
                    Rectangle {
                        id: closeBtnRect
                        z: 10
                        implicitWidth: 24; implicitHeight: 24; radius: 12
                        color: closeArea.containsMouse ? Theme.tile : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icons.close
                            font.family: Theme.iconFontFamily; font.pixelSize: 14; color: Theme.subtext
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dwWindow.selectedWidgetId = ""
                        }
                    }
                }

                MouseArea {
                    id: inspDragArea
                    anchors.fill: parent
                    anchors.rightMargin: 32
                    z: 5
                    cursorShape: Qt.SizeAllCursor
                    drag.target: inspectorCard
                    drag.minimumX: 10
                    drag.maximumX: (dwWindow ? dwWindow.width : 1920) - inspectorCard.width - 10
                    drag.minimumY: Theme.waybarHeight + 6
                    drag.maximumY: (dwWindow ? dwWindow.height : 1080) - inspectorCard.height - 10
                    onReleased: {
                        inspectorCard.customX = inspectorCard.x;
                        inspectorCard.customY = inspectorCard.y;
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.withAlpha(Theme.outline, 0.2) }

            // 1. Estilo do Card
            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                Text { text: Theme.t("widgets.style_visual", "Estilo Visual"); font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.subtext }
                Row {
                    spacing: 6
                    readonly property var styles: [
                        { label: "Vidro", val: "glass" },
                        { label: "Sólido", val: "solid" },
                        { label: "Glow", val: "glow" },
                        { label: "Livre", val: "borderless" }
                    ]
                    Repeater {
                        model: parent.styles
                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: sText.implicitWidth + 12
                            implicitHeight: 24; radius: 12
                            readonly property bool isCurrent: (dwWindow.selectedWidgetData && (dwWindow.selectedWidgetData.style || "glass") === modelData.val)
                            color: isCurrent ? Theme.primary : Theme.tile

                            Text {
                                id: sText
                                anchors.centerIn: parent; text: parent.modelData.label
                                font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Medium
                                color: parent.isCurrent ? Theme.background : Theme.textColor
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: if (dwWindow.selectedWidgetId) dwWindow.updateWidgetProp(dwWindow.selectedWidgetId, "style", parent.modelData.val)
                            }
                        }
                    }
                }
            }

            // 2. Escala / Tamanho
            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                Text { text: Theme.t("widgets.scale", "Escala"); font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.subtext }
                Row {
                    spacing: 6
                    readonly property var scales: [
                        { label: "80%", val: 0.8 },
                        { label: "100%", val: 1.0 },
                        { label: "120%", val: 1.2 }
                    ]
                    Repeater {
                        model: parent.scales
                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: scText.implicitWidth + 14
                            implicitHeight: 24; radius: 12
                            readonly property bool isCurrent: (dwWindow.selectedWidgetData && (dwWindow.selectedWidgetData.scale || 1.0) === modelData.val)
                            color: isCurrent ? Theme.primary : Theme.tile

                            Text {
                                id: scText
                                anchors.centerIn: parent; text: parent.modelData.label
                                font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Medium
                                color: parent.isCurrent ? Theme.background : Theme.textColor
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: if (dwWindow.selectedWidgetId) dwWindow.updateWidgetProp(dwWindow.selectedWidgetId, "scale", parent.modelData.val)
                            }
                        }
                    }
                }
            }

            // 3. Opacidade do Fundo
            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                Text { text: Theme.t("widgets.opacity", "Opacidade do Fundo"); font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.subtext }
                Row {
                    spacing: 6
                    readonly property var opacities: [
                        { label: "40%", val: 0.40 },
                        { label: "70%", val: 0.70 },
                        { label: "85%", val: 0.85 },
                        { label: "100%", val: 1.0 }
                    ]
                    Repeater {
                        model: parent.opacities
                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: opText.implicitWidth + 12
                            implicitHeight: 24; radius: 12
                            readonly property bool isCurrent: (dwWindow.selectedWidgetData && (dwWindow.selectedWidgetData.opacity !== undefined ? dwWindow.selectedWidgetData.opacity : 0.85) === modelData.val)
                            color: isCurrent ? Theme.primary : Theme.tile

                            Text {
                                id: opText
                                anchors.centerIn: parent; text: parent.modelData.label
                                font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Medium
                                color: parent.isCurrent ? Theme.background : Theme.textColor
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: if (dwWindow.selectedWidgetId) dwWindow.updateWidgetProp(dwWindow.selectedWidgetId, "opacity", parent.modelData.val)
                            }
                        }
                    }
                }
            }

            // 4. Cor de Destaque
            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                Text { text: Theme.t("widgets.accent_color", "Cor de Destaque"); font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.subtext }
                Row {
                    spacing: 8
                    readonly property var colors: [
                        { name: "Padrão", hex: "" },
                        { name: "Ciano", hex: "#00f0ff" },
                        { name: "Rosa", hex: "#ff007f" },
                        { name: "Esmeralda", hex: "#10b981" },
                        { name: "Violeta", hex: "#a855f7" },
                        { name: "Âmbar", hex: "#f59e0b" }
                    ]
                    Repeater {
                        model: parent.colors
                        delegate: Rectangle {
                            required property var modelData
                            width: 24; height: 24; radius: 12
                            color: modelData.hex !== "" ? modelData.hex : Theme.primary
                            border.color: (dwWindow.selectedWidgetData && (dwWindow.selectedWidgetData.accent || "") === modelData.hex) ? "#ffffff" : "transparent"
                            border.width: 2

                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: if (dwWindow.selectedWidgetId) dwWindow.updateWidgetProp(dwWindow.selectedWidgetId, "accent", parent.modelData.hex)
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.withAlpha(Theme.outline, 0.2) }

            // Botão Duplicar e Excluir
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 28; radius: 14
                    color: Theme.tile; border.color: Theme.withAlpha(Theme.outline, 0.3); border.width: 1
                    Text {
                        anchors.centerIn: parent; text: "⧉ " + Theme.t("widgets.duplicate", "Duplicar")
                        font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.textColor
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (dwWindow.selectedWidgetId) dwWindow.duplicateWidget(dwWindow.selectedWidgetId)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 28; radius: 14
                    color: Theme.withAlpha(Theme.critical, 0.15); border.color: Theme.critical; border.width: 1
                    Text {
                        anchors.centerIn: parent; text: Theme.t("common.delete", "Excluir")
                        font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.critical
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (dwWindow.selectedWidgetId) dwWindow.removeWidget(dwWindow.selectedWidgetId)
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "desktopwidgets"

        function toggleEdit(): void {
            dwWindow.editMode = !dwWindow.editMode;
            if (!dwWindow.editMode) dwWindow.selectedWidgetId = "";
        }

        function add(type: string): void {
            dwWindow.addWidget(type);
        }

        function snap(): void {
            dwWindow.snapToGrid = !dwWindow.snapToGrid;
        }

        function select(id: string): void {
            dwWindow.selectedWidgetId = id;
        }
    }
}
