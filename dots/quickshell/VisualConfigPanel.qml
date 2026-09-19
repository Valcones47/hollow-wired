import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "."

// Painel de Configurações Visuais do Rice (Rice Control Center):
// - 0. Fastfetch (Logos em ~/Imagens/FastFetch, dimensões, módulos, preview no terminal)
// - 1. Kitty Terminal (Opacidade, fonte, padding, blur, cursor, áudio)
// - 2. Mako Notificações (Posição 3x2, timeout, bordas, raio, teste)
// - 3. Tela & Monitores (Detecção eDP-1, 144Hz vs 60Hz, VRR FreeSync, slider de brilho)
// - 4. Áudio & Som (Saída padrão, microfone padrão, volume, teste de som estéreo E/D)
// - 5. Teclado & Mouse (ABNT2 vs US Intl, sensibilidade, aceleração Flat vs Adaptativa, NumLock)
// - 6. Energia & Bateria (Perfis Desempenho/Equilíbrio/Economia, saúde da bateria %, ciclos)
// - 7. Inicialização / Autostart (Gerenciador de apps no boot com toggles e adicionar apps)
// - 8. Cores & Wallust (Paleta completa de 16 cores com cópia HEX, regenerar cores, switcher)
// - 9. Efeitos & Janelas (Luz noturna, dim inativo, arredondamento, gaps, animações, SDDM/Limine)
// - 10. Sistema & Restauração (Snapshots Btrfs com 1 clique, reiniciar áudio, destravar pacman, Doctor)
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
    Component.onCompleted: win.refreshAll()

    // ================= DADOS & ESTADO =================
    property int currentTab: 0 // 0..10

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
    property real monitorScale: 1.0
    property bool vrrEnabled: false
    property int screenBrightness: 40
    property var availableHzList: [144, 60]

    // Áudio
    property var audioData: ({ sinks: [], sources: [], sink_volume: 100, source_volume: 80, sink_muted: false, source_muted: false })

    // Teclado & Mouse
    property string kbLayout: "br"
    property real mouseSensitivity: 0.0
    property string mouseAccel: "flat"
    property bool numlock: true
    property string discordClient: "discord"
    property bool discordRunning: false
    property string discordMuteBind: "CTRL + SHIFT + M"
    property string discordDeafenBind: "Num_Lock"

    // Energia & Bateria
    property var powerData: ({ has_battery: true, percent: 100, status: "AC Conectado", health: 100, cycles: 0, profile: "performance" })

    // Autostart
    property var autostartEntries: []
    property var availableApps: []

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

    // Snapshots Btrfs
    property var snapshotsData: ({ snapshots: [] })

    // Bluetooth
    property var btData: ({ powered: true, discovering: false, devices: [] })

    // Rede & Wi-Fi
    property var netData: ({ wifi_enabled: true, connected_ssid: "", signal: 0, security: "", ip: "", gateway: "", is_5g: false })
    property var netScanData: []
    property var pingMs: null
    property string netPassInput: ""
    property string netSelectedSsid: ""

    // Aplicativos Padrão
    property var defaultAppsData: ({ browser: {}, filemanager: {}, editor: {}, video: {}, image: {}, audio: {} })
    property string pickingDefaultCategory: ""
    property string defaultAppSearchQuery: ""

    // Jogos & GPU
    property var gamingData: ({ gpu: { name: "", temp: 0, vram_used: 0, vram_total: 4096, util: 0, available: false }, gamemode_active: false })

    // Armazenamento
    property var storageData: ({ root_total: "", root_used: "", root_avail: "", root_pct: 0, pacman_cache: "", thumbnails: "", trash: "", user_cache: "" })

    // Guia de Atalhos
    property string bindsFilter: ""

    // Central de Softwares & Atualizações
    property var softwareUpdatesData: ({ count: 0, packages: [], checked_at: "" })
    property var softwareCatalogData: []
    property string softwareCatFilter: "all"
    property string softwareSearchQuery: ""

    // Perfis de Estilo & Backups
    property var presetsData: []
    property var backupsData: []

    // Toast de notificação interna
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
    function appIconSource(iconName) {
        if (!iconName || iconName === "") {
            return Quickshell.iconPath("application-x-executable");
        }
        if (iconName.startsWith("/") || iconName.startsWith("file://")) {
            return iconName.startsWith("file://") ? iconName : "file://" + iconName;
        }
        return Quickshell.iconPath(iconName, "application-x-executable");
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
                    if (d.monitor_scale !== undefined) win.monitorScale = parseFloat(d.monitor_scale) || 1.0;
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
                        if (arr[0].scale) win.monitorScale = parseFloat(arr[0].scale) || 1.0;

                        const modes = arr[0].availableModes || [];
                        const hzSet = {};
                        for (let i = 0; i < modes.length; i++) {
                            const m = modes[i].match(/@([0-9]+(?:\.[0-9]+)?)Hz/);
                            if (m && m[1]) {
                                const rounded = Math.round(parseFloat(m[1]));
                                if (rounded > 0) hzSet[rounded] = true;
                            }
                        }
                        if (win.monitorHz > 0) hzSet[win.monitorHz] = true;
                        let hzList = Object.keys(hzSet).map(Number).sort((a, b) => b - a);
                        if (hzList.length === 0) hzList = [144, 60];
                        win.availableHzList = hzList;
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

    Process {
        id: loadAudioProc
        command: ["rice-audio", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.audioData = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadPowerProc
        command: ["rice-power", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.powerData = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadAutostartProc
        command: ["rice-autostart", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.autostartEntries = JSON.parse(text) || [];
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadAvailableAppsProc
        command: ["rice-autostart", "available"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.availableApps = JSON.parse(text) || [];
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadSnapshotsProc
        command: ["rice-snapshots", "list", "6"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.snapshotsData = JSON.parse(text) || { snapshots: [] };
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadBtProc
        command: ["rice-bluetooth", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.btData = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadNetProc
        command: ["rice-network", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.netData = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadNetScanProc
        command: ["rice-network", "scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.netScanData = JSON.parse(text) || [];
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadPingProc
        command: ["rice-network", "ping"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    win.pingMs = d.ping_ms;
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadDefaultAppsProc
        command: ["rice-default-apps", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.defaultAppsData = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadGamingProc
        command: ["rice-gaming", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.gamingData = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadStorageProc
        command: ["rice-storage", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.storageData = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadSoftwareUpdatesProc
        command: ["rice-software", "updates"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.softwareUpdatesData = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadSoftwareAppsProc
        command: ["rice-software", "apps"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.softwareCatalogData = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadPresetsProc
        command: ["rice-presets", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.presetsData = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadBackupsProc
        command: ["rice-presets", "backup-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    win.backupsData = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadDiscordProc
        command: ["rice-discord-binds", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d) {
                        win.discordClient = d.client || "discord";
                        win.discordRunning = !!d.running;
                        win.discordMuteBind = d.mute_bind || "CTRL + SHIFT + M";
                        win.discordDeafenBind = d.deafen_bind || "Num_Lock";
                    }
                } catch (e) {}
            }
        }
    }

    property string recordingDiscordTarget: ""
    property bool editingManualMute: false
    property bool editingManualDeafen: false

    Process {
        id: recordDiscordProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                try {
                    const d = JSON.parse(line.trim());
                    if (d.status === "ok") {
                        if (d.target === "mute") {
                            win.discordMuteBind = d.key;
                            win.showToast(Theme.t("discord.recorded_mute", "Tecla de Mute gravada: ") + d.key);
                        } else if (d.target === "deafen") {
                            win.discordDeafenBind = d.key;
                            win.showToast(Theme.t("discord.recorded_deafen", "Tecla de Deafen gravada: ") + d.key);
                        }
                    } else if (d.status === "cancelled") {
                        win.showToast(Theme.t("discord.cancel", "Gravação cancelada"));
                    } else if (d.status === "timeout") {
                        win.showToast("Tempo esgotado (nenhuma tecla detectada)");
                    }
                } catch (e) {}
                win.recordingDiscordTarget = "";
            }
        }
        onExited: {
            win.recordingDiscordTarget = "";
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
        loadAudioProc.running = true;
        loadPowerProc.running = true;
        loadAutostartProc.running = true;
        loadAvailableAppsProc.running = true;
        loadSnapshotsProc.running = true;
        loadBtProc.running = true;
        loadNetProc.running = true;
        loadNetScanProc.running = true;
        loadPingProc.running = true;
        loadDefaultAppsProc.running = true;
        loadGamingProc.running = true;
        loadStorageProc.running = true;
        loadSoftwareUpdatesProc.running = true;
        loadSoftwareAppsProc.running = true;
        loadPresetsProc.running = true;
        loadBackupsProc.running = true;
        loadDiscordProc.running = true;
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

    component SwitchToggle: Rectangle {
        id: swt
        property bool checked: false
        signal toggled(bool nextVal)

        implicitWidth: 38
        implicitHeight: 20
        radius: 10
        color: swt.checked ? Theme.primary : Theme.tileHigh

        Rectangle {
            width: 14; height: 14; radius: 7
            anchors.verticalCenter: parent.verticalCenter
            x: swt.checked ? parent.width - width - 3 : 3
            color: Theme.textColor
            Behavior on x { NumberAnimation { duration: 140 } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: swt.toggled(!swt.checked)
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
        color: Qt.rgba(0, 0, 0, win.open ? 0.65 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea {
            anchors.fill: parent
            onClicked: win.open = false
        }
    }

    // ================= CARTÃO PRINCIPAL (SIDEBAR + CONTEÚDO) =================
    Rectangle {
        id: card
        width: 1040
        height: 660
        anchors.centerIn: parent
        radius: 20
        color: Theme.mix(Theme.background, "#0a0a12", 0.4)
        border.width: 1.5
        border.color: Theme.withAlpha(Theme.primary, 0.4)
        focus: win.open
        Keys.onEscapePressed: win.open = false

        // Borda com efeito sutil de profundidade
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: card.radius + 2
            color: "transparent"
            border.width: 1
            border.color: Theme.withAlpha(Theme.primary, 0.15)
            z: -1
        }

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
                Layout.preferredWidth: 248
                Layout.fillHeight: true
                topLeftRadius: 20
                bottomLeftRadius: 20
                color: Theme.withAlpha(Theme.mix(Theme.background, "#000000", 0.35), 0.75)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

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
                                text: Theme.t("settings.panel_title", "Painel Rice")
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                color: Theme.textColor
                            }
                            Text {
                                text: Theme.t("settings.panel_subtitle", "Central de Controle Gráfica")
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

                    // Campo de Busca de Configurações
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 8
                        color: Theme.withAlpha(Theme.background, 0.6)
                        border.width: 1
                        border.color: catSearchInput.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: Theme.icons.magnify
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 13
                                color: catSearchInput.activeFocus ? Theme.primary : Theme.subtext
                            }

                            TextInput {
                                id: catSearchInput
                                Layout.fillWidth: true
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textColor
                                selectByMouse: true
                                clip: true
                                property string query: text.toLowerCase().trim()

                                Text {
                                    visible: !catSearchInput.text && !catSearchInput.activeFocus
                                    text: Theme.t("settings.search_placeholder", "Buscar configurações...")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.withAlpha(Theme.subtext, 0.6)
                                }

                                onAccepted: {
                                    if (navRepeater.count > 0) {
                                        const firstItem = navRepeater.itemAt(0);
                                        if (firstItem && firstItem.targetTab !== undefined) {
                                            win.currentTab = firstItem.targetTab;
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: catSearchInput.text.length > 0
                                text: Theme.icons.close
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 12
                                color: Theme.subtext
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: catSearchInput.text = ""
                                }
                            }
                        }
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
                                { tabIndex: 0, name: Theme.t("settings.cat_fastfetch", "Fastfetch"), icon: Theme.icons.packages, desc: Theme.t("settings.desc_fastfetch", "Logo & Módulos"), keywords: "fastfetch neofetch logo distro terminal specs cpu ram hardware modelo" },
                                { tabIndex: 1, name: Theme.t("settings.cat_kitty", "Kitty Terminal"), icon: Theme.icons.console, desc: Theme.t("settings.desc_kitty", "Fonte & Opacidade"), keywords: "kitty terminal console fonte font opacidade padding cursor audio blur som" },
                                { tabIndex: 2, name: Theme.t("settings.cat_mako", "Notificações"), icon: Theme.icons.bell, desc: Theme.t("settings.desc_mako", "Posição & Estilo"), keywords: "mako notificacoes notifications som posicao borda alert toast banner" },
                                { tabIndex: 3, name: Theme.t("settings.cat_monitors", "Tela & Monitores"), icon: Theme.icons.monitor, desc: Theme.t("settings.desc_monitors", "144Hz & Brilho"), keywords: "tela monitor refresh rate hz taxa atualizacao resolucao escala zoom scale hidpi brilho brightness vrr freesync g-sync frequencia" },
                                { tabIndex: 4, name: Theme.t("settings.cat_audio", "Áudio & Som"), icon: Theme.icons.volHigh, desc: Theme.t("settings.desc_audio", "Saída & Microfone"), keywords: "audio som volume microfone mic fone speaker sink source pipewire dispositivos" },
                                { tabIndex: 5, name: Theme.t("settings.cat_input", "Teclado & Mouse"), icon: Theme.icons.tune, desc: Theme.t("settings.desc_input", "Layout & Sensibilidade"), keywords: "teclado mouse keyboard layout abnt2 sensibilidade aceleração accel numlock atalhos velocidade" },
                                { tabIndex: 6, name: Theme.t("settings.cat_power", "Energia & Bateria"), icon: Theme.icons.bat, desc: Theme.t("settings.desc_power", "Perfis & Saúde"), keywords: "energia bateria power perfis profiles saver balanced performance saude health suspenso sleep carga" },
                                { tabIndex: 7, name: Theme.t("settings.cat_boot", "Inicialização (Boot)"), icon: Theme.icons.speed, desc: Theme.t("settings.desc_boot", "Apps ao Iniciar"), keywords: "boot inicializacao startup autostart apps servicos sddm limine login inicio" },
                                { tabIndex: 8, name: Theme.t("settings.cat_wallust", "Cores & Wallust"), icon: Theme.icons.palette, desc: Theme.t("settings.desc_wallust", "Paleta Dinâmica"), keywords: "cores color colors wallust tema theme wallpaper paleta palette dinamica accent visual" },
                                { tabIndex: 9, name: Theme.t("settings.cat_effects", "Efeitos & Janelas"), icon: Theme.icons.laptop, desc: Theme.t("settings.desc_effects", "Bordas & SDDM"), keywords: "efeitos effects janelas windows blur desfoque bordas borders sombras shadows sddm animacoes animations transparência" },
                                { tabIndex: 10, name: Theme.t("settings.cat_bluetooth", "Bluetooth"), icon: Theme.icons.bt, desc: Theme.t("settings.desc_bluetooth", "Controles & Fones"), keywords: "bluetooth bt fones earbuds controle joystick pareamento connect conectar dispositivos" },
                                { tabIndex: 11, name: Theme.t("settings.cat_network", "Rede & Wi-Fi"), icon: Theme.icons.wifi4, desc: Theme.t("settings.desc_network", "Conexões & Latência"), keywords: "rede network wifi wi-fi conexao ethernet ip dns ping latencia internet speed" },
                                { tabIndex: 12, name: Theme.t("settings.cat_defaults", "Aplicativos Padrão"), icon: Theme.icons.dashboard, desc: Theme.t("settings.desc_defaults", "Navegador, Pastas & Vídeo"), keywords: "aplicativos padrao default apps navegador browser chrome firefox zen brave pasta dolphin nautilus video vlc player musica mpv email editor code text" },
                                { tabIndex: 13, name: Theme.t("settings.cat_gaming", "Jogos & GPU"), icon: Theme.icons.gamepad, desc: Theme.t("settings.desc_gaming", "NVIDIA, GameMode & Steam"), keywords: "jogos games gaming gpu nvidia prime prime-run dgpu igpu intel gamemode steam mangohud fps desempenho" },
                                { tabIndex: 14, name: Theme.t("settings.cat_storage", "Armazenamento"), icon: Theme.icons.disk, desc: Theme.t("settings.desc_storage", "Limpeza Segura de Disco"), keywords: "armazenamento storage disco disk espaco limpar limpeza cache lixeira logs btrfs free space" },
                                { tabIndex: 15, name: Theme.t("settings.cat_shortcuts", "Guia de Atalhos"), icon: Theme.icons.magnify, desc: Theme.t("settings.desc_shortcuts", "Buscar Teclas do Rice"), keywords: "atalhos shortcuts teclas binds keybinds cheatsheet super mod custom user-binds" },
                                { tabIndex: 16, name: Theme.t("settings.cat_system", "Sistema & Reparo"), icon: Theme.icons.health, desc: Theme.t("settings.desc_system", "Snapshots & Auto-Reparo"), keywords: "sistema system reparo repair snapshot timeshift btrfs auto-reparo diagnostico info logs status" },
                                { tabIndex: 17, name: Theme.t("settings.cat_store", "Loja & Atualizações"), icon: Theme.icons.packages, desc: Theme.t("settings.desc_store", "Apps & Updates do Sistema"), keywords: "loja store updates atualizacoes pacotes packages arch pacman aur yay flatpak programas instalar" },
                                { tabIndex: 18, name: Theme.t("settings.cat_presets", "Perfis & Backup"), icon: Theme.icons.palette, desc: Theme.t("settings.desc_presets", "Estilos & Restauração"), keywords: "perfis presets backup restore salvar restaurar estilos styles config exportar importar" },
                                { tabIndex: 19, name: Theme.t("settings.cat_shell_custom", "Customização do Shell"), icon: Theme.icons.palette, desc: Theme.t("settings.desc_shell_custom", "Hub, Sidebar & Dock"), keywords: "shell quickshell customizacao dock topbar sidebar hub aparencia widgets glass solid glow borderless escala" }
                            ]

                            Repeater {
                                id: navRepeater
                                model: {
                                    const q = catSearchInput.query;
                                    if (!q) return navCol.navItems;
                                    return navCol.navItems.filter(item => {
                                        const nameMatch = (item.name || "").toLowerCase().includes(q);
                                        const descMatch = (item.desc || "").toLowerCase().includes(q);
                                        const keyMatch = (item.keywords || "").toLowerCase().includes(q);
                                        return nameMatch || descMatch || keyMatch;
                                    });
                                }
                                delegate: Rectangle {
                                    id: navDelegate
                                    required property var modelData
                                    required property int index
                                    readonly property int targetTab: navDelegate.modelData.tabIndex

                                    Layout.fillWidth: true
                                    implicitHeight: 44
                                    radius: 10
                                    color: win.currentTab === navDelegate.targetTab
                                        ? Theme.withAlpha(Theme.primary, 0.22)
                                        : (navItemArea.containsMouse ? Theme.tileHigh : "transparent")
                                    border.width: win.currentTab === navDelegate.targetTab ? 1 : 0
                                    border.color: Theme.primary

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Rectangle {
                                        width: 3
                                        height: 20
                                        radius: 1.5
                                        color: Theme.primary
                                        anchors.left: parent.left
                                        anchors.leftMargin: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: win.currentTab === navDelegate.targetTab
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        Text {
                                            text: navDelegate.modelData.icon
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 16
                                            color: win.currentTab === navDelegate.targetTab ? Theme.primary : Theme.subtext
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            Text {
                                                text: navDelegate.modelData.name
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.weight: win.currentTab === navDelegate.targetTab ? Font.Bold : Font.Normal
                                                color: win.currentTab === navDelegate.targetTab ? Theme.textColor : Theme.subtext
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: navDelegate.modelData.desc
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                color: Theme.withAlpha(Theme.subtext, 0.6)
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: navItemArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.currentTab = navDelegate.targetTab
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 70
                                visible: navRepeater.count === 0
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Theme.icons.alert
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 20
                                        color: Theme.subtext
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Theme.t("settings.no_categories", "Nenhuma categoria encontrada")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        color: Theme.subtext
                                    }
                                }
                            }
                        }
                    }

                    // Rodapé da Sidebar: Seletor de Idioma e Atalho
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 6
                                color: Theme.locale === "pt-BR" ? Theme.primary : Theme.tile
                                border.color: Theme.locale === "pt-BR" ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "Português"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Theme.locale === "pt-BR" ? Font.Bold : Font.Normal
                                    color: Theme.locale === "pt-BR" ? Theme.background : Theme.textColor
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Theme.setLocale("pt-BR")
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 6
                                color: Theme.locale === "en" ? Theme.primary : Theme.tile
                                border.color: Theme.locale === "en" ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "English"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Theme.locale === "en" ? Font.Bold : Font.Normal
                                    color: Theme.locale === "en" ? Theme.background : Theme.textColor
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Theme.setLocale("en")
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: 6
                            color: Theme.tile
                            Text {
                                anchors.centerIn: parent
                                text: "Super + I · Quickshell"
                                font.family: Theme.monoFamily
                                font.pixelSize: 10
                                color: Theme.subtext
                            }
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
                                    "Áudio, Som & Microfone",
                                    "Teclado, Mouse & Entradas",
                                    "Energia & Bateria",
                                    "Inicialização Automática (Boot)",
                                    "Cores & Wallust Dinâmico",
                                    "Efeitos Visuais, Bordas & SDDM",
                                    "Bluetooth & Periféricos sem Fio",
                                    "Rede, Conexões & Wi-Fi",
                                    "Aplicativos Padrão do Sistema",
                                    "Jogos & Gráficos NVIDIA",
                                    "Armazenamento & Limpeza de Disco",
                                    "Guia de Teclas & Atalhos",
                                    "Sistema, Snapshots & Reparo",
                                    "Central de Aplicativos & Atualizações",
                                    "Perfis de Estilo & Gerenciador de Backup"
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
                                    "Selecione saída de áudio, microfone, volumes e execute teste estéreo.",
                                    "Seletor de layout ABNT2/US, sensibilidade do mouse e perfil de aceleração.",
                                    "Monitore saúde da bateria, ciclos de carga e escolha perfis de energia.",
                                    "Gerencie quais programas iniciam automaticamente ao ligar o computador.",
                                    "Visualize a paleta de 16 cores ativas do wallpaper e copie códigos HEX.",
                                    "Luz noturna, transparência inativa, cantos arredondados, animações e login.",
                                    "Gerencie controles de videogame, fones de ouvido e conexões Bluetooth.",
                                    "Monitore a velocidade e latência da internet e conecte-se a novas redes Wi-Fi.",
                                    "Escolha quais programas abrem páginas da web, pastas, códigos, fotos e vídeos.",
                                    "Monitore a GPU dedicada RTX 3050, GameMode e parâmetros da Steam.",
                                    "Monitore o uso do SSD e recupere espaço em disco com limpezas seguras.",
                                    "Consulte e busque todos os atalhos de teclado do Hyprland com 1 clique.",
                                    "Crie pontos de restauração Btrfs e resolva problemas comuns com 1 clique.",
                                    "Verifique atualizações pendentes do Arch Linux e instale programas essenciais.",
                                    "Alterne estilos estéticos do rice e crie cópias de segurança com 1 clique."
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
                                        onClicked: Quickshell.execDetached(["dolphin", (Quickshell.env("HOME") || "") + "/Imagens/FastFetch"])
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
                                    title: Theme.t("monitor.hz_section", "Taxa de Atualização da Tela (Frequência)")
                                    subtitle: Theme.t("monitor.hz_section_desc", "Alterne instantaneamente entre todas as taxas suportadas pelo seu monitor")
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: Math.min(win.availableHzList.length, 3)
                                    rowSpacing: 10
                                    columnSpacing: 10

                                    Repeater {
                                        model: win.availableHzList
                                        delegate: Rectangle {
                                            id: hzCard
                                            required property int modelData
                                            required property int index

                                            readonly property bool isSelected: win.monitorHz === hzCard.modelData
                                            readonly property bool isMax: hzCard.index === 0
                                            readonly property bool isMin: hzCard.index === (win.availableHzList.length - 1)

                                            Layout.fillWidth: true
                                            implicitHeight: 72
                                            radius: 12
                                            color: isSelected ? Theme.withAlpha(Theme.primary, 0.22) : (hzCardArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: isSelected ? 1.5 : 0
                                            border.color: Theme.primary

                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 12

                                                Text {
                                                    text: hzCard.modelData >= 120 ? Theme.icons.lightning : (hzCard.modelData >= 75 ? Theme.icons.speed : Theme.icons.saver)
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 22
                                                    color: hzCard.isSelected ? Theme.primary : Theme.subtext
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1

                                                    RowLayout {
                                                        spacing: 6
                                                        Text {
                                                            text: hzCard.modelData + " Hz"
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 13
                                                            font.weight: Font.DemiBold
                                                            color: Theme.textColor
                                                        }
                                                        Rectangle {
                                                            visible: hzCard.isSelected
                                                            implicitHeight: 16
                                                            implicitWidth: activeHzBadge.implicitWidth + 8
                                                            radius: 4
                                                            color: Theme.primary
                                                            Text {
                                                                id: activeHzBadge
                                                                anchors.centerIn: parent
                                                                text: Theme.t("common.active", "Ativo")
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 9
                                                                font.weight: Font.Bold
                                                                color: Theme.background
                                                            }
                                                        }
                                                    }

                                                    Text {
                                                        text: hzCard.isMax
                                                            ? Theme.t("monitor.hz_max_desc", "Máxima fluidez e menor latência")
                                                            : (hzCard.isMin ? Theme.t("monitor.hz_min_desc", "Economia de energia e bateria") : Theme.t("monitor.hz_bal_desc", "Fluidez intermediária balanceada"))
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: Theme.subtext
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: hzCardArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.monitorHz = hzCard.modelData;
                                                    Quickshell.execDetached(["rice-hypr-prefs", "set", "monitor_hz", hzCard.modelData.toString()]);
                                                    win.showToast("Taxa ajustada para " + hzCard.modelData + " Hz");
                                                }
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Escala da Tela (HiDPI / Zoom)"
                                    subtitle: "Ajuste o tamanho de janelas e fontes (100% padrão para 1080p, aumente para 2K/4K ou diminua se ficou grande)"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: [
                                            { label: "100%", val: 1.0, desc: "Padrão (1080p)" },
                                            { label: "125%", val: 1.25, desc: "Médio (2K)" },
                                            { label: "150%", val: 1.5, desc: "Grande (HiDPI)" },
                                            { label: "175%", val: 1.75, desc: "Ultra" },
                                            { label: "200%", val: 2.0, desc: "4K / TV" }
                                        ]

                                        delegate: Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 60
                                            radius: 10
                                            readonly property bool isCurrent: Math.abs(win.monitorScale - modelData.val) < 0.05
                                            color: isCurrent ? Theme.withAlpha(Theme.primary, 0.25) : (scaleArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: isCurrent ? 1.5 : 1
                                            border.color: isCurrent ? Theme.primary : Theme.withAlpha(Theme.outline, 0.15)

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 2
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: modelData.label
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 14
                                                    font.weight: Font.Bold
                                                    color: isCurrent ? Theme.primary : Theme.textColor
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: modelData.desc
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    color: Theme.subtext
                                                }
                                            }

                                            MouseArea {
                                                id: scaleArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.monitorScale = modelData.val;
                                                    Quickshell.execDetached(["rice-hypr-prefs", "set", "monitor_scale", String(modelData.val)]);
                                                    win.showToast("Escala do monitor ajustada para " + modelData.label);
                                                }
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

                        // ==================== ABA 4: ÁUDIO & SOM ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 4
                            contentHeight: audioCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: audioCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Dispositivo de Saída de Áudio (Alto-falantes / Fones)"
                                    subtitle: "Clique para definir onde o som dos programas deve tocar"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Repeater {
                                        model: win.audioData.sinks || []
                                        delegate: Rectangle {
                                            id: sinkCard
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 56
                                            radius: 10
                                            color: sinkCard.modelData.is_default ? Theme.withAlpha(Theme.primary, 0.22) : (sinkArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: sinkCard.modelData.is_default ? 1.5 : 0
                                            border.color: Theme.primary

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 12

                                                Text {
                                                    text: sinkCard.modelData.is_default ? Theme.icons.volHigh : Theme.icons.headphones
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 20
                                                    color: sinkCard.modelData.is_default ? Theme.primary : Theme.subtext
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    Text {
                                                        text: sinkCard.modelData.description
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 12
                                                        font.weight: sinkCard.modelData.is_default ? Font.DemiBold : Font.Normal
                                                        color: Theme.textColor
                                                    }
                                                    Text {
                                                        text: sinkCard.modelData.is_default ? "Dispositivo Padrão Ativo · " + sinkCard.modelData.volume + "%" : "Clique para selecionar"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: sinkCard.modelData.is_default ? Theme.primary : Theme.subtext
                                                    }
                                                }

                                                Rectangle {
                                                    visible: sinkCard.modelData.is_default
                                                    implicitHeight: 22
                                                    implicitWidth: 70
                                                    radius: 11
                                                    color: Theme.primary
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "Ativo"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        font.weight: Font.Bold
                                                        color: Theme.background
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: sinkArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-audio", "set-sink", sinkCard.modelData.name]);
                                                    win.showToast("Saída alterada: " + sinkCard.modelData.description);
                                                    audioRefreshTimer.restart();
                                                }
                                            }
                                        }
                                    }
                                }

                                CfgSlider {
                                    title: "Volume Geral da Saída Padrão"
                                    minVal: 0; maxVal: 150; value: win.audioData.sink_volume || 100; unit: "%"
                                    onChanged: newVal => {
                                        win.audioData.sink_volume = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-audio", "set-sink-volume", String(win.audioData.sink_volume)]);
                                        });
                                    }
                                }

                                SectionHeader {
                                    title: "Dispositivo de Entrada de Áudio (Microfone)"
                                    subtitle: "Selecione o microfone ativo para jogos, Discord e gravações"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Repeater {
                                        model: win.audioData.sources || []
                                        delegate: Rectangle {
                                            id: sourceCard
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 56
                                            radius: 10
                                            color: sourceCard.modelData.is_default ? Theme.withAlpha(Theme.primary, 0.22) : (sourceArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: sourceCard.modelData.is_default ? 1.5 : 0
                                            border.color: Theme.primary

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 12

                                                Text {
                                                    text: Theme.icons.mic
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 20
                                                    color: sourceCard.modelData.is_default ? Theme.primary : Theme.subtext
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    Text {
                                                        text: sourceCard.modelData.description
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 12
                                                        font.weight: sourceCard.modelData.is_default ? Font.DemiBold : Font.Normal
                                                        color: Theme.textColor
                                                    }
                                                    Text {
                                                        text: sourceCard.modelData.is_default ? "Microfone Padrão Ativo · " + sourceCard.modelData.volume + "%" : "Clique para selecionar"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: sourceCard.modelData.is_default ? Theme.primary : Theme.subtext
                                                    }
                                                }

                                                Rectangle {
                                                    visible: sourceCard.modelData.is_default
                                                    implicitHeight: 22
                                                    implicitWidth: 70
                                                    radius: 11
                                                    color: Theme.primary
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "Ativo"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        font.weight: Font.Bold
                                                        color: Theme.background
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: sourceArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-audio", "set-source", sourceCard.modelData.name]);
                                                    win.showToast("Microfone alterado: " + sourceCard.modelData.description);
                                                    audioRefreshTimer.restart();
                                                }
                                            }
                                        }
                                    }
                                }

                                CfgSlider {
                                    title: "Volume / Sensibilidade do Microfone"
                                    minVal: 0; maxVal: 150; value: win.audioData.source_volume || 80; unit: "%"
                                    onChanged: newVal => {
                                        win.audioData.source_volume = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-audio", "set-source-volume", String(win.audioData.source_volume)]);
                                        });
                                    }
                                }

                                SectionHeader {
                                    title: "Teste & Diagnóstico"
                                    subtitle: "Verifique se os canais de áudio estão funcionando perfeitamente"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    ActionBtn {
                                        icon: Theme.icons.speaker
                                        text: "Testar Alto-falantes (Esquerdo / Direito)"
                                        primary: true
                                        onClicked: {
                                            Quickshell.execDetached(["rice-audio", "test"]);
                                            win.showToast("Reproduzindo teste estéreo...");
                                        }
                                    }
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: "Reiniciar PipeWire"
                                        onClicked: {
                                            Quickshell.execDetached(["rice-maintenance", "audio"]);
                                            win.showToast("Reiniciando áudio...");
                                            audioRefreshTimer.restart();
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                                Timer {
                                    id: audioRefreshTimer
                                    interval: 800
                                    onTriggered: loadAudioProc.running = true
                                }
                            }
                        }

                        // ==================== ABA 5: TECLADO & MOUSE ====================
                        Flickable {
                            id: inputFlickable
                            anchors.fill: parent
                            visible: win.currentTab === 5
                            contentHeight: inputCol.implicitHeight + 40
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            WheelHandler {
                                onWheel: event => {
                                    inputFlickable.contentY = Math.max(0, Math.min(inputFlickable.contentHeight - inputFlickable.height, inputFlickable.contentY - event.angleDelta.y));
                                }
                            }

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
                                            Text { text: "🇧🇷"; font.pixelSize: 24 }
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
                                            Text { text: "🇺🇸"; font.pixelSize: 24 }
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

                                SectionHeader {
                                    title: Theme.t("settings.discord_binds", "Atalhos Globais do Discord")
                                    subtitle: "Mute e Deafen globais que funcionam mesmo com Discord ou Vesktop minimizado em segundo plano"
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: discordCol.implicitHeight + 28
                                    radius: 12
                                    color: Theme.tile
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.outline, 0.2)

                                    ColumnLayout {
                                        id: discordCol
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 14

                                        // Status do cliente Discord / Vesktop
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 12

                                            Rectangle {
                                                width: 36; height: 36; radius: 18
                                                color: Theme.withAlpha(Theme.primary, 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "󰙯"
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 18
                                                    color: Theme.primary
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                RowLayout {
                                                    spacing: 6
                                                    Text {
                                                        text: win.discordClient === "vesktop" ? "Vesktop (Discord Client)" : "Discord Oficial"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 12
                                                        font.weight: Font.Bold
                                                        color: Theme.textColor
                                                    }
                                                    Rectangle {
                                                        width: 8; height: 8; radius: 4
                                                        color: win.discordRunning ? "#10b981" : Theme.withAlpha(Theme.subtext, 0.5)
                                                    }
                                                    Text {
                                                        text: win.discordRunning ? "Em execução" : "Não detectado no momento"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: win.discordRunning ? "#10b981" : Theme.subtext
                                                    }
                                                }
                                                Text {
                                                    text: "Os atalhos gravam diretamente em ~/.config/hypr/hyprland.lua usando hl.bind"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }

                                            Rectangle {
                                                implicitWidth: 80; implicitHeight: 28; radius: 14
                                                color: checkMouse.pressed ? Theme.tileHigh : Theme.surface
                                                border.width: 1; border.color: Theme.withAlpha(Theme.outline, 0.25)
                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 4
                                                    Text {
                                                        text: Theme.icons.refresh
                                                        font.family: Theme.iconFontFamily
                                                        font.pixelSize: 11
                                                        color: Theme.textColor
                                                    }
                                                    Text {
                                                        text: "Verificar"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: Theme.textColor
                                                    }
                                                }
                                                MouseArea {
                                                    id: checkMouse
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: loadDiscordProc.running = true
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.withAlpha(Theme.outline, 0.15) }

                                        // Nota explicativa da simulação
                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: simNoteRow.implicitHeight + 16
                                            radius: 8
                                            color: Theme.withAlpha(Theme.primary, 0.08)
                                            border.width: 1
                                            border.color: Theme.withAlpha(Theme.primary, 0.25)
                                            RowLayout {
                                                id: simNoteRow
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 8
                                                Text {
                                                    text: Theme.icons.info
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 14
                                                    color: Theme.primary
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: Theme.t("discord.sim_note", "O atalho gravado intercepta a tecla no Hyprland e simula o atalho nativo do Discord em segundo plano, liberando as teclas modificadoras automaticamente para não travar em jogos.")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    wrapMode: Text.Wrap
                                                    color: Theme.subtext
                                                }
                                            }
                                        }

                                        // 1. Mute Bind Card
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 12

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2
                                                    Text {
                                                        text: Theme.t("discord.mute_title", "Mutar / Desmutar Microfone (Mute)")
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        color: Theme.textColor
                                                    }
                                                    Text {
                                                        text: Theme.t("discord.mute_desc", "Simula o envio de Ctrl + Shift + M para o Discord/Vesktop")
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: Theme.subtext
                                                    }
                                                }

                                                // Badge de Atalho Ativo
                                                Rectangle {
                                                    implicitWidth: mbBadgeRow.implicitWidth + 16
                                                    implicitHeight: 28; radius: 14
                                                    color: Theme.withAlpha(Theme.primary, 0.15)
                                                    border.width: 1; border.color: Theme.primary
                                                    RowLayout {
                                                        id: mbBadgeRow
                                                        anchors.centerIn: parent
                                                        spacing: 6
                                                        Text {
                                                            text: Theme.icons.microphone || ""
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 11
                                                            color: Theme.primary
                                                        }
                                                        Text {
                                                            text: win.discordMuteBind
                                                            font.family: Theme.monoFamily
                                                            font.pixelSize: 11
                                                            font.weight: Font.Bold
                                                            color: Theme.primary
                                                        }
                                                    }
                                                }

                                                // Botão Gravar Tecla
                                                Rectangle {
                                                    readonly property bool isRec: win.recordingDiscordTarget === "mute"
                                                    implicitWidth: recMuteRow.implicitWidth + 20
                                                    implicitHeight: 30; radius: 15
                                                    color: isRec ? Theme.critical : (recMuteMouse.containsMouse ? Theme.primary : Theme.surface)
                                                    border.width: 1
                                                    border.color: isRec ? Theme.critical : (recMuteMouse.containsMouse ? Theme.primary : Theme.withAlpha(Theme.outline, 0.3))
                                                    Behavior on color { ColorAnimation { duration: 150 } }

                                                    RowLayout {
                                                        id: recMuteRow
                                                        anchors.centerIn: parent
                                                        spacing: 6
                                                        Text {
                                                            text: parent.isRec ? "⏹" : "⏺"
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            color: parent.isRec || recMuteMouse.containsMouse ? Theme.background : Theme.critical
                                                        }
                                                        Text {
                                                            text: parent.isRec ? Theme.t("discord.recording", "Aperte uma tecla no teclado...") : Theme.t("discord.record_key", "Gravar Tecla")
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                            color: parent.isRec || recMuteMouse.containsMouse ? Theme.background : Theme.textColor
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: recMuteMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (parent.isRec) {
                                                                recordDiscordProc.running = false;
                                                                win.recordingDiscordTarget = "";
                                                            } else {
                                                                win.recordingDiscordTarget = "mute";
                                                                win.editingManualMute = false;
                                                                recordDiscordProc.command = ["rice-discord-binds", "record", "--target", "mute", "--timeout", "15"];
                                                                recordDiscordProc.running = true;
                                                            }
                                                        }
                                                    }
                                                }

                                                // Botão Digitar Tecla
                                                Rectangle {
                                                    implicitWidth: editMuteRow.implicitWidth + 16
                                                    implicitHeight: 30; radius: 15
                                                    color: win.editingManualMute ? Theme.tileHigh : (editMuteMouse.containsMouse ? Theme.surface : "transparent")
                                                    border.width: 1; border.color: win.editingManualMute ? Theme.primary : Theme.withAlpha(Theme.outline, 0.25)
                                                    RowLayout {
                                                        id: editMuteRow
                                                        anchors.centerIn: parent
                                                        spacing: 4
                                                        Text {
                                                            text: Theme.icons.edit || "✎"
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 10
                                                            color: Theme.textColor
                                                        }
                                                        Text {
                                                            text: Theme.t("discord.edit_manual", "Digitar")
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 10
                                                            color: Theme.textColor
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: editMuteMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: win.editingManualMute = !win.editingManualMute
                                                    }
                                                }
                                            }

                                            // Campo de Digitação Manual (se aberto)
                                            RowLayout {
                                                Layout.fillWidth: true
                                                visible: win.editingManualMute
                                                spacing: 8

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 32; radius: 8
                                                    color: Theme.surface
                                                    border.width: 1; border.color: Theme.withAlpha(Theme.outline, 0.3)
                                                    TextInput {
                                                        id: manualMuteInput
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        text: win.discordMuteBind
                                                        font.family: Theme.monoFamily
                                                        font.pixelSize: 11
                                                        color: Theme.textColor
                                                        selectByMouse: true
                                                    }
                                                }

                                                Rectangle {
                                                    implicitWidth: 70; height: 32; radius: 8
                                                    color: Theme.primary
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Theme.t("discord.save", "Salvar")
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        font.weight: Font.Bold
                                                        color: Theme.background
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            const keyVal = manualMuteInput.text.trim();
                                                            if (keyVal.length > 0) {
                                                                win.discordMuteBind = keyVal;
                                                                Quickshell.execDetached(["rice-discord-binds", "set", "--mute", keyVal]);
                                                                win.showToast(Theme.t("discord.recorded_mute", "Tecla de Mute salva: ") + keyVal);
                                                                win.editingManualMute = false;
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Presets rápidos de teclas de Mute
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                Text {
                                                    text: "Sugestões rápidas:"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    color: Theme.subtext
                                                }
                                                Repeater {
                                                    model: ["Num_Lock", "F8", "Pause", "Scroll_Lock", "CTRL + SHIFT + M"]
                                                    delegate: Rectangle {
                                                        required property string modelData
                                                        implicitWidth: mbTxt.implicitWidth + 14
                                                        implicitHeight: 24; radius: 12
                                                        readonly property bool isCur: win.discordMuteBind === modelData
                                                        color: isCur ? Theme.primary : Theme.surface
                                                        border.width: 1; border.color: isCur ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)
                                                        Text {
                                                            id: mbTxt
                                                            anchors.centerIn: parent
                                                            text: parent.modelData
                                                            font.family: Theme.monoFamily
                                                            font.pixelSize: 9
                                                            font.weight: Font.Medium
                                                            color: parent.isCur ? Theme.background : Theme.textColor
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                win.discordMuteBind = parent.modelData;
                                                                Quickshell.execDetached(["rice-discord-binds", "set", "--mute", parent.modelData]);
                                                                win.showToast(Theme.t("discord.recorded_mute", "Tecla de Mute configurada: ") + parent.modelData);
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.withAlpha(Theme.outline, 0.15) }

                                        // 2. Deafen Bind Card
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 12

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2
                                                    Text {
                                                        text: Theme.t("discord.deafen_title", "Desativar / Ativar Áudio (Deafen)")
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        color: Theme.textColor
                                                    }
                                                    Text {
                                                        text: Theme.t("discord.deafen_desc", "Simula o envio de Ctrl + Shift + D para o Discord/Vesktop")
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: Theme.subtext
                                                    }
                                                }

                                                // Badge de Atalho Ativo
                                                Rectangle {
                                                    implicitWidth: dbBadgeRow.implicitWidth + 16
                                                    implicitHeight: 28; radius: 14
                                                    color: Theme.withAlpha(Theme.primary, 0.15)
                                                    border.width: 1; border.color: Theme.primary
                                                    RowLayout {
                                                        id: dbBadgeRow
                                                        anchors.centerIn: parent
                                                        spacing: 6
                                                        Text {
                                                            text: Theme.icons.headphones || "🎧"
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 11
                                                            color: Theme.primary
                                                        }
                                                        Text {
                                                            text: win.discordDeafenBind
                                                            font.family: Theme.monoFamily
                                                            font.pixelSize: 11
                                                            font.weight: Font.Bold
                                                            color: Theme.primary
                                                        }
                                                    }
                                                }

                                                // Botão Gravar Tecla
                                                Rectangle {
                                                    readonly property bool isRec: win.recordingDiscordTarget === "deafen"
                                                    implicitWidth: recDeafenRow.implicitWidth + 20
                                                    implicitHeight: 30; radius: 15
                                                    color: isRec ? Theme.critical : (recDeafenMouse.containsMouse ? Theme.primary : Theme.surface)
                                                    border.width: 1
                                                    border.color: isRec ? Theme.critical : (recDeafenMouse.containsMouse ? Theme.primary : Theme.withAlpha(Theme.outline, 0.3))
                                                    Behavior on color { ColorAnimation { duration: 150 } }

                                                    RowLayout {
                                                        id: recDeafenRow
                                                        anchors.centerIn: parent
                                                        spacing: 6
                                                        Text {
                                                            text: parent.isRec ? "⏹" : "⏺"
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            color: parent.isRec || recDeafenMouse.containsMouse ? Theme.background : Theme.critical
                                                        }
                                                        Text {
                                                            text: parent.isRec ? Theme.t("discord.recording", "Aperte uma tecla no teclado...") : Theme.t("discord.record_key", "Gravar Tecla")
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                            color: parent.isRec || recDeafenMouse.containsMouse ? Theme.background : Theme.textColor
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: recDeafenMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (parent.isRec) {
                                                                recordDiscordProc.running = false;
                                                                win.recordingDiscordTarget = "";
                                                            } else {
                                                                win.recordingDiscordTarget = "deafen";
                                                                win.editingManualDeafen = false;
                                                                recordDiscordProc.command = ["rice-discord-binds", "record", "--target", "deafen", "--timeout", "15"];
                                                                recordDiscordProc.running = true;
                                                            }
                                                        }
                                                    }
                                                }

                                                // Botão Digitar Tecla
                                                Rectangle {
                                                    implicitWidth: editDeafenRow.implicitWidth + 16
                                                    implicitHeight: 30; radius: 15
                                                    color: win.editingManualDeafen ? Theme.tileHigh : (editDeafenMouse.containsMouse ? Theme.surface : "transparent")
                                                    border.width: 1; border.color: win.editingManualDeafen ? Theme.primary : Theme.withAlpha(Theme.outline, 0.25)
                                                    RowLayout {
                                                        id: editDeafenRow
                                                        anchors.centerIn: parent
                                                        spacing: 4
                                                        Text {
                                                            text: Theme.icons.edit || "✎"
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 10
                                                            color: Theme.textColor
                                                        }
                                                        Text {
                                                            text: Theme.t("discord.edit_manual", "Digitar")
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 10
                                                            color: Theme.textColor
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: editDeafenMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: win.editingManualDeafen = !win.editingManualDeafen
                                                    }
                                                }
                                            }

                                            // Campo de Digitação Manual (se aberto)
                                            RowLayout {
                                                Layout.fillWidth: true
                                                visible: win.editingManualDeafen
                                                spacing: 8

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 32; radius: 8
                                                    color: Theme.surface
                                                    border.width: 1; border.color: Theme.withAlpha(Theme.outline, 0.3)
                                                    TextInput {
                                                        id: manualDeafenInput
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        text: win.discordDeafenBind
                                                        font.family: Theme.monoFamily
                                                        font.pixelSize: 11
                                                        color: Theme.textColor
                                                        selectByMouse: true
                                                    }
                                                }

                                                Rectangle {
                                                    implicitWidth: 70; height: 32; radius: 8
                                                    color: Theme.primary
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Theme.t("discord.save", "Salvar")
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        font.weight: Font.Bold
                                                        color: Theme.background
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            const keyVal = manualDeafenInput.text.trim();
                                                            if (keyVal.length > 0) {
                                                                win.discordDeafenBind = keyVal;
                                                                Quickshell.execDetached(["rice-discord-binds", "set", "--deafen", keyVal]);
                                                                win.showToast(Theme.t("discord.recorded_deafen", "Tecla de Deafen salva: ") + keyVal);
                                                                win.editingManualDeafen = false;
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Presets rápidos de teclas de Deafen
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                Text {
                                                    text: "Sugestões rápidas:"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    color: Theme.subtext
                                                }
                                                Repeater {
                                                    model: ["Num_Lock", "F9", "Pause", "Scroll_Lock", "CTRL + SHIFT + D"]
                                                    delegate: Rectangle {
                                                        required property string modelData
                                                        implicitWidth: dbTxt.implicitWidth + 14
                                                        implicitHeight: 24; radius: 12
                                                        readonly property bool isCur: win.discordDeafenBind === modelData
                                                        color: isCur ? Theme.primary : Theme.surface
                                                        border.width: 1; border.color: isCur ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)
                                                        Text {
                                                            id: dbTxt
                                                            anchors.centerIn: parent
                                                            text: parent.modelData
                                                            font.family: Theme.monoFamily
                                                            font.pixelSize: 9
                                                            font.weight: Font.Medium
                                                            color: parent.isCur ? Theme.background : Theme.textColor
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                win.discordDeafenBind = parent.modelData;
                                                                Quickshell.execDetached(["rice-discord-binds", "set", "--deafen", parent.modelData]);
                                                                win.showToast(Theme.t("discord.recorded_deafen", "Tecla de Deafen configurada: ") + parent.modelData);
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

                        // ==================== ABA 6: ENERGIA & BATERIA ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 6
                            contentHeight: powerCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: powerCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Perfil de Desempenho & Energia"
                                    subtitle: "Ajusta o escalonamento do processador e limites térmicos do sistema"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Repeater {
                                        model: [
                                            { id: "performance", name: "Desempenho", icon: Theme.icons.perf, desc: "Clocks máximos para jogos e tarefas pesadas" },
                                            { id: "balanced", name: "Equilibrado", icon: Theme.icons.balanced, desc: "Balanço inteligente entre fluidez e consumo" },
                                            { id: "power-saver", name: "Economia", icon: Theme.icons.saver, desc: "Prioriza autonomia da bateria e silêncio" }
                                        ]
                                        delegate: Rectangle {
                                            id: pCard
                                            required property var modelData
                                            readonly property bool active: win.powerData.profile === pCard.modelData.id
                                            Layout.fillWidth: true
                                            implicitHeight: 74
                                            radius: 12
                                            color: active ? Theme.withAlpha(Theme.primary, 0.22) : (pCardArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: active ? 1.5 : 0
                                            border.color: Theme.primary

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 12

                                                Text {
                                                    text: pCard.modelData.icon
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 22
                                                    color: pCard.active ? Theme.primary : Theme.subtext
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2
                                                    Text {
                                                        text: pCard.modelData.name
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 13
                                                        font.weight: pCard.active ? Font.DemiBold : Font.Normal
                                                        color: Theme.textColor
                                                    }
                                                    Text {
                                                        text: pCard.modelData.desc
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: pCard.active ? Theme.primary : Theme.subtext
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: pCardArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.powerData.profile = pCard.modelData.id;
                                                    Quickshell.execDetached(["rice-power", "set-profile", pCard.modelData.id]);
                                                    win.showToast("Perfil de energia: " + pCard.modelData.name);
                                                    powerRefreshTimer.restart();
                                                }
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Saúde & Estatísticas da Bateria"
                                    subtitle: "Dados de integridade física e ciclos de carga do notebook"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 80
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 12
                                            Text { text: Theme.icons.batHealth; font.family: Theme.iconFontFamily; font.pixelSize: 24; color: Theme.primary }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text { text: "Saúde da Bateria"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.subtext }
                                                Text { text: win.powerData.health + "% Capacidade"; font.family: Theme.fontFamily; font.pixelSize: 15; font.weight: Font.Bold; color: Theme.textColor }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 80
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 12
                                            Text { text: Theme.icons.history; font.family: Theme.iconFontFamily; font.pixelSize: 24; color: Theme.secondary }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text { text: "Ciclos de Carga"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.subtext }
                                                Text { text: win.powerData.cycles + " Ciclos Completos"; font.family: Theme.fontFamily; font.pixelSize: 15; font.weight: Font.Bold; color: Theme.textColor }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 80
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 12
                                            Text { text: Theme.icons.lightning; font.family: Theme.iconFontFamily; font.pixelSize: 24; color: Theme.primary }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text { text: "Status de Alimentação"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.subtext }
                                                Text { text: win.powerData.status + " (" + win.powerData.percent + "%)"; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Bold; color: Theme.textColor }
                                            }
                                        }
                                    }
                                }
                                Timer {
                                    id: powerRefreshTimer
                                    interval: 800
                                    onTriggered: loadPowerProc.running = true
                                }
                            }
                        }

                        // ==================== ABA 7: INICIALIZAÇÃO / AUTOSTART ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 7
                            contentHeight: autoCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: autoCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Aplicativos na Inicialização do Sistema"
                                    subtitle: "Ative ou desative quais programas abrem sozinhos quando você liga o computador"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        visible: win.autostartEntries.length === 0
                                        text: "Nenhum aplicativo configurado para iniciar automaticamente."
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.subtext
                                    }

                                    Repeater {
                                        model: win.autostartEntries
                                        delegate: Rectangle {
                                            id: autoCard
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 56
                                            radius: 10
                                            color: Theme.tile
                                            border.width: 1
                                            border.color: Theme.withAlpha(Theme.outline, 0.2)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 12

                                                Rectangle {
                                                    implicitWidth: 32
                                                    implicitHeight: 32
                                                    radius: 8
                                                    color: Theme.withAlpha(Theme.primary, 0.15)
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Theme.icons.speed
                                                        font.family: Theme.iconFontFamily
                                                        font.pixelSize: 16
                                                        color: Theme.primary
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    Text {
                                                        text: autoCard.modelData.name
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 12
                                                        font.weight: Font.DemiBold
                                                        color: Theme.textColor
                                                    }
                                                    Text {
                                                        text: autoCard.modelData.exec || autoCard.modelData.filename
                                                        font.family: Theme.monoFamily
                                                        font.pixelSize: 10
                                                        color: Theme.subtext
                                                        elide: Text.ElideMiddle
                                                    }
                                                }

                                                // Botão Lixeira
                                                Rectangle {
                                                    implicitWidth: 28
                                                    implicitHeight: 28
                                                    radius: 14
                                                    color: delArea.containsMouse ? Theme.withAlpha(Theme.critical, 0.2) : "transparent"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Theme.icons.trash
                                                        font.family: Theme.iconFontFamily
                                                        font.pixelSize: 13
                                                        color: Theme.critical
                                                    }
                                                    MouseArea {
                                                        id: delArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            Quickshell.execDetached(["rice-autostart", "remove", autoCard.modelData.filename]);
                                                            win.showToast("Removido do autostart: " + autoCard.modelData.name);
                                                            autostartRefreshTimer.restart();
                                                        }
                                                    }
                                                }

                                                // Toggle Ativado
                                                Rectangle {
                                                    implicitWidth: 36
                                                    implicitHeight: 20
                                                    radius: 10
                                                    color: autoCard.modelData.enabled ? Theme.primary : Theme.tileHigh

                                                    Rectangle {
                                                        width: 14; height: 14; radius: 7
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        x: autoCard.modelData.enabled ? parent.width - width - 3 : 3
                                                        color: Theme.textColor
                                                        Behavior on x { NumberAnimation { duration: 120 } }
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            Quickshell.execDetached(["rice-autostart", "toggle", autoCard.modelData.filename]);
                                                            autoCard.modelData.enabled = !autoCard.modelData.enabled;
                                                            win.showToast((autoCard.modelData.enabled ? "Ativado: " : "Desativado: ") + autoCard.modelData.name);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Adicionar Aplicativo à Inicialização Rápida"
                                    subtitle: "Selecione qualquer aplicativo instalado para abrir junto com o Hyprland"
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: win.availableApps
                                        delegate: Rectangle {
                                            id: appChip
                                            required property var modelData
                                            implicitHeight: 32
                                            implicitWidth: appChipRow.implicitWidth + 20
                                            radius: 8
                                            color: appChip.modelData.already_added ? Theme.withAlpha(Theme.primary, 0.2) : (appChipArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: appChip.modelData.already_added ? 1 : 0
                                            border.color: Theme.primary

                                            RowLayout {
                                                id: appChipRow
                                                anchors.centerIn: parent
                                                spacing: 6
                                                Text {
                                                    text: appChip.modelData.already_added ? Theme.icons.verified : Theme.icons.plus
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 12
                                                    color: appChip.modelData.already_added ? Theme.primary : Theme.textColor
                                                }
                                                Text {
                                                    text: appChip.modelData.name
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    color: Theme.textColor
                                                }
                                            }

                                            MouseArea {
                                                id: appChipArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (!appChip.modelData.already_added) {
                                                        Quickshell.execDetached(["rice-autostart", "add", appChip.modelData.filename]);
                                                        win.showToast("Adicionado ao autostart: " + appChip.modelData.name);
                                                        autostartRefreshTimer.restart();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                Timer {
                                    id: autostartRefreshTimer
                                    interval: 600
                                    onTriggered: {
                                        loadAutostartProc.running = true;
                                        loadAvailableAppsProc.running = true;
                                    }
                                }
                            }
                        }

                        // ==================== ABA 8: CORES & WALLUST ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 8
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

                        // ==================== ABA 9: EFEITOS VISUAIS & JANELAS ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 9
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
                                                "bash", "-c", "echo '==> Digite sua senha para configurar o SDDM e Limine:'; sudo rice-apply-boot-login; echo; read -n 1 -s -r -p '✔ Concluído! Pressione qualquer tecla para fechar...'"
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

                        // ==================== ABA 10: BLUETOOTH ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 10
                            contentHeight: btCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: btCol
                                width: parent.width
                                spacing: 16

                                RowLayout {
                                    Layout.fillWidth: true
                                    SectionHeader {
                                        title: "Bluetooth & Dispositivos sem Fio"
                                        subtitle: "Conecte controles Xbox/PS, fones de ouvido e periféricos sem fio"
                                    }
                                    Item { Layout.fillWidth: true }
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: "Escanear"
                                        onClicked: {
                                            Quickshell.execDetached(["rice-bluetooth", "scan"]);
                                            showToast("Buscando dispositivos próximos...");
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 60
                                    radius: 12
                                    color: Theme.tile
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.outline, 0.2)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        Text {
                                            text: win.btData && win.btData.powered ? Theme.icons.bt : Theme.icons.btOff
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 22
                                            color: win.btData && win.btData.powered ? Theme.primary : Theme.subtext
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text {
                                                text: win.btData && win.btData.powered ? "Bluetooth Ativado" : "Bluetooth Desativado"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                color: Theme.textColor
                                            }
                                            Text {
                                                text: win.btData && win.btData.powered ? "Pronto para conexões e pareamento automático" : "Ligue o adaptador para conectar periféricos"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.subtext
                                            }
                                        }

                                        SwitchToggle {
                                            checked: win.btData && win.btData.powered
                                            onToggled: {
                                                Quickshell.execDetached(["rice-bluetooth", "toggle-power"]);
                                                loadBtProc.running = true;
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Dispositivos Pareados & Conhecidos"
                                    subtitle: "Clique em Conectar para vincular o controle ou fone instantaneamente"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: (win.btData && win.btData.devices) ? win.btData.devices : []
                                        delegate: Rectangle {
                                            id: btDevCard
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 64
                                            radius: 12
                                            color: btDevCard.modelData.connected ? Theme.withAlpha(Theme.primary, 0.14) : Theme.tile
                                            border.width: btDevCard.modelData.connected ? 1.5 : 1
                                            border.color: btDevCard.modelData.connected ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 12

                                                Rectangle {
                                                    implicitWidth: 38
                                                    implicitHeight: 38
                                                    radius: 10
                                                    color: btDevCard.modelData.connected ? Theme.withAlpha(Theme.primary, 0.25) : Theme.tileHigh

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: btDevCard.modelData.icon === "gamepad" ? Theme.icons.gamepad
                                                            : (btDevCard.modelData.icon === "headset" ? Theme.icons.headphones
                                                            : (btDevCard.modelData.icon === "mouse" ? Theme.icons.cursor
                                                            : (btDevCard.modelData.icon === "keyboard" ? Theme.icons.tune
                                                            : Theme.icons.bt)))
                                                        font.family: Theme.iconFontFamily
                                                        font.pixelSize: 18
                                                        color: btDevCard.modelData.connected ? Theme.primary : Theme.textColor
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2
                                                    RowLayout {
                                                        spacing: 8
                                                        Text {
                                                            text: btDevCard.modelData.name
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 12
                                                            font.weight: Font.DemiBold
                                                            color: Theme.textColor
                                                        }
                                                        Rectangle {
                                                            visible: btDevCard.modelData.connected
                                                            implicitWidth: 70
                                                            implicitHeight: 18
                                                            radius: 9
                                                            color: Theme.withAlpha(Theme.primary, 0.25)
                                                            border.width: 1
                                                            border.color: Theme.primary
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "● Conectado"
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 9
                                                                font.weight: Font.Bold
                                                                color: Theme.primary
                                                            }
                                                        }
                                                        Rectangle {
                                                            visible: btDevCard.modelData.battery !== null
                                                            implicitWidth: 46
                                                            implicitHeight: 18
                                                            radius: 9
                                                            color: Theme.withAlpha(Theme.foreground, 0.1)
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "🔋 " + (btDevCard.modelData.battery || 0) + "%"
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 9
                                                                color: Theme.textColor
                                                            }
                                                        }
                                                    }
                                                    Text {
                                                        text: btDevCard.modelData.mac
                                                        font.family: Theme.monoFamily
                                                        font.pixelSize: 10
                                                        color: Theme.subtext
                                                    }
                                                }

                                                ActionBtn {
                                                    icon: btDevCard.modelData.connected ? Theme.icons.close : Theme.icons.btConnected
                                                    text: btDevCard.modelData.connected ? "Desconectar" : "Conectar"
                                                    primary: !btDevCard.modelData.connected
                                                    onClicked: {
                                                        if (btDevCard.modelData.connected) {
                                                            Quickshell.execDetached(["rice-bluetooth", "disconnect", btDevCard.modelData.mac]);
                                                        } else {
                                                            Quickshell.execDetached(["rice-bluetooth", "connect", btDevCard.modelData.mac]);
                                                        }
                                                        loadBtProc.running = true;
                                                    }
                                                }

                                                Rectangle {
                                                    implicitWidth: 32
                                                    implicitHeight: 32
                                                    radius: 8
                                                    color: rmBtArea.containsMouse ? Theme.withAlpha("#ff5555", 0.2) : "transparent"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Theme.icons.trash
                                                        font.family: Theme.iconFontFamily
                                                        font.pixelSize: 13
                                                        color: rmBtArea.containsMouse ? "#ff5555" : Theme.subtext
                                                    }
                                                    MouseArea {
                                                        id: rmBtArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            Quickshell.execDetached(["rice-bluetooth", "remove", btDevCard.modelData.mac]);
                                                            loadBtProc.running = true;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        visible: !win.btData || !win.btData.devices || win.btData.devices.length === 0
                                        text: "Nenhum dispositivo encontrado. Coloque seu controle ou fone em modo de pareamento e clique em 'Escanear'."
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.subtext
                                    }
                                }
                            }
                        }

                        // ==================== ABA 11: REDE & WI-FI ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 11
                            contentHeight: netCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: netCol
                                width: parent.width
                                spacing: 16

                                RowLayout {
                                    Layout.fillWidth: true
                                    SectionHeader {
                                        title: "Rede & Wi-Fi"
                                        subtitle: "Monitore a conexão de internet e conecte-se a novas redes"
                                    }
                                    Item { Layout.fillWidth: true }
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: "Atualizar Redes"
                                        onClicked: {
                                            Quickshell.execDetached(["rice-network", "scan"]);
                                            loadNetScanProc.running = true;
                                            showToast("Buscando redes Wi-Fi...");
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 100
                                    radius: 12
                                    color: win.netData && win.netData.connected_ssid ? Theme.withAlpha(Theme.primary, 0.15) : Theme.tile
                                    border.width: 1.5
                                    border.color: win.netData && win.netData.connected_ssid ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 16

                                        Rectangle {
                                            implicitWidth: 46
                                            implicitHeight: 46
                                            radius: 12
                                            color: Theme.withAlpha(Theme.primary, 0.25)
                                            Text {
                                                anchors.centerIn: parent
                                                text: win.netData && win.netData.wifi_enabled ? Theme.icons.wifi4 : Theme.icons.wifiOff
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 24
                                                color: Theme.primary
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4

                                            RowLayout {
                                                spacing: 8
                                                Text {
                                                    text: win.netData && win.netData.connected_ssid ? win.netData.connected_ssid : "Nenhuma rede conectada"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 15
                                                    font.weight: Font.Bold
                                                    color: Theme.textColor
                                                }
                                                Rectangle {
                                                    visible: win.netData && win.netData.is_5g
                                                    implicitWidth: 42
                                                    implicitHeight: 18
                                                    radius: 9
                                                    color: Theme.withAlpha(Theme.primary, 0.3)
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "5 GHz"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 9
                                                        font.weight: Font.Bold
                                                        color: Theme.primary
                                                    }
                                                }
                                                Rectangle {
                                                    visible: win.netData && win.netData.signal > 0
                                                    implicitWidth: 44
                                                    implicitHeight: 18
                                                    radius: 9
                                                    color: Theme.withAlpha(Theme.foreground, 0.1)
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: (win.netData ? win.netData.signal : 0) + "%"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 9
                                                        color: Theme.textColor
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                spacing: 12
                                                Text {
                                                    text: "IP: " + (win.netData && win.netData.ip ? win.netData.ip : "---")
                                                    font.family: Theme.monoFamily
                                                    font.pixelSize: 11
                                                    color: Theme.subtext
                                                }
                                                Text {
                                                    text: "Gateway: " + (win.netData && win.netData.gateway ? win.netData.gateway : "---")
                                                    font.family: Theme.monoFamily
                                                    font.pixelSize: 11
                                                    color: Theme.subtext
                                                }
                                                Text {
                                                    text: win.pingMs !== null ? ("Ping: " + win.pingMs + " ms") : ""
                                                    font.family: Theme.monoFamily
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    color: Theme.primary
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            spacing: 6
                                            ActionBtn {
                                                icon: Theme.icons.speed
                                                text: "Testar Ping"
                                                onClicked: loadPingProc.running = true
                                            }
                                            ActionBtn {
                                                visible: win.netData && !!win.netData.connected_ssid
                                                icon: Theme.icons.close
                                                text: "Desconectar"
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-network", "disconnect"]);
                                                    loadNetProc.running = true;
                                                }
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Redes Wi-Fi Disponíveis"
                                    subtitle: "Selecione uma rede para conectar"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: win.netScanData || []
                                        delegate: Rectangle {
                                            id: wifiCard
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: isConnecting ? 96 : 50
                                            radius: 10
                                            color: wifiCard.modelData.active ? Theme.withAlpha(Theme.primary, 0.15) : Theme.tile
                                            border.width: 1
                                            border.color: wifiCard.modelData.active ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                            property bool isConnecting: win.netSelectedSsid === wifiCard.modelData.ssid

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 8

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 10

                                                    Text {
                                                        text: wifiCard.modelData.signal > 70 ? Theme.icons.wifi4
                                                            : (wifiCard.modelData.signal > 40 ? Theme.icons.wifi3 : Theme.icons.wifi2)
                                                        font.family: Theme.iconFontFamily
                                                        font.pixelSize: 16
                                                        color: wifiCard.modelData.active ? Theme.primary : Theme.subtext
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: wifiCard.modelData.ssid
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 12
                                                        font.weight: wifiCard.modelData.active ? Font.Bold : Font.Normal
                                                        color: Theme.textColor
                                                    }

                                                    Text {
                                                        visible: wifiCard.modelData.protected
                                                        text: Theme.icons.lock
                                                        font.family: Theme.iconFontFamily
                                                        font.pixelSize: 12
                                                        color: Theme.subtext
                                                    }

                                                    Rectangle {
                                                        visible: wifiCard.modelData.is_5g
                                                        implicitWidth: 34
                                                        implicitHeight: 18
                                                        radius: 9
                                                        color: Theme.withAlpha(Theme.foreground, 0.08)
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "5G"
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 9
                                                            color: Theme.subtext
                                                        }
                                                    }

                                                    Text {
                                                        text: wifiCard.modelData.signal + "%"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        color: Theme.subtext
                                                    }

                                                    ActionBtn {
                                                        visible: !wifiCard.modelData.active && !wifiCard.isConnecting
                                                        icon: Theme.icons.confirm
                                                        text: "Conectar"
                                                        primary: true
                                                        onClicked: {
                                                            if (wifiCard.modelData.protected) {
                                                                win.netSelectedSsid = wifiCard.modelData.ssid;
                                                                win.netPassInput = "";
                                                            } else {
                                                                Quickshell.execDetached(["rice-network", "connect", wifiCard.modelData.ssid]);
                                                                loadNetProc.running = true;
                                                            }
                                                        }
                                                    }

                                                    Rectangle {
                                                        visible: wifiCard.modelData.active
                                                        implicitWidth: 64
                                                        implicitHeight: 24
                                                        radius: 12
                                                        color: Theme.withAlpha(Theme.primary, 0.2)
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "Ativa"
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 10
                                                            font.weight: Font.Bold
                                                            color: Theme.primary
                                                        }
                                                    }
                                                }

                                                RowLayout {
                                                    visible: wifiCard.isConnecting
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        implicitHeight: 32
                                                        radius: 8
                                                        color: Theme.background
                                                        border.width: 1
                                                        border.color: Theme.primary

                                                        TextInput {
                                                            id: passInput
                                                            anchors.fill: parent
                                                            anchors.margins: 6
                                                            echoMode: TextInput.Password
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 12
                                                            color: Theme.textColor
                                                            clip: true
                                                            onTextChanged: win.netPassInput = text
                                                            Text {
                                                                visible: !passInput.text
                                                                text: "Digite a senha do Wi-Fi..."
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 11
                                                                color: Theme.subtext
                                                            }
                                                        }
                                                    }

                                                    ActionBtn {
                                                        icon: Theme.icons.confirm
                                                        text: "Confirmar"
                                                        primary: true
                                                        onClicked: {
                                                            Quickshell.execDetached(["rice-network", "connect", wifiCard.modelData.ssid, win.netPassInput]);
                                                            win.netSelectedSsid = "";
                                                            loadNetProc.running = true;
                                                        }
                                                    }

                                                    ActionBtn {
                                                        icon: Theme.icons.close
                                                        text: "Cancelar"
                                                        onClicked: win.netSelectedSsid = ""
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ==================== ABA 12: APLICATIVOS PADRÃO ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 12
                            contentHeight: defCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: defCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Aplicativos Padrão do Sistema"
                                    subtitle: "Selecione quais programas abrem páginas da web, pastas, códigos, fotos e vídeos"
                                }

                                Repeater {
                                    model: [
                                        { id: "browser", title: "Navegador Web", icon: Theme.icons.dashboard, desc: "Abre links HTTP/HTTPS e arquivos HTML" },
                                        { id: "filemanager", title: "Gerenciador de Pastas", icon: Theme.icons.laptop, desc: "Abre diretórios e dispositivos" },
                                        { id: "editor", title: "Editor de Código & Texto", icon: Theme.icons.console, desc: "Abre scripts, código-fonte e notas de texto" },
                                        { id: "video", title: "Player de Vídeo", icon: Theme.icons.media, desc: "Reproduz filmes, gravações e clipes MP4/MKV" },
                                        { id: "image", title: "Visualizador de Imagens", icon: Theme.icons.camera, desc: "Abre capturas de tela e fotos PNG/JPG" },
                                        { id: "audio", title: "Player de Música & Áudio", icon: Theme.icons.music, desc: "Reproduz faixas MP3, FLAC, OGG, WAV e AAC" }
                                    ]
                                    delegate: Rectangle {
                                        id: defCatCard
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: catCol.implicitHeight + 28
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: defCatCard.isPicking ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                        property var catInfo: (win.defaultAppsData && win.defaultAppsData[defCatCard.modelData.id]) ? win.defaultAppsData[defCatCard.modelData.id] : null
                                        property bool isPicking: win.pickingDefaultCategory === defCatCard.modelData.id

                                        ColumnLayout {
                                            id: catCol
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 12

                                            // Cabeçalho da Categoria
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                Text {
                                                    text: defCatCard.modelData.icon
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 18
                                                    color: Theme.primary
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    Text {
                                                        text: defCatCard.modelData.title
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 13
                                                        font.weight: Font.DemiBold
                                                        color: Theme.textColor
                                                    }
                                                    Text {
                                                        text: defCatCard.modelData.desc
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: Theme.subtext
                                                    }
                                                }
                                            }

                                            // Banner do App Padrão Atual
                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 46
                                                radius: 8
                                                color: Theme.withAlpha(Theme.background, 0.6)
                                                border.width: 1
                                                border.color: Theme.withAlpha(Theme.outline, 0.2)

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    spacing: 10

                                                    Image {
                                                        Layout.preferredWidth: 26
                                                        Layout.preferredHeight: 26
                                                        source: (defCatCard.catInfo && defCatCard.catInfo.current_icon) ? win.appIconSource(defCatCard.catInfo.current_icon) : win.appIconSource("")
                                                        fillMode: Image.PreserveAspectFit
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 0
                                                        Text {
                                                            text: (defCatCard.catInfo && defCatCard.catInfo.current_name) ? defCatCard.catInfo.current_name : "Não definido"
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 12
                                                            font.weight: Font.DemiBold
                                                            color: Theme.textColor
                                                            elide: Text.ElideRight
                                                        }
                                                        Text {
                                                            text: (defCatCard.catInfo && defCatCard.catInfo.current_desktop) ? defCatCard.catInfo.current_desktop : "Nenhum aplicativo associado"
                                                            font.family: Theme.monoFamily
                                                            font.pixelSize: 9
                                                            color: Theme.subtext
                                                            elide: Text.ElideRight
                                                        }
                                                    }

                                                    Rectangle {
                                                        implicitHeight: 22
                                                        implicitWidth: currentBadgeRow.implicitWidth + 14
                                                        radius: 6
                                                        color: (defCatCard.catInfo && defCatCard.catInfo.is_set) ? Theme.withAlpha(Theme.primary, 0.2) : Theme.withAlpha(Theme.warning, 0.2)
                                                        border.width: 1
                                                        border.color: (defCatCard.catInfo && defCatCard.catInfo.is_set) ? Theme.primary : Theme.warning

                                                        RowLayout {
                                                            id: currentBadgeRow
                                                            anchors.centerIn: parent
                                                            spacing: 4
                                                            Text {
                                                                text: (defCatCard.catInfo && defCatCard.catInfo.is_set) ? Theme.icons.confirm : Theme.icons.alert
                                                                font.family: Theme.iconFontFamily
                                                                font.pixelSize: 11
                                                                color: (defCatCard.catInfo && defCatCard.catInfo.is_set) ? Theme.primary : Theme.warning
                                                            }
                                                            Text {
                                                                text: (defCatCard.catInfo && defCatCard.catInfo.is_set) ? "Padrão Ativo" : "Não Definido"
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 10
                                                                font.weight: Font.Bold
                                                                color: (defCatCard.catInfo && defCatCard.catInfo.is_set) ? Theme.textColor : Theme.warning
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Linha de Ação: Entrada Manual Direta + Botões
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 34
                                                    radius: 8
                                                    color: Theme.background
                                                    border.width: 1
                                                    border.color: customInput.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.3)

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10
                                                        spacing: 8

                                                        Text {
                                                            text: Theme.icons.pencil
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 12
                                                            color: Theme.subtext
                                                        }

                                                        TextInput {
                                                            id: customInput
                                                            Layout.fillWidth: true
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            color: Theme.textColor
                                                            selectByMouse: true
                                                            clip: true
                                                            text: ""

                                                            Text {
                                                                visible: !customInput.text && !customInput.activeFocus
                                                                text: "Digitar app específico (ex: zen, firefox, code, dolphin, mpv)..."
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 11
                                                                color: Theme.withAlpha(Theme.subtext, 0.6)
                                                            }

                                                            onAccepted: applyBtnArea.clicked(null)
                                                        }

                                                        Text {
                                                            visible: customInput.text.length > 0
                                                            text: Theme.icons.close
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 12
                                                            color: Theme.subtext
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: customInput.text = ""
                                                            }
                                                        }
                                                    }
                                                }

                                                // Botão Salvar App Digitado
                                                Rectangle {
                                                    implicitHeight: 34
                                                    implicitWidth: applyRow.implicitWidth + 20
                                                    radius: 8
                                                    color: applyBtnArea.containsMouse ? Theme.mix(Theme.primary, Theme.background, 0.2) : Theme.primary

                                                    RowLayout {
                                                        id: applyRow
                                                        anchors.centerIn: parent
                                                        spacing: 6
                                                        Text {
                                                            text: Theme.icons.confirm
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 12
                                                            color: Theme.background
                                                        }
                                                        Text {
                                                            text: "Salvar"
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            font.weight: Font.Bold
                                                            color: Theme.background
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: applyBtnArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            const val = customInput.text.trim();
                                                            if (!val) {
                                                                win.showToast("Digite o nome de um app ou escolha na lista");
                                                                return;
                                                            }
                                                            Quickshell.execDetached(["rice-default-apps", "set", defCatCard.modelData.id, val]);
                                                            win.showToast("Definindo " + val + " como padrão...");
                                                            customInput.text = "";
                                                            defaultAppsRefreshTimer.restart();
                                                        }
                                                    }
                                                }

                                                // Botão Escolher dos Apps Instalados
                                                Rectangle {
                                                    implicitHeight: 34
                                                    implicitWidth: pickBtnRow.implicitWidth + 20
                                                    radius: 8
                                                    color: defCatCard.isPicking ? Theme.withAlpha(Theme.primary, 0.25) : (pickBtnArea.containsMouse ? Theme.tileHigh : Theme.background)
                                                    border.width: 1
                                                    border.color: defCatCard.isPicking ? Theme.primary : Theme.withAlpha(Theme.outline, 0.3)

                                                    RowLayout {
                                                        id: pickBtnRow
                                                        anchors.centerIn: parent
                                                        spacing: 6
                                                        Text {
                                                            text: defCatCard.isPicking ? Theme.icons.close : Theme.icons.magnify
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 12
                                                            color: defCatCard.isPicking ? Theme.primary : Theme.textColor
                                                        }
                                                        Text {
                                                            text: defCatCard.isPicking ? "Fechar Lista" : "Escolher App..."
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            font.weight: Font.Medium
                                                            color: defCatCard.isPicking ? Theme.primary : Theme.textColor
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: pickBtnArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (defCatCard.isPicking) {
                                                                win.pickingDefaultCategory = "";
                                                            } else {
                                                                win.pickingDefaultCategory = defCatCard.modelData.id;
                                                                win.defaultAppSearchQuery = "";
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Gaveta Expansível com Todos os Aplicativos do Sistema
                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: pickerCol.implicitHeight + 20
                                                visible: defCatCard.isPicking
                                                radius: 10
                                                color: Theme.withAlpha(Theme.background, 0.85)
                                                border.width: 1
                                                border.color: Theme.withAlpha(Theme.primary, 0.3)

                                                ColumnLayout {
                                                    id: pickerCol
                                                    anchors.fill: parent
                                                    anchors.margins: 10
                                                    spacing: 8

                                                    // Campo de busca com filtro dinâmico
                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        implicitHeight: 32
                                                        radius: 6
                                                        color: Theme.background
                                                        border.width: 1
                                                        border.color: searchAppInput.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.25)

                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 8
                                                            anchors.rightMargin: 8
                                                            spacing: 6

                                                            Text {
                                                                text: Theme.icons.magnify
                                                                font.family: Theme.iconFontFamily
                                                                font.pixelSize: 12
                                                                color: Theme.subtext
                                                            }

                                                            TextInput {
                                                                id: searchAppInput
                                                                Layout.fillWidth: true
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 11
                                                                color: Theme.textColor
                                                                selectByMouse: true
                                                                clip: true
                                                                text: win.defaultAppSearchQuery
                                                                onTextChanged: win.defaultAppSearchQuery = text

                                                                Text {
                                                                    visible: !searchAppInput.text
                                                                    text: "Pesquisar entre todos os aplicativos do sistema..."
                                                                    font.family: Theme.fontFamily
                                                                    font.pixelSize: 11
                                                                    color: Theme.withAlpha(Theme.subtext, 0.6)
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Lista rolável de aplicativos instalados
                                                    Flickable {
                                                        Layout.fillWidth: true
                                                        implicitHeight: Math.min(appListCol.implicitHeight, 210)
                                                        contentHeight: appListCol.implicitHeight
                                                        clip: true
                                                        boundsBehavior: Flickable.StopAtBounds

                                                        ColumnLayout {
                                                            id: appListCol
                                                            width: parent.width
                                                            spacing: 4

                                                            Repeater {
                                                                model: {
                                                                    const q = (win.defaultAppSearchQuery || "").toLowerCase().trim();
                                                                    const list = win.availableApps || [];
                                                                    if (!q) return list;
                                                                    return list.filter(a => {
                                                                        const name = (a.name || "").toLowerCase();
                                                                        const file = (a.filename || "").toLowerCase();
                                                                        const comment = (a.comment || "").toLowerCase();
                                                                        return name.includes(q) || file.includes(q) || comment.includes(q);
                                                                    });
                                                                }
                                                                delegate: Rectangle {
                                                                    id: appItemRow
                                                                    required property var modelData
                                                                    Layout.fillWidth: true
                                                                    implicitHeight: 38
                                                                    radius: 6
                                                                    color: appItemArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.5)
                                                                    border.width: (defCatCard.catInfo && defCatCard.catInfo.current_desktop === appItemRow.modelData.filename) ? 1 : 0
                                                                    border.color: Theme.primary

                                                                    RowLayout {
                                                                        anchors.fill: parent
                                                                        anchors.leftMargin: 8
                                                                        anchors.rightMargin: 8
                                                                        spacing: 10

                                                                        Image {
                                                                            Layout.preferredWidth: 24
                                                                            Layout.preferredHeight: 24
                                                                            source: win.appIconSource(appItemRow.modelData.icon)
                                                                            fillMode: Image.PreserveAspectFit
                                                                        }

                                                                        ColumnLayout {
                                                                            Layout.fillWidth: true
                                                                            spacing: 0
                                                                            Text {
                                                                                text: appItemRow.modelData.name
                                                                                font.family: Theme.fontFamily
                                                                                font.pixelSize: 11
                                                                                font.weight: Font.DemiBold
                                                                                color: Theme.textColor
                                                                                elide: Text.ElideRight
                                                                            }
                                                                            Text {
                                                                                text: appItemRow.modelData.filename
                                                                                font.family: Theme.monoFamily
                                                                                font.pixelSize: 9
                                                                                color: Theme.subtext
                                                                                elide: Text.ElideRight
                                                                            }
                                                                        }

                                                                        Text {
                                                                            visible: defCatCard.catInfo && defCatCard.catInfo.current_desktop === appItemRow.modelData.filename
                                                                            text: Theme.icons.confirm + " Atual"
                                                                            font.family: Theme.fontFamily
                                                                            font.pixelSize: 10
                                                                            font.weight: Font.Bold
                                                                            color: Theme.primary
                                                                        }
                                                                    }

                                                                    MouseArea {
                                                                        id: appItemArea
                                                                        anchors.fill: parent
                                                                        hoverEnabled: true
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: {
                                                                            Quickshell.execDetached(["rice-default-apps", "set", defCatCard.modelData.id, appItemRow.modelData.filename]);
                                                                            win.showToast("Definido como padrão: " + appItemRow.modelData.name);
                                                                            win.pickingDefaultCategory = "";
                                                                            defaultAppsRefreshTimer.restart();
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

                                Timer {
                                    id: defaultAppsRefreshTimer
                                    interval: 600
                                    onTriggered: {
                                        loadDefaultAppsProc.running = true;
                                    }
                                }
                            }
                        }

                        // ==================== ABA 13: JOGOS & GPU ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 13
                            contentHeight: gamingCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: gamingCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Jogos & Placa Gráfica Dedicada"
                                    subtitle: "Monitore a NVIDIA GeForce RTX 3050, GameMode e parâmetros da Steam"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 74
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 10
                                            Rectangle {
                                                implicitWidth: 38; implicitHeight: 38; radius: 10
                                                color: Theme.withAlpha("#ff7733", 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "🌡️"
                                                    font.pixelSize: 16
                                                }
                                            }
                                            ColumnLayout {
                                                spacing: 2
                                                Text {
                                                    text: "Temperatura GPU"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                                Text {
                                                    text: (win.gamingData && win.gamingData.gpu && win.gamingData.gpu.temp ? win.gamingData.gpu.temp : "--") + " °C"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 16
                                                    font.weight: Font.Bold
                                                    color: Theme.textColor
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 74
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 10
                                            Rectangle {
                                                implicitWidth: 38; implicitHeight: 38; radius: 10
                                                color: Theme.withAlpha(Theme.primary, 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Theme.icons.memory
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 16
                                                    color: Theme.primary
                                                }
                                            }
                                            ColumnLayout {
                                                spacing: 2
                                                Text {
                                                    text: "VRAM Utilizada"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                                Text {
                                                    text: (win.gamingData && win.gamingData.gpu && win.gamingData.gpu.vram_used ? win.gamingData.gpu.vram_used : 0) + " / " + (win.gamingData && win.gamingData.gpu && win.gamingData.gpu.vram_total ? win.gamingData.gpu.vram_total : 4096) + " MB"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.Bold
                                                    color: Theme.textColor
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 74
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 10
                                            Rectangle {
                                                implicitWidth: 38; implicitHeight: 38; radius: 10
                                                color: Theme.withAlpha(Theme.primary, 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Theme.icons.gpu
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 16
                                                    color: Theme.primary
                                                }
                                            }
                                            ColumnLayout {
                                                spacing: 2
                                                Text {
                                                    text: "Driver NVIDIA"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                                Text {
                                                    text: win.gamingData && win.gamingData.gpu && win.gamingData.gpu.driver ? win.gamingData.gpu.driver : "Ativo"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.Bold
                                                    color: Theme.textColor
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 64
                                    radius: 12
                                    color: Theme.tile
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.outline, 0.2)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        Text {
                                            text: Theme.icons.speed
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 22
                                            color: win.gamingData && win.gamingData.gamemode_active ? Theme.primary : Theme.subtext
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text {
                                                text: "Feral GameMode"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                color: Theme.textColor
                                            }
                                            Text {
                                                text: "Otimiza a CPU para priorizar taxas de quadros (FPS) e reduz a latência nos jogos"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.subtext
                                            }
                                        }

                                        SwitchToggle {
                                            checked: win.gamingData && win.gamingData.gamemode_active
                                            onToggled: {
                                                Quickshell.execDetached(["rice-gaming", "toggle-gamemode"]);
                                                loadGamingProc.running = true;
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Parâmetros para Jogos da Steam"
                                    subtitle: "Clique em Copiar e cole nas Propriedades do Jogo -> Opções de Inicialização"
                                }

                                Repeater {
                                    model: [
                                        { id: "nvidia", title: "NVIDIA Dedicada (prime-run)", param: "prime-run %command%", desc: "Garante que o jogo rode diretamente na GPU dedicada NVIDIA RTX 3050." },
                                        { id: "gamemode", title: "NVIDIA + Feral GameMode", param: "gamemoderun prime-run %command%", desc: "Combina aceleração máxima da GPU com prioridade de processador." },
                                        { id: "compat", title: "Compatibilidade (Desativa NVAPI)", param: "PROTON_DISABLE_NVAPI=1 prime-run %command%", desc: "Use apenas se algum jogo der tela preta ou erro com DLSS." }
                                    ]
                                    delegate: Rectangle {
                                        id: steamCard
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 70
                                        radius: 10
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: steamCard.modelData.title
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: steamCard.modelData.desc
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                                Text {
                                                    text: steamCard.modelData.param
                                                    font.family: Theme.monoFamily
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: Theme.primary
                                                }
                                            }

                                            ActionBtn {
                                                icon: Theme.icons.confirm
                                                text: "Copiar"
                                                primary: true
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-gaming", "copy-param", steamCard.modelData.id]);
                                                    showToast("Parâmetro copiado para a área de transferência!");
                                                }
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    ActionBtn {
                                        icon: Theme.icons.gamepad
                                        text: "Abrir Steam"
                                        onClicked: Quickshell.execDetached(["steam"])
                                    }
                                    ActionBtn {
                                        icon: Theme.icons.speed
                                        text: "Abrir Heroic Games"
                                        onClicked: Quickshell.execDetached(["heroic"])
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }

                        // ==================== ABA 14: ARMAZENAMENTO ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 14
                            contentHeight: storCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: storCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Armazenamento & Limpeza Segura"
                                    subtitle: "Monitore o SSD e libere gigabytes de caches temporários sem risco"
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 96
                                    radius: 12
                                    color: Theme.tile
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.outline, 0.2)

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 8

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "SSD Principal (Partição Btrfs /)"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                color: Theme.textColor
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: (win.storageData ? win.storageData.root_used : "") + " usado de " + (win.storageData ? win.storageData.root_total : "") + " (" + (win.storageData ? win.storageData.root_avail : "") + " livres)"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.subtext
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 12
                                            radius: 6
                                            color: Theme.background

                                            Rectangle {
                                                height: parent.height
                                                width: parent.width * ((win.storageData && win.storageData.root_pct ? win.storageData.root_pct : 0) / 100.0)
                                                radius: 6
                                                color: (win.storageData && win.storageData.root_pct > 85) ? "#ff5555" : Theme.primary
                                            }
                                        }

                                        Text {
                                            text: (win.storageData ? win.storageData.root_pct : 0) + "% do espaço ocupado"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.subtext
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: "Caches & Espaço Recuperável"
                                    subtitle: "Arquivos que podem ser apagados com segurança para recuperar espaço"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 80
                                        radius: 10
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)
                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 2
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: "Cache Pacman"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.subtext
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: win.storageData ? win.storageData.pacman_cache : "0 B"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                                font.weight: Font.Bold
                                                color: Theme.primary
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 80
                                        radius: 10
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)
                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 2
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: "Miniaturas"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.subtext
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: win.storageData ? win.storageData.thumbnails : "0 B"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                                font.weight: Font.Bold
                                                color: Theme.primary
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 80
                                        radius: 10
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)
                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 2
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: "Lixeira"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.subtext
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: win.storageData ? win.storageData.trash : "0 B"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                                font.weight: Font.Bold
                                                color: Theme.primary
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 80
                                        radius: 10
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)
                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 2
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: "Caches de Apps"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.subtext
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: win.storageData ? win.storageData.user_cache : "0 B"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                                font.weight: Font.Bold
                                                color: Theme.primary
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 56
                                        radius: 10
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12
                                            Text {
                                                text: Theme.icons.packages
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 18
                                                color: Theme.primary
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: "Limpar Pacotes Antigos do Pacman"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Mantém as 2 últimas versões instaladas para rollback seguro e remove o restante."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }
                                            ActionBtn {
                                                icon: Theme.icons.broom
                                                text: "Limpar"
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-storage", "clean-pacman"]);
                                                    loadStorageProc.running = true;
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 56
                                        radius: 10
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12
                                            Text {
                                                text: Theme.icons.camera
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 18
                                                color: Theme.primary
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: "Limpar Miniaturas em Cache"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Remove thumbnails geradas para arquivos e vídeos. Elas serão recriadas se necessário."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }
                                            ActionBtn {
                                                icon: Theme.icons.broom
                                                text: "Limpar"
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-storage", "clean-thumbnails"]);
                                                    loadStorageProc.running = true;
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 56
                                        radius: 10
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12
                                            Text {
                                                text: Theme.icons.trash
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 18
                                                color: Theme.primary
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: "Esvaziar Lixeira do Usuário"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: "Apaga permanentemente os arquivos descartados em ~/.local/share/Trash."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }
                                            ActionBtn {
                                                icon: Theme.icons.trash
                                                text: "Esvaziar"
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-storage", "clean-trash"]);
                                                    loadStorageProc.running = true;
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12
                                        ActionBtn {
                                            icon: Theme.icons.broom
                                            text: "Executar Limpeza Profunda Completa"
                                            primary: true
                                            onClicked: {
                                                Quickshell.execDetached(["rice-storage", "clean-all"]);
                                                loadStorageProc.running = true;
                                                showToast("Limpeza profunda concluída!");
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                            }
                        }

                        // ==================== ABA 15: GUIA DE ATALHOS ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 15
                            contentHeight: bindsCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: bindsCol
                                width: parent.width
                                spacing: 14

                                RowLayout {
                                    Layout.fillWidth: true
                                    SectionHeader {
                                        title: "Guia de Teclas & Atalhos"
                                        subtitle: "Atalhos essenciais do Hyprland com busca instantânea"
                                    }
                                    Item { Layout.fillWidth: true }

                                    Rectangle {
                                        implicitWidth: 200
                                        implicitHeight: 32
                                        radius: 8
                                        color: Theme.background
                                        border.width: 1
                                        border.color: searchInput.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 6
                                            Text {
                                                text: Theme.icons.magnify
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 13
                                                color: Theme.subtext
                                            }
                                            TextInput {
                                                id: searchInput
                                                Layout.fillWidth: true
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.textColor
                                                clip: true
                                                onTextChanged: win.bindsFilter = text.toLowerCase()
                                                Text {
                                                    visible: !searchInput.text
                                                    text: "Buscar atalho..."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    color: Theme.subtext
                                                }
                                            }
                                        }
                                    }
                                }

                                // Banner de Personalização de Atalhos do Usuário
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: customBindsCol.implicitHeight + 24
                                    radius: 12
                                    color: Theme.tile
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.primary, 0.4)

                                    ColumnLayout {
                                        id: customBindsCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 10

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
                                                spacing: 2
                                                Text {
                                                    text: Theme.t("binds.custom_title", "Personalizar Atalhos Próprios (~/.config/hypr/user-binds.lua)")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.Bold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: Theme.t("binds.custom_desc", "Adicione ou altere qualquer atalho do Hyprland sem perder suas customizações em atualizações futuras.")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                    wrapMode: Text.WordWrap
                                                    Layout.fillWidth: true
                                                }
                                            }

                                            ActionBtn {
                                                icon: Theme.icons.pencil
                                                text: Theme.t("binds.custom_btn", "Editar Atalhos Customizados")
                                                primary: true
                                                onClicked: {
                                                    Quickshell.execDetached(["bash", "-c", "f=\"$HOME/.config/hypr/user-binds.lua\"; if [ ! -f \"$f\" ]; then for p in \"$HOME/.hollow-wired/dots/hypr/user-binds.lua.example\" \"$HOME/projetos/hyprland-setup/dots/hypr/user-binds.lua.example\" \"$HOME/hyprland-setup/dots/hypr/user-binds.lua.example\"; do if [ -f \"$p\" ]; then cp \"$p\" \"$f\" && break; fi; done; if [ ! -f \"$f\" ]; then echo '-- ~/.config/hypr/user-binds.lua\n-- Adicione seus atalhos personalizados aqui!\n-- hl.bind(\"CTRL + ALT + Delete\", hl.dsp.exec_cmd(\"quickshell ipc call energy open\"))\n' > \"$f\"; fi; fi; xdg-open \"$f\" || kate \"$f\" || kitty -e micro \"$f\""]);
                                                    win.showToast(Theme.t("binds.opened_toast", "Abrindo user-binds.lua..."));
                                                }
                                            }
                                        }
                                    }
                                }

                                Repeater {
                                    model: [
                                        {
                                            cat: "Janelas & Navegação",
                                            binds: [
                                                { key: "Super + Q", action: "Abrir Terminal Kitty" },
                                                { key: "Super + C", action: "Fechar Janela Ativa" },
                                                { key: "Alt + F4", action: "Fechar Janela Ativa (Padrão Windows)" },
                                                { key: "Super + F", action: "Alternar Tela Cheia (Fullscreen)" },
                                                { key: "Super + Shift + V", action: "Alternar Janela Flutuante" },
                                                { key: "Super + P", action: "Alternar Modo Pseudo-Tiling" },
                                                { key: "Super + J", action: "Alternar Divisão Horizontal / Vertical" },
                                                { key: "Super + Setas", action: "Mudar Foco entre Janelas" },
                                                { key: "Super + 1..9", action: "Mudar para Área de Trabalho (Workspace)" },
                                                { key: "Super + Shift + 1..9", action: "Mover Janela para Área de Trabalho" },
                                                { key: "Super + A", action: "Abrir Área Especial (Scratchpad)" }
                                            ]
                                        },
                                        {
                                            cat: "Aplicativos & Ferramentas do Rice",
                                            binds: [
                                                { key: "Ctrl + Alt + Del", action: "Menu de Energia / Desligar / Suspender" },
                                                { key: "Super / Super + R", action: "Menu de Aplicativos (Launcher Quickshell)" },
                                                { key: "Super + E", action: "Gerenciador de Pastas (Dolphin)" },
                                                { key: "Super + I", action: "Painel de Controle Rice (Esta Central Gráfica)" },
                                                { key: "Super + S", action: "Trocar Papel de Parede (Waywallen Switcher)" },
                                                { key: "Super + V", action: "Histórico da Área de Transferência" },
                                                { key: "Super + B", action: "Alternar Desfoque de Janelas (Blur On/Off)" },
                                                { key: "Super + W", action: "Editar Widgets da Área de Trabalho" },
                                                { key: "Super + N", action: "Abrir Central de Notificações" },
                                                { key: "Super + Shift + N", action: "Alternar Não Perturbe (DND)" },
                                                { key: "Super + L", action: "Bloquear Tela (Hyprlock)" },
                                                { key: "Alt + Tab", action: "Alternador de Janelas com Miniaturas" }
                                            ]
                                        },
                                        {
                                            cat: "Captura & Gravação de Tela",
                                            binds: [
                                                { key: "Print / Super+Shift+S", action: "Captura de Região (Salva e Copia)" },
                                                { key: "Super + Alt + S", action: "Captura com Editor de Anotações (Swappy)" },
                                                { key: "Shift + Print", action: "Captura da Tela Inteira" },
                                                { key: "Ctrl + Print", action: "Captura da Janela Ativa" },
                                                { key: "Super + Shift + R", action: "Gravar Vídeo de Região com Áudio" },
                                                { key: "Super + Ctrl + Shift + R", action: "Gravar Vídeo da Tela Inteira" }
                                            ]
                                        },
                                        {
                                            cat: "Áudio & Multimídia",
                                            binds: [
                                                { key: "Volume + / -", action: "Aumentar / Diminuir Volume" },
                                                { key: "Mute", action: "Silenciar / Reativar Som" },
                                                { key: "NumLock", action: "Silenciar Microfone Instantaneamente" },
                                                { key: "Brilho + / -", action: "Aumentar / Diminuir Brilho do Monitor" },
                                                { key: "Play / Pause", action: "Reproduzir / Pausar Música" }
                                            ]
                                        }
                                    ]
                                    delegate: ColumnLayout {
                                        id: catBindsCol
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 8

                                        property var filteredBinds: catBindsCol.modelData.binds.filter(b => {
                                            if (!win.bindsFilter) return true;
                                            return b.key.toLowerCase().includes(win.bindsFilter) || b.action.toLowerCase().includes(win.bindsFilter);
                                        })

                                        visible: filteredBinds.length > 0

                                        Text {
                                            text: catBindsCol.modelData.cat
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: Theme.primary
                                        }

                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Repeater {
                                                model: catBindsCol.filteredBinds
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    implicitHeight: 34
                                                    implicitWidth: bindRow.implicitWidth + 20
                                                    radius: 8
                                                    color: Theme.tile
                                                    border.width: 1
                                                    border.color: Theme.withAlpha(Theme.outline, 0.2)

                                                    RowLayout {
                                                        id: bindRow
                                                        anchors.centerIn: parent
                                                        spacing: 8

                                                        Rectangle {
                                                            implicitHeight: 22
                                                            implicitWidth: keyTxt.implicitWidth + 12
                                                            radius: 6
                                                            color: Theme.background
                                                            border.width: 1
                                                            border.color: Theme.withAlpha(Theme.primary, 0.4)
                                                            Text {
                                                                id: keyTxt
                                                                anchors.centerIn: parent
                                                                text: parent.parent.parent.modelData.key
                                                                font.family: Theme.monoFamily
                                                                font.pixelSize: 10
                                                                font.weight: Font.Bold
                                                                color: Theme.primary
                                                            }
                                                        }

                                                        Text {
                                                            text: parent.parent.modelData.action
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            color: Theme.textColor
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ==================== ABA 16: SISTEMA, SNAPSHOTS & REPARO ====================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 16
                            contentHeight: sysCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: sysCol
                                width: parent.width
                                spacing: 16

                                SectionHeader {
                                    title: "Pontos de Restauração Btrfs (Snapshots de Segurança)"
                                    subtitle: "Crie pontos de restauração antes de atualizar o sistema para desfazer qualquer problema pelo Limine"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    ActionBtn {
                                        icon: Theme.icons.plus
                                        text: "Criar Ponto de Restauração Agora"
                                        primary: true
                                        onClicked: {
                                            Quickshell.execDetached(["rice-snapshots", "create", "Snapshot Manual do Usuário"]);
                                            win.showToast("Criando snapshot Btrfs...");
                                            snapRefreshTimer.restart();
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                // Lista de Snapshots Recentes
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        model: win.snapshotsData.snapshots || []
                                        delegate: Rectangle {
                                            id: snapCard
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 46
                                            radius: 8
                                            color: Theme.tile
                                            border.width: 1
                                            border.color: Theme.withAlpha(Theme.outline, 0.15)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 10

                                                Rectangle {
                                                    implicitWidth: 26
                                                    implicitHeight: 26
                                                    radius: 6
                                                    color: Theme.withAlpha(Theme.primary, 0.2)
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Theme.icons.disk
                                                        font.family: Theme.iconFontFamily
                                                        font.pixelSize: 13
                                                        color: Theme.primary
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    Text {
                                                        text: "#" + snapCard.modelData.id + " · " + snapCard.modelData.description
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                        color: Theme.textColor
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        text: snapCard.modelData.date + " · Tipo: " + snapCard.modelData.type
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 9
                                                        color: Theme.subtext
                                                    }
                                                }

                                                Rectangle {
                                                    implicitWidth: 24
                                                    implicitHeight: 24
                                                    radius: 12
                                                    color: snapDelArea.containsMouse ? Theme.withAlpha(Theme.critical, 0.2) : "transparent"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Theme.icons.trash
                                                        font.family: Theme.iconFontFamily
                                                        font.pixelSize: 12
                                                        color: Theme.critical
                                                    }
                                                    MouseArea {
                                                        id: snapDelArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            Quickshell.execDetached(["rice-snapshots", "delete", String(snapCard.modelData.id)]);
                                                            win.showToast("Excluindo snapshot #" + snapCard.modelData.id);
                                                            snapRefreshTimer.restart();
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                Timer {
                                    id: snapRefreshTimer
                                    interval: 800
                                    onTriggered: loadSnapshotsProc.running = true
                                }

                                SectionHeader {
                                    title: "Auto-Reparo & Soluções Rápidas de Um Clique"
                                    subtitle: "Ferramentas práticas para resolver problemas comuns sem abrir o terminal ou digitar comandos"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // Card 1: Áudio PipeWire
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 64
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12

                                            Rectangle {
                                                implicitWidth: 38
                                                implicitHeight: 38
                                                radius: 10
                                                color: Theme.withAlpha(Theme.primary, 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Theme.icons.volHigh
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 18
                                                    color: Theme.primary
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: "Reiniciar Sistema de Áudio (PipeWire)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
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
                                        implicitHeight: 64
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12

                                            Rectangle {
                                                implicitWidth: 38
                                                implicitHeight: 38
                                                radius: 10
                                                color: Theme.withAlpha(Theme.primary, 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Theme.icons.lock
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 18
                                                    color: Theme.primary
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: "Destravar Pacman (Remover db.lck)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
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
                                        implicitHeight: 64
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12

                                            Rectangle {
                                                implicitWidth: 38
                                                implicitHeight: 38
                                                radius: 10
                                                color: Theme.withAlpha(Theme.primary, 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Theme.icons.broom
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 18
                                                    color: Theme.primary
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: "Limpeza de Disco & Caches Antigos"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
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
                                        implicitHeight: 64
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12

                                            Rectangle {
                                                implicitWidth: 38
                                                implicitHeight: 38
                                                radius: 10
                                                color: Theme.withAlpha(Theme.primary, 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Theme.icons.health
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 18
                                                    color: Theme.primary
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: "Assistente de Diagnóstico (Rice Doctor)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
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

                        // ==========================================
                        // ABA 17: CENTRAL DE APLICATIVOS & ATUALIZAÇÕES
                        // ==========================================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 17
                            contentHeight: appStoreCol.implicitHeight + 24
                            contentWidth: width
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: appStoreCol
                                width: parent.width
                                spacing: 18

                                // 1. Banner de Atualizações do Sistema
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 110
                                    radius: 14
                                    color: Theme.tile
                                    border.width: 1
                                    border.color: win.softwareUpdatesData.count > 0 ? Theme.withAlpha("#f59e0b", 0.5) : Theme.withAlpha(Theme.primary, 0.3)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 16

                                        Rectangle {
                                            implicitWidth: 54
                                            implicitHeight: 54
                                            radius: 27
                                            color: win.softwareUpdatesData.count > 0
                                                ? Theme.withAlpha("#f59e0b", 0.2)
                                                : Theme.withAlpha("#10b981", 0.2)

                                            Text {
                                                anchors.centerIn: parent
                                                text: win.softwareUpdatesData.count > 0 ? "\u{F002A}" : "\u{F012C}"
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 26
                                                color: win.softwareUpdatesData.count > 0 ? "#f59e0b" : "#10b981"
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4

                                            RowLayout {
                                                spacing: 8
                                                Text {
                                                    text: win.softwareUpdatesData.count > 0
                                                        ? win.softwareUpdatesData.count + " Atualizações Disponíveis"
                                                        : "Sistema 100% Atualizado (Arch Linux / CachyOS)"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 15
                                                    font.weight: Font.Bold
                                                    color: Theme.textColor
                                                }

                                                Rectangle {
                                                    visible: win.softwareUpdatesData.count > 0
                                                    implicitHeight: 20
                                                    implicitWidth: updCountText.implicitWidth + 12
                                                    radius: 10
                                                    color: Theme.withAlpha("#f59e0b", 0.25)
                                                    Text {
                                                        id: updCountText
                                                        anchors.centerIn: parent
                                                        text: win.softwareUpdatesData.count + " pacotes"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        font.weight: Font.Bold
                                                        color: "#f59e0b"
                                                    }
                                                }
                                            }

                                            Text {
                                                text: win.softwareUpdatesData.count > 0
                                                    ? "Há novos pacotes do sistema e do repositório AUR prontos para instalar com segurança."
                                                    : "Todos os pacotes oficiais, kernel e drivers estão na versão mais recente."
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.subtext
                                            }

                                            // Chips de pacotes atualizáveis
                                            Flickable {
                                                Layout.fillWidth: true
                                                implicitHeight: 24
                                                contentWidth: pkgsRow.implicitWidth
                                                clip: true
                                                visible: win.softwareUpdatesData.packages && win.softwareUpdatesData.packages.length > 0

                                                Row {
                                                    id: pkgsRow
                                                    spacing: 6
                                                    Repeater {
                                                        model: win.softwareUpdatesData.packages || []
                                                        delegate: Rectangle {
                                                            implicitHeight: 22
                                                            implicitWidth: pkgNameText.implicitWidth + 14
                                                            radius: 11
                                                            color: Theme.tileHigh
                                                            border.width: 1
                                                            border.color: Theme.withAlpha(Theme.outline, 0.2)
                                                            Text {
                                                                id: pkgNameText
                                                                anchors.centerIn: parent
                                                                text: modelData
                                                                font.family: Theme.monoFamily
                                                                font.pixelSize: 10
                                                                color: Theme.textColor
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            spacing: 8
                                            ActionBtn {
                                                icon: Theme.icons.refresh
                                                text: "Verificar Novamente"
                                                onClicked: {
                                                    loadSoftwareUpdatesProc.running = true;
                                                    loadSoftwareAppsProc.running = true;
                                                    win.showToast("Verificando atualizações...");
                                                }
                                            }

                                            ActionBtn {
                                                icon: "\u{F03D8}"
                                                text: "Atualizar Dotfiles (" + (win.softwareUpdatesData.rice_updates || 0) + ")"
                                                primary: true
                                                visible: (win.softwareUpdatesData.rice_updates || 0) > 0
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-software", "update-rice"]);
                                                    win.showToast("Atualizador de Dotfiles aberto!");
                                                }
                                            }

                                            ActionBtn {
                                                icon: "\u{F002A}"
                                                text: "Atualizar Tudo Agora"
                                                primary: !(win.softwareUpdatesData.rice_updates > 0)
                                                visible: (win.softwareUpdatesData.count || 0) > 0
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-software", "update-system"]);
                                                    win.showToast("Janela de atualização aberta no terminal!");
                                                }
                                            }
                                        }
                                    }
                                }

                                // 2. Barra de Filtro de Categorias
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Text {
                                        text: "CATÁLOGO DE SOFTWARES RECOMENDADOS"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: Theme.primary
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Filtros
                                    RowLayout {
                                        spacing: 6
                                        Repeater {
                                            model: [
                                                { id: "all", label: "Todos" },
                                                { id: "comm", label: "Comunicação" },
                                                { id: "media", label: "Mídia & Streaming" },
                                                { id: "gaming", label: "Jogos" },
                                                { id: "prod", label: "Produtividade" },
                                                { id: "browser", label: "Navegadores" },
                                                { id: "tools", label: "Utilitários" }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                implicitHeight: 28
                                                implicitWidth: catBtnText.implicitWidth + 16
                                                radius: 14
                                                color: win.softwareCatFilter === modelData.id
                                                    ? Theme.primary
                                                    : (catArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.6))
                                                border.width: 1
                                                border.color: win.softwareCatFilter === modelData.id ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                                Text {
                                                    id: catBtnText
                                                    anchors.centerIn: parent
                                                    text: modelData.label
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    font.weight: win.softwareCatFilter === modelData.id ? Font.Bold : Font.Normal
                                                    color: win.softwareCatFilter === modelData.id ? Theme.background : Theme.textColor
                                                }

                                                MouseArea {
                                                    id: catArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: win.softwareCatFilter = modelData.id
                                                }
                                            }
                                        }
                                    }
                                }

                                // 3. Grid de Aplicativos
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    rowSpacing: 12
                                    columnSpacing: 12

                                    Repeater {
                                        model: (win.softwareCatalogData || []).filter(function(app) {
                                            if (win.softwareCatFilter !== "all" && app.category !== win.softwareCatFilter) return false;
                                            return true;
                                        })

                                        delegate: Rectangle {
                                            id: appCard
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 88
                                            radius: 12
                                            color: Theme.tile
                                            border.width: 1
                                            border.color: Theme.withAlpha(Theme.outline, 0.2)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 12

                                                // Ícone do app
                                                Rectangle {
                                                    implicitWidth: 46
                                                    implicitHeight: 46
                                                    radius: 10
                                                    color: appCard.modelData.installed
                                                        ? Theme.withAlpha(Theme.primary, 0.18)
                                                        : Theme.withAlpha(Theme.textColor, 0.08)
                                                    border.width: 1
                                                    border.color: appCard.modelData.installed ? Theme.withAlpha(Theme.primary, 0.4) : Theme.withAlpha(Theme.outline, 0.15)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: appCard.modelData.icon || "\u{F01E}"
                                                        font.family: Theme.iconFontFamily
                                                        font.pixelSize: 20
                                                        color: appCard.modelData.installed ? Theme.primary : Theme.subtext
                                                    }
                                                }

                                                // Info
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2

                                                    RowLayout {
                                                        spacing: 8
                                                        Text {
                                                            text: appCard.modelData.name
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 12
                                                            font.weight: Font.DemiBold
                                                            color: Theme.textColor
                                                        }

                                                        Rectangle {
                                                            implicitHeight: 18
                                                            implicitWidth: stBadgeText.implicitWidth + 10
                                                            radius: 9
                                                            color: appCard.modelData.installed
                                                                ? Theme.withAlpha("#10b981", 0.18)
                                                                : Theme.withAlpha(Theme.subtext, 0.12)
                                                            border.width: 1
                                                            border.color: appCard.modelData.installed ? "#10b981" : Theme.withAlpha(Theme.outline, 0.2)

                                                            Text {
                                                                id: stBadgeText
                                                                anchors.centerIn: parent
                                                                text: appCard.modelData.installed ? "✓ Instalado" : "Disponível"
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 9
                                                                font.weight: Font.Bold
                                                                color: appCard.modelData.installed ? "#10b981" : Theme.subtext
                                                            }
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: appCard.modelData.desc
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: Theme.subtext
                                                        wrapMode: Text.WordWrap
                                                        maximumLineCount: 2
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                // Ações
                                                RowLayout {
                                                    spacing: 6

                                                    // Se instalado: Botão Abrir e Botão Remover
                                                    ActionBtn {
                                                        visible: appCard.modelData.installed
                                                        icon: "\u{F04B}"
                                                        text: "Abrir"
                                                        primary: true
                                                        onClicked: {
                                                            Quickshell.execDetached(["rice-software", "launch", appCard.modelData.id]);
                                                        }
                                                    }

                                                    Rectangle {
                                                        visible: appCard.modelData.installed
                                                        implicitWidth: 32
                                                        implicitHeight: 32
                                                        radius: 8
                                                        color: uninstArea.containsMouse ? Theme.withAlpha("#ef4444", 0.2) : Theme.tileHigh
                                                        border.width: 1
                                                        border.color: uninstArea.containsMouse ? "#ef4444" : Theme.withAlpha(Theme.outline, 0.2)

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: Theme.icons.trash
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 13
                                                            color: uninstArea.containsMouse ? "#ef4444" : Theme.subtext
                                                        }

                                                        MouseArea {
                                                            id: uninstArea
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                Quickshell.execDetached(["rice-software", "uninstall", appCard.modelData.id]);
                                                            }
                                                        }
                                                    }

                                                    // Se não instalado: Botão Instalar 1-clique
                                                    ActionBtn {
                                                        visible: !appCard.modelData.installed
                                                        icon: "\u{F01DA}"
                                                        text: "Instalar"
                                                        primary: false
                                                        onClicked: {
                                                            Quickshell.execDetached(["rice-software", "install", appCard.modelData.id]);
                                                            win.showToast("Instalando " + appCard.modelData.name + " no terminal!");
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ==========================================
                        // ABA 18: PERFIS DE ESTILO & BACKUP DO RICE
                        // ==========================================
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 18
                            contentHeight: presetsCol.implicitHeight + 24
                            contentWidth: width
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: presetsCol
                                width: parent.width
                                spacing: 20

                                // 1. Seção de Perfis Visuais
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "PERFIS DE ESTILO & PERFORMANCE"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: Theme.primary
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "Altera gaps, cantos arredondados, animações e efeitos com 1 clique"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.subtext
                                        }
                                    }

                                    // Cards dos Perfis
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Repeater {
                                            model: win.presetsData || []
                                            delegate: Rectangle {
                                                id: presetCard
                                                required property var modelData
                                                Layout.fillWidth: true
                                                implicitHeight: 82
                                                radius: 12
                                                color: Theme.tile
                                                border.width: 1
                                                border.color: prsArea.containsMouse ? presetCard.modelData.accent : Theme.withAlpha(Theme.outline, 0.2)

                                                Behavior on border.color { ColorAnimation { duration: 140 } }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 14
                                                    spacing: 14

                                                    Rectangle {
                                                        implicitWidth: 46
                                                        implicitHeight: 46
                                                        radius: 12
                                                        color: Theme.withAlpha(presetCard.modelData.accent, 0.18)
                                                        border.width: 1
                                                        border.color: Theme.withAlpha(presetCard.modelData.accent, 0.5)

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: presetCard.modelData.icon || "\u{F01E}"
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 20
                                                            color: presetCard.modelData.accent
                                                        }
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 3

                                                        RowLayout {
                                                            spacing: 10
                                                            Text {
                                                                text: presetCard.modelData.name
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 13
                                                                font.weight: Font.Bold
                                                                color: Theme.textColor
                                                            }

                                                            // Badges com os parâmetros
                                                            Rectangle {
                                                                implicitHeight: 18
                                                                implicitWidth: gpText.implicitWidth + 10
                                                                radius: 9
                                                                color: Theme.tileHigh
                                                                Text {
                                                                    id: gpText
                                                                    anchors.centerIn: parent
                                                                    text: "Gaps: " + presetCard.modelData.gaps_in + "px"
                                                                    font.family: Theme.monoFamily
                                                                    font.pixelSize: 9
                                                                    color: Theme.subtext
                                                                }
                                                            }

                                                            Rectangle {
                                                                implicitHeight: 18
                                                                implicitWidth: rdText.implicitWidth + 10
                                                                radius: 9
                                                                color: Theme.tileHigh
                                                                Text {
                                                                    id: rdText
                                                                    anchors.centerIn: parent
                                                                    text: "Cantos: " + presetCard.modelData.rounding + "px"
                                                                    font.family: Theme.monoFamily
                                                                    font.pixelSize: 9
                                                                    color: Theme.subtext
                                                                }
                                                            }
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: presetCard.modelData.desc
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            color: Theme.subtext
                                                        }
                                                    }

                                                    ActionBtn {
                                                        icon: "\u{F00C}"
                                                        text: "Aplicar Perfil"
                                                        primary: true
                                                        onClicked: {
                                                            Quickshell.execDetached(["rice-presets", "apply", presetCard.modelData.id]);
                                                            win.showToast("Perfil " + presetCard.modelData.name + " aplicado!");
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    id: prsArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    z: -1
                                                }
                                            }
                                        }
                                    }
                                }

                                // 2. Seção de Backups & Restauração Local
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "PONTOS DE RESTAURAÇÃO DO RICE (BACKUPS)"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: Theme.primary
                                        }
                                        Item { Layout.fillWidth: true }
                                        ActionBtn {
                                            icon: Theme.icons.disk
                                            text: "Criar Novo Backup Agora"
                                            primary: true
                                            onClicked: {
                                                Quickshell.execDetached(["rice-presets", "backup-create"]);
                                                win.showToast("Criando backup das configurações...");
                                                backupReloadTimer.restart();
                                            }
                                        }
                                    }

                                    Timer {
                                        id: backupReloadTimer
                                        interval: 1000
                                        onTriggered: loadBackupsProc.running = true
                                    }

                                    // Lista de Backups
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Repeater {
                                            model: win.backupsData || []
                                            delegate: Rectangle {
                                                id: bkCard
                                                required property var modelData
                                                Layout.fillWidth: true
                                                implicitHeight: 64
                                                radius: 12
                                                color: Theme.tile
                                                border.width: 1
                                                border.color: Theme.withAlpha(Theme.outline, 0.2)

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 12
                                                    spacing: 12

                                                    Rectangle {
                                                        implicitWidth: 38
                                                        implicitHeight: 38
                                                        radius: 10
                                                        color: Theme.withAlpha(Theme.primary, 0.15)
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: Theme.icons.disk
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 16
                                                            color: Theme.primary
                                                        }
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 2
                                                        Text {
                                                            text: bkCard.modelData.name
                                                            font.family: Theme.monoFamily
                                                            font.pixelSize: 11
                                                            font.weight: Font.Medium
                                                            color: Theme.textColor
                                                        }
                                                        RowLayout {
                                                            spacing: 8
                                                            Text {
                                                                text: "Data: " + bkCard.modelData.date
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
                                                                text: "Tamanho: " + bkCard.modelData.size
                                                                font.family: Theme.monoFamily
                                                                font.pixelSize: 10
                                                                color: Theme.subtext
                                                            }
                                                        }
                                                    }

                                                    ActionBtn {
                                                        icon: Theme.icons.refresh
                                                        text: "Restaurar"
                                                        onClicked: {
                                                            Quickshell.execDetached(["rice-presets", "backup-restore", bkCard.modelData.path]);
                                                            win.showToast("Restaurando configurações do backup...");
                                                        }
                                                    }

                                                    Rectangle {
                                                        implicitWidth: 32
                                                        implicitHeight: 32
                                                        radius: 8
                                                        color: delBkArea.containsMouse ? Theme.withAlpha("#ef4444", 0.2) : Theme.tileHigh
                                                        border.width: 1
                                                        border.color: delBkArea.containsMouse ? "#ef4444" : Theme.withAlpha(Theme.outline, 0.2)

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: Theme.icons.trash
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 13
                                                            color: delBkArea.containsMouse ? "#ef4444" : Theme.subtext
                                                        }

                                                        MouseArea {
                                                            id: delBkArea
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                Quickshell.execDetached(["rice-presets", "backup-delete", bkCard.modelData.path]);
                                                                backupReloadTimer.restart();
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Placeholder se vazio
                                        Rectangle {
                                            visible: !win.backupsData || win.backupsData.length === 0
                                            Layout.fillWidth: true
                                            implicitHeight: 70
                                            radius: 10
                                            color: Theme.withAlpha(Theme.tile, 0.5)
                                            border.width: 1
                                            border.color: Theme.withAlpha(Theme.outline, 0.15)

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: "Nenhum ponto de restauração encontrado."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    font.weight: Font.Medium
                                                    color: Theme.subtext
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: "Clique em 'Criar Novo Backup Agora' para gerar uma cópia de segurança completa das suas configs."
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.withAlpha(Theme.subtext, 0.7)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ==========================================
                        // ABA 19: CUSTOMIZAÇÃO DO SHELL (HUB, SIDEBAR, DOCK)
                        // ==========================================
                        Flickable {
                            id: shellCustomTab
                            anchors.fill: parent
                            visible: win.currentTab === 19
                            contentHeight: shellCustomCol.implicitHeight + 40
                            contentWidth: width
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            property string targetComp: "dock"

                            ColumnLayout {
                                id: shellCustomCol
                                width: parent.width
                                spacing: 18

                                // 1. Cabeçalho e Seletor do Componente
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: Theme.t("settings.cat_shell_custom", "CUSTOMIZAÇÃO DO SHELL").toUpperCase()
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: Theme.primary
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: Theme.t("shell_custom.preview_desc", "Configurações sincronizadas em tempo real via ShellCustomization.")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.subtext
                                        }
                                    }

                                    // Seletor de Componentes: Hub, Sidebar, Dock
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 48
                                        radius: 12
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 8

                                            Repeater {
                                                model: [
                                                    { id: "hub", name: Theme.t("shell_custom.hub", "Hub Central"), icon: Theme.icons.dashboard },
                                                    { id: "sidebar", name: Theme.t("shell_custom.sidebar", "Barra Lateral"), icon: Theme.icons.tune },
                                                    { id: "dock", name: Theme.t("shell_custom.dock", "Dock Inferior"), icon: Theme.icons.gamepad }
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    radius: 8
                                                    readonly property bool isSelected: shellCustomTab.targetComp === modelData.id
                                                    color: isSelected ? Theme.primary : (compArea.containsMouse ? Theme.tileHigh : "transparent")
                                                    border.width: isSelected ? 0 : 1
                                                    border.color: Theme.withAlpha(Theme.outline, 0.15)

                                                    Behavior on color { ColorAnimation { duration: 100 } }

                                                    RowLayout {
                                                        anchors.centerIn: parent
                                                        spacing: 8
                                                        Text {
                                                            text: modelData.icon
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 14
                                                            color: isSelected ? Theme.background : Theme.textColor
                                                        }
                                                        Text {
                                                            text: modelData.name
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            font.weight: isSelected ? Font.Bold : Font.Normal
                                                            color: isSelected ? Theme.background : Theme.textColor
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: compArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: shellCustomTab.targetComp = modelData.id
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // 2. Live Preview Card
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 140
                                    radius: 12
                                    color: Theme.withAlpha(Theme.background, 0.6)
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.outline, 0.25)
                                    clip: true

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 10

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: Theme.t("shell_custom.preview_title", "Prévia Visual Dinâmica")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: Theme.primary
                                            }
                                            Item { Layout.fillWidth: true }
                                            // Badges de Status Atual
                                            Row {
                                                spacing: 6
                                                Rectangle {
                                                    implicitWidth: b1.implicitWidth + 10; implicitHeight: 18; radius: 4
                                                    color: Theme.tile
                                                    Text { id: b1; anchors.centerIn: parent; text: ShellCustomization.getStyle(shellCustomTab.targetComp).toUpperCase(); font.pixelSize: 9; font.weight: Font.Bold; color: Theme.textColor }
                                                }
                                                Rectangle {
                                                    implicitWidth: b2.implicitWidth + 10; implicitHeight: 18; radius: 4
                                                    color: Theme.tile
                                                    Text { id: b2; anchors.centerIn: parent; text: Math.round(ShellCustomization.getScale(shellCustomTab.targetComp) * 100) + "%"; font.pixelSize: 9; font.weight: Font.Bold; color: Theme.textColor }
                                                }
                                                Rectangle {
                                                    implicitWidth: b3.implicitWidth + 10; implicitHeight: 18; radius: 4
                                                    color: Theme.tile
                                                    Text { id: b3; anchors.centerIn: parent; text: Math.round(ShellCustomization.getOpacity(shellCustomTab.targetComp) * 100) + "%"; font.pixelSize: 9; font.weight: Font.Bold; color: Theme.textColor }
                                                }
                                            }
                                        }

                                        // Mockup visual do componente
                                        Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: Math.min(parent.width - 20, 360 * ShellCustomization.getScale(shellCustomTab.targetComp))
                                                height: 56 * ShellCustomization.getScale(shellCustomTab.targetComp)
                                                radius: 12
                                                color: ShellCustomization.getBgColor(shellCustomTab.targetComp)
                                                border.width: ShellCustomization.getBorderWidth(shellCustomTab.targetComp)
                                                border.color: ShellCustomization.getBorderColor(shellCustomTab.targetComp)

                                                // Glow ring se o estilo for glow
                                                Rectangle {
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    radius: 16
                                                    color: "transparent"
                                                    border.color: ShellCustomization.getAccent(shellCustomTab.targetComp)
                                                    border.width: 1
                                                    opacity: ShellCustomization.getStyle(shellCustomTab.targetComp) === "glow" ? 0.4 : 0
                                                    visible: opacity > 0
                                                    z: -1
                                                }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 16
                                                    anchors.rightMargin: 16
                                                    spacing: 12

                                                    Rectangle {
                                                        width: 28; height: 28; radius: 14
                                                        color: Theme.withAlpha(ShellCustomization.getAccent(shellCustomTab.targetComp), 0.25)
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: shellCustomTab.targetComp === "hub" ? Theme.icons.dashboard : (shellCustomTab.targetComp === "sidebar" ? Theme.icons.tune : Theme.icons.gamepad)
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 14
                                                            color: ShellCustomization.getAccent(shellCustomTab.targetComp)
                                                        }
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 2
                                                        Text {
                                                            text: (shellCustomTab.targetComp === "hub" ? "Rice Central Hub" : (shellCustomTab.targetComp === "sidebar" ? "Energy & Quick Sidebar" : "Hollow-Wired Dock"))
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            font.weight: Font.Bold
                                                            color: Theme.textColor
                                                        }
                                                        Text {
                                                            text: "Style: " + ShellCustomization.getStyle(shellCustomTab.targetComp) + " | Scale: " + Math.round(ShellCustomization.getScale(shellCustomTab.targetComp) * 100) + "%"
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 9
                                                            color: Theme.subtext
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // 3. Painel Inspector com 4 Seções (Card unificado)
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: controlsCol.implicitHeight + 28
                                    radius: 12
                                    color: Theme.tile
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.outline, 0.2)

                                    ColumnLayout {
                                        id: controlsCol
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 16

                                        // Seção 1: Estilo Visual
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text {
                                                text: Theme.t("shell_custom.style", "Estilo Visual")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: Theme.subtext
                                            }
                                            Row {
                                                spacing: 8
                                                readonly property var styles: [
                                                    { label: Theme.t("shell_custom.style_glass", "Vidro (Glass)"), val: "glass" },
                                                    { label: Theme.t("shell_custom.style_solid", "Sólido"), val: "solid" },
                                                    { label: Theme.t("shell_custom.style_glow", "Glow"), val: "glow" },
                                                    { label: Theme.t("shell_custom.style_borderless", "Livre"), val: "borderless" }
                                                ]
                                                Repeater {
                                                    model: parent.styles
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        implicitWidth: stText.implicitWidth + 16
                                                        implicitHeight: 28
                                                        radius: 14
                                                        readonly property bool isCurrent: ShellCustomization.getStyle(shellCustomTab.targetComp) === modelData.val
                                                        color: isCurrent ? Theme.primary : (stMouse.containsMouse ? Theme.tileHigh : Theme.surface)
                                                        border.width: 1
                                                        border.color: isCurrent ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                                        Text {
                                                            id: stText
                                                            anchors.centerIn: parent
                                                            text: parent.modelData.label
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 10
                                                            font.weight: Font.Medium
                                                            color: parent.isCurrent ? Theme.background : Theme.textColor
                                                        }
                                                        MouseArea {
                                                            id: stMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: ShellCustomization.setComponentProp(shellCustomTab.targetComp, "style", parent.modelData.val)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.withAlpha(Theme.outline, 0.15) }

                                        // Seção 2: Escala
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text {
                                                text: Theme.t("shell_custom.scale", "Escala de Tamanho")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: Theme.subtext
                                            }
                                            Row {
                                                spacing: 8
                                                readonly property var scales: [
                                                    { label: "80%", val: 0.8 },
                                                    { label: "100%", val: 1.0 },
                                                    { label: "120%", val: 1.2 }
                                                ]
                                                Repeater {
                                                    model: parent.scales
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        implicitWidth: scText.implicitWidth + 18
                                                        implicitHeight: 28
                                                        radius: 14
                                                        readonly property bool isCurrent: Math.abs(ShellCustomization.getScale(shellCustomTab.targetComp) - modelData.val) < 0.05
                                                        color: isCurrent ? Theme.primary : (scMouse.containsMouse ? Theme.tileHigh : Theme.surface)
                                                        border.width: 1
                                                        border.color: isCurrent ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                                        Text {
                                                            id: scText
                                                            anchors.centerIn: parent
                                                            text: parent.modelData.label
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 10
                                                            font.weight: Font.Medium
                                                            color: parent.isCurrent ? Theme.background : Theme.textColor
                                                        }
                                                        MouseArea {
                                                            id: scMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: ShellCustomization.setComponentProp(shellCustomTab.targetComp, "scale", parent.modelData.val)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.withAlpha(Theme.outline, 0.15) }

                                        // Seção 3: Opacidade do Fundo
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text {
                                                text: Theme.t("shell_custom.opacity", "Opacidade do Fundo")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: Theme.subtext
                                            }
                                            Row {
                                                spacing: 8
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
                                                        implicitWidth: opText.implicitWidth + 16
                                                        implicitHeight: 28
                                                        radius: 14
                                                        readonly property bool isCurrent: Math.abs(ShellCustomization.getOpacity(shellCustomTab.targetComp) - modelData.val) < 0.03
                                                        color: isCurrent ? Theme.primary : (opMouse.containsMouse ? Theme.tileHigh : Theme.surface)
                                                        border.width: 1
                                                        border.color: isCurrent ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                                        Text {
                                                            id: opText
                                                            anchors.centerIn: parent
                                                            text: parent.modelData.label
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 10
                                                            font.weight: Font.Medium
                                                            color: parent.isCurrent ? Theme.background : Theme.textColor
                                                        }
                                                        MouseArea {
                                                            id: opMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: ShellCustomization.setComponentProp(shellCustomTab.targetComp, "opacity", parent.modelData.val)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.withAlpha(Theme.outline, 0.15) }

                                        // Seção 4: Cor de Destaque
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text {
                                                text: Theme.t("shell_custom.accent", "Cor de Destaque")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: Theme.subtext
                                            }
                                            Row {
                                                spacing: 12
                                                readonly property var colors: [
                                                    { name: Theme.t("shell_custom.accent_default", "Padrão"), hex: "" },
                                                    { name: Theme.t("shell_custom.accent_cyan", "Ciano"), hex: "#00f0ff" },
                                                    { name: Theme.t("shell_custom.accent_pink", "Rosa"), hex: "#ff007f" },
                                                    { name: Theme.t("shell_custom.accent_emerald", "Esmeralda"), hex: "#10b981" },
                                                    { name: Theme.t("shell_custom.accent_violet", "Violeta"), hex: "#a855f7" },
                                                    { name: Theme.t("shell_custom.accent_amber", "Âmbar"), hex: "#f59e0b" }
                                                ]
                                                Repeater {
                                                    model: parent.colors
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: 28; height: 28; radius: 14
                                                        readonly property string curHex: (ShellCustomization.config[shellCustomTab.targetComp] && ShellCustomization.config[shellCustomTab.targetComp].accent) || ""
                                                        readonly property bool isCurrent: curHex === modelData.hex
                                                        color: modelData.hex !== "" ? modelData.hex : Theme.primary
                                                        border.color: isCurrent ? "#ffffff" : Theme.withAlpha(Theme.outline, 0.3)
                                                        border.width: isCurrent ? 2 : 1

                                                        Text {
                                                            anchors.centerIn: parent
                                                            visible: parent.isCurrent
                                                            text: "✓"
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            font.weight: Font.Bold
                                                            color: "#000000"
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: ShellCustomization.setComponentProp(shellCustomTab.targetComp, "accent", parent.modelData.hex)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Seção Específica da Dock: Ícone do Launcher
                                Rectangle {
                                    visible: shellCustomTab.targetComp === "dock"
                                    Layout.fillWidth: true
                                    implicitHeight: dockIconCol.implicitHeight + 28
                                    radius: 12
                                    color: Theme.tile
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.outline, 0.2)

                                    ColumnLayout {
                                        id: dockIconCol
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 14

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: Theme.t("dock.launcher_icon_title", "Ícone do Launcher da Dock").toUpperCase()
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: Theme.primary
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: "PNG, JPG, SVG, WebP ou GIF"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                color: Theme.subtext
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 14

                                            // Mini preview do ícone atual
                                            Rectangle {
                                                width: 52; height: 52; radius: 12
                                                color: Theme.surface
                                                border.width: 1
                                                border.color: Theme.withAlpha(Theme.outline, 0.3)

                                                AnimatedImage {
                                                    anchors.centerIn: parent
                                                    width: 36; height: 36
                                                    source: {
                                                        const p = DockConfig.launcherIcon;
                                                        if (!p) return "file:///usr/share/pixmaps/archlinux-logo.png";
                                                        return p.startsWith("/") ? "file://" + p : p;
                                                    }
                                                    fillMode: Image.PreserveAspectFit
                                                    mipmap: true
                                                    asynchronous: true
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: Theme.t("dock.launcher_icon_desc", "Ícone fixo à esquerda da Dock para abrir o Launcher.")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    color: Theme.textColor
                                                    wrapMode: Text.WordWrap
                                                }

                                                RowLayout {
                                                    spacing: 10

                                                    Rectangle {
                                                        implicitWidth: chooseTxt.implicitWidth + 24
                                                        implicitHeight: 30
                                                        radius: 15
                                                        color: chooseArea.pressed ? Theme.withAlpha(Theme.primary, 0.7) : Theme.primary

                                                        RowLayout {
                                                            anchors.centerIn: parent
                                                            spacing: 6
                                                            Text {
                                                                text: Theme.icons.palette
                                                                font.family: Theme.iconFontFamily
                                                                font.pixelSize: 12
                                                                color: Theme.background
                                                            }
                                                            Text {
                                                                id: chooseTxt
                                                                text: Theme.t("dock.choose_icon", "Escolher Imagem / GIF...")
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 10
                                                                font.weight: Font.Bold
                                                                color: Theme.background
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: chooseArea
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                Quickshell.execDetached(["rice-set-dock-icon"]);
                                                            }
                                                        }
                                                    }

                                                    Rectangle {
                                                        implicitWidth: rstTxt.implicitWidth + 20
                                                        implicitHeight: 30
                                                        radius: 15
                                                        color: rstArea.pressed ? Theme.tileHigh : Theme.surface
                                                        border.width: 1
                                                        border.color: Theme.withAlpha(Theme.outline, 0.25)

                                                        Text {
                                                            id: rstTxt
                                                            anchors.centerIn: parent
                                                            text: Theme.t("dock.reset_icon", "Restaurar Padrão Arch")
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 10
                                                            font.weight: Font.Medium
                                                            color: Theme.textColor
                                                        }

                                                        MouseArea {
                                                            id: rstArea
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                Quickshell.execDetached(["rice-set-dock-icon", "--reset"]);
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // 4. Ações Globais: Aplicar a Todos e Restaurar Padrões
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 38
                                        radius: 10
                                        color: applyMouse.pressed ? Theme.withAlpha(Theme.primary, 0.8) : Theme.primary
                                        border.width: 1
                                        border.color: Theme.primary

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 8
                                            Text {
                                                text: Theme.icons.refresh
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 14
                                                color: Theme.background
                                            }
                                            Text {
                                                text: Theme.t("shell_custom.apply_all", "Aplicar Estilo a Todos")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: Theme.background
                                            }
                                        }

                                        MouseArea {
                                            id: applyMouse
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                ShellCustomization.applyToAll(shellCustomTab.targetComp);
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 38
                                        radius: 10
                                        color: resetMouse.pressed ? Theme.tileHigh : Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.3)

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 8
                                            Text {
                                                text: Theme.icons.backupRestore
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 14
                                                color: Theme.textColor
                                            }
                                            Text {
                                                text: Theme.t("shell_custom.reset", "Restaurar Padrão")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                color: Theme.textColor
                                            }
                                        }

                                        MouseArea {
                                            id: resetMouse
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                ShellCustomization.reset(shellCustomTab.targetComp);
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
            if (!win.open) {
                win.open = true;
            } else {
                win.refreshAll();
            }
        }
        function scrollInput(y: string): void {
            inputFlickable.contentY = Math.max(0, Math.min(inputFlickable.contentHeight - inputFlickable.height, parseFloat(y) || 0));
        }
        function refresh(): void {
            loadStorageProc.running = true;
            loadSoftwareUpdatesProc.running = true;
            loadSoftwareAppsProc.running = true;
            loadPresetsProc.running = true;
            loadBackupsProc.running = true;
        }
    }
}
