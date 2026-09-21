import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "."

// Aba Gravação de Tela do Hub Central (estilo OBS Studio nativo)
// Suporta:
//   - Gravação com GPU dedicada NVIDIA RTX 3050 (NVENC) para 0% impacto em CPU/jogos
//   - Tela Inteira, Aplicativo/Janela específica ou Região livre (slurp)
//   - Áudio do Sistema (Desktop) e Microfone (Voz) com mixagem automática PipeWire
//   - Paleta 100% dinâmica sincronizada com Wallust (Theme.tile, Theme.textColor, Theme.primary)
//   - Gravações salvas em ~/Vídeos/Gravações
Item {
    id: root

    property bool isRecording: false
    property int elapsedSeconds: 0
    property string recordingFile: ""
    property string captureMode: "screen" // "screen", "window", "region"
    property string selectedWindowGeom: ""
    property string selectedWindowTitle: ""
    // "auto" deixa o rice-record escolher o encoder que a máquina realmente tem.
    // Fixar NVENC como padrão quebrava a gravação em qualquer PC sem NVIDIA.
    property string selectedCodec: "auto" // auto | h264_nvenc (NVIDIA) | h264_vaapi (Intel/AMD) | libx264 (CPU)

    // Qual encoder o modo automático vai escolher nesta máquina (só pro rótulo;
    // quem decide de verdade é o detect_codec() do rice-record).
    readonly property string effectiveCodec: {
        if (selectedCodec !== "auto") return selectedCodec;
        const gpu = (SysStats.gpuName || "").toLowerCase();
        if (gpu.indexOf("nvidia") !== -1 || gpu.indexOf("geforce") !== -1 || gpu.indexOf("rtx") !== -1 || gpu.indexOf("gtx") !== -1)
            return "h264_nvenc";
        return "h264_vaapi";
    }
    readonly property bool codecIsHardware: effectiveCodec !== "libx264"
    readonly property string codecBadgeText: {
        const prefix = selectedCodec === "auto" ? "⚙ " : "";
        if (effectiveCodec === "h264_nvenc") return prefix + "⚡ NVENC (" + SysStats.gpuName + ")";
        if (effectiveCodec === "h264_vaapi") return prefix + "🎮 GPU (VAAPI)";
        return prefix + "💻 CPU";
    }
    property bool audioDesktop: true
    property bool audioMic: false
    property int fpsRate: 60
    property var recentRecordings: []
    property var openWindows: []

    function formatDuration(sec) {
        const s = Math.max(0, Math.floor(sec || 0));
        const m = Math.floor(s / 60);
        const rem = s % 60;
        return (m < 10 ? "0" + m : m) + ":" + (rem < 10 ? "0" + rem : rem);
    }

    function refresh() {
        statusProc.running = true;
        listProc.running = true;
        windowsProc.running = true;
    }

    onVisibleChanged: {
        if (visible) refresh();
    }

    // Polling regular quando o painel está visível para sincronizar status
    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        onTriggered: {
            statusProc.running = true;
            if (root.isRecording) {
                root.elapsedSeconds++;
            }
        }
    }

    // Processo de Status
    Process {
        id: statusProc
        command: ["rice-record", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.isRecording = !!data.recording;
                    if (data.recording) {
                        root.elapsedSeconds = data.elapsed || root.elapsedSeconds;
                        root.recordingFile = data.file || "";
                    } else {
                        root.elapsedSeconds = 0;
                    }
                } catch (e) {}
            }
        }
    }

    // Processo de Lista de Gravações
    Process {
        id: listProc
        command: ["rice-record", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.recentRecordings = JSON.parse(text) || [];
                } catch (e) {
                    root.recentRecordings = [];
                }
            }
        }
    }

    // Processo de Lista de Janelas Abertas
    Process {
        id: windowsProc
        command: ["rice-record", "list-windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const wins = JSON.parse(text) || [];
                    root.openWindows = wins;
                    if (wins.length > 0 && !root.selectedWindowGeom) {
                        root.selectedWindowGeom = wins[0].geom;
                        root.selectedWindowTitle = (wins[0].class ? wins[0].class + ": " : "") + wins[0].title;
                    }
                } catch (e) {
                    root.openWindows = [];
                }
            }
        }
    }

    // Processo de Iniciar Gravação
    Process {
        id: startProc
        property var procArgs: []
        command: ["rice-record", "start"].concat(procArgs)
        onExited: {
            statusProc.running = true;
            listProc.running = true;
        }
    }

    // Processo de Parar Gravação
    Process {
        id: stopProc
        command: ["rice-record", "stop"]
        onExited: {
            root.isRecording = false;
            root.elapsedSeconds = 0;
            statusProc.running = true;
            listProc.running = true;
        }
    }

    // Processo de Selecionar Região/Janela com Slurp
    Process {
        id: slurpProc
        command: ["rice-record", "select-geom"]
        stdout: StdioCollector {
            onStreamFinished: {
                const geom = text.trim();
                if (geom) {
                    root.selectedWindowGeom = geom;
                    root.selectedWindowTitle = "Área Selecionada (" + geom + ")";
                }
            }
        }
    }

    // Processo de Ações com Arquivos
    Process { id: openFolderProc; command: ["rice-record", "open-folder"] }
    // Chamado de dentro dos componentes da lista, que não enxergam o id do timer.
    function scheduleRefresh() { recRefreshTimer.restart(); }
    Timer {
        id: recRefreshTimer
        interval: 500
        repeat: false
        onTriggered: listProc.running = true
    }

    function toggleRecording() {
        if (isRecording) {
            stopProc.running = true;
        } else {
            const args = [];
            args.push("--mode", captureMode);
            if (captureMode === "window" || captureMode === "region") {
                if (selectedWindowGeom) {
                    args.push("--geom", selectedWindowGeom);
                }
            }
            args.push("--audio-desktop", audioDesktop ? "1" : "0");
            args.push("--audio-mic", audioMic ? "1" : "0");
            args.push("--fps", String(fpsRate));
            args.push("--codec", selectedCodec);

            startProc.procArgs = args;
            startProc.running = true;
            isRecording = true;
            elapsedSeconds = 0;
        }
    }

    function formatTime(sec) {
        const h = Math.floor(sec / 3600);
        const m = Math.floor((sec % 3600) / 60);
        const s = sec % 60;
        const pad = (n) => (n < 10 ? "0" + n : String(n));
        return (h > 0 ? pad(h) + ":" : "") + pad(m) + ":" + pad(s);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gap + 2

        // ==========================================
        // 1. CARD PRINCIPAL DE CONTROLE & STATUS
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 84
            radius: Theme.tileRadius
            color: Theme.tile
            border.color: root.isRecording ? "#ef4444" : Theme.withAlpha(Theme.outline, 0.3)
            border.width: root.isRecording ? 2 : 1

            // Animação de pulso quando gravando
            SequentialAnimation on border.color {
                running: root.isRecording
                loops: Animation.Infinite
                ColorAnimation { to: "#b91c1c"; duration: 700 }
                ColorAnimation { to: "#ef4444"; duration: 700 }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.gap + 4
                spacing: Theme.gap * 2

                // Indicador de Status com Ícone
                Rectangle {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    radius: 24
                    color: root.isRecording ? Theme.withAlpha("#ef4444", 0.25) : Theme.withAlpha(Theme.primary, 0.15)

                    Text {
                        anchors.centerIn: parent
                        text: root.isRecording ? Theme.icons.record : Theme.icons.camera
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 22
                        color: root.isRecording ? "#ef4444" : Theme.primary
                    }
                }

                // Texto de Status e Timer
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        spacing: 8
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: root.isRecording ? "#ef4444" : "#10b981"
                            SequentialAnimation on opacity {
                                running: root.isRecording
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
                        }
                        Text {
                            text: root.isRecording ? Theme.t("recording.status_recording", "GRAVANDO TELA...") : Theme.t("recording.studio_title", "ESTÚDIO DE GRAVAÇÃO")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: root.isRecording ? "#ef4444" : Theme.subtext
                        }

                        // Badge da GPU em uso
                        Rectangle {
                            height: 18
                            implicitWidth: gpuBadgeRow.implicitWidth + 12
                            radius: 9
                            color: root.codecIsHardware ? Theme.withAlpha("#10b981", 0.2) : Theme.withAlpha(Theme.primary, 0.2)
                            border.width: 1
                            border.color: root.codecIsHardware ? "#10b981" : Theme.primary

                            RowLayout {
                                id: gpuBadgeRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: root.codecBadgeText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: root.codecIsHardware ? "#10b981" : Theme.primary
                                }
                            }
                        }

                        // Timer
                        Text {
                            visible: root.isRecording
                            text: root.formatDuration(root.elapsedSeconds)
                            font.family: Theme.monoFamily
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Theme.textColor
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // Botão Abrir Pasta de Gravações
                Rectangle {
                    Layout.preferredHeight: 36
                    implicitWidth: folderBtnRow.implicitWidth + 24
                    radius: Theme.tileRadius
                    color: openFolderArea.containsMouse ? Theme.tileHigh : Theme.tile
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outline, 0.3)

                    RowLayout {
                        id: folderBtnRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: Theme.icons.disk
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 15
                            color: Theme.textColor
                        }
                        Text {
                            text: Theme.t("recording.open_folder", "Abrir Pasta")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: Theme.textColor
                        }
                    }

                    MouseArea {
                        id: openFolderArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: openFolderProc.running = true
                    }
                }

                // Botão Grande de Iniciar / Parar Gravação
                Rectangle {
                    Layout.preferredHeight: 46
                    Layout.preferredWidth: 165
                    radius: Theme.tileRadius
                    color: root.isRecording
                        ? (recBtnArea.containsMouse ? "#dc2626" : "#ef4444")
                        : (recBtnArea.containsMouse ? Qt.lighter(Theme.primary, 1.1) : Theme.primary)

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: root.isRecording ? "\u{F04DB}" : Theme.icons.record
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 18
                            color: root.isRecording ? "#ffffff" : Theme.background
                        }
                        Text {
                            text: root.isRecording ? "Parar Gravação" : "Iniciar Gravação"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: root.isRecording ? "#ffffff" : Theme.background
                        }
                    }

                    MouseArea {
                        id: recBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleRecording()
                    }
                }
            }
        }

        // ==========================================
        // 2. CORPO DIVIDIDO: CONFIGURAÇÕES & HISTÓRICO
        // ==========================================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.gap + 2

            // ------------------------------------------
            // COLUNA DA ESQUERDA: CONFIGURAÇÕES DE VÍDEO E ÁUDIO
            // ------------------------------------------
            Rectangle {
                Layout.preferredWidth: 400
                Layout.fillHeight: true
                radius: Theme.tileRadius
                color: Theme.tile
                border.color: Theme.withAlpha(Theme.outline, 0.25)
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.gap + 4
                    spacing: 8

                    // Seção de Vídeo
                    Text {
                        text: "FONTE DE VÍDEO"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    // Seletor de Modo: Tela Inteira / Aplicativo / Região
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { mode: "screen", label: "Tela Inteira", icon: Theme.icons.monitor },
                                { mode: "window", label: "Aplicativo", icon: Theme.icons.laptop },
                                { mode: "region", label: "Região", icon: Theme.icons.fileCompare }
                            ]
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                radius: 8
                                color: root.captureMode === modelData.mode
                                    ? Theme.withAlpha(Theme.primary, 0.22)
                                    : (modeArea.containsMouse ? Theme.withAlpha(Theme.textColor, 0.08) : Theme.tileHigh)
                                border.color: root.captureMode === modelData.mode ? Theme.primary : Theme.withAlpha(Theme.outline, 0.25)
                                border.width: 1

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 1
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.icon
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 14
                                        color: root.captureMode === modelData.mode ? Theme.primary : Theme.textColor
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: root.captureMode === modelData.mode ? Font.Bold : Font.Normal
                                        color: root.captureMode === modelData.mode ? Theme.primary : Theme.textColor
                                    }
                                }

                                MouseArea {
                                    id: modeArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.captureMode = modelData.mode;
                                        if (modelData.mode === "region") {
                                            slurpProc.running = true;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Opções de Janela / Aplicativo se o modo for "window" ou "region"
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.captureMode === "window" ? 92 : 56
                        radius: 8
                        visible: root.captureMode !== "screen"
                        color: Theme.tileHigh
                        border.color: Theme.withAlpha(Theme.outline, 0.25)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: root.captureMode === "window" ? "Alvo da Captura:" : "Região Definida:"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.subtext
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "Selecionar na Tela"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: Theme.primary
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: slurpProc.running = true
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.selectedWindowTitle || (root.selectedWindowGeom ? root.selectedWindowGeom : "Clique em 'Selecionar na Tela'")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: Theme.textColor
                                elide: Text.ElideMiddle
                            }

                            // Chips de Janelas Abertas (apenas modo janela)
                            Flickable {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                contentWidth: winChipsRow.implicitWidth
                                clip: true
                                visible: root.captureMode === "window" && root.openWindows.length > 0

                                Row {
                                    id: winChipsRow
                                    spacing: 6
                                    Repeater {
                                        model: root.openWindows
                                        delegate: Rectangle {
                                            readonly property bool isSelected: root.selectedWindowGeom === modelData.geom
                                            height: 22
                                            width: winChipText.implicitWidth + 14
                                            radius: 11
                                            color: isSelected ? Theme.primary : (chipArea.containsMouse ? Theme.withAlpha(Theme.textColor, 0.12) : Theme.withAlpha(Theme.background, 0.5))
                                            border.color: isSelected ? Theme.primary : Theme.withAlpha(Theme.outline, 0.25)
                                            border.width: 1

                                            Text {
                                                id: winChipText
                                                anchors.centerIn: parent
                                                text: modelData.class || modelData.title
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                font.weight: isSelected ? Font.Bold : Font.Normal
                                                color: isSelected ? Theme.background : Theme.textColor
                                            }

                                            MouseArea {
                                                id: chipArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.selectedWindowGeom = modelData.geom;
                                                    root.selectedWindowTitle = (modelData.class ? modelData.class + ": " : "") + modelData.title;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Seletor de Hardware Encoder (NVIDIA dGPU vs Intel vs CPU)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "GPU / Encoder:"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.subtext
                        }
                        Item { Layout.fillWidth: true }

                        Repeater {
                            model: [
                                { id: "auto", label: Theme.t("rec.codec_auto", "Automático") },
                                { id: "h264_nvenc", label: "NVIDIA (" + SysStats.gpuName + ")" },
                                { id: "h264_vaapi", label: "VAAPI (GPU)" },
                                { id: "libx264", label: "CPU" }
                            ]
                            delegate: Rectangle {
                                readonly property bool isSelected: root.selectedCodec === modelData.id
                                Layout.preferredHeight: 26
                                Layout.preferredWidth: encText.implicitWidth + 14
                                radius: 6
                                color: isSelected ? Theme.withAlpha(Theme.primary, 0.2) : Theme.tileHigh
                                border.color: isSelected ? Theme.primary : Theme.withAlpha(Theme.outline, 0.25)
                                border.width: 1

                                Text {
                                    id: encText
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: isSelected ? Font.Bold : Font.Normal
                                    color: isSelected ? Theme.primary : Theme.textColor
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedCodec = modelData.id
                                }
                            }
                        }
                    }

                    // Taxa de Quadros (FPS)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: "Taxa de Quadros:"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.subtext
                        }
                        Item { Layout.fillWidth: true }
                        Repeater {
                            model: [60, 144]
                            delegate: Rectangle {
                                Layout.preferredWidth: 60
                                Layout.preferredHeight: 26
                                radius: 6
                                color: root.fpsRate === modelData
                                    ? Theme.primary
                                    : (fpsArea.containsMouse ? Theme.withAlpha(Theme.textColor, 0.1) : Theme.tileHigh)
                                border.color: root.fpsRate === modelData ? Theme.primary : Theme.withAlpha(Theme.outline, 0.25)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData + " FPS"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: root.fpsRate === modelData ? Theme.background : Theme.textColor
                                }

                                MouseArea {
                                    id: fpsArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.fpsRate = modelData
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.withAlpha(Theme.outline, 0.25)
                    }

                    // Seção de Áudio
                    Text {
                        text: "ÁUDIO & FONTES (PIPEWIRE)"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    // Toggle Áudio do Sistema
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        radius: 8
                        color: root.audioDesktop ? Theme.withAlpha(Theme.primary, 0.15) : Theme.tileHigh
                        border.color: root.audioDesktop ? Theme.withAlpha(Theme.primary, 0.5) : Theme.withAlpha(Theme.outline, 0.25)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 10

                            Text {
                                text: root.audioDesktop ? Theme.icons.volHigh : Theme.icons.volOff
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 18
                                color: root.audioDesktop ? Theme.primary : Theme.subtext
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: "Áudio do Sistema (Desktop)"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    color: Theme.textColor
                                }
                                Text {
                                    text: "Jogos, navegador, música e mídias"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.subtext
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 20
                                radius: 10
                                color: root.audioDesktop ? Theme.primary : Theme.withAlpha(Theme.outline, 0.4)
                                Rectangle {
                                    width: 14
                                    height: 14
                                    radius: 7
                                    x: root.audioDesktop ? 19 : 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.textColor
                                    Behavior on x { NumberAnimation { duration: 120 } }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.audioDesktop = !root.audioDesktop
                        }
                    }

                    // Toggle Microfone
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        radius: 8
                        color: root.audioMic ? Theme.withAlpha(Theme.primary, 0.15) : Theme.tileHigh
                        border.color: root.audioMic ? Theme.withAlpha(Theme.primary, 0.5) : Theme.withAlpha(Theme.outline, 0.25)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 10

                            Text {
                                text: root.audioMic ? Theme.icons.mic : Theme.icons.micOff
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 18
                                color: root.audioMic ? Theme.primary : Theme.subtext
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: "Microfone (Voz)"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    color: Theme.textColor
                                }
                                Text {
                                    text: "Entrada de voz padrão do sistema"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.subtext
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 20
                                radius: 10
                                color: root.audioMic ? Theme.primary : Theme.withAlpha(Theme.outline, 0.4)
                                Rectangle {
                                    width: 14
                                    height: 14
                                    radius: 7
                                    x: root.audioMic ? 19 : 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.textColor
                                    Behavior on x { NumberAnimation { duration: 120 } }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.audioMic = !root.audioMic
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ------------------------------------------
            // COLUNA DA DIREITA: GRAVAÇÕES RECENTES
            // ------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.tileRadius
                color: Theme.tile
                border.color: Theme.withAlpha(Theme.outline, 0.25)
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.gap + 4
                    spacing: Theme.gap

                    // Cabeçalho da Galeria
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "GRAVAÇÕES RECENTES"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: Theme.primary
                        }

                        Rectangle {
                            Layout.preferredHeight: 18
                            Layout.preferredWidth: countText.implicitWidth + 12
                            radius: 9
                            color: Theme.withAlpha(Theme.primary, 0.15)
                            border.color: Theme.withAlpha(Theme.primary, 0.35)
                            border.width: 1

                            Text {
                                id: countText
                                anchors.centerIn: parent
                                text: String(root.recentRecordings.length)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: Theme.primary
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Botão Recarregar
                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 14
                            color: refRecArea.containsMouse ? Theme.tileHigh : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: Theme.icons.refresh
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 14
                                color: Theme.subtext
                            }
                            MouseArea {
                                id: refRecArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: listProc.running = true
                            }
                        }
                    }

                    // Lista de Vídeos Recentes
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListView {
                            id: recView
                            anchors.fill: parent
                            clip: true
                            spacing: 6
                            model: root.recentRecordings

                            delegate: Rectangle {
                                width: recView.width
                                height: 54
                                radius: 8
                                color: recItemArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.background, 0.45)
                                border.color: Theme.withAlpha(Theme.outline, 0.25)
                                border.width: 1

                                MouseArea {
                                    id: recItemArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton
                                    onDoubleClicked: {
                                        playProc.command = ["rice-record", "play", modelData.path];
                                        playProc.running = true;
                                    }
                                }

                                RowLayout {
                                    z: 2
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 10

                                    // Ícone de Vídeo
                                    Rectangle {
                                        Layout.preferredWidth: 34
                                        Layout.preferredHeight: 34
                                        radius: 6
                                        color: Theme.withAlpha(Theme.primary, 0.15)
                                        Text {
                                            anchors.centerIn: parent
                                            text: Theme.icons.video || Theme.icons.record
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 15
                                            color: Theme.primary
                                        }
                                    }

                                    // Nome, data e tamanho
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            color: Theme.textColor
                                            elide: Text.ElideMiddle
                                        }

                                        RowLayout {
                                            spacing: 8
                                            Text {
                                                text: modelData.date
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                color: Theme.subtext
                                            }
                                            Text {
                                                text: "•"
                                                font.pixelSize: 10
                                                color: Theme.subtext
                                            }
                                            Text {
                                                text: modelData.size
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                color: Theme.subtext
                                            }
                                        }
                                    }

                                    // Botão Reproduzir
                                    Rectangle {
                                        Layout.preferredWidth: 30
                                        Layout.preferredHeight: 30
                                        radius: 15
                                        color: playBtnArea.containsMouse ? Theme.primary : Theme.tileHigh

                                        Text {
                                            anchors.centerIn: parent
                                            anchors.horizontalCenterOffset: 1
                                            text: Theme.icons.play
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 13
                                            color: playBtnArea.containsMouse ? Theme.background : Theme.textColor
                                        }

                                        MouseArea {
                                            id: playBtnArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                Quickshell.execDetached(["rice-record", "play", modelData.path]);
                                            }
                                        }
                                    }

                                    // Botão Excluir
                                    Rectangle {
                                        Layout.preferredWidth: 30
                                        Layout.preferredHeight: 30
                                        radius: 15
                                        color: delBtnArea.containsMouse ? Theme.withAlpha("#ef4444", 0.25) : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: Theme.icons.trash
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 13
                                            color: delBtnArea.containsMouse ? "#ef4444" : Theme.subtext
                                        }

                                        MouseArea {
                                            id: delBtnArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const pathToDelete = modelData.path;
                                                Quickshell.execDetached(["rice-record", "delete", pathToDelete]);
                                                root.recentRecordings = root.recentRecordings.filter(function(item) { return item.path !== pathToDelete; });
                                                root.scheduleRefresh();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Estado vazio se não houver vídeos
                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: root.recentRecordings.length === 0
                            spacing: 8

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: Theme.icons.video || Theme.icons.record
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 36
                                color: Theme.withAlpha(Theme.subtext, 0.4)
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Nenhuma gravação recente"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: Theme.subtext
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Grave sua tela ou jogos e seus vídeos aparecerão aqui."
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.withAlpha(Theme.subtext, 0.7)
                            }
                        }
                    }
                }
            }
        }
    }
}
