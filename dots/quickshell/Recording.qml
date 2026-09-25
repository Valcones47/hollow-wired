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
    property string view: "record"   // "record" | "library"
    // `qs ipc call recording view library` (testes e atalhos).
    IpcHandler {
        target: "recording"
        function view(v: string): void { if (v === "record" || v === "library") root.view = v; }
    }
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
        const auto = selectedCodec === "auto" ? Theme.t("rec.codec_auto", "Automático") + " · " : "";
        if (effectiveCodec === "h264_nvenc") return auto + "NVENC" + (SysStats.gpuName ? " · " + SysStats.gpuName : "");
        if (effectiveCodec === "h264_vaapi") return auto + "VAAPI";
        return auto + "CPU";
    }
    property bool audioDesktop: true
    property bool audioMic: false
    property int fpsRate: 60
    // Bitrate da gravação em kbps (0 = qualidade constante). Lembrado em
    // ~/.config/hollow-wired/record.json.
    property int bitrateKbps: 0
    function setBitrate(k) {
        bitrateKbps = k;
        recPrefs.setText(JSON.stringify({ bitrate_kbps: k }) + "\n");
    }
    FileView {
        id: recPrefs
        path: Quickshell.env("HOME") + "/.config/hollow-wired/record.json"
        printErrors: false
        onLoaded: {
            try { root.bitrateKbps = Math.max(0, parseInt((JSON.parse(text()) || {}).bitrate_kbps) || 0); } catch (e) {}
        }
    }
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
        if (view === "library") library.refresh();
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
            args.push("--bitrate", String(bitrateKbps));
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
            border.color: root.isRecording ? Theme.critical : Theme.withAlpha(Theme.outline, 0.3)
            border.width: root.isRecording ? 2 : 1

            // Animação de pulso quando gravando
            SequentialAnimation on border.color {
                running: root.isRecording
                loops: Animation.Infinite
                ColorAnimation { to: Theme.withAlpha(Theme.critical, 0.6); duration: 700 }
                ColorAnimation { to: Theme.critical; duration: 700 }
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
                    color: root.isRecording ? Theme.withAlpha(Theme.critical, 0.25) : Theme.withAlpha(Theme.primary, 0.15)

                    Text {
                        anchors.centerIn: parent
                        text: root.isRecording ? Theme.icons.record : Theme.icons.camera
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 22
                        color: root.isRecording ? Theme.critical : Theme.primary
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
                            color: root.isRecording ? Theme.critical : Theme.subtext
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
                            color: root.isRecording ? Theme.critical : Theme.subtext
                        }

                        // Badge da GPU em uso
                        Rectangle {
                            height: 18
                            implicitWidth: gpuBadgeRow.implicitWidth + 12
                            radius: 9
                            color: root.codecIsHardware ? "transparent" : Theme.withAlpha(Theme.primary, 0.2)

                            RowLayout {
                                id: gpuBadgeRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: root.codecBadgeText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: root.codecIsHardware ? Theme.subtext : Theme.primary
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
                        ? (recBtnArea.containsMouse ? Theme.critical : Theme.critical)
                        : (recBtnArea.containsMouse ? Qt.lighter(Theme.primary, 1.1) : Theme.primary)

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: root.isRecording ? "\u{F04DB}" : Theme.icons.record
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 18
                            color: root.isRecording ? Theme.background : Theme.background
                        }
                        Text {
                            text: root.isRecording ? "Parar Gravação" : "Iniciar Gravação"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: root.isRecording ? Theme.background : Theme.background
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
        // Subabas: gravar (configurações) e gerenciar as gravações.
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: [
                    { k: "record", label: Theme.t("rec.tab_record", "Gravar") },
                    { k: "library", label: Theme.t("rec.tab_library", "Gravações") + (root.recentRecordings.length ? "  " + root.recentRecordings.length : "") }
                ]
                delegate: Rectangle {
                    id: st
                    required property var modelData
                    readonly property bool on: root.view === st.modelData.k
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 9
                    color: st.on ? Theme.tileHigh : (stArea.containsMouse ? Theme.withAlpha(Theme.tileHigh, 0.5) : Theme.withAlpha(Theme.tile, 0.5))
                    Text {
                        anchors.centerIn: parent
                        text: st.modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: st.on ? Font.DemiBold : Font.Normal
                        color: st.on ? Theme.textColor : Theme.subtext
                    }
                    MouseArea {
                        id: stArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.view = st.modelData.k
                    }
                }
            }
        }

        RecordingLibrary {
            id: library
            visible: root.view === "library"
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        RowLayout {
            visible: root.view === "record"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.gap + 2

            // ------------------------------------------
            // COLUNA DA ESQUERDA: VÍDEO
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
                    spacing: 8

                    // Seção de Vídeo
                    Text {
                        text: Theme.t("rec.source", "FONTE DE VÍDEO")
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
                                    text: Theme.t("rec.pick_screen", "Selecionar na Tela")
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
                            text: Theme.t("rec.encoder", "Codificador")
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
                            text: Theme.t("rec.fps", "Quadros por segundo")
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

                    // Bitrate: tamanho x qualidade do arquivo. Fixo (CBR) nos níveis;
                    // "Constante" deixa o codificador decidir (o antigo, arquivo grande).
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: Theme.t("rec.bitrate", "Bitrate")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.subtext
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: root.bitrateKbps > 0
                                    ? Theme.t("rec.bitrate_per_min", "até ~%1 MB por minuto").replace("%1", Math.round(root.bitrateKbps * 60 / 8192 + 1))
                                    : Theme.t("rec.bitrate_var", "tamanho varia com o movimento")
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.subtext
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: [
                                    { kbps: 4000, label: Theme.t("rec.br_low", "Baixo") },
                                    { kbps: 8000, label: Theme.t("rec.br_mid", "Médio") },
                                    { kbps: 16000, label: Theme.t("rec.br_high", "Alto") },
                                    { kbps: 30000, label: Theme.t("rec.br_vhigh", "Muito alto") },
                                    { kbps: 50000, label: Theme.t("rec.br_max", "Máximo") },
                                    { kbps: 0, label: Theme.t("rec.br_const", "Constante") }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: root.bitrateKbps === modelData.kbps
                                    height: 26
                                    width: brRow.implicitWidth + 16
                                    radius: 6
                                    color: sel ? Theme.primary : (brArea.containsMouse ? Theme.withAlpha(Theme.textColor, 0.1) : Theme.tileHigh)
                                    Row {
                                        id: brRow
                                        anchors.centerIn: parent
                                        spacing: 5
                                        Text {
                                            text: modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: sel ? Theme.background : Theme.textColor
                                        }
                                        Text {
                                            text: modelData.kbps > 0 ? (modelData.kbps / 1000) + " Mbps" : Theme.t("rec.br_const_q", "qualidade fixa")
                                            font.family: Theme.monoFamily
                                            font.pixelSize: 10
                                            color: sel ? Theme.withAlpha(Theme.background, 0.8) : Theme.subtext
                                        }
                                    }
                                    MouseArea {
                                        id: brArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setBitrate(modelData.kbps)
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // COLUNA DA DIREITA: ÁUDIO
            Rectangle {
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                radius: Theme.tileRadius
                color: Theme.tile
                border.color: Theme.withAlpha(Theme.outline, 0.25)
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.gap + 4
                    spacing: 8

                    // Seção de Áudio
                    Text {
                        text: Theme.t("rec.audio", "ÁUDIO")
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
                                    text: Theme.t("rec.audio_sys", "Áudio do sistema")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    color: Theme.textColor
                                }
                                Text {
                                    text: Theme.t("rec.audio_sys_sub", "Jogos, navegador, música e vídeos")
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
                                    text: Theme.t("rec.audio_mic", "Microfone")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    color: Theme.textColor
                                }
                                Text {
                                    text: Theme.t("rec.audio_mic_sub", "O microfone padrão do sistema")
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

        }
    }
}
