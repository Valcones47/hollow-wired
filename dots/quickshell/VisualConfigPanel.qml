import QtQuick
import QtQuick.Controls
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
    // Abre na primeira categoria da navegação (Cores & Wallust). Antes abria no
    // Fastfetch, que é a configuração mais nichada de todas.
    property int currentTab: 8

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
    property var makoProblems: []
    property int makoRadius: 8
    property int makoBorder: 2

    // Tela & Monitores
    property string monitorName: ""
    property string monitorModel: ""
    property string monitorRes: ""
    property int monitorHz: 60
    property real monitorScale: 1.0
    property bool vrrEnabled: false
    property int screenBrightness: 40
    property var availableHzList: []

    // Lista completa de monitores (saída do `hyprctl monitors -j`) e qual deles
    // está sendo configurado. Antes o painel só enxergava o primeiro monitor:
    // quem usa duas telas não conseguia configurar a segunda.
    property var monitorsData: []
    property string selectedMonitor: ""
    property bool hasBacklight: false

    // ---------- helpers de monitor ----------
    function monitorObj() {
        for (let i = 0; i < monitorsData.length; i++) {
            if (monitorsData[i].name === selectedMonitor) return monitorsData[i];
        }
        return monitorsData.length > 0 ? monitorsData[0] : null;
    }

    function currentResolution() {
        const m = monitorObj();
        return m ? (m.width + "x" + m.height) : "";
    }
    function currentRefresh() {
        const m = monitorObj();
        return m ? (m.refreshRate || 0) : 0;
    }
    function currentScale() {
        const m = monitorObj();
        return m ? (m.scale || 1) : 1;
    }
    function currentTransform() {
        const m = monitorObj();
        return m ? (m.transform || 0) : 0;
    }

    // Modos vêm do Hyprland como "1920x1080@144.03Hz". Agrupa por resolução,
    // guardando a maior taxa de cada uma (é a que o clique na resolução aplica).
    function parsedModes(name) {
        let target = null;
        for (let i = 0; i < monitorsData.length; i++) {
            if (monitorsData[i].name === name) { target = monitorsData[i]; break; }
        }
        if (!target) target = monitorsData.length > 0 ? monitorsData[0] : null;
        if (!target) return [];
        const modes = target.availableModes || [];
        const out = [];
        for (let i = 0; i < modes.length; i++) {
            const m = ("" + modes[i]).match(/^(\d+)x(\d+)@([0-9.]+)Hz$/);
            if (!m) continue;
            out.push({ res: m[1] + "x" + m[2], pixels: parseInt(m[1]) * parseInt(m[2]), hz: parseFloat(m[3]), raw: m[3] });
        }
        // Alguns drivers não listam o modo ativo; garante que ele esteja lá.
        if (target.width && target.height && target.refreshRate) {
            const activeRes = target.width + "x" + target.height;
            let found = false;
            for (let i = 0; i < out.length; i++) {
                if (out[i].res === activeRes && Math.abs(out[i].hz - target.refreshRate) < 1) { found = true; break; }
            }
            if (!found)
                out.push({ res: activeRes, pixels: target.width * target.height, hz: target.refreshRate, raw: (Math.round(target.refreshRate * 100) / 100).toFixed(2) });
        }
        return out;
    }

    function resolutionsFor(name) {
        const modes = parsedModes(name);
        const byRes = {};
        for (let i = 0; i < modes.length; i++) {
            const e = modes[i];
            if (!byRes[e.res] || byRes[e.res].hz < e.hz) byRes[e.res] = e;
        }
        const list = Object.keys(byRes).map(r => byRes[r]);
        list.sort((a, b) => b.pixels - a.pixels || b.hz - a.hz);
        const native = list.length > 0 ? list[0].res : "";
        return list.map(e => ({
            res: e.res,
            maxHz: Math.round(e.hz),
            maxHzRaw: e.raw,
            isNative: e.res === native
        }));
    }

    function ratesFor(name, res) {
        const modes = parsedModes(name);
        const seen = {};
        const list = [];
        for (let i = 0; i < modes.length; i++) {
            if (modes[i].res !== res) continue;
            const key = Math.round(modes[i].hz);
            if (seen[key]) continue;
            seen[key] = true;
            list.push(modes[i]);
        }
        list.sort((a, b) => b.hz - a.hz);
        const maxHz = list.length > 0 ? Math.round(list[0].hz) : 0;
        return list.map(e => ({
            hz: e.hz,
            raw: e.raw,
            label: Math.round(e.hz) === maxHz
                ? Theme.t("monitor.hz_max", "Mais fluido")
                : (Math.round(e.hz) <= 60 ? Theme.t("monitor.hz_saver", "Economiza bateria") : Theme.t("monitor.hz_mid", "Intermediário"))
        }));
    }

    // ---------- aplicar (com reversão automática) ----------
    // Trocar resolução, taxa ou rotação pode resultar em tela ilegível (ou preta)
    // num monitor que não aguenta o modo. Seguindo o que o Windows faz, a nova
    // configuração é aplicada e precisa ser confirmada em 15s — senão volta
    // sozinha para a anterior.
    property string revertMonitor: ""
    property string revertMode: ""
    property real revertScale: 1
    property int revertTransform: 0
    property int revertSeconds: 0

    function snapshotForRevert() {
        const m = monitorObj();
        if (!m) return;
        win.revertMonitor = m.name;
        win.revertMode = m.width + "x" + m.height + "@" + (Math.round((m.refreshRate || 60) * 100) / 100).toFixed(2);
        win.revertScale = m.scale || 1;
        win.revertTransform = m.transform || 0;
    }

    function startRevertCountdown() {
        win.revertSeconds = 15;
        revertTimer.restart();
    }

    function applyMonitorMode(res, rateRaw) {
        const m = monitorObj();
        if (!m || !res) return;
        snapshotForRevert();
        Quickshell.execDetached(["rice-hypr-prefs", "monitor", m.name, res + "@" + rateRaw,
                                 String(m.scale || 1), String(m.transform || 0)]);
        monitorReloadTimer.restart();
        startRevertCountdown();
    }

    function applyMonitorScale(val) {
        const m = monitorObj();
        if (!m) return;
        snapshotForRevert();
        const mode = m.width + "x" + m.height + "@" + (Math.round((m.refreshRate || 60) * 100) / 100).toFixed(2);
        Quickshell.execDetached(["rice-hypr-prefs", "monitor", m.name, mode, String(val), String(m.transform || 0)]);
        // A escala global antiga continua sendo gravada pra compatibilidade.
        Quickshell.execDetached(["rice-hypr-prefs", "set", "monitor_scale", String(val)]);
        monitorReloadTimer.restart();
        startRevertCountdown();
    }

    function applyMonitorTransform(val) {
        const m = monitorObj();
        if (!m) return;
        snapshotForRevert();
        const mode = m.width + "x" + m.height + "@" + (Math.round((m.refreshRate || 60) * 100) / 100).toFixed(2);
        Quickshell.execDetached(["rice-hypr-prefs", "monitor", m.name, mode, String(m.scale || 1), String(val)]);
        monitorReloadTimer.restart();
        startRevertCountdown();
    }

    function keepMonitorConfig() {
        revertTimer.stop();
        win.revertSeconds = 0;
        win.showToast(Theme.t("monitor.kept", "Configuração de tela mantida"));
    }

    function revertMonitorConfig() {
        revertTimer.stop();
        win.revertSeconds = 0;
        if (win.revertMonitor === "") return;
        Quickshell.execDetached(["rice-hypr-prefs", "monitor", win.revertMonitor, win.revertMode,
                                 String(win.revertScale), String(win.revertTransform)]);
        monitorReloadTimer.restart();
        win.showToast(Theme.t("monitor.reverted", "Configuração anterior restaurada"));
    }

    Timer {
        id: revertTimer
        interval: 1000
        repeat: true
        onTriggered: {
            win.revertSeconds--;
            if (win.revertSeconds <= 0) win.revertMonitorConfig();
        }
    }

    Timer {
        id: monitorReloadTimer
        interval: 700
        onTriggered: loadMonitorsProc.running = true
    }

    // Áudio
    property var audioData: ({ sinks: [], sources: [], sink_volume: 100, source_volume: 80, sink_muted: false, source_muted: false })

    // Teclado & Mouse
    property string kbLayout: "br"
    property string kbVariant: ""
    property int repeatDelay: 600
    property int repeatRate: 25
    property bool hasTouchpad: false
    property bool touchpadTap: true
    property bool touchpadNatural: false
    property bool touchpadDwt: false
    property real mouseSensitivity: 0.0
    property string mouseAccel: "flat"
    property bool numlock: true
    property string discordClient: "discord"
    property bool discordRunning: false
    property string discordMuteBind: "CTRL + SHIFT + M"
    property string discordDeafenBind: "Num_Lock"

    // Energia & Bateria
    // Tempos de ociosidade (minutos; 0 = nunca), lidos e gravados pelo rice-idle.
    property var idleValues: ({ dim: 0, screen_off: 0, lock: 0, suspend: 0 })
    property var powerData: ({ has_battery: true, percent: 100, status: "AC Conectado", health: 100, cycles: 0, profile: "performance" })

    // Autostart
    property var autostartEntries: []
    property var availableApps: []
    // A lista de "adicionar à inicialização" despejava os 160+ aplicativos
    // instalados de uma vez, deixando a página quilométrica. Agora ela é
    // filtrada por busca e limitada ao que cabe na tela.
    property string bootAppQuery: ""

    // ---------- Atalhos de aplicativos (aba Guia de Atalhos) ----------
    property var appBinds: []
    property string bindAppQuery: ""
    property string bindAppCommand: ""
    property string bindAppName: ""
    property string bindCombo: ""
    property string bindConflict: ""
    property bool bindCapturing: false
    property bool bindsSubPage: false
    // Qual programa está esperando uma tecla. Com isso a gravação já salva
    // sozinha ao capturar, em vez de exigir um terceiro clique.
    property string bindRecordingFor: ""
    property string bindRecordingName: ""
    // Atalhos que o rice define e que podem ser trocados (rice-app-binds system-list).
    property var systemBinds: []
    property string sysRecordingFor: ""

    // O guia mostra "Super + Q"; o script devolve "SUPER + Q". A comparação é
    // pelo texto normalizado, senão nada casaria.
    function normCombo(text) {
        return String(text).split("+").map(p => p.trim().toUpperCase()).filter(p => p !== "").join(" + ");
    }

    function systemBindInfo(key) {
        const want = win.normCombo(key);
        const list = win.systemBinds || [];
        for (let i = 0; i < list.length; i++) {
            if (win.normCombo(list[i].combo) === want) return list[i];
        }
        return null;
    }

    function startSysBindCapture(oldCombo, label) {
        win.sysRecordingFor = oldCombo;
        win.bindRecordingFor = "";
        win.bindRecordingName = label;
        win.bindConflict = "";
        win.bindCapturing = true;
        recordAppBindProc.running = true;
    }
    readonly property var bindAppsFiltered: {
        const q = win.bindAppQuery.trim().toLowerCase();
        const all = win.availableApps || [];
        if (q === "") return [];
        const out = [];
        for (let i = 0; i < all.length; i++) {
            const a = all[i];
            if (((a.name || "") + " " + (a.exec || "")).toLowerCase().indexOf(q) !== -1) out.push(a);
            if (out.length >= 12) break;
        }
        return out;
    }
    readonly property var bootAppsFiltered: {
        const q = win.bootAppQuery.trim().toLowerCase();
        const all = win.availableApps || [];
        if (q === "") return all.slice(0, 18);
        const out = [];
        for (let i = 0; i < all.length; i++) {
            const a = all[i];
            const hay = ((a.name || "") + " " + (a.exec || "")).toLowerCase();
            if (hay.indexOf(q) !== -1) out.push(a);
            if (out.length >= 40) break;
        }
        return out;
    }

    // Cores & Wallust
    property var wallustColors: ({})

    // Efeitos / Hyprland
    property bool nightlightActive: false
    property int nightlightTemp: 4500
    property string nightlightSchedule: "off"
    property string nightlightStart: "19:00"
    property string nightlightEnd: "07:00"
    property string nightlightSunrise: ""
    property string nightlightSunset: ""
    property bool dimInactive: false
    property real dimStrength: 0.2
    property int rounding: 8
    property int gapsIn: 6
    property string animPreset: "smooth"
    property string wallTransition: "wipe"
    property int wallTransitionMs: 900
    property var previewStatus: ({})

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
    property var softwareUpdatesData: ({ count: 0, sys_count: 0, repo_count: 0, aur_count: 0, flatpak_count: 0, packages: [], rice_updates: 0, store: "", checked_at: "" })

    // Atualizador do rice (dotfiles do hollow-wired), consultado direto no
    // rice-update pra ter versão instalada, data e a lista de novidades.
    property var riceInfo: ({ status: "", count: 0, commits: [] })
    readonly property bool riceHasUpdate: (riceInfo.count || 0) > 0
    readonly property bool riceCheckFailed: riceInfo.status === "fetch_failed" || riceInfo.status === "error"
    property string softwareCatFilter: "all"
    property string softwareSearchQuery: ""

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
    // Quantas previews em alta resolução já existem. Alimenta os rótulos dos
    // botões de gerar/fotografar.
    Process {
        id: previewStatusProc
        command: ["rice-wallpaper-previews", "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.previewStatus = JSON.parse(text); } catch (e) {}
            }
        }
    }

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
        id: loadSysBindsProc
        command: ["rice-app-binds", "system-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.systemBinds = (JSON.parse(text).binds) || []; } catch (e) {}
            }
        }
    }

    Process {
        id: saveSysBindProc
        command: ["rice-app-binds", "system-list"]
        onExited: (code, status) => loadSysBindsProc.running = true
    }

    Process {
        id: loadAppBindsProc
        command: ["rice-app-binds", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.appBinds = (JSON.parse(text).binds) || []; } catch (e) {}
            }
        }
    }

    Process {
        id: saveAppBindProc
        command: ["rice-app-binds", "list"]
        onExited: (code, status) => loadAppBindsProc.running = true
    }

    Process {
        // O gravador lê o /dev/input e devolve a combinação já no formato do
        // Hyprland, avisando quando ela colide com um atalho existente.
        id: recordAppBindProc
        command: ["rice-app-binds", "record", "--timeout", "12"]
        stdout: StdioCollector {
            onStreamFinished: {
                win.bindCapturing = false;
                try {
                    const d = JSON.parse(text);
                    if (d.status === "ok") {
                        win.bindCombo = d.key || "";
                        win.bindConflict = d.conflict || "";
                        if (win.sysRecordingFor !== "" && win.bindCombo !== "") {
                            saveSysBindProc.command = ["rice-app-binds", "override",
                                                       win.sysRecordingFor, win.bindCombo];
                            saveSysBindProc.running = true;
                            win.showToast(win.bindRecordingName + ": " + win.bindCombo);
                            win.sysRecordingFor = "";
                        } else if (win.bindRecordingFor !== "" && win.bindCombo !== "") {
                            saveAppBindProc.command = ["rice-app-binds", "add", win.bindCombo,
                                                       win.bindRecordingFor, "--name", win.bindRecordingName];
                            saveAppBindProc.running = true;
                            win.showToast(win.bindRecordingName + ": " + win.bindCombo);
                            win.bindRecordingFor = "";
                        }
                    } else if (d.status === "timeout") {
                        win.bindRecordingFor = "";
                        win.sysRecordingFor = "";
                        win.showToast(Theme.t("toast.bind_timeout", "Nenhuma tecla detectada"));
                    } else if (d.status === "cancelled") {
                        win.bindRecordingFor = "";
                        win.sysRecordingFor = "";
                        win.showToast(Theme.t("toast.bind_cancelled", "Gravação cancelada"));
                    } else {
                        win.showToast(Theme.t("toast.bind_error", "Não consegui ler o teclado"));
                    }
                } catch (e) { win.bindCapturing = false; }
            }
        }
    }

    Process {
        id: makoResetProc
        command: ["rice-mako-apply", "reset"]
        onExited: (code, status) => loadMakoProc.running = true
    }

    Process {
        // Conserto guiado das notificações. Rodar `execDetached` e recarregar na
        // mesma hora criava uma corrida: o painel relia o arquivo antes do
        // script terminar de escrever, e a tela continuava mostrando o valor
        // velho — foi o que fez o ajuste parecer que "nunca salva".
        id: makoFixProc
        command: ["rice-mako-apply", "doctor", "--fix"]
        onExited: (code, status) => loadMakoProc.running = true
    }

    Process {
        id: loadMakoProc
        command: ["rice-mako-apply", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    win.makoAnchor = d.anchor || "top-right";
                    // Nada de `|| 5` aqui: timeout 0 é justamente o valor que
                    // prende a notificação na tela, e mascará-lo como 5 fazia
                    // o painel mentir e o ajuste parecer "não salvar".
                    win.makoTimeout = (d.timeout !== undefined && d.timeout !== null) ? d.timeout : 5;
                    win.makoRadius = (d.radius !== undefined) ? d.radius : 14;
                    win.makoBorder = d.border_size !== undefined ? d.border_size : 1;
                    win.makoProblems = d.problems || [];
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
                    if (d.schedule !== undefined) win.nightlightSchedule = d.schedule;
                    if (d.start !== undefined) win.nightlightStart = d.start;
                    if (d.end !== undefined) win.nightlightEnd = d.end;
                    win.nightlightSunrise = d.sunrise || "";
                    win.nightlightSunset = d.sunset || "";
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
                    if (d.wallpaper_transition !== undefined) win.wallTransition = d.wallpaper_transition;
                    if (d.wallpaper_transition_ms !== undefined) win.wallTransitionMs = d.wallpaper_transition_ms;
                    if (d.monitor_hz !== undefined) win.monitorHz = parseInt(d.monitor_hz) || 0;
                    if (d.monitor_scale !== undefined) win.monitorScale = parseFloat(d.monitor_scale) || 1.0;
                    if (d.vrr !== undefined) win.vrrEnabled = (d.vrr === 1 || d.vrr === true);
                    if (d.kb_layout !== undefined) win.kbLayout = d.kb_layout;
                    if (d.kb_variant !== undefined) win.kbVariant = d.kb_variant || "";
                    if (d.repeat_delay !== undefined) win.repeatDelay = parseInt(d.repeat_delay) || 600;
                    if (d.repeat_rate !== undefined) win.repeatRate = parseInt(d.repeat_rate) || 25;
                    if (d.touchpad_tap !== undefined) win.touchpadTap = !!d.touchpad_tap;
                    if (d.touchpad_natural_scroll !== undefined) win.touchpadNatural = !!d.touchpad_natural_scroll;
                    if (d.touchpad_dwt !== undefined) win.touchpadDwt = !!d.touchpad_dwt;
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
                        win.monitorsData = arr;
                        // Mantém a tela escolhida entre recarregamentos; na
                        // primeira vez seleciona a que está em foco.
                        let stillThere = false;
                        for (let i = 0; i < arr.length; i++) {
                            if (arr[i].name === win.selectedMonitor) { stillThere = true; break; }
                        }
                        if (!stillThere) {
                            let focused = arr[0].name;
                            for (let i = 0; i < arr.length; i++) {
                                if (arr[i].focused) { focused = arr[i].name; break; }
                            }
                            win.selectedMonitor = focused;
                        }
                        win.monitorName = arr[0].name || "";
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

    // Desktop sem backlight (monitor externo) não tem controle de brilho por
    // software — a seção inteira fica oculta em vez de mostrar um slider morto.
    // Só mostra a seção de touchpad em máquinas que têm um.
    Process {
        id: loadIdleProc
        command: ["rice-idle", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.idleValues = JSON.parse(text); } catch (e) {}
            }
        }
    }

    Process {
        id: checkTouchpadProc
        command: ["sh", "-c", "hyprctl devices -j 2>/dev/null | grep -ci touchpad || true"]
        stdout: StdioCollector {
            onStreamFinished: win.hasTouchpad = (parseInt(text.trim()) || 0) > 0
        }
    }

    Process {
        id: checkBacklightProc
        command: ["sh", "-c", "ls /sys/class/backlight/ 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: win.hasBacklight = text.trim().length > 0
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
        id: loadRiceUpdateProc
        command: ["rice-update", "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.riceInfo = JSON.parse(text); } catch (e) {}
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
                        win.showToast(Theme.t("toast.timeout_nokey", "Tempo esgotado (nenhuma tecla detectada)"));
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
        checkBacklightProc.running = true;
        checkTouchpadProc.running = true;
        loadIdleProc.running = true;
        loadBrightnessProc.running = true;
        loadWallustColorsProc.running = true;
        loadColorOverridesProc.running = true;
        loadAppBindsProc.running = true;
        loadSysBindsProc.running = true;
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
        loadRiceUpdateProc.running = true;
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
        // Tamanho proporcional à tela em vez de 1040x660 fixo: em 1080p o painel
        // ficava apertado demais (listas de 3 itens por vez, textos cortados) e
        // em telas maiores desperdiçava espaço. Mantém um piso pra não quebrar
        // o layout em telas pequenas.
        width: Math.max(1040, Math.min(1560, win.width * 0.88))
        height: Math.max(640, Math.min(950, win.height * 0.90))
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

        // ---------- confirmação de mudança de tela (estilo Windows) ----------
        // Resolução, taxa ou rotação incompatíveis podem deixar a tela ilegível.
        // A configuração nova volta sozinha em 15s se ninguém confirmar.
        Rectangle {
            id: revertBar
            z: 100
            visible: win.revertSeconds > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 22
            implicitWidth: revertRow.implicitWidth + 32
            implicitHeight: 62
            radius: 16
            color: Theme.mix(Theme.background, "#000000", 0.25)
            border.width: 1.5
            border.color: Theme.primary

            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }

            RowLayout {
                id: revertRow
                anchors.centerIn: parent
                spacing: 16

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: Theme.t("monitor.confirm_title", "Manter esta configuração de tela?")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Theme.textColor
                    }
                    Text {
                        text: Theme.t("monitor.confirm_sub", "Voltando à configuração anterior em ") + win.revertSeconds + "s"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.subtext
                    }
                }

                Rectangle {
                    implicitHeight: 30
                    implicitWidth: keepLabel.implicitWidth + 24
                    radius: 15
                    color: keepArea.containsMouse ? Theme.primary : Theme.withAlpha(Theme.primary, 0.85)
                    Text {
                        id: keepLabel
                        anchors.centerIn: parent
                        text: Theme.t("monitor.confirm_keep", "Manter")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Theme.background
                    }
                    MouseArea {
                        id: keepArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.keepMonitorConfig()
                    }
                }

                Rectangle {
                    implicitHeight: 30
                    implicitWidth: undoLabel.implicitWidth + 24
                    radius: 15
                    color: undoArea.containsMouse ? Theme.tileHigh : Theme.tile
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outline, 0.25)
                    Text {
                        id: undoLabel
                        anchors.centerIn: parent
                        text: Theme.t("monitor.confirm_revert", "Reverter agora")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.textColor
                    }
                    MouseArea {
                        id: undoArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.revertMonitorConfig()
                    }
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ==================== LADO ESQUERDO: BARRA LATERAL ====================
            Rectangle {
                Layout.preferredWidth: 292
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
                                    // Pula os cabeçalhos de grupo e abre a primeira
                                    // categoria que realmente casou com a busca.
                                    for (let i = 0; i < navRepeater.count; i++) {
                                        const it = navRepeater.itemAt(i);
                                        if (it && it.isHeader === false && it.targetTab >= 0) {
                                            win.currentTab = it.targetTab;
                                            break;
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
                        id: navFlick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: navCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        // Sem indicador, não dava pra perceber que a lista de
                        // categorias continuava abaixo da área visível.
                        ScrollBar.vertical: ScrollBar {
                            id: navScroll
                            policy: navFlick.contentHeight > navFlick.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                            width: 6
                            contentItem: Rectangle {
                                implicitWidth: 4
                                radius: 2
                                color: navScroll.pressed ? Theme.primary : Theme.withAlpha(Theme.outline, 0.5)
                            }
                        }

                        ColumnLayout {
                            id: navCol
                            width: parent.width
                            spacing: 4

                            // Categorias agrupadas por assunto. Antes eram 19 itens
                            // numa lista corrida, sem separação: achar "Rede" ou
                            // "Armazenamento" exigia ler a lista inteira.
                            readonly property var navItems: [
                                { group: "look", tabIndex: 8, name: Theme.t("settings.cat_wallust", "Cores & Wallust"), icon: Theme.icons.palette, desc: Theme.t("settings.desc_wallust", "Paleta Dinâmica"), keywords: "cores color colors wallust tema theme wallpaper papel de parede paleta palette dinamica accent visual fundo" },
                                { group: "look", tabIndex: 9, name: Theme.t("settings.cat_effects", "Efeitos & Janelas"), icon: Theme.icons.laptop, desc: Theme.t("settings.desc_effects", "Bordas & Animações"), keywords: "efeitos effects janelas windows blur desfoque bordas borders sombras shadows sddm animacoes animations transparência luz noturna" },
                                { group: "look", tabIndex: 18, name: Theme.t("settings.cat_shell_custom", "Customização do Shell"), icon: Theme.icons.tune, desc: Theme.t("settings.desc_shell_custom", "Hub, Sidebar & Dock"), keywords: "shell quickshell customizacao dock topbar barra sidebar hub aparencia widgets glass solid glow borderless escala" },
                                { group: "look", tabIndex: 2, name: Theme.t("settings.cat_mako", "Notificações"), icon: Theme.icons.bell, desc: Theme.t("settings.desc_mako", "Posição & Estilo"), keywords: "mako notificacoes notifications som posicao borda alert toast banner avisos" },
                                { group: "look", tabIndex: 1, name: Theme.t("settings.cat_kitty", "Kitty Terminal"), icon: Theme.icons.console, desc: Theme.t("settings.desc_kitty", "Fonte & Opacidade"), keywords: "kitty terminal console fonte font opacidade padding cursor audio blur som transparencia" },
                                { group: "look", tabIndex: 0, name: Theme.t("settings.cat_fastfetch", "Fastfetch"), icon: Theme.icons.packages, desc: Theme.t("settings.desc_fastfetch", "Logo & Módulos"), keywords: "fastfetch neofetch logo distro terminal specs cpu ram hardware modelo" },

                                { group: "hardware", tabIndex: 3, name: Theme.t("settings.cat_monitors", "Tela & Monitores"), icon: Theme.icons.monitor, desc: Theme.t("settings.desc_monitors", "Resolução & Taxa"), keywords: "tela monitor monitores display resolucao resolution refresh rate hz taxa atualizacao escala zoom scale hidpi brilho brightness vrr freesync g-sync frequencia rotacao girar vertical" },
                                { group: "hardware", tabIndex: 4, name: Theme.t("settings.cat_audio", "Áudio & Som"), icon: Theme.icons.volHigh, desc: Theme.t("settings.desc_audio", "Saída & Microfone"), keywords: "audio som volume microfone mic fone speaker caixa sink source pipewire dispositivos" },
                                { group: "hardware", tabIndex: 5, name: Theme.t("settings.cat_input", "Teclado & Mouse"), icon: Theme.icons.cursor, desc: Theme.t("settings.desc_input", "Teclado & Sensibilidade"), keywords: "teclado mouse keyboard layout abnt2 sensibilidade aceleração accel numlock atalhos velocidade ponteiro" },
                                { group: "hardware", tabIndex: 6, name: Theme.t("settings.cat_power", "Energia & Bateria"), icon: Theme.icons.bat, desc: Theme.t("settings.desc_power", "Perfis & Saúde"), keywords: "energia bateria power perfis profiles economia desempenho saude health suspender sleep carga" },
                                { group: "hardware", tabIndex: 10, name: Theme.t("settings.cat_bluetooth", "Bluetooth"), icon: Theme.icons.bt, desc: Theme.t("settings.desc_bluetooth", "Controles & Fones"), keywords: "bluetooth bt fones earbuds controle joystick pareamento connect conectar dispositivos" },
                                { group: "hardware", tabIndex: 11, name: Theme.t("settings.cat_network", "Rede & Wi-Fi"), icon: Theme.icons.wifi4, desc: Theme.t("settings.desc_network", "Conexões & Latência"), keywords: "rede network wifi wi-fi conexao ethernet cabo ip dns ping latencia internet speed velocidade" },
                                { group: "hardware", tabIndex: 13, name: Theme.t("settings.cat_gaming", "Jogos & GPU"), icon: Theme.icons.gamepad, desc: Theme.t("settings.desc_gaming", "Placa de Vídeo & Steam"), keywords: "jogos games gaming gpu placa de video nvidia prime prime-run dgpu igpu intel amd gamemode steam mangohud fps desempenho" },

                                { group: "system", tabIndex: 7, name: Theme.t("settings.cat_boot", "Inicialização"), icon: Theme.icons.speed, desc: Theme.t("settings.desc_boot", "Apps ao Iniciar"), keywords: "boot inicializacao startup autostart apps servicos sddm limine login inicio ligar" },
                                { group: "system", tabIndex: 12, name: Theme.t("settings.cat_defaults", "Aplicativos Padrão"), icon: Theme.icons.dashboard, desc: Theme.t("settings.desc_defaults", "Navegador, Pastas & Vídeo"), keywords: "aplicativos padrao default apps navegador browser chrome firefox zen brave pasta dolphin nautilus video vlc player musica mpv email editor code text" },
                                { group: "system", tabIndex: 17, name: Theme.t("settings.cat_store", "Programas & Atualizações"), icon: Theme.icons.packages, desc: Theme.t("settings.desc_store", "Atualizar & Instalar"), keywords: "loja store updates atualizacoes pacotes packages arch pacman aur yay flatpak programas instalar adicionar remover" },
                                { group: "system", tabIndex: 14, name: Theme.t("settings.cat_storage", "Armazenamento"), icon: Theme.icons.disk, desc: Theme.t("settings.desc_storage", "Limpeza de Disco"), keywords: "armazenamento storage disco disk hd ssd espaco limpar limpeza cache lixeira logs btrfs free space" },
                                { group: "system", tabIndex: 16, name: Theme.t("settings.cat_system", "Sistema & Reparo"), icon: Theme.icons.health, desc: Theme.t("settings.desc_system", "Snapshots & Auto-Reparo"), keywords: "sistema system reparo repair consertar snapshot restauracao backup btrfs auto-reparo diagnostico info logs status" },

                                { group: "help", tabIndex: 15, name: Theme.t("settings.cat_shortcuts", "Guia de Atalhos"), icon: Theme.icons.magnify, desc: Theme.t("settings.desc_shortcuts", "Teclas do Rice"), keywords: "atalhos shortcuts teclas binds keybinds cheatsheet super mod custom user-binds ajuda boas-vindas" }
                            ]

                            readonly property var navGroups: [
                                { id: "look", name: Theme.t("settings.group_look", "Aparência") },
                                { id: "hardware", name: Theme.t("settings.group_hardware", "Hardware") },
                                { id: "system", name: Theme.t("settings.group_system", "Sistema") },
                                { id: "help", name: Theme.t("settings.group_help", "Ajuda") }
                            ]

                            // Lista final: cabeçalho de grupo + itens do grupo.
                            // Durante a busca, grupos sem resultado somem.
                            readonly property var navModel: {
                                const q = catSearchInput.query;
                                const matches = !q ? navItems : navItems.filter(item => {
                                    const hay = ((item.name || "") + " " + (item.desc || "") + " " + (item.keywords || "")).toLowerCase();
                                    return hay.includes(q);
                                });
                                const out = [];
                                for (let g = 0; g < navGroups.length; g++) {
                                    const inGroup = matches.filter(i => i.group === navGroups[g].id);
                                    if (inGroup.length === 0) continue;
                                    out.push({ isHeader: true, name: navGroups[g].name, tabIndex: -1 });
                                    for (let i = 0; i < inGroup.length; i++) out.push(inGroup[i]);
                                }
                                return out;
                            }

                            Repeater {
                                id: navRepeater
                                model: navCol.navModel
                                delegate: Rectangle {
                                    id: navDelegate
                                    required property var modelData
                                    required property int index
                                    readonly property int targetTab: navDelegate.modelData.tabIndex
                                    readonly property bool isHeader: navDelegate.modelData.isHeader === true

                                    Layout.fillWidth: true
                                    Layout.topMargin: isHeader && index > 0 ? 8 : 0
                                    implicitHeight: isHeader ? 22 : 44
                                    radius: 10
                                    color: navDelegate.isHeader
                                        ? "transparent"
                                        : (win.currentTab === navDelegate.targetTab
                                            ? Theme.withAlpha(Theme.primary, 0.22)
                                            : (navItemArea.containsMouse ? Theme.tileHigh : "transparent"))
                                    border.width: !navDelegate.isHeader && win.currentTab === navDelegate.targetTab ? 1 : 0
                                    border.color: Theme.primary

                                    // Cabeçalho do grupo
                                    Text {
                                        visible: navDelegate.isHeader
                                        anchors.left: parent.left
                                        anchors.leftMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: navDelegate.modelData.name
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.capitalization: Font.AllUppercase
                                        font.letterSpacing: 0.8
                                        color: Theme.withAlpha(Theme.subtext, 0.75)
                                    }

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Rectangle {
                                        width: 3
                                        height: 20
                                        radius: 1.5
                                        color: Theme.primary
                                        anchors.left: parent.left
                                        anchors.leftMargin: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !navDelegate.isHeader && win.currentTab === navDelegate.targetTab
                                    }

                                    RowLayout {
                                        visible: !navDelegate.isHeader
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
                                        visible: !navDelegate.isHeader
                                        enabled: !navDelegate.isHeader
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
                                    Theme.t("header.title_0", "Fastfetch & Terminal Fetch"),
                                    Theme.t("header.title_1", "Kitty Terminal & Tipografia"),
                                    Theme.t("header.title_2", "Mako Notificações"),
                                    Theme.t("header.title_3", "Monitores & Exibição"),
                                    Theme.t("header.title_4", "Áudio, Som & Microfone"),
                                    Theme.t("header.title_5", "Teclado, Mouse & Entradas"),
                                    Theme.t("header.title_6", "Energia & Bateria"),
                                    Theme.t("header.title_7", "Inicialização Automática (Boot)"),
                                    Theme.t("header.title_8", "Cores & Wallust Dinâmico"),
                                    Theme.t("header.title_9", "Efeitos Visuais, Bordas & SDDM"),
                                    Theme.t("header.title_10", "Bluetooth & Periféricos sem Fio"),
                                    Theme.t("header.title_11", "Rede, Conexões & Wi-Fi"),
                                    Theme.t("header.title_12", "Aplicativos Padrão do Sistema"),
                                    Theme.t("header.title_13", "Jogos & Gráficos NVIDIA"),
                                    Theme.t("header.title_14", "Armazenamento & Limpeza de Disco"),
                                    Theme.t("header.title_15", "Guia de Teclas & Atalhos"),
                                    Theme.t("header.title_16", "Sistema, Snapshots & Reparo"),
                                    Theme.t("header.title_17", "Programas & Atualizações"),
                                    Theme.t("header.title_18", "Customização do Shell")
                                ][win.currentTab] || Theme.t("settings.panel_title", "Configurações")
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: Theme.textColor
                            }

                            Text {
                                text: [
                                    Theme.t("header.sub_0", "Personalize o logo, dimensões e informações mostradas no terminal."),
                                    Theme.t("header.sub_1", "Ajuste opacidade, tamanho de texto, espaçamento interno e cursor."),
                                    Theme.t("header.sub_2", "Escolha a posição na tela, tempo de exibição e bordas das notificações."),
                                    Theme.t("header.sub_3", "Controle taxa de atualização (144Hz/60Hz), FreeSync/VRR e brilho."),
                                    Theme.t("header.sub_4", "Selecione saída de áudio, microfone, volumes e execute teste estéreo."),
                                    Theme.t("header.sub_5", "Seletor de layout ABNT2/US, sensibilidade do mouse e perfil de aceleração."),
                                    Theme.t("header.sub_6", "Monitore saúde da bateria, ciclos de carga e escolha perfis de energia."),
                                    Theme.t("header.sub_7", "Gerencie quais programas iniciam automaticamente ao ligar o computador."),
                                    Theme.t("header.sub_8", "Veja a paleta do wallpaper, troque qualquer cor na roda de cores e trave a paleta se quiser."),
                                    Theme.t("header.sub_9", "Luz noturna, transparência inativa, cantos arredondados, animações e login."),
                                    Theme.t("header.sub_10", "Gerencie controles de videogame, fones de ouvido e conexões Bluetooth."),
                                    Theme.t("header.sub_11", "Monitore a velocidade e latência da internet e conecte-se a novas redes Wi-Fi."),
                                    Theme.t("header.sub_12", "Escolha quais programas abrem páginas da web, pastas, códigos, fotos e vídeos."),
                                    Theme.t("header.sub_13", "Monitore a GPU dedicada RTX 3050, GameMode e parâmetros da Steam."),
                                    Theme.t("header.sub_14", "Monitore o uso do SSD e recupere espaço em disco com limpezas seguras."),
                                    Theme.t("header.sub_15", "Consulte e busque todos os atalhos de teclado do Hyprland com 1 clique."),
                                    Theme.t("header.sub_16", "Crie pontos de restauração Btrfs e resolva problemas comuns com 1 clique."),
                                    Theme.t("header.sub_17", "Atualize o sistema e o hollow-wired, e abra a loja de programas para instalar o que quiser."),
                                    Theme.t("header.sub_18", "Ajuste estilo, escala, blur e cores de destaque dos componentes do shell.")
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
                    // Largura máxima de leitura: com o painel maior, deixar os
                    // controles esticarem por 1200px+ deixava sliders enormes e
                    // textos numa linha larguíssima, difícil de acompanhar.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.maximumWidth: 1120
                        Layout.alignment: Qt.AlignHCenter

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
                                        title: Theme.t("ff.section_logo", "Logo & Imagens do Fastfetch")
                                        subtitle: Theme.t("ff.section_logo_sub", "Imagens detectadas em ~/Imagens/FastFetch")
                                    }
                                    Item { Layout.fillWidth: true }
                                    ActionBtn {
                                        icon: Theme.icons.laptop
                                        text: Theme.t("ff.open_folder", "Abrir Pasta")
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
                                                text: Theme.t("ff.default_arch", "Arch Padrão")
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
                                        title: Theme.t("ff.logo_width", "Largura do Logo (Colunas)")
                                        minVal: 15; maxVal: 50; value: win.ffWidth; unit: " col"
                                        onChanged: newVal => {
                                            win.ffWidth = Math.round(newVal);
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-fastfetch-apply", "set-size", String(win.ffWidth), String(win.ffHeight)]);
                                            });
                                        }
                                    }
                                    CfgSlider {
                                        title: Theme.t("ff.logo_height", "Altura do Logo (Linhas)")
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
                                    title: Theme.t("ff.section_modules", "Módulos de Sistema Exibidos")
                                    subtitle: Theme.t("ff.section_modules_sub", "Clique para ativar ou ocultar cada informação no Fastfetch")
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Repeater {
                                        model: [
                                            { key: "os", label: Theme.t("ff.mod_os", "Sistema (OS)"), icon: Theme.icons.arch },
                                            { key: "host", label: Theme.t("ff.mod_host", "Máquina"), icon: Theme.icons.laptop },
                                            { key: "kernel", label: Theme.t("ff.mod_kernel", "Kernel"), icon: Theme.icons.chip },
                                            { key: "uptime", label: Theme.t("ff.mod_uptime", "Tempo de Atividade"), icon: Theme.icons.clock },
                                            { key: "packages", label: Theme.t("ff.mod_packages", "Pacotes"), icon: Theme.icons.packages },
                                            { key: "shell", label: Theme.t("ff.mod_shell", "Shell"), icon: Theme.icons.console },
                                            { key: "display", label: Theme.t("ff.mod_display", "Tela & Resolução"), icon: Theme.icons.monitor },
                                            { key: "de", label: Theme.t("ff.mod_de", "Ambiente (DE)"), icon: Theme.icons.dashboard },
                                            { key: "wm", label: Theme.t("ff.mod_wm", "Compositor (WM)"), icon: Theme.icons.workspaces },
                                            { key: "theme", label: Theme.t("ff.mod_theme", "Tema & Cores"), icon: Theme.icons.palette },
                                            { key: "icons", label: Theme.t("ff.mod_icons", "Ícones"), icon: Theme.icons.tune },
                                            { key: "terminal", label: Theme.t("ff.mod_terminal", "Terminal"), icon: Theme.icons.console },
                                            { key: "cpu", label: Theme.t("ff.mod_cpu", "Processador (CPU)"), icon: Theme.icons.cpu },
                                            { key: "gpu", label: Theme.t("ff.mod_gpu", "Placa de Vídeo (GPU)"), icon: Theme.icons.gpu },
                                            { key: "memory", label: Theme.t("ff.mod_memory", "Memória RAM"), icon: Theme.icons.memory },
                                            { key: "swap", label: Theme.t("ff.mod_swap", "Swap / zRAM"), icon: Theme.icons.disk },
                                            { key: "disk", label: Theme.t("ff.mod_disk", "Armazenamento"), icon: Theme.icons.disk }
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
                                        text: Theme.t("ff.preview_btn", "Visualizar no Terminal (Kitty)")
                                        primary: true
                                        onClicked: Quickshell.execDetached(["rice-fastfetch-apply", "run"])
                                    }
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: Theme.t("ff.reset_btn", "Restaurar Padrões")
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
                                    title: Theme.t("kitty.section_appear", "Aparência & Tipografia")
                                    subtitle: Theme.t("kitty.section_appear_sub", "Ajuste em tempo real da opacidade e legibilidade do terminal Kitty")
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20
                                    CfgSlider {
                                        title: Theme.t("kitty.opacity", "Opacidade de Fundo")
                                        minVal: 0.3; maxVal: 1.0; value: win.kittyOpacity; decimals: 2
                                        onChanged: newVal => {
                                            win.kittyOpacity = newVal;
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-kitty-apply", "set", "opacity", String(win.kittyOpacity)]);
                                            });
                                        }
                                    }
                                    CfgSlider {
                                        title: Theme.t("kitty.font_size", "Tamanho da Fonte")
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
                                    title: Theme.t("kitty.padding", "Espaçamento Interno (Margem / Padding)")
                                    minVal: 0; maxVal: 32; value: win.kittyPadding; unit: " px"
                                    onChanged: newVal => {
                                        win.kittyPadding = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-kitty-apply", "set", "padding", String(win.kittyPadding)]);
                                        });
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("kitty.section_cursor", "Estilo do Cursor & Efeitos")
                                    subtitle: Theme.t("kitty.section_cursor_sub", "Formato do ponteiro e comportamento de áudio")
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    Repeater {
                                        model: [
                                            { id: "beam", name: Theme.t("kitty.cursor_beam", "Linha Vertical (Beam)"), icon: Theme.icons.cursor },
                                            { id: "block", name: Theme.t("kitty.cursor_block", "Bloco Sólido (Block)"), icon: Theme.icons.dashboard },
                                            { id: "underline", name: Theme.t("kitty.cursor_underline", "Sublinhado (Underline)"), icon: Theme.icons.timer }
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
                                    title: Theme.t("kitty.blur_title", "Desfoque de Fundo (Background Blur)")
                                    subtitle: Theme.t("kitty.blur_desc", "Ativa efeito de vidro fosco atrás do terminal (Hyprland)")
                                    checked: win.kittyBlur
                                    onToggled: nv => {
                                        win.kittyBlur = nv;
                                        Quickshell.execDetached(["rice-kitty-apply", "set", "blur", nv ? "1" : "0"]);
                                    }
                                }

                                CfgToggle {
                                    title: Theme.t("kitty.bell_title", "Sino Sonoro (Audio Bell)")
                                    subtitle: Theme.t("kitty.bell_desc", "Toca bipe do sistema ao atingir o limite ou cometer erro")
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
                                        text: Theme.t("kitty.open_btn", "Abrir Novo Terminal Kitty")
                                        primary: true
                                        onClicked: Quickshell.execDetached(["kitty"])
                                    }
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: Theme.t("kitty.reset_btn", "Restaurar Padrões")
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

                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: win.makoProblems.length > 0
                                    radius: 14
                                    color: Qt.rgba(1, 0.65, 0.2, 0.10)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 0.65, 0.2, 0.35)
                                    implicitHeight: makoWarnRow.implicitHeight + 28

                                    RowLayout {
                                        id: makoWarnRow
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 14

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Text {
                                                text: Theme.t("mako.problem_title", "As notificações estão com problema")
                                                color: "#ffb347"
                                                font.pixelSize: 14
                                                font.bold: true
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                                color: Theme.subtext
                                                font.pixelSize: 12
                                                text: {
                                                    const p = win.makoProblems;
                                                    let out = [];
                                                    if (p.indexOf("timeout_zero") !== -1 || p.indexOf("timeout_missing") !== -1
                                                        || p.indexOf("timeout_zero_low") !== -1 || p.indexOf("timeout_zero_critical") !== -1)
                                                        out.push(Theme.t("mako.problem_stuck", "os avisos não somem sozinhos da tela"));
                                                    if (p.indexOf("include_missing") !== -1)
                                                        out.push(Theme.t("mako.problem_colors", "o arquivo de cores sumiu e toda a configuração está sendo ignorada"));
                                                    if (p.indexOf("not_running") !== -1)
                                                        out.push(Theme.t("mako.problem_dead", "o serviço de notificações não está rodando"));
                                                    return out.join(" · ");
                                                }
                                            }
                                        }

                                        ActionBtn {
                                            icon: Theme.icons.refresh
                                            text: Theme.t("mako.problem_fix", "Consertar agora")
                                            primary: true
                                            onClicked: makoFixProc.running = true
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("mako.section_pos", "Posição na Tela")
                                    subtitle: Theme.t("mako.section_pos_sub", "Escolha onde os banners de notificação devem surgir")
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 3
                                    rowSpacing: 8
                                    columnSpacing: 8

                                    Repeater {
                                        model: [
                                            { id: "top-left", name: Theme.t("mako.pos_top_left", "Canto Superior Esquerdo") },
                                            { id: "top-center", name: Theme.t("mako.pos_top_center", "Superior Centro") },
                                            { id: "top-right", name: Theme.t("mako.pos_top_right", "Canto Superior Direito (Padrão)") },
                                            { id: "bottom-left", name: Theme.t("mako.pos_bottom_left", "Canto Inferior Esquerdo") },
                                            { id: "bottom-center", name: Theme.t("mako.pos_bottom_center", "Inferior Centro") },
                                            { id: "bottom-right", name: Theme.t("mako.pos_bottom_right", "Canto Inferior Direito") }
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
                                    title: Theme.t("mako.section_geom", "Comportamento & Geometria")
                                    subtitle: Theme.t("mako.section_geom_sub", "Tempo de exibição, bordas e arredondamento dos banners")
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20
                                    CfgSlider {
                                        title: Theme.t("mako.timeout", "Tempo em Tela (Timeout)")
                                        minVal: 2; maxVal: 30; value: win.makoTimeout; unit: " s"
                                        onChanged: newVal => {
                                            win.makoTimeout = Math.round(newVal);
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-mako-apply", "set", "timeout", String(win.makoTimeout)]);
                                            });
                                        }
                                    }
                                    CfgSlider {
                                        title: Theme.t("mako.radius", "Arredondamento dos Cantos")
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
                                    title: Theme.t("mako.border_size", "Espessura da Borda")
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
                                        text: Theme.t("mako.test_btn", "Enviar Notificação de Teste")
                                        primary: true
                                        onClicked: Quickshell.execDetached(["rice-mako-apply", "test"])
                                    }
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: Theme.t("mako.reset_btn", "Restaurar Padrões")
                                        onClicked: makoResetProc.running = true
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

                                // -------------------------------------------------- monitores
                                SectionHeader {
                                    title: Theme.t("monitor.list_title", "Monitores conectados")
                                    subtitle: win.monitorsData.length > 1
                                        ? Theme.t("monitor.list_sub_multi", "Escolha qual tela você quer configurar abaixo")
                                        : Theme.t("monitor.list_sub_one", "Informações de hardware da tela ativa")
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: Math.max(1, Math.min(win.monitorsData.length, 2))
                                    columnSpacing: 10
                                    rowSpacing: 10

                                    Repeater {
                                        model: win.monitorsData

                                        delegate: Rectangle {
                                            id: monCard
                                            required property var modelData
                                            readonly property bool isSelected: win.selectedMonitor === monCard.modelData.name

                                            Layout.fillWidth: true
                                            implicitHeight: 78
                                            radius: 12
                                            color: monCard.isSelected ? Theme.withAlpha(Theme.primary, 0.18) : Theme.tile
                                            border.width: monCard.isSelected ? 1.5 : 1
                                            border.color: monCard.isSelected ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                                            Behavior on color { ColorAnimation { duration: 140 } }

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
                                                        font.pixelSize: 20
                                                        color: Theme.primary
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2

                                                    RowLayout {
                                                        spacing: 8
                                                        Text {
                                                            text: monCard.modelData.name + " · " + monCard.modelData.width + "x" + monCard.modelData.height
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 13
                                                            font.weight: Font.Bold
                                                            color: Theme.textColor
                                                        }
                                                        Rectangle {
                                                            implicitHeight: 16
                                                            implicitWidth: hzBadge.implicitWidth + 12
                                                            radius: 8
                                                            color: Theme.withAlpha(Theme.primary, 0.25)
                                                            Text {
                                                                id: hzBadge
                                                                anchors.centerIn: parent
                                                                text: Math.round(monCard.modelData.refreshRate || 0) + " Hz"
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 9
                                                                font.weight: Font.Bold
                                                                color: Theme.primary
                                                            }
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: ((monCard.modelData.make || "") + " " + (monCard.modelData.model || "")).trim()
                                                            + "   ·   " + Theme.t("monitor.scale_label", "escala") + " " + monCard.modelData.scale
                                                            + (monCard.modelData.transform ? "   ·   " + (monCard.modelData.transform * 90) + "°" : "")
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: Theme.subtext
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: win.selectedMonitor = monCard.modelData.name
                                            }
                                        }
                                    }
                                }

                                // -------------------------------------------------- resolução
                                SectionHeader {
                                    title: Theme.t("monitor.res_title", "Resolução")
                                    subtitle: Theme.t("monitor.res_sub", "Tamanho da imagem em pixels. O padrão é sempre a resolução nativa da tela — reduzir deixa tudo maior, porém menos nítido.")
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 4
                                    columnSpacing: 8
                                    rowSpacing: 8

                                    Repeater {
                                        model: win.resolutionsFor(win.selectedMonitor)

                                        delegate: Rectangle {
                                            id: resCard
                                            required property var modelData
                                            readonly property bool isCurrent: win.currentResolution() === resCard.modelData.res

                                            Layout.fillWidth: true
                                            implicitHeight: 58
                                            radius: 10
                                            color: resCard.isCurrent ? Theme.withAlpha(Theme.primary, 0.25) : (resArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: resCard.isCurrent ? 1.5 : 1
                                            border.color: resCard.isCurrent ? Theme.primary : Theme.withAlpha(Theme.outline, 0.15)

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 2
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: resCard.modelData.res
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.Bold
                                                    color: resCard.isCurrent ? Theme.primary : Theme.textColor
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: resCard.modelData.isNative
                                                        ? Theme.t("monitor.res_native", "Nativa (recomendada)")
                                                        : resCard.modelData.maxHz + " Hz " + Theme.t("monitor.res_max", "máx")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    color: Theme.subtext
                                                }
                                            }

                                            MouseArea {
                                                id: resArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: win.applyMonitorMode(resCard.modelData.res, resCard.modelData.maxHzRaw)
                                            }
                                        }
                                    }
                                }

                                // ---------------------------------------------- taxa de atualização
                                SectionHeader {
                                    title: Theme.t("monitor.hz_title", "Taxa de atualização")
                                    subtitle: Theme.t("monitor.hz_sub", "Quantas imagens a tela desenha por segundo. Valores maiores deixam o movimento mais suave; menores economizam bateria.")
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 4
                                    columnSpacing: 8
                                    rowSpacing: 8

                                    Repeater {
                                        model: win.ratesFor(win.selectedMonitor, win.currentResolution())

                                        delegate: Rectangle {
                                            id: hzCard
                                            required property var modelData
                                            readonly property bool isCurrent: Math.abs(win.currentRefresh() - modelData.hz) < 1

                                            Layout.fillWidth: true
                                            implicitHeight: 58
                                            radius: 10
                                            color: hzCard.isCurrent ? Theme.withAlpha(Theme.primary, 0.25) : (hzArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: hzCard.isCurrent ? 1.5 : 1
                                            border.color: hzCard.isCurrent ? Theme.primary : Theme.withAlpha(Theme.outline, 0.15)

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 2
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: Math.round(modelData.hz) + " Hz"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.Bold
                                                    color: hzCard.isCurrent ? Theme.primary : Theme.textColor
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: modelData.label
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    color: Theme.subtext
                                                }
                                            }

                                            MouseArea {
                                                id: hzArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: win.applyMonitorMode(win.currentResolution(), modelData.raw)
                                            }
                                        }
                                    }
                                }

                                // -------------------------------------------------- escala
                                SectionHeader {
                                    title: Theme.t("monitor.scale_title", "Escala da interface (zoom)")
                                    subtitle: Theme.t("monitor.scale_sub", "Aumenta o tamanho de janelas, ícones e textos sem mudar a resolução. Útil em telas 2K/4K ou para quem tem dificuldade de leitura.")
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 5
                                    columnSpacing: 8
                                    rowSpacing: 8

                                    Repeater {
                                        model: [
                                            { label: "100%", val: 1.0, desc: Theme.t("monitor.scale_100", "Padrão (1080p)") },
                                            { label: "125%", val: 1.25, desc: Theme.t("monitor.scale_125", "Médio (2K)") },
                                            { label: "150%", val: 1.5, desc: Theme.t("monitor.scale_150", "Grande (HiDPI)") },
                                            { label: "175%", val: 1.75, desc: Theme.t("monitor.scale_175", "Ultra") },
                                            { label: "200%", val: 2.0, desc: Theme.t("monitor.scale_200", "4K / TV") }
                                        ]

                                        delegate: Rectangle {
                                            id: scaleCard
                                            required property var modelData
                                            readonly property bool isCurrent: Math.abs(win.currentScale() - scaleCard.modelData.val) < 0.05

                                            Layout.fillWidth: true
                                            implicitHeight: 58
                                            radius: 10
                                            color: scaleCard.isCurrent ? Theme.withAlpha(Theme.primary, 0.25) : (scaleArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: scaleCard.isCurrent ? 1.5 : 1
                                            border.color: scaleCard.isCurrent ? Theme.primary : Theme.withAlpha(Theme.outline, 0.15)

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 2
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: scaleCard.modelData.label
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.Bold
                                                    color: scaleCard.isCurrent ? Theme.primary : Theme.textColor
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: scaleCard.modelData.desc
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
                                                onClicked: win.applyMonitorScale(scaleCard.modelData.val)
                                            }
                                        }
                                    }
                                }

                                // -------------------------------------------------- rotação
                                SectionHeader {
                                    title: Theme.t("monitor.rotation_title", "Rotação da tela")
                                    subtitle: Theme.t("monitor.rotation_sub", "Gira a imagem — para monitores de pé (vertical) ou telas montadas de lado.")
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 4
                                    columnSpacing: 8
                                    rowSpacing: 8

                                    Repeater {
                                        model: [
                                            { label: Theme.t("monitor.rot_0", "Normal"), val: 0, icon: Theme.icons.monitor },
                                            { label: Theme.t("monitor.rot_1", "90° (vertical)"), val: 1, icon: Theme.icons.laptop },
                                            { label: Theme.t("monitor.rot_2", "180° (invertida)"), val: 2, icon: Theme.icons.monitor },
                                            { label: Theme.t("monitor.rot_3", "270° (vertical)"), val: 3, icon: Theme.icons.laptop }
                                        ]

                                        delegate: Rectangle {
                                            id: rotCard
                                            required property var modelData
                                            readonly property bool isCurrent: win.currentTransform() === rotCard.modelData.val

                                            Layout.fillWidth: true
                                            implicitHeight: 52
                                            radius: 10
                                            color: rotCard.isCurrent ? Theme.withAlpha(Theme.primary, 0.25) : (rotArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: rotCard.isCurrent ? 1.5 : 1
                                            border.color: rotCard.isCurrent ? Theme.primary : Theme.withAlpha(Theme.outline, 0.15)

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 8
                                                Text {
                                                    text: rotCard.modelData.icon
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 15
                                                    rotation: rotCard.modelData.val * 90
                                                    color: rotCard.isCurrent ? Theme.primary : Theme.subtext
                                                }
                                                Text {
                                                    text: rotCard.modelData.label
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    font.weight: rotCard.isCurrent ? Font.Bold : Font.Normal
                                                    color: rotCard.isCurrent ? Theme.primary : Theme.textColor
                                                }
                                            }

                                            MouseArea {
                                                id: rotArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: win.applyMonitorTransform(rotCard.modelData.val)
                                            }
                                        }
                                    }
                                }

                                // -------------------------------------------------- VRR
                                SectionHeader {
                                    title: Theme.t("monitor.sync_title", "Sincronização & tearing")
                                    subtitle: Theme.t("monitor.sync_sub", "Elimina cortes visuais (tearing) adaptando os frames à taxa do monitor")
                                }

                                CfgToggle {
                                    title: Theme.t("monitor.vrr_title", "Taxa adaptativa (VRR / FreeSync)")
                                    subtitle: Theme.t("monitor.vrr_desc", "Ajusta a taxa do monitor conforme os FPS do jogo. Em alguns painéis causa piscadas com a tela ociosa.")
                                    checked: win.vrrEnabled
                                    onToggled: nv => {
                                        win.vrrEnabled = nv;
                                        Quickshell.execDetached(["rice-hypr-prefs", "set", "vrr", nv ? "1" : "0"]);
                                        win.showToast(nv ? Theme.t("monitor.vrr_toast_on", "Taxa adaptativa ativada") : Theme.t("monitor.vrr_toast_off", "Taxa adaptativa desativada"));
                                    }
                                }

                                // -------------------------------------------------- brilho
                                SectionHeader {
                                    visible: win.hasBacklight
                                    title: Theme.t("monitor.brightness_section", "Brilho do painel")
                                    subtitle: Theme.t("monitor.brightness_section_sub", "Ajuste da iluminação da tela interna (backlight)")
                                }

                                CfgSlider {
                                    visible: win.hasBacklight
                                    title: Theme.t("monitor.brightness_slider", "Nível de brilho")
                                    minVal: 5; maxVal: 100; value: win.screenBrightness; unit: "%"
                                    onChanged: newVal => {
                                        win.screenBrightness = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["brightnessctl", "set", win.screenBrightness + "%"]);
                                        });
                                    }
                                }

                                // -------------------------------------------------- reverter
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    spacing: 10

                                    ActionBtn {
                                        icon: Theme.icons.restore
                                        text: Theme.t("monitor.auto_btn", "Voltar à configuração automática desta tela")
                                        onClicked: {
                                            Quickshell.execDetached(["rice-hypr-prefs", "monitor-forget", win.selectedMonitor]);
                                            win.showToast(Theme.t("monitor.auto_toast", "Configuração automática restaurada"));
                                            monitorReloadTimer.restart();
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
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
                                    title: Theme.t("audio.section_out", "Dispositivo de Saída de Áudio (Alto-falantes / Fones)")
                                    subtitle: Theme.t("audio.section_out_sub", "Clique para definir onde o som dos programas deve tocar")
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
                                                        text: sinkCard.modelData.is_default ? Theme.t("audio.default_active", "Dispositivo Padrão Ativo") + " · " + sinkCard.modelData.volume + "%" : Theme.t("audio.click_select", "Clique para selecionar")
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
                                                        text: Theme.t("common.active", "Ativo")
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
                                                    win.showToast(Theme.t("toast.output_changed", "Saída alterada: ") + sinkCard.modelData.description);
                                                    audioRefreshTimer.restart();
                                                }
                                            }
                                        }
                                    }
                                }

                                CfgSlider {
                                    title: Theme.t("audio.vol_out", "Volume Geral da Saída Padrão")
                                    minVal: 0; maxVal: 150; value: win.audioData.sink_volume || 100; unit: "%"
                                    onChanged: newVal => {
                                        win.audioData.sink_volume = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-audio", "set-sink-volume", String(win.audioData.sink_volume)]);
                                        });
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("audio.section_in", "Dispositivo de Entrada de Áudio (Microfone)")
                                    subtitle: Theme.t("audio.section_in_sub", "Selecione o microfone ativo para jogos, Discord e gravações")
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
                                                        text: sourceCard.modelData.is_default ? Theme.t("audio.default_in_active", "Microfone Padrão Ativo") + " · " + sourceCard.modelData.volume + "%" : Theme.t("audio.click_select", "Clique para selecionar")
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
                                                        text: Theme.t("common.active", "Ativo")
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
                                                    win.showToast(Theme.t("toast.mic_changed", "Microfone alterado: ") + sourceCard.modelData.description);
                                                    audioRefreshTimer.restart();
                                                }
                                            }
                                        }
                                    }
                                }

                                CfgSlider {
                                    title: Theme.t("audio.vol_in", "Volume / Sensibilidade do Microfone")
                                    minVal: 0; maxVal: 150; value: win.audioData.source_volume || 80; unit: "%"
                                    onChanged: newVal => {
                                        win.audioData.source_volume = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-audio", "set-source-volume", String(win.audioData.source_volume)]);
                                        });
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("audio.diag_title", "Teste & Diagnóstico")
                                    subtitle: Theme.t("audio.diag_sub", "Verifique se os canais de áudio estão funcionando perfeitamente")
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    ActionBtn {
                                        icon: Theme.icons.speaker
                                        text: Theme.t("audio.test_btn", "Testar Alto-falantes (Esquerdo / Direito)")
                                        primary: true
                                        onClicked: {
                                            Quickshell.execDetached(["rice-audio", "test"]);
                                            win.showToast(Theme.t("toast.stereo_test", "Reproduzindo teste estéreo..."));
                                        }
                                    }
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: Theme.t("audio.restart_btn", "Reiniciar PipeWire")
                                        onClicked: {
                                            Quickshell.execDetached(["rice-maintenance", "audio"]);
                                            win.showToast(Theme.t("toast.audio_restart", "Reiniciando áudio..."));
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
                                    title: Theme.t("input.kb_title", "Disposição do teclado")
                                    subtitle: Theme.t("input.kb_sub", "Muda o mapa de teclas na hora, sem reiniciar a sessão. O padrão vem do idioma escolhido na instalação do sistema.")
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 4
                                    columnSpacing: 8
                                    rowSpacing: 8

                                    Repeater {
                                        // Antes só existiam dois cartões fixos (ABNT2 e US
                                        // Internacional): quem instalasse o rice com teclado
                                        // de outro país não tinha como escolher o seu.
                                        model: [
                                            { flag: "🇧🇷", layout: "br",  variant: "",      name: Theme.t("input.kb_br", "Português (ABNT2)"),      desc: Theme.t("input.kb_br_desc", "Tecla Ç dedicada") },
                                            { flag: "🇺🇸", layout: "us",  variant: "intl",  name: Theme.t("input.kb_us", "Inglês Internacional"),   desc: Theme.t("input.kb_us_desc", "Acentos por tecla morta") },
                                            { flag: "🇺🇸", layout: "us",  variant: "",      name: Theme.t("input.kb_us_plain", "Inglês (US)"),      desc: Theme.t("input.kb_us_plain_desc", "Sem acentuação") },
                                            { flag: "🇵🇹", layout: "pt",  variant: "",      name: Theme.t("input.kb_pt", "Português (Portugal)"),   desc: "" },
                                            { flag: "🇪🇸", layout: "es",  variant: "",      name: Theme.t("input.kb_es", "Espanhol"),               desc: "" },
                                            { flag: "🇫🇷", layout: "fr",  variant: "",      name: Theme.t("input.kb_fr", "Francês (AZERTY)"),       desc: "" },
                                            { flag: "🇩🇪", layout: "de",  variant: "",      name: Theme.t("input.kb_de", "Alemão (QWERTZ)"),        desc: "" },
                                            { flag: "🇮🇹", layout: "it",  variant: "",      name: Theme.t("input.kb_it", "Italiano"),               desc: "" },
                                            { flag: "🇬🇧", layout: "gb",  variant: "",      name: Theme.t("input.kb_gb", "Inglês (Reino Unido)"),   desc: "" },
                                            { flag: "🇱🇦", layout: "latam", variant: "",   name: Theme.t("input.kb_latam", "Espanhol (Latino)"),   desc: "" }
                                        ]

                                        delegate: Rectangle {
                                            id: kbCard
                                            required property var modelData
                                            readonly property bool isCurrent: win.kbLayout === kbCard.modelData.layout
                                                && (win.kbVariant || "") === kbCard.modelData.variant

                                            Layout.fillWidth: true
                                            implicitHeight: 58
                                            radius: 10
                                            color: kbCard.isCurrent ? Theme.withAlpha(Theme.primary, 0.22) : (kbArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                            border.width: kbCard.isCurrent ? 1.5 : 1
                                            border.color: kbCard.isCurrent ? Theme.primary : Theme.withAlpha(Theme.outline, 0.15)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 10

                                                Text { text: kbCard.modelData.flag; font.pixelSize: 19 }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: kbCard.modelData.name
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                        color: kbCard.isCurrent ? Theme.primary : Theme.textColor
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        visible: kbCard.modelData.desc !== ""
                                                        text: kbCard.modelData.desc
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 9
                                                        color: Theme.subtext
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: kbArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.kbLayout = kbCard.modelData.layout;
                                                    win.kbVariant = kbCard.modelData.variant;
                                                    Quickshell.execDetached(["rice-hypr-prefs", "set", "kb_layout", kbCard.modelData.layout]);
                                                    Quickshell.execDetached(["rice-hypr-prefs", "set", "kb_variant", kbCard.modelData.variant]);
                                                    win.showToast(Theme.t("input.kb_toast", "Teclado alterado para ") + kbCard.modelData.name);
                                                }
                                            }
                                        }
                                    }
                                }

                                // ---------------------------------------- repetição de teclas
                                SectionHeader {
                                    title: Theme.t("input.repeat_title", "Repetição de teclas")
                                    subtitle: Theme.t("input.repeat_sub", "Quanto tempo segurando uma tecla até ela começar a repetir, e com que velocidade repete.")
                                }

                                CfgSlider {
                                    title: Theme.t("input.repeat_delay", "Espera até começar a repetir")
                                    minVal: 200; maxVal: 1000; value: win.repeatDelay; unit: " ms"
                                    onChanged: newVal => {
                                        win.repeatDelay = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-hypr-prefs", "set", "repeat_delay", String(win.repeatDelay)]);
                                        });
                                    }
                                }

                                CfgSlider {
                                    title: Theme.t("input.repeat_rate", "Velocidade da repetição")
                                    minVal: 10; maxVal: 60; value: win.repeatRate; unit: Theme.t("input.repeat_unit", " por segundo")
                                    onChanged: newVal => {
                                        win.repeatRate = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-hypr-prefs", "set", "repeat_rate", String(win.repeatRate)]);
                                        });
                                    }
                                }

                                // ---------------------------------------------- touchpad
                                SectionHeader {
                                    visible: win.hasTouchpad
                                    title: Theme.t("input.touchpad_title", "Touchpad")
                                    subtitle: Theme.t("input.touchpad_sub", "Ajustes do painel sensível do notebook")
                                }

                                CfgToggle {
                                    visible: win.hasTouchpad
                                    title: Theme.t("input.touchpad_tap", "Tocar para clicar")
                                    subtitle: Theme.t("input.touchpad_tap_desc", "Um toque leve no touchpad já conta como clique, sem precisar pressionar.")
                                    checked: win.touchpadTap
                                    onToggled: nv => {
                                        win.touchpadTap = nv;
                                        Quickshell.execDetached(["rice-hypr-prefs", "set", "touchpad_tap", nv ? "true" : "false"]);
                                    }
                                }

                                CfgToggle {
                                    visible: win.hasTouchpad
                                    title: Theme.t("input.touchpad_natural", "Rolagem natural")
                                    subtitle: Theme.t("input.touchpad_natural_desc", "A página acompanha o movimento dos dedos, como no celular.")
                                    checked: win.touchpadNatural
                                    onToggled: nv => {
                                        win.touchpadNatural = nv;
                                        Quickshell.execDetached(["rice-hypr-prefs", "set", "touchpad_natural_scroll", nv ? "true" : "false"]);
                                    }
                                }

                                CfgToggle {
                                    visible: win.hasTouchpad
                                    title: Theme.t("input.touchpad_dwt", "Desativar enquanto digita")
                                    subtitle: Theme.t("input.touchpad_dwt_desc", "Evita cliques acidentais com a palma da mão durante a digitação.")
                                    checked: win.touchpadDwt
                                    onToggled: nv => {
                                        win.touchpadDwt = nv;
                                        Quickshell.execDetached(["rice-hypr-prefs", "set", "touchpad_dwt", nv ? "true" : "false"]);
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("input.mouse_sens_title", "Sensibilidade & Velocidade do Mouse")
                                    subtitle: Theme.t("input.mouse_sens_sub", "Ajuste preciso de -1.0 a +1.0 (0.0 = velocidade nativa do sensor)")
                                }

                                CfgSlider {
                                    title: Theme.t("input.mouse_speed", "Velocidade do Ponteiro")
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
                                        text: Theme.t("input.mouse_reset", "Redefinir Sensibilidade Neutra (0.0)")
                                        onClicked: {
                                            win.mouseSensitivity = 0.0;
                                            Quickshell.execDetached(["rice-hypr-prefs", "set", "mouse_sensitivity", "0.0"]);
                                            win.showToast(Theme.t("toast.sens_reset", "Sensibilidade redefinida para 0.0"));
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                SectionHeader {
                                    title: Theme.t("input.mouse_accel_title", "Perfil de Aceleração do Mouse")
                                    subtitle: Theme.t("input.mouse_accel_sub", "Flat elimina aceleração (ideal para mira em jogos); Adaptativo acelera com movimentos rápidos")
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
                                                    text: Theme.t("input.accel_flat", "Flat (Sem Aceleração - 1:1)")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: Theme.t("input.accel_flat_desc", "Movimento previsível e consistente. Essencial para jogos (FPS).")
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
                                                win.showToast(Theme.t("toast.mouse_flat", "Perfil de mouse: Flat (Sem aceleração)"));
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
                                                    text: Theme.t("input.accel_adapt", "Adaptativo (Com Aceleração)")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: Theme.t("input.accel_adapt_desc", "Aumenta a velocidade em gestos rápidos. Padrão confortável.")
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
                                                win.showToast(Theme.t("toast.mouse_adaptive", "Perfil de mouse: Adaptativo"));
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("input.boot_title", "Comportamento de Inicialização")
                                    subtitle: Theme.t("input.boot_sub", "Opções de inicialização automática de hardware")
                                }

                                CfgToggle {
                                    title: Theme.t("input.numlock_title", "NumLock Ativado no Boot")
                                    subtitle: Theme.t("input.numlock_desc", "Habilita o teclado numérico automaticamente assim que a sessão do Hyprland inicia.")
                                    checked: win.numlock
                                    onToggled: nv => {
                                        win.numlock = nv;
                                        Quickshell.execDetached(["rice-hypr-prefs", "set", "numlock", String(nv)]);
                                        win.showToast(nv ? "NumLock ativado por padrão" : "NumLock desativado por padrão");
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("settings.discord_binds", "Atalhos Globais do Discord")
                                    subtitle: Theme.t("input.discord_sub", "Mute e Deafen globais que funcionam mesmo com Discord ou Vesktop minimizado em segundo plano")
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
                                                    text: Theme.t("discord.bind_note", "Os atalhos gravam diretamente em ~/.config/hypr/hyprland.lua usando hl.bind")
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
                                                        text: Theme.t("discord.verify_btn", "Verificar")
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
                                                    text: Theme.t("discord.quick_suggestions", "Sugestões rápidas:")
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
                                                    text: Theme.t("discord.quick_suggestions", "Sugestões rápidas:")
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
                                    title: Theme.t("power.section_profile", "Perfil de Desempenho & Energia")
                                    subtitle: Theme.t("power.section_profile_sub", "Ajusta o escalonamento do processador e limites térmicos do sistema")
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Repeater {
                                        model: [
                                            { id: "performance", name: "Desempenho", icon: Theme.icons.perf, desc: Theme.t("power.prof_perf_desc", "Clocks máximos para jogos e tarefas pesadas") },
                                            { id: "balanced", name: "Equilibrado", icon: Theme.icons.balanced, desc: Theme.t("power.prof_bal_desc", "Balanço inteligente entre fluidez e consumo") },
                                            { id: "power-saver", name: "Economia", icon: Theme.icons.saver, desc: Theme.t("power.prof_saver_desc", "Prioriza autonomia da bateria e silêncio") }
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
                                                    win.showToast(Theme.t("toast.power_profile", "Perfil de energia: ") + pCard.modelData.name);
                                                    powerRefreshTimer.restart();
                                                }
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("power.section_battery", "Saúde & Estatísticas da Bateria")
                                    subtitle: Theme.t("power.section_battery_sub", "Dados de integridade física e ciclos de carga do notebook")
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
                                                Text { text: Theme.t("power.battery_health", "Saúde da Bateria"); font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.subtext }
                                                Text { text: win.powerData.health + "% " + Theme.t("power.capacity", "Capacidade"); font.family: Theme.fontFamily; font.pixelSize: 15; font.weight: Font.Bold; color: Theme.textColor }
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
                                                Text { text: Theme.t("power.charge_cycles", "Ciclos de Carga"); font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.subtext }
                                                Text { text: win.powerData.cycles + " " + Theme.t("power.cycles_completed", "Ciclos Completos"); font.family: Theme.fontFamily; font.pixelSize: 15; font.weight: Font.Bold; color: Theme.textColor }
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
                                                Text { text: Theme.t("power.power_status", "Status de Alimentação"); font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.subtext }
                                                Text { text: win.powerData.status + " (" + win.powerData.percent + "%)"; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Bold; color: Theme.textColor }
                                            }
                                        }
                                    }
                                }
                                // ------------------------------------------- ociosidade
                                SectionHeader {
                                    title: Theme.t("power.idle_title", "Quando o computador fica parado")
                                    subtitle: Theme.t("power.idle_sub", "Tempo sem mexer no mouse ou no teclado até cada ação acontecer. Escolha \"Nunca\" para desligar a ação.")
                                }

                                Repeater {
                                    model: [
                                        { key: "dim",        title: Theme.t("power.idle_dim", "Escurecer a tela"),      desc: Theme.t("power.idle_dim_desc", "Reduz o brilho pela metade; volta ao normal ao mexer.") },
                                        { key: "screen_off", title: Theme.t("power.idle_screen", "Desligar a tela"),     desc: Theme.t("power.idle_screen_desc", "A tela apaga, o computador continua ligado.") },
                                        { key: "lock",       title: Theme.t("power.idle_lock", "Bloquear a sessão"),     desc: Theme.t("power.idle_lock_desc", "Pede a senha para voltar a usar.") },
                                        { key: "suspend",    title: Theme.t("power.idle_suspend", "Suspender (dormir)"), desc: Theme.t("power.idle_suspend_desc", "Coloca o PC para dormir, gastando quase nada de bateria.") }
                                    ]

                                    delegate: ColumnLayout {
                                        id: idleRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        spacing: 6

                                        Text {
                                            text: idleRow.modelData.title
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            color: Theme.textColor
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: idleRow.modelData.desc
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.subtext
                                            wrapMode: Text.WordWrap
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Repeater {
                                                model: [0, 1, 5, 10, 15, 30, 60]

                                                delegate: Rectangle {
                                                    id: idleChip
                                                    required property var modelData
                                                    readonly property int minutes: idleChip.modelData
                                                    readonly property bool isCurrent: (win.idleValues[idleRow.modelData.key] || 0) === idleChip.minutes

                                                    Layout.fillWidth: true
                                                    implicitHeight: 32
                                                    radius: 8
                                                    color: idleChip.isCurrent ? Theme.withAlpha(Theme.primary, 0.25) : (idleChipArea.containsMouse ? Theme.tileHigh : Theme.tile)
                                                    border.width: idleChip.isCurrent ? 1.5 : 1
                                                    border.color: idleChip.isCurrent ? Theme.primary : Theme.withAlpha(Theme.outline, 0.15)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: idleChip.minutes === 0
                                                            ? Theme.t("power.idle_never", "Nunca")
                                                            : idleChip.minutes + " min"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        font.weight: idleChip.isCurrent ? Font.Bold : Font.Normal
                                                        color: idleChip.isCurrent ? Theme.primary : Theme.textColor
                                                    }

                                                    MouseArea {
                                                        id: idleChipArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            const next = Object.assign({}, win.idleValues);
                                                            next[idleRow.modelData.key] = idleChip.minutes;
                                                            win.idleValues = next;
                                                            Quickshell.execDetached(["rice-idle", "set", idleRow.modelData.key, String(idleChip.minutes)]);
                                                            win.showToast(idleRow.modelData.title + ": " + (idleChip.minutes === 0
                                                                ? Theme.t("power.idle_never", "Nunca")
                                                                : idleChip.minutes + " min"));
                                                        }
                                                    }
                                                }
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
                                    title: Theme.t("boot.section_autostart", "Aplicativos na Inicialização do Sistema")
                                    subtitle: Theme.t("boot.section_autostart_sub", "Ative ou desative quais programas abrem sozinhos quando você liga o computador")
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        visible: win.autostartEntries.length === 0
                                        text: Theme.t("boot.empty_autostart", "Nenhum aplicativo configurado para iniciar automaticamente.")
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
                                                            win.showToast(Theme.t("toast.autostart_removed", "Removido do autostart: ") + autoCard.modelData.name);
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

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    SectionHeader {
                                        title: Theme.t("boot.section_quick_add", "Adicionar Aplicativo à Inicialização")
                                        subtitle: Theme.t("boot.section_quick_add_sub", "Procure o programa pelo nome e clique para que ele abra junto com o sistema")
                                    }
                                    Item { Layout.fillWidth: true }

                                    Rectangle {
                                        implicitWidth: 240
                                        implicitHeight: 32
                                        radius: 8
                                        color: Theme.background
                                        border.width: 1
                                        border.color: bootSearchInput.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

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
                                                id: bootSearchInput
                                                Layout.fillWidth: true
                                                verticalAlignment: TextInput.AlignVCenter
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                color: Theme.textColor
                                                selectByMouse: true
                                                onTextChanged: win.bootAppQuery = text
                                                Text {
                                                    anchors.fill: parent
                                                    verticalAlignment: Text.AlignVCenter
                                                    visible: bootSearchInput.text === ""
                                                    text: Theme.t("boot.search_ph", "Procurar aplicativo...")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    color: Theme.subtext
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: win.bootAppQuery.trim() === ""
                                        ? Theme.t("boot.search_hint", "Mostrando alguns dos ") + (win.availableApps || []).length + Theme.t("boot.search_hint_end", " aplicativos instalados. Use a busca para achar o que você quer.")
                                        : (win.bootAppsFiltered.length === 0
                                            ? Theme.t("boot.search_none", "Nenhum aplicativo encontrado com esse nome.")
                                            : win.bootAppsFiltered.length + Theme.t("boot.search_found", " aplicativo(s) encontrado(s)."))
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.subtext
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: win.bootAppsFiltered
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
                                                        win.showToast(Theme.t("toast.autostart_added", "Adicionado ao autostart: ") + appChip.modelData.name);
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
                                    title: Theme.t("wallust.section_palette", "Paleta Dinâmica Extraída do Wallpaper")
                                    subtitle: Theme.t("wallust.section_palette_sub", "Todas as cores da interface e terminal são geradas pelo Wallust a partir do papel de parede ativo")
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Repeater {
                                        model: [
                                            { key: "background", label: Theme.t("wallust.bg", "Fundo"), hex: win.wallustColors.background || "#170D0C" },
                                            { key: "foreground", label: Theme.t("wallust.fg", "Texto"), hex: win.wallustColors.foreground || "#C2A6A5" },
                                            { key: "color4", label: Theme.t("wallust.accent1", "Destaque 1"), hex: win.wallustColors.color4 || "#5D1D1D" },
                                            { key: "color10", label: Theme.t("wallust.accent2", "Destaque 2"), hex: win.wallustColors.color10 || "#A62727" }
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

                                            // Bolinha que marca a cor trocada à mão.
                                            Rectangle {
                                                visible: win.colorOverrides[colorCard.modelData.key] !== undefined
                                                anchors.top: parent.top
                                                anchors.right: parent.right
                                                anchors.margins: 6
                                                width: 8; height: 8; radius: 4
                                                color: Theme.primary
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton) {
                                                        Quickshell.execDetached(["wl-copy", colorCard.modelData.hex]);
                                                        win.showToast(Theme.t("toast.copied", "Copiado: ") + colorCard.modelData.hex);
                                                    } else {
                                                        win.openColorPicker(colorCard.modelData.key, colorCard.modelData.label, colorCard.modelData.hex);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("wallust.section_ansi", "Paleta Completa de 16 Cores ANSI")
                                    subtitle: Theme.t("wallust.section_ansi_sub", "Clique numa cor para escolher outra na roda de cores. Clique com o botão direito para copiar o código HEX.")
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

                                            Rectangle {
                                                visible: win.colorOverrides["color" + parent.modelData] !== undefined
                                                anchors.top: parent.top
                                                anchors.right: parent.right
                                                anchors.margins: 5
                                                width: 7; height: 7; radius: 3.5
                                                color: Theme.primary
                                            }

                                            MouseArea {
                                                id: colorChipArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton) {
                                                        Quickshell.execDetached(["wl-copy", parent.hex]);
                                                        win.showToast(Theme.t("toast.copied_c", "Copiado c") + parent.modelData + ": " + parent.hex);
                                                    } else {
                                                        win.openColorPicker("color" + parent.modelData, "c" + parent.modelData, parent.hex);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                CfgToggle {
                                    title: Theme.t("wallust.auto_title", "Cores seguem o wallpaper")
                                    subtitle: Theme.t("wallust.auto_sub", "Ligado: trocar o papel de parede gera uma paleta nova. Desligado: as cores ficam como estão agora.")
                                    checked: win.colorsFollowWallpaper
                                    onToggled: next => {
                                        win.colorsFollowWallpaper = next;
                                        setColorProc.command = ["rice-colors", "auto", next ? "1" : "0"];
                                        setColorProc.running = true;
                                        win.showToast(next ? Theme.t("toast.colors_auto_on", "As cores vão acompanhar o wallpaper")
                                                           : Theme.t("toast.colors_auto_off", "Paleta travada: trocar o wallpaper não muda mais as cores"));
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("wallust.section_transition", "Transição ao trocar o wallpaper")
                                    subtitle: Theme.t("wallust.section_transition_sub", "Como o papel de parede novo entra na tela. Enquanto a troca acontece por trás, o antigo continua em movimento.")
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 4
                                    columnSpacing: 12
                                    rowSpacing: 12

                                    Repeater {
                                        model: [
                                            { id: "fade", name: Theme.t("wallust.tr_fade", "Dissolver"), desc: Theme.t("wallust.tr_fade_desc", "Um aparece sobre o outro") },
                                            { id: "wipe", name: Theme.t("wallust.tr_wipe", "Varredura"), desc: Theme.t("wallust.tr_wipe_desc", "Entra pela lateral") },
                                            { id: "wave", name: Theme.t("wallust.tr_wave", "Onda"), desc: Theme.t("wallust.tr_wave_desc", "Varredura ondulada") },
                                            { id: "grow", name: Theme.t("wallust.tr_grow", "Círculo"), desc: Theme.t("wallust.tr_grow_desc", "Abre do centro") }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool active: win.wallTransition === modelData.id
                                            Layout.fillWidth: true
                                            implicitHeight: 52
                                            radius: 10
                                            color: active ? Theme.withAlpha(Theme.primary, 0.22) : (trArea.containsMouse ? Theme.tileHigh : Theme.tile)
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
                                                    color: Theme.textColor
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
                                                id: trArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.wallTransition = parent.modelData.id;
                                                    Quickshell.execDetached(["rice-wallpaper-fade", "--style", parent.modelData.id]);
                                                    win.showToast(Theme.t("toast.wall_transition", "Transição: ") + parent.modelData.name);
                                                }
                                            }
                                        }
                                    }
                                }

                                CfgSlider {
                                    title: Theme.t("wallust.tr_duration", "Duração da transição")
                                    minVal: 300
                                    maxVal: 2500
                                    value: win.wallTransitionMs
                                    unit: " ms"
                                    onChanged: newVal => {
                                        win.wallTransitionMs = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-hypr-prefs", "set",
                                                "wallpaper_transition_ms", String(win.wallTransitionMs)]);
                                        });
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("wallust.section_previews", "Imagens dos wallpapers em alta resolução")
                                    subtitle: Theme.t("wallust.section_previews_sub", "O Wallpaper Engine guarda só um ícone quadrado de cada papel de parede. Estas imagens são usadas na transição e para gerar as cores.")
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        const st = win.previewStatus;
                                        if (!st || st.total === undefined)
                                            return Theme.t("wallust.previews_loading", "Verificando...");
                                        return Theme.t("wallust.previews_count", "Vídeos: ")
                                             + st.videos_prontos + "/" + st.videos + "   "
                                             + Theme.t("wallust.previews_scenes", "Cenas: ")
                                             + st.cenas_prontas + "/" + st.cenas;
                                    }
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.subtext
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ActionBtn {
                                        icon: Theme.icons.packages
                                        text: Theme.t("wallust.previews_videos_btn", "Extrair Quadro dos Wallpapers de Vídeo")
                                        onClicked: {
                                            Quickshell.execDetached(["rice-wallpaper-previews", "videos"]);
                                            win.showToast(Theme.t("toast.previews_videos", "Extraindo os quadros em segundo plano..."));
                                            previewRecheck.restart();
                                        }
                                    }

                                    ActionBtn {
                                        icon: Theme.icons.monitor
                                        text: Theme.t("wallust.previews_scenes_btn", "Fotografar os Wallpapers Animados")
                                        onClicked: {
                                            Quickshell.execDetached(["rice-wallpaper-previews", "scenes"]);
                                            win.showToast(Theme.t("toast.previews_scenes", "Fotografando: a tela vai piscar entre os wallpapers e voltar ao normal no fim."));
                                            previewRecheck.restart();
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: Theme.t("wallust.previews_warn", "Os animados (cenas) não têm vídeo de onde tirar um quadro: a única forma é deixar cada um rodar e fotografar a tela. Por isso esse botão troca os wallpapers por alguns segundos, esconde a interface e depois devolve tudo como estava. Uma cena é pulada se sobrar alguma janela na tela.")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.subtext
                                    wrapMode: Text.WordWrap
                                }

                                Timer {
                                    id: previewRecheck
                                    interval: 8000
                                    repeat: true
                                    triggeredOnStart: false
                                    property int ticks: 0
                                    onTriggered: {
                                        previewStatusProc.running = true;
                                        ticks += 1;
                                        if (ticks > 12) { ticks = 0; stop(); }
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("wallust.section_actions", "Ações de Wallpaper & Sincronização")
                                    subtitle: Theme.t("wallust.section_actions_sub", "Alterne papéis de parede animados ou regenere a paleta do sistema")
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ActionBtn {
                                        icon: Theme.icons.palette
                                        text: Theme.t("wallust.refresh_btn", "Regenerar Cores do Wallpaper Atual")
                                        primary: true
                                        onClicked: {
                                            Quickshell.execDetached(["rice-wallust-refresh", "--force"]);
                                            refreshColorsTimer.restart();
                                            win.showToast(Theme.t("toast.wallust_refresh", "Regenerando cores do Wallust..."));
                                        }
                                    }

                                    ActionBtn {
                                        icon: Theme.icons.restore
                                        visible: Object.keys(win.colorOverrides).length > 0
                                        text: Theme.t("wallust.reset_colors_btn", "Desfazer Cores Trocadas à Mão")
                                        onClicked: {
                                            setColorProc.command = ["rice-colors", "reset"];
                                            setColorProc.running = true;
                                            win.showToast(Theme.t("toast.colors_reset", "Voltando à paleta do wallpaper..."));
                                        }
                                    }

                                    ActionBtn {
                                        icon: Theme.icons.dashboard
                                        text: Theme.t("wallust.switcher_btn", "Abrir Seletor de Wallpapers (Super + S)")
                                        onClicked: {
                                            win.open = false;
                                            // Usa o Waywallen (Wallpaper Engine) quando instalado; senão
                                            // abre o seletor de imagem estática do rice.
                                            Quickshell.execDetached(["sh", "-c",
                                                "if flatpak info org.waywallen.waywallen >/dev/null 2>&1; then exec waywallen-switcher; else exec rice-wallpaper-set; fi"]);
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ActionBtn {
                                        icon: Theme.icons.palette
                                        text: Theme.t("wallust.static_btn", "Escolher Imagem de Fundo (sem Wallpaper Engine)")
                                        onClicked: {
                                            win.open = false;
                                            Quickshell.execDetached(["rice-wallpaper-set"]);
                                        }
                                    }

                                    ActionBtn {
                                        icon: Theme.icons.lock
                                        text: Theme.t("wallust.sddm_btn", "Atualizar Fundo da Tela de Login")
                                        onClicked: {
                                            Quickshell.execDetached(["rice-sddm-sync-wallpaper"]);
                                            win.showToast(Theme.t("wallust.sddm_toast", "Gerando o fundo da tela de login..."));
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
                                    title: Theme.t("effects.nightlight_title", "Luz Noturna (Filtro de Luz Azul)")
                                    subtitle: Theme.t("effects.nightlight_sub", "Reduz o cansaço visual ajustando a temperatura de cor da tela")
                                }

                                CfgToggle {
                                    title: Theme.t("effects.nightlight_toggle", "Ativar Luz Noturna")
                                    subtitle: Theme.t("effects.nightlight_toggle_desc", "Aplica filtro quente instantaneamente via hyprsunset")
                                    checked: win.nightlightActive
                                    onToggled: nv => {
                                        win.nightlightActive = nv;
                                        Quickshell.execDetached(["rice-nightlight", "toggle"]);
                                    }
                                }

                                CfgSlider {
                                    title: Theme.t("effects.nightlight_temp", "Temperatura de Cor")
                                    minVal: 2500; maxVal: 6500; value: win.nightlightTemp; unit: " K"
                                    onChanged: newVal => {
                                        win.nightlightTemp = Math.round(newVal);
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-nightlight", "set", String(win.nightlightTemp)]);
                                        });
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("effects.nightlight_sched", "Ligar sozinha")
                                    subtitle: Theme.t("effects.nightlight_sched_sub", "O horário do sol é calculado no próprio computador, sem internet — continua certo com o notebook fora de casa.")
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Repeater {
                                        model: [
                                            { id: "off",   name: Theme.t("effects.nl_off", "Só no botão"), desc: Theme.t("effects.nl_off_desc", "Nunca liga sozinha") },
                                            { id: "sun",   name: Theme.t("effects.nl_sun", "Pelo sol"), desc: Theme.t("effects.nl_sun_desc", "Do pôr ao nascer do sol") },
                                            { id: "fixed", name: Theme.t("effects.nl_fixed", "Horário fixo"), desc: Theme.t("effects.nl_fixed_desc", "Você escolhe as horas") }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool active: win.nightlightSchedule === modelData.id
                                            Layout.fillWidth: true
                                            implicitHeight: 52
                                            radius: 10
                                            color: active ? Theme.withAlpha(Theme.primary, 0.22) : (nlArea.containsMouse ? Theme.tileHigh : Theme.tile)
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
                                                    color: Theme.textColor
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
                                                id: nlArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.nightlightSchedule = parent.modelData.id;
                                                    Quickshell.execDetached(["rice-nightlight", "schedule", parent.modelData.id]);
                                                    nlRecheck.restart();
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: win.nightlightSchedule === "sun" && win.nightlightSunset !== ""
                                    text: Theme.t("effects.nl_today", "Hoje aqui: o sol se põe às ") + win.nightlightSunset
                                        + Theme.t("effects.nl_today2", " e nasce às ") + win.nightlightSunrise + "."
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.subtext
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    visible: win.nightlightSchedule === "fixed"

                                    CfgSlider {
                                        Layout.fillWidth: true
                                        title: Theme.t("effects.nl_start", "Liga às")
                                        minVal: 0; maxVal: 23
                                        value: parseInt(win.nightlightStart.split(":")[0]) || 19
                                        unit: "h"
                                        onChanged: newVal => {
                                            win.nightlightStart = ("0" + Math.round(newVal)).slice(-2) + ":00";
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-nightlight", "times",
                                                    win.nightlightStart, win.nightlightEnd]);
                                            });
                                        }
                                    }

                                    CfgSlider {
                                        Layout.fillWidth: true
                                        title: Theme.t("effects.nl_end", "Desliga às")
                                        minVal: 0; maxVal: 23
                                        value: parseInt(win.nightlightEnd.split(":")[0]) || 7
                                        unit: "h"
                                        onChanged: newVal => {
                                            win.nightlightEnd = ("0" + Math.round(newVal)).slice(-2) + ":00";
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-nightlight", "times",
                                                    win.nightlightStart, win.nightlightEnd]);
                                            });
                                        }
                                    }
                                }

                                Timer {
                                    id: nlRecheck
                                    interval: 1200
                                    onTriggered: loadNightlightProc.running = true
                                }

                                SectionHeader {
                                    title: Theme.t("effects.dim_title", "Foco & Janelas Inativas")
                                    subtitle: Theme.t("effects.dim_sub", "Escurece as janelas que não estão recebendo comandos no momento")
                                }

                                CfgToggle {
                                    title: Theme.t("effects.dim_toggle", "Escurecer Janelas Inativas (Dim Inactive)")
                                    subtitle: Theme.t("effects.dim_toggle_desc", "Destaca a janela atualmente em uso escurecendo as janelas de fundo")
                                    checked: win.dimInactive
                                    onToggled: nv => {
                                        win.dimInactive = nv;
                                        Quickshell.execDetached(["rice-hypr-prefs", "set", "dim_inactive", nv ? "true" : "false"]);
                                    }
                                }

                                CfgSlider {
                                    title: Theme.t("effects.dim_strength", "Intensidade do Escurecimento (Dim Strength)")
                                    minVal: 0.05; maxVal: 0.50; value: win.dimStrength; decimals: 2
                                    onChanged: newVal => {
                                        win.dimStrength = newVal;
                                        debounceTimer.exec(() => {
                                            Quickshell.execDetached(["rice-hypr-prefs", "set", "dim_strength", String(win.dimStrength)]);
                                        });
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("effects.geom_title", "Geometria do Hyprland")
                                    subtitle: Theme.t("effects.geom_sub", "Curvatura dos cantos e espaçamento entre janelas")
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20
                                    CfgSlider {
                                        title: Theme.t("effects.rounding", "Arredondamento dos Cantos (Rounding)")
                                        minVal: 0; maxVal: 20; value: win.rounding; unit: " px"
                                        onChanged: newVal => {
                                            win.rounding = Math.round(newVal);
                                            debounceTimer.exec(() => {
                                                Quickshell.execDetached(["rice-hypr-prefs", "set", "rounding", String(win.rounding)]);
                                            });
                                        }
                                    }
                                    CfgSlider {
                                        title: Theme.t("effects.gaps_in", "Espaçamento Interno (Gaps In)")
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
                                    title: Theme.t("effects.anim_title", "Estilo de Animação")
                                    subtitle: Theme.t("effects.anim_sub", "Curvas de Bézier e velocidade para abertura, fechamento e workspaces — escolha um preset ou ajuste cada parte")
                                }

                                // Presets, curva de Bézier por grupo, duração e estilo
                                // (rice-anim). Ver AnimCurveEditor.qml.
                                AnimCurveEditor {
                                    Layout.fillWidth: true
                                    onToast: msg => win.showToast(msg)
                                }

                                SectionHeader {
                                    title: Theme.t("effects.boot_login_title", "Inicialização & Tela de Login (SDDM & Limine)")
                                    subtitle: Theme.t("effects.boot_login_sub", "Aplica o tema SilentSDDM e wallpaper suavizado no bootloader do sistema")
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ActionBtn {
                                        icon: Theme.icons.verified
                                        text: Theme.t("effects.apply_boot_login", "Aplicar SDDM e Bootloader Limine")
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
                                        text: Theme.t("effects.test_sddm", "Testar Tela do SDDM em Janela")
                                        onClicked: {
                                            // rice-sddm-preview roda de dentro da pasta do tema e com o
                                            // QML2_IMPORT_PATH certo (sem isso o teclado virtual do tema
                                            // não carrega). Mantém o comando cru como reserva.
                                            Quickshell.execDetached(["bash", "-c",
                                                "command -v rice-sddm-preview >/dev/null 2>&1 && exec rice-sddm-preview; "
                                                + "cd /usr/share/sddm/themes/SilentSDDM && QML2_IMPORT_PATH=./components/ "
                                                + "{ sddm-greeter-qt6 --test-mode --theme . 2>/dev/null || sddm-greeter --test-mode --theme .; }"]);
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
                                        title: Theme.t("bt.section_title", "Bluetooth & Dispositivos sem Fio")
                                        subtitle: Theme.t("bt.section_sub", "Conecte controles Xbox/PS, fones de ouvido e periféricos sem fio")
                                    }
                                    Item { Layout.fillWidth: true }
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: Theme.t("bt.scan_btn", "Escanear")
                                        onClicked: {
                                            Quickshell.execDetached(["rice-bluetooth", "scan"]);
                                            showToast(Theme.t("toast.scanning_bt", "Buscando dispositivos próximos..."));
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
                                                text: win.btData && win.btData.powered ? "Bluetooth Ativado" : Theme.t("bt.status_off", "Bluetooth Desativado")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                color: Theme.textColor
                                            }
                                            Text {
                                                text: win.btData && win.btData.powered ? Theme.t("bt.status_on_desc", "Pronto para conexões e pareamento automático") : "Ligue o adaptador para conectar periféricos"
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
                                    title: Theme.t("bt.devices_title", "Dispositivos Pareados & Conhecidos")
                                    subtitle: Theme.t("bt.devices_sub", "Clique em Conectar para vincular o controle ou fone instantaneamente")
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
                                                                text: Theme.t("bt.connected", "● Conectado")
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
                                                    text: btDevCard.modelData.connected ? Theme.t("bt.disconnect", "Desconectar") : "Conectar"
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
                                        text: Theme.t("bt.empty", "Nenhum dispositivo encontrado. Coloque seu controle ou fone em modo de pareamento e clique em 'Escanear'.")
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
                                        title: Theme.t("net.section_title", "Rede & Wi-Fi")
                                        subtitle: Theme.t("net.section_sub", "Monitore a conexão de internet e conecte-se a novas redes")
                                    }
                                    Item { Layout.fillWidth: true }
                                    ActionBtn {
                                        icon: Theme.icons.refresh
                                        text: Theme.t("net.scan_btn", "Atualizar Redes")
                                        onClicked: {
                                            Quickshell.execDetached(["rice-network", "scan"]);
                                            loadNetScanProc.running = true;
                                            showToast(Theme.t("toast.scanning_wifi", "Buscando redes Wi-Fi..."));
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
                                                    text: win.netData && win.netData.connected_ssid ? win.netData.connected_ssid : Theme.t("net.no_conn", "Nenhuma rede conectada")
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
                                                    text: Theme.t("net.ip_label", "IP: ") + (win.netData && win.netData.ip ? win.netData.ip : "---")
                                                    font.family: Theme.monoFamily
                                                    font.pixelSize: 11
                                                    color: Theme.subtext
                                                }
                                                Text {
                                                    text: Theme.t("net.gateway_label", "Roteador: ") + (win.netData && win.netData.gateway ? win.netData.gateway : "---")
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
                                                text: Theme.t("net.test_ping", "Testar Ping")
                                                onClicked: loadPingProc.running = true
                                            }
                                            ActionBtn {
                                                visible: win.netData && !!win.netData.connected_ssid
                                                icon: Theme.icons.close
                                                text: Theme.t("net.disconnect", "Desconectar")
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-network", "disconnect"]);
                                                    loadNetProc.running = true;
                                                }
                                            }
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("net.available_title", "Redes Wi-Fi Disponíveis")
                                    subtitle: Theme.t("net.available_sub", "Selecione uma rede para conectar")
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
                                                        text: Theme.t("net.connect_btn", "Conectar")
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
                                                            text: Theme.t("net.active_badge", "Ativa")
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
                                                                text: Theme.t("net.password_placeholder", "Digite a senha do Wi-Fi...")
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 11
                                                                color: Theme.subtext
                                                            }
                                                        }
                                                    }

                                                    ActionBtn {
                                                        icon: Theme.icons.confirm
                                                        text: Theme.t("net.confirm", "Confirmar")
                                                        primary: true
                                                        onClicked: {
                                                            Quickshell.execDetached(["rice-network", "connect", wifiCard.modelData.ssid, win.netPassInput]);
                                                            win.netSelectedSsid = "";
                                                            loadNetProc.running = true;
                                                        }
                                                    }

                                                    ActionBtn {
                                                        icon: Theme.icons.close
                                                        text: Theme.t("common.cancel", "Cancelar")
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
                                    title: Theme.t("defaults.section_title", "Aplicativos Padrão do Sistema")
                                    subtitle: Theme.t("defaults.section_sub", "Selecione quais programas abrem páginas da web, pastas, códigos, fotos e vídeos")
                                }

                                Repeater {
                                    model: [
                                        { id: "browser", title: "Navegador Web", icon: Theme.icons.dashboard, desc: Theme.t("defaults.cat_browser_desc", "Abre links HTTP/HTTPS e arquivos HTML") },
                                        { id: "filemanager", title: "Gerenciador de Pastas", icon: Theme.icons.laptop, desc: Theme.t("defaults.cat_filemanager_desc", "Abre diretórios e dispositivos") },
                                        { id: "editor", title: "Editor de Código & Texto", icon: Theme.icons.console, desc: Theme.t("defaults.cat_editor_desc", "Abre scripts, código-fonte e notas de texto") },
                                        { id: "video", title: "Player de Vídeo", icon: Theme.icons.media, desc: Theme.t("defaults.cat_video_desc", "Reproduz filmes, gravações e clipes MP4/MKV") },
                                        { id: "image", title: "Visualizador de Imagens", icon: Theme.icons.camera, desc: Theme.t("defaults.cat_image_desc", "Abre capturas de tela e fotos PNG/JPG") },
                                        { id: "audio", title: "Player de Música & Áudio", icon: Theme.icons.music, desc: Theme.t("defaults.cat_audio_desc", "Reproduz faixas MP3, FLAC, OGG, WAV e AAC") }
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
                                                            text: (defCatCard.catInfo && defCatCard.catInfo.current_name) ? defCatCard.catInfo.current_name : Theme.t("defaults.not_set", "Não definido")
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 12
                                                            font.weight: Font.DemiBold
                                                            color: Theme.textColor
                                                            elide: Text.ElideRight
                                                        }
                                                        Text {
                                                            text: (defCatCard.catInfo && defCatCard.catInfo.current_desktop) ? defCatCard.catInfo.current_desktop : Theme.t("defaults.no_app_assoc", "Nenhum aplicativo associado")
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
                                                                text: (defCatCard.catInfo && defCatCard.catInfo.is_set) ? Theme.t("defaults.active_default", "Padrão Ativo") : "Não Definido"
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
                                                                text: Theme.t("defaults.input_placeholder", "Digitar app específico (ex: zen, firefox, code, dolphin, mpv)...")
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
                                                            text: Theme.t("defaults.save_btn", "Salvar")
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
                                                                win.showToast(Theme.t("toast.type_app_name", "Digite o nome de um app ou escolha na lista"));
                                                                return;
                                                            }
                                                            Quickshell.execDetached(["rice-default-apps", "set", defCatCard.modelData.id, val]);
                                                            win.showToast(Theme.t("toast.setting", "Definindo ") + val + " como padrão...");
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
                                                            text: defCatCard.isPicking ? "Fechar Lista" : Theme.t("defaults.choose_app", "Escolher App...")
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
                                                                    text: Theme.t("defaults.search_placeholder", "Pesquisar entre todos os aplicativos do sistema...")
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
                                                                            text: Theme.icons.confirm + Theme.t("defaults.current_tag", " Atual")
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
                                                                            win.showToast(Theme.t("toast.set_default", "Definido como padrão: ") + appItemRow.modelData.name);
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
                                    title: Theme.t("gaming.section_title", "Jogos & Placa Gráfica Dedicada")
                                    subtitle: Theme.t("gaming.section_sub", "Monitore a NVIDIA GeForce RTX 3050, GameMode e parâmetros da Steam")
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
                                                    text: Theme.t("gaming.gpu_temp", "Temperatura GPU")
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
                                                    text: Theme.t("gaming.vram_used", "VRAM Utilizada")
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
                                                    text: Theme.t("gaming.nvidia_driver", "Driver NVIDIA")
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
                                                text: Theme.t("gaming.gamemode_title", "Feral GameMode")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                color: Theme.textColor
                                            }
                                            Text {
                                                text: Theme.t("gaming.gamemode_desc", "Otimiza a CPU para priorizar taxas de quadros (FPS) e reduz a latência nos jogos")
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
                                    title: Theme.t("gaming.steam_params", "Parâmetros para Jogos da Steam")
                                    subtitle: Theme.t("gaming.steam_params_sub", "Clique em Copiar e cole nas Propriedades do Jogo -> Opções de Inicialização")
                                }

                                Repeater {
                                    model: [
                                        { id: "nvidia", title: "NVIDIA Dedicada (prime-run)", param: "prime-run %command%", desc: Theme.t("gaming.param_nvidia_desc", "Garante que o jogo rode diretamente na GPU dedicada NVIDIA RTX 3050.") },
                                        { id: "gamemode", title: "NVIDIA + Feral GameMode", param: "gamemoderun prime-run %command%", desc: Theme.t("gaming.param_gamemode_desc", "Combina aceleração máxima da GPU com prioridade de processador.") },
                                        { id: "compat", title: "Compatibilidade (Desativa NVAPI)", param: "PROTON_DISABLE_NVAPI=1 prime-run %command%", desc: Theme.t("gaming.param_compat_desc", "Use apenas se algum jogo der tela preta ou erro com DLSS.") }
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
                                                text: Theme.t("gaming.copy", "Copiar")
                                                primary: true
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-gaming", "copy-param", steamCard.modelData.id]);
                                                    showToast(Theme.t("toast.param_copied", "Parâmetro copiado para a área de transferência!"));
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
                                        text: Theme.t("gaming.open_steam", "Abrir Steam")
                                        onClicked: Quickshell.execDetached(["steam"])
                                    }
                                    ActionBtn {
                                        icon: Theme.icons.speed
                                        text: Theme.t("gaming.open_heroic", "Abrir Heroic Games")
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
                                    title: Theme.t("storage.section_title", "Armazenamento & Limpeza Segura")
                                    subtitle: Theme.t("storage.section_sub", "Monitore o SSD e libere gigabytes de caches temporários sem risco")
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
                                                text: Theme.t("storage.ssd_root", "SSD Principal (Partição Btrfs /)")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                color: Theme.textColor
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: (win.storageData ? win.storageData.root_used : "") + " " + Theme.t("storage.used_of", "usado de") + " " + (win.storageData ? win.storageData.root_total : "") + " (" + (win.storageData ? win.storageData.root_avail : "") + " " + Theme.t("storage.free", "livres") + ")"
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
                                            text: (win.storageData ? win.storageData.root_pct : 0) + "% " + Theme.t("storage.space_occupied", "do espaço ocupado")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.subtext
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("storage.section_recover", "Caches & Espaço Recuperável")
                                    subtitle: Theme.t("storage.section_recover_sub", "Arquivos que podem ser apagados com segurança para recuperar espaço")
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
                                                text: Theme.t("storage.pacman_cache", "Cache Pacman")
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
                                                text: Theme.t("storage.thumbnails", "Miniaturas")
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
                                                text: Theme.t("storage.trash", "Lixeira")
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
                                                text: Theme.t("storage.app_cache", "Caches de Apps")
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
                                                    text: Theme.t("storage.clean_pacman_title", "Limpar Pacotes Antigos do Pacman")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: Theme.t("storage.clean_pacman_desc", "Mantém as 2 últimas versões instaladas para rollback seguro e remove o restante.")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }
                                            ActionBtn {
                                                icon: Theme.icons.broom
                                                text: Theme.t("storage.clean_btn", "Limpar")
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
                                                    text: Theme.t("storage.clean_thumbs_title", "Limpar Miniaturas em Cache")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: Theme.t("storage.clean_thumbs_desc", "Remove thumbnails geradas para arquivos e vídeos. Elas serão recriadas se necessário.")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }
                                            ActionBtn {
                                                icon: Theme.icons.broom
                                                text: Theme.t("storage.clean_btn", "Limpar")
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
                                                    text: Theme.t("storage.empty_trash_title", "Esvaziar Lixeira do Usuário")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: Theme.t("storage.empty_trash_desc", "Apaga permanentemente os arquivos descartados em ~/.local/share/Trash.")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }
                                            ActionBtn {
                                                icon: Theme.icons.trash
                                                text: Theme.t("storage.empty_btn", "Esvaziar")
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
                                            text: Theme.t("storage.deep_clean_btn", "Executar Limpeza Profunda Completa")
                                            primary: true
                                            onClicked: {
                                                Quickshell.execDetached(["rice-storage", "clean-all"]);
                                                loadStorageProc.running = true;
                                                showToast(Theme.t("toast.deep_clean_done", "Limpeza profunda concluída!"));
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
                            visible: win.currentTab === 15 && !win.bindsSubPage
                            contentHeight: bindsCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: bindsCol
                                width: parent.width
                                spacing: 14

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ActionBtn {
                                        icon: Theme.icons.info
                                        text: Theme.t("binds.welcome_btn", "Abrir Guia de Boas-vindas")
                                        primary: true
                                        onClicked: {
                                            win.open = false;
                                            Quickshell.execDetached(["quickshell", "ipc", "call", "welcome", "open"]);
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    SectionHeader {
                                        title: Theme.t("binds.section_title", "Guia de Teclas & Atalhos")
                                        subtitle: Theme.t("binds.section_sub", "Clique num atalho para trocar a combinação de teclas. Botão direito devolve a original.")
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
                                                    text: Theme.t("binds.search_placeholder", "Buscar atalho...")
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
                                                text: Theme.t("binds.custom_btn", "Gerenciar Atalhos dos Programas")
                                                primary: true
                                                onClicked: {
                                                    loadAppBindsProc.running = true;
                                                    win.bindsSubPage = true;
                                                }
                                            }
                                        }
                                    }
                                }

                                Repeater {
                                    model: [
                                        {
                                            cat: Theme.t("binds.cat_windows", "Janelas & Navegação"),
                                            binds: [
                                                { key: "Super + Q", action: Theme.t("binds.act_kitty", "Abrir Terminal Kitty") },
                                                { key: "Super + C", action: Theme.t("binds.act_close", "Fechar Janela Ativa") },
                                                { key: "Alt + F4", action: Theme.t("binds.act_close_alt", "Fechar Janela Ativa (Padrão Windows)") },
                                                { key: "Super + F", action: Theme.t("binds.act_fullscreen", "Alternar Tela Cheia (Fullscreen)") },
                                                { key: "Super + Shift + V", action: Theme.t("binds.act_floating", "Alternar Janela Flutuante") },
                                                { key: "Super + P", action: Theme.t("binds.act_pseudo", "Alternar Modo Pseudo-Tiling") },
                                                { key: "Super + J", action: Theme.t("binds.act_split", "Alternar Divisão Horizontal / Vertical") },
                                                { key: "Super + Setas", action: Theme.t("binds.act_focus", "Mudar Foco entre Janelas") },
                                                { key: "Super + 1..9", action: Theme.t("binds.act_workspace", "Mudar para Área de Trabalho (Workspace)") },
                                                { key: "Super + Shift + 1..9", action: Theme.t("binds.act_movetoworkspace", "Mover Janela para Área de Trabalho") },
                                                { key: "Super + A", action: Theme.t("binds.act_scratchpad", "Abrir Área Especial (Scratchpad)") }
                                            ]
                                        },
                                        {
                                            cat: Theme.t("binds.cat_rice", "Aplicativos & Ferramentas do Rice"),
                                            binds: [
                                                { key: "Ctrl + Alt + Del", action: Theme.t("binds.act_powermenu", "Menu de Energia / Desligar / Suspender") },
                                                { key: "Super / Super + R", action: Theme.t("binds.act_launcher", "Menu de Aplicativos (Launcher Quickshell)") },
                                                { key: "Super + E", action: Theme.t("binds.act_dolphin", "Gerenciador de Pastas (Dolphin)") },
                                                { key: "Super + I", action: Theme.t("binds.act_ricepanel", "Painel de Controle Rice (Esta Central Gráfica)") },
                                                { key: "Super + S", action: Theme.t("binds.act_wallpaper", "Trocar Papel de Parede (Waywallen Switcher)") },
                                                { key: "Super + V", action: Theme.t("binds.act_clipboard", "Histórico da Área de Transferência") },
                                                { key: "Super + Ctrl + V", action: Theme.t("binds.act_clipboard_fav", "Favoritos da Área de Transferência") },
                                                { key: "Super + B", action: Theme.t("binds.act_blur", "Alternar Desfoque de Janelas (Blur On/Off)") },
                                                { key: "Super + W", action: Theme.t("binds.act_widgets", "Editar Widgets da Área de Trabalho") },
                                                { key: "Super + N", action: Theme.t("binds.act_notifcenter", "Abrir Central de Notificações") },
                                                { key: "Super + Shift + N", action: Theme.t("binds.act_dnd", "Alternar Não Perturbe (DND)") },
                                                { key: "Super + L", action: Theme.t("binds.act_lock", "Bloquear Tela (Hyprlock)") },
                                                { key: "Alt + Tab", action: Theme.t("binds.act_alttab", "Alternador de Janelas com Miniaturas") }
                                            ]
                                        },
                                        {
                                            cat: Theme.t("binds.cat_capture", "Captura & Gravação de Tela"),
                                            binds: [
                                                { key: "Print / Super+Shift+S", action: Theme.t("binds.act_screenshot_region", "Captura de Região (cancelar = tela inteira)") },
                                                { key: "Super + Alt + S", action: Theme.t("binds.act_screenshot_swappy", "Captura com Editor de Anotações (Swappy)") },
                                                { key: "Shift + Print", action: Theme.t("binds.act_screenshot_full", "Captura da Tela Inteira") },
                                                { key: "Ctrl + Print", action: Theme.t("binds.act_screenshot_window", "Captura da Janela Ativa") },
                                                { key: "Super + Shift + R", action: Theme.t("binds.act_record_region", "Gravar Vídeo de Região com Áudio") },
                                                { key: "Super + Ctrl + Shift + R", action: Theme.t("binds.act_record_full", "Gravar Vídeo da Tela Inteira") }
                                            ]
                                        },
                                        {
                                            cat: Theme.t("binds.cat_media", "Áudio & Multimídia"),
                                            binds: [
                                                { key: "Volume + / -", action: Theme.t("binds.act_vol", "Aumentar / Diminuir Volume") },
                                                { key: "Mute", action: Theme.t("binds.act_mute", "Silenciar / Reativar Som") },
                                                { key: "NumLock", action: Theme.t("binds.act_mic_mute", "Silenciar Microfone Instantaneamente") },
                                                { key: "Brilho + / -", action: Theme.t("binds.act_bright", "Aumentar / Diminuir Brilho do Monitor") },
                                                { key: "Play / Pause", action: Theme.t("binds.act_playpause", "Reproduzir / Pausar Música") }
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
                                                    id: guideBind
                                                    required property var modelData
                                                    // O guia era só leitura. Agora cada atalho que o
                                                    // rice define numa linha sozinha pode ser trocado
                                                    // daqui: o rice-app-binds desfaz o original e
                                                    // religa a mesma ação na tecla nova.
                                                    readonly property var info: win.systemBindInfo(guideBind.modelData.key)
                                                    readonly property bool editable: guideBind.info !== null && guideBind.info.customizable
                                                    readonly property bool changed: guideBind.info !== null && guideBind.info.overridden
                                                    implicitHeight: 34
                                                    implicitWidth: bindRow.implicitWidth + 20
                                                    radius: 8
                                                    color: guideArea.containsMouse && guideBind.editable ? Theme.tileHigh : Theme.tile
                                                    border.width: 1
                                                    border.color: guideBind.changed ? Theme.primary
                                                                                    : Theme.withAlpha(Theme.outline, 0.2)

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
                                                                // Só troca o texto quando a combinação
                                                                // foi realmente alterada: senão o guia
                                                                // perderia a grafia amigável ("Super +
                                                                // Setas") em favor do formato interno.
                                                                text: guideBind.changed ? guideBind.info.current
                                                                                        : guideBind.modelData.key
                                                                font.family: Theme.monoFamily
                                                                font.pixelSize: 10
                                                                font.weight: Font.Bold
                                                                color: Theme.primary
                                                            }
                                                        }

                                                        Text {
                                                            text: guideBind.modelData.action
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 11
                                                            color: Theme.textColor
                                                        }

                                                        Text {
                                                            visible: guideBind.editable
                                                            text: guideBind.changed ? Theme.icons.restore : Theme.icons.pencil
                                                            font.family: Theme.iconFontFamily
                                                            font.pixelSize: 12
                                                            color: guideArea.containsMouse ? Theme.primary : Theme.subtext
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: guideArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        enabled: guideBind.editable
                                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: mouse => {
                                                            if (mouse.button === Qt.RightButton || guideBind.changed) {
                                                                // botão direito (ou um já trocado) devolve o original
                                                                saveSysBindProc.command = ["rice-app-binds", "override-reset",
                                                                                           guideBind.modelData.key];
                                                                saveSysBindProc.running = true;
                                                                win.showToast(Theme.t("toast.bind_restored", "Atalho original restaurado"));
                                                            } else {
                                                                win.startSysBindCapture(guideBind.modelData.key, guideBind.modelData.action);
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

                        // ============ ABA 15b: GERENCIAR ATALHOS DOS PROGRAMAS ============
                        // Sub-aba aberta pelo botão do guia. Aqui a lista é por
                        // programa: cada linha mostra o atalho que ele tem (ou
                        // que não tem) e deixa gravar, trocar ou apagar na hora.
                        Flickable {
                            anchors.fill: parent
                            visible: win.currentTab === 15 && win.bindsSubPage
                            contentHeight: subBindsCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: subBindsCol
                                width: parent.width
                                spacing: 14

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ActionBtn {
                                        icon: Theme.icons.chevronRight
                                        text: Theme.t("binds.sub_back", "Voltar ao guia")
                                        onClicked: {
                                            win.bindsSubPage = false;
                                            win.bindRecordingFor = "";
                                            win.bindCapturing = false;
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    ActionBtn {
                                        icon: Theme.icons.console
                                        text: Theme.t("binds.sub_advanced", "Editar o arquivo (avançado)")
                                        onClicked: {
                                            Quickshell.execDetached(["rice-edit-user-binds"]);
                                            win.showToast(Theme.t("binds.opened_toast", "Abrindo user-binds.lua..."));
                                        }
                                    }
                                }

                                SectionHeader {
                                    title: Theme.t("binds.sub_title", "Atalhos dos Programas")
                                    subtitle: Theme.t("binds.sub_desc", "Clique em Definir atalho, aperte a combinação de teclas e pronto. Esc cancela.")
                                }

                                // Faixa de captura em andamento
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: win.bindCapturing
                                    radius: 12
                                    color: Qt.rgba(1, 0.65, 0.2, 0.12)
                                    border.width: 1
                                    border.color: Theme.primary
                                    implicitHeight: 54

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12
                                        Text {
                                            text: Theme.icons.cursor
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 18
                                            color: Theme.primary
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                text: Theme.t("binds.sub_capturing", "Aperte a combinação de teclas agora...")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                color: Theme.textColor
                                            }
                                            Text {
                                                text: win.bindRecordingName + " · " + Theme.t("binds.sub_capturing_hint", "Esc cancela")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.subtext
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: win.bindConflict !== ""
                                    wrapMode: Text.WordWrap
                                    text: Theme.t("binds.app_conflict", "Atenção: essa combinação já era usada por outro atalho do sistema.")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: "#ffb347"
                                }

                                // ---- programas que já têm atalho ----
                                Text {
                                    Layout.fillWidth: true
                                    visible: win.appBinds.length > 0
                                    text: Theme.t("binds.sub_with", "Programas com atalho")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: Theme.subtext
                                }

                                Repeater {
                                    model: win.appBinds
                                    delegate: Rectangle {
                                        id: boundRow
                                        required property var modelData
                                        // "managed" = criado por aqui, então dá para trocar e
                                        // apagar. Os outros vêm do hyprland.lua do rice ou de
                                        // linhas que a pessoa escreveu à mão: aparecem para ela
                                        // saber que existem, mas não são mexidos daqui.
                                        readonly property bool managed: (boundRow.modelData.source || "managed") === "managed"
                                        Layout.fillWidth: true
                                        implicitHeight: 52
                                        radius: 10
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: boundRow.managed ? Theme.withAlpha(Theme.primary, 0.35)
                                                                       : Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 12

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: boundRow.modelData.name
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: boundRow.modelData.command
                                                    font.family: Theme.monoFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                    elide: Text.ElideMiddle
                                                }
                                            }

                                            Rectangle {
                                                implicitWidth: Math.max(100, boundCombo.implicitWidth + 20)
                                                implicitHeight: 28
                                                radius: 7
                                                color: Theme.withAlpha(Theme.primary, 0.18)
                                                Text {
                                                    id: boundCombo
                                                    anchors.centerIn: parent
                                                    text: boundRow.modelData.combo
                                                    font.family: Theme.monoFamily
                                                    font.pixelSize: 11
                                                    font.weight: Font.DemiBold
                                                    color: Theme.primary
                                                }
                                            }

                                            Text {
                                                visible: !boundRow.managed
                                                text: (boundRow.modelData.source === "system")
                                                    ? Theme.t("binds.sub_from_rice", "atalho do rice")
                                                    : Theme.t("binds.sub_from_file", "escrito à mão")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                color: Theme.subtext
                                            }

                                            ActionBtn {
                                                visible: boundRow.managed
                                                icon: Theme.icons.pencil
                                                text: Theme.t("binds.sub_change", "Trocar")
                                                onClicked: win.startBindCapture(boundRow.modelData.command, boundRow.modelData.name)
                                            }

                                            Rectangle {
                                                visible: boundRow.managed
                                                implicitWidth: 28
                                                implicitHeight: 28
                                                radius: 8
                                                color: rmRowArea.containsMouse ? Theme.critical : "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Theme.icons.trash
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 14
                                                    color: rmRowArea.containsMouse ? "#ffffff" : Theme.subtext
                                                }
                                                MouseArea {
                                                    id: rmRowArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        saveAppBindProc.command = ["rice-app-binds", "remove", boundRow.modelData.combo];
                                                        saveAppBindProc.running = true;
                                                        win.showToast(Theme.t("toast.bind_removed", "Atalho removido"));
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // ---- procurar um programa para dar atalho ----
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 6
                                    spacing: 12

                                    Text {
                                        text: Theme.t("binds.sub_add", "Dar atalho a outro programa")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: Theme.subtext
                                    }
                                    Item { Layout.fillWidth: true }

                                    Rectangle {
                                        implicitWidth: 260
                                        implicitHeight: 32
                                        radius: 8
                                        color: Theme.background
                                        border.width: 1
                                        border.color: subBindSearch.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

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
                                                id: subBindSearch
                                                Layout.fillWidth: true
                                                verticalAlignment: TextInput.AlignVCenter
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                color: Theme.textColor
                                                selectByMouse: true
                                                onTextChanged: win.bindAppQuery = text
                                                Text {
                                                    anchors.fill: parent
                                                    verticalAlignment: Text.AlignVCenter
                                                    visible: subBindSearch.text === ""
                                                    text: Theme.t("binds.app_ph2", "Procurar programa...")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    color: Theme.subtext
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: win.bindAppQuery.trim() === ""
                                    text: Theme.t("binds.sub_search_hint", "Digite o nome de um programa acima para dar um atalho a ele.")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.subtext
                                }

                                Repeater {
                                    model: win.bindAppsFiltered
                                    delegate: Rectangle {
                                        id: freeRow
                                        required property var modelData
                                        readonly property string cmd: freeRow.modelData.exec || freeRow.modelData.name
                                        Layout.fillWidth: true
                                        implicitHeight: 48
                                        radius: 10
                                        color: Theme.tile
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.outline, 0.2)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 12

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: freeRow.modelData.name
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: freeRow.cmd
                                                    font.family: Theme.monoFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                    elide: Text.ElideMiddle
                                                }
                                            }

                                            Text {
                                                text: Theme.t("binds.sub_none", "sem atalho")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.subtext
                                            }

                                            ActionBtn {
                                                icon: Theme.icons.plus
                                                primary: true
                                                text: Theme.t("binds.sub_set", "Definir atalho")
                                                onClicked: win.startBindCapture(freeRow.cmd, freeRow.modelData.name)
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
                                    title: Theme.t("sys.section_snap", "Pontos de Restauração Btrfs (Snapshots de Segurança)")
                                    subtitle: Theme.t("sys.section_snap_sub", "Crie pontos de restauração antes de atualizar o sistema para desfazer qualquer problema pelo Limine")
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    ActionBtn {
                                        icon: Theme.icons.plus
                                        text: Theme.t("sys.create_snap_btn", "Criar Ponto de Restauração Agora")
                                        primary: true
                                        onClicked: {
                                            Quickshell.execDetached(["rice-snapshots", "create", "Snapshot Manual do Usuário"]);
                                            win.showToast(Theme.t("toast.snapshot_creating", "Criando snapshot Btrfs..."));
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
                                                            win.showToast(Theme.t("toast.snapshot_deleting", "Excluindo snapshot #") + snapCard.modelData.id);
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
                                    title: Theme.t("sys.section_autorepair", "Auto-Reparo & Soluções Rápidas de Um Clique")
                                    subtitle: Theme.t("sys.section_autorepair_sub", "Ferramentas práticas para resolver problemas comuns sem abrir o terminal ou digitar comandos")
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
                                                    text: Theme.t("sys.audio_repair_title", "Reiniciar Sistema de Áudio (PipeWire)")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: Theme.t("sys.audio_repair_desc", "Se o som parou ou o microfone não responde após conectar um fone/headset.")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }

                                            ActionBtn {
                                                icon: Theme.icons.refresh
                                                text: Theme.t("sys.audio_repair_btn", "Reiniciar Áudio")
                                                primary: true
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-maintenance", "audio"]);
                                                    win.showToast(Theme.t("toast.pipewire_restart", "Reiniciando PipeWire e WirePlumber..."));
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
                                                    text: Theme.t("sys.pacman_unlock_title", "Destravar Pacman (Remover db.lck)")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: Theme.t("sys.pacman_unlock_desc", "Resolve o erro 'banco de dados está bloqueado' se o terminal fechou durante um update.")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }

                                            ActionBtn {
                                                icon: Theme.icons.verified
                                                text: Theme.t("sys.pacman_unlock_btn", "Destravar Pacman")
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
                                                    text: Theme.t("sys.clean_disk_title", "Limpeza de Disco & Caches Antigos")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: Theme.t("sys.clean_disk_desc", "Remove versões antigas de pacotes do pacman e miniaturas expiradas com segurança.")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }

                                            ActionBtn {
                                                icon: Theme.icons.disk
                                                text: Theme.t("sys.clean_disk_btn", "Limpar Caches")
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-maintenance", "cleancache"]);
                                                    win.showToast(Theme.t("toast.cleaning_cache", "Limpando caches do sistema..."));
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
                                                    text: Theme.t("sys.doctor_title", "Assistente de Diagnóstico (Rice Doctor)")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textColor
                                                }
                                                Text {
                                                    text: Theme.t("sys.doctor_desc", "Varredura completa de integridade de áudio, GPU, Waywallen, SDDM e zRAM.")
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                }
                                            }

                                            ActionBtn {
                                                icon: Theme.icons.console
                                                text: Theme.t("sys.doctor_btn", "Executar Rice Doctor")
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
                        // ABA 17: PROGRAMAS & ATUALIZAÇÕES
                        // ==========================================
                        // Esta aba deixou de ser um "catálogo de aplicativos": o Pamac
                        // (ou o gerenciador gráfico que o usuário tiver) faz isso muito
                        // melhor. Aqui ficou só o que ele não faz — contagem unificada
                        // de atualizações, atualização das dotfiles do rice e kits de
                        // primeira instalação para quem está chegando do Windows.
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
                                spacing: 16

                                // ------------------------------------------ atualizações
                                SectionHeader {
                                    title: Theme.t("store.updates_title", "Atualizações do sistema")
                                    subtitle: Theme.t("store.updates_sub", "Programas, drivers e correções de segurança pendentes")
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 96
                                    radius: 14
                                    color: Theme.tile
                                    border.width: 1
                                    border.color: win.softwareUpdatesData.sys_count > 0
                                        ? Theme.withAlpha("#f59e0b", 0.5)
                                        : Theme.withAlpha("#10b981", 0.4)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 16

                                        Rectangle {
                                            implicitWidth: 56
                                            implicitHeight: 56
                                            radius: 14
                                            color: win.softwareUpdatesData.sys_count > 0
                                                ? Theme.withAlpha("#f59e0b", 0.18)
                                                : Theme.withAlpha("#10b981", 0.18)
                                            Text {
                                                anchors.centerIn: parent
                                                text: win.softwareUpdatesData.sys_count > 0 ? Theme.icons.update : Theme.icons.confirm
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 26
                                                color: win.softwareUpdatesData.sys_count > 0 ? "#f59e0b" : "#10b981"
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3

                                            Text {
                                                text: win.softwareUpdatesData.sys_count > 0
                                                    ? win.softwareUpdatesData.sys_count + " " + Theme.t("store.updates_pending", "atualizações pendentes")
                                                    : Theme.t("store.up_to_date", "Sistema em dia")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 16
                                                font.weight: Font.Bold
                                                color: Theme.textColor
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                // Detalhe por origem: o contador antigo só via os
                                                // repositórios oficiais e dizia "tudo em dia" com
                                                // dezenas de pacotes do AUR pendentes.
                                                text: {
                                                    const d = win.softwareUpdatesData;
                                                    if ((d.sys_count || 0) === 0)
                                                        return Theme.t("store.checked_at", "Verificado às ") + (d.checked_at || "--");
                                                    const parts = [];
                                                    if (d.repo_count > 0) parts.push(d.repo_count + " " + Theme.t("store.from_repo", "oficiais"));
                                                    if (d.aur_count > 0) parts.push(d.aur_count + " " + Theme.t("store.from_aur", "do AUR"));
                                                    if (d.flatpak_count > 0) parts.push(d.flatpak_count + " Flatpak");
                                                    return parts.join("  ·  ");
                                                }
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.subtext
                                                elide: Text.ElideRight
                                            }
                                        }

                                        ActionBtn {
                                            visible: win.softwareUpdatesData.sys_count > 0
                                            icon: Theme.icons.update
                                            text: Theme.t("store.update_all", "Atualizar tudo")
                                            primary: true
                                            onClicked: {
                                                Quickshell.execDetached(["rice-software", "update-system"]);
                                                win.showToast(Theme.t("toast.update_window", "Janela de atualização aberta no terminal!"));
                                            }
                                        }

                                        ActionBtn {
                                            icon: Theme.icons.refresh
                                            text: Theme.t("store.check_again", "Verificar")
                                            onClicked: {
                                                loadSoftwareUpdatesProc.running = true;
                                                win.showToast(Theme.t("toast.checking_updates", "Verificando atualizações..."));
                                            }
                                        }
                                    }
                                }

                                // -------------------------------------------- loja real
                                SectionHeader {
                                    title: Theme.t("store.browse_title", "Procurar e instalar programas")
                                    subtitle: Theme.t("store.browse_sub", "A loja do sistema tem busca, avaliações, AUR e Flatpak — é lá que dá para instalar qualquer programa.")
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 70
                                    radius: 14
                                    color: storeArea.containsMouse ? Theme.tileHigh : Theme.tile
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.primary, 0.35)

                                    Behavior on color { ColorAnimation { duration: 140 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 14

                                        Rectangle {
                                            implicitWidth: 40
                                            implicitHeight: 40
                                            radius: 10
                                            color: Theme.withAlpha(Theme.primary, 0.2)
                                            Text {
                                                anchors.centerIn: parent
                                                text: Theme.icons.packages
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 20
                                                color: Theme.primary
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text {
                                                text: Theme.t("store.open_store", "Abrir a loja de programas")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 14
                                                font.weight: Font.Bold
                                                color: Theme.textColor
                                            }
                                            Text {
                                                text: win.softwareUpdatesData.store && win.softwareUpdatesData.store !== ""
                                                    ? win.softwareUpdatesData.store
                                                    : Theme.t("store.no_store", "Nenhuma instalada — clique para instalar o Pamac")
                                                font.family: Theme.monoFamily
                                                font.pixelSize: 10
                                                color: Theme.subtext
                                            }
                                        }

                                        Text {
                                            text: Theme.icons.chevronRight
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 18
                                            color: Theme.primary
                                        }
                                    }

                                    MouseArea {
                                        id: storeArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            win.open = false;
                                            Quickshell.execDetached(["rice-software", "open-store"]);
                                        }
                                    }
                                }

                                // ------------------------------------ atualizador do rice
                                SectionHeader {
                                    title: Theme.t("store.rice_section", "Atualizador do hollow-wired")
                                    subtitle: Theme.t("store.rice_section_sub", "As melhorias e correções do próprio desktop chegam por aqui — nenhum gerenciador de pacotes cuida disso.")
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: riceCol.implicitHeight + 32
                                    radius: 14
                                    color: Theme.tile
                                    border.width: 1
                                    border.color: win.riceHasUpdate
                                        ? Theme.withAlpha(Theme.primary, 0.55)
                                        : (win.riceCheckFailed ? Theme.withAlpha("#f59e0b", 0.45) : Theme.withAlpha("#10b981", 0.4))

                                    ColumnLayout {
                                        id: riceCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 16
                                        spacing: 12

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 16

                                            Rectangle {
                                                implicitWidth: 56
                                                implicitHeight: 56
                                                radius: 14
                                                color: win.riceHasUpdate
                                                    ? Theme.withAlpha(Theme.primary, 0.18)
                                                    : (win.riceCheckFailed ? Theme.withAlpha("#f59e0b", 0.18) : Theme.withAlpha("#10b981", 0.18))
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: win.riceHasUpdate ? Theme.icons.update
                                                        : (win.riceCheckFailed ? Theme.icons.alert : Theme.icons.confirm)
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 26
                                                    color: win.riceHasUpdate ? Theme.primary
                                                        : (win.riceCheckFailed ? "#f59e0b" : "#10b981")
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 3

                                                Text {
                                                    text: win.riceHasUpdate
                                                        ? (win.riceInfo.count || 0) + " " + Theme.t("store.rice_available", "atualizações do rice disponíveis")
                                                        : (win.riceCheckFailed
                                                            ? Theme.t("store.rice_offline", "Não deu para verificar agora")
                                                            : Theme.t("store.rice_latest", "Você está na versão mais recente"))
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 16
                                                    font.weight: Font.Bold
                                                    color: Theme.textColor
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: {
                                                        const info = win.riceInfo || ({});
                                                        if (win.riceCheckFailed)
                                                            return info.message || Theme.t("store.rice_offline_sub", "Verifique a conexão com a internet e tente de novo.");
                                                        let line = Theme.t("store.rice_version", "Versão instalada ") + (info.local || info.hash || "?");
                                                        if (info.local_date) line += "  ·  " + Theme.t("store.rice_from", "de ") + info.local_date;
                                                        if (win.riceHasUpdate && info.remote)
                                                            line += "  →  " + info.remote + (info.remote_date ? " (" + info.remote_date + ")" : "");
                                                        return line;
                                                    }
                                                    font.family: Theme.monoFamily
                                                    font.pixelSize: 10
                                                    color: Theme.subtext
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            ActionBtn {
                                                icon: Theme.icons.refresh
                                                text: Theme.t("store.rice_check", "Verificar")
                                                onClicked: {
                                                    loadRiceUpdateProc.running = true;
                                                    win.showToast(Theme.t("toast.checking_updates", "Verificando atualizações..."));
                                                }
                                            }

                                            ActionBtn {
                                                visible: win.riceHasUpdate
                                                icon: Theme.icons.update
                                                text: Theme.t("store.rice_update_btn", "Atualizar o rice")
                                                primary: true
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-software", "update-rice"]);
                                                    win.showToast(Theme.t("toast.dotfiles_updater", "Atualizador de Dotfiles aberto!"));
                                                }
                                            }

                                            // O rice-update também é um "conserta problemas":
                                            // notificações presas, serviços caídos, arquivos de
                                            // estado corrompidos e atualizações que ficaram
                                            // pela metade.
                                            ActionBtn {
                                                icon: Theme.icons.health
                                                text: Theme.t("store.rice_fix_btn", "Procurar e consertar problemas")
                                                onClicked: {
                                                    Quickshell.execDetached(["rice-update", "fix-gui"]);
                                                    win.showToast(Theme.t("toast.rice_fix", "Procurando problemas no rice..."));
                                                }
                                            }
                                        }

                                        // Lista do que vem na atualização (até 5 novidades).
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            visible: win.riceHasUpdate && (win.riceInfo.commits || []).length > 0
                                            spacing: 4

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 1
                                                color: Theme.withAlpha(Theme.outline, 0.2)
                                            }

                                            Text {
                                                text: Theme.t("store.rice_changes", "O que vem nesta atualização:")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                color: Theme.subtext
                                            }

                                            Repeater {
                                                model: win.riceInfo.commits || []
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    spacing: 8
                                                    Text {
                                                        text: "•"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        color: Theme.primary
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        color: Theme.textColor
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: Theme.t("store.rice_note", "A atualização faz uma cópia de segurança das suas configurações antes de aplicar, e mantém dock, widgets, atalhos e cores personalizados.")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.withAlpha(Theme.subtext, 0.8)
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }

                        // ==========================================
                        // ABA 18: CUSTOMIZAÇÃO DO SHELL (HUB, SIDEBAR, DOCK)
                        // ==========================================
                        Flickable {
                            id: shellCustomTab
                            anchors.fill: parent
                            visible: win.currentTab === 18
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
                                                            text: Theme.t("shell_custom.style_label", "Estilo: ") + ShellCustomization.getStyle(shellCustomTab.targetComp)
                                                                + "  ·  " + Theme.t("shell_custom.scale_label", "escala ") + Math.round(ShellCustomization.getScale(shellCustomTab.targetComp) * 100) + "%"
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
                                                text: Theme.t("shell_custom.formats_desc", "PNG, JPG, SVG, WebP ou GIF")
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

    // ================= SELETOR DE CORES (RODA HSV) =================
    // O painel só mostrava a paleta extraída do wallpaper e deixava copiar o
    // HEX. Agora dá para trocar qualquer cor à mão: as escolhas ficam num
    // arquivo separado (color-overrides.json) e são reaplicadas por cima de
    // cada nova paleta, então trocar o wallpaper não apaga o que foi ajustado.
    property var colorOverrides: ({})
    property bool colorsFollowWallpaper: true
    property string pickerKey: ""
    property string pickerLabel: ""
    property string pickerBaseHex: "#000000"
    property real pickerHue: 0
    property real pickerSat: 0
    property real pickerVal: 1

    readonly property color pickerColor: Qt.hsva(win.pickerHue, win.pickerSat, win.pickerVal, 1)
    readonly property string pickerHex: {
        const c = win.pickerColor;
        const h = n => ("0" + Math.round(n * 255).toString(16)).slice(-2).toUpperCase();
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    function startBindCapture(command, name) {
        win.bindRecordingFor = command;
        win.bindRecordingName = name;
        win.bindConflict = "";
        win.bindCapturing = true;
        recordAppBindProc.running = true;
    }

    function openColorPicker(key, label, hex) {
        win.pickerKey = key;
        win.pickerLabel = label;
        win.pickerBaseHex = hex || "#000000";
        win.setPickerFromHex(hex);
    }

    function setPickerFromHex(hex) {
        const c = Qt.color(hex || "#000000");
        win.pickerHue = c.hsvHue >= 0 ? c.hsvHue : 0;
        win.pickerSat = c.hsvSaturation;
        win.pickerVal = c.hsvValue;
    }

    Process {
        id: loadColorOverridesProc
        command: ["rice-colors", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    win.colorOverrides = d.overrides || ({});
                    win.colorsFollowWallpaper = (d.auto !== undefined) ? d.auto : true;
                } catch (e) {}
            }
        }
    }

    Process {
        id: setColorProc
        command: ["rice-colors", "get"]
        onExited: (code, status) => {
            loadColorOverridesProc.running = true;
            loadWallustColorsProc.running = true;
        }
    }

    Rectangle {
        id: colorPickerOverlay
        anchors.fill: parent
        z: 9000
        visible: win.pickerKey !== ""
        color: Qt.rgba(0, 0, 0, 0.55)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: win.pickerKey = ""
        }

        Rectangle {
            anchors.centerIn: parent
            width: 380
            height: pickerCol.implicitHeight + 40
            radius: 20
            color: Theme.background
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.35)

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: pickerCol
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 14

                Text {
                    text: Theme.t("colors.picker_title", "Escolher cor") + ": " + win.pickerLabel
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: Theme.textColor
                }

                // Roda de matiz + saturação. Desenhada em fatias (matiz) com um
                // gradiente radial branco por cima (saturação) — o mesmo truque
                // usado por seletores nativos, sem depender de módulo extra.
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 220
                    implicitHeight: 220

                    Canvas {
                        id: wheel
                        anchors.fill: parent
                        onPaint: {
                            const ctx = getContext("2d");
                            const w = width, h = height;
                            const cx = w / 2, cy = h / 2, r = Math.min(cx, cy) - 2;
                            ctx.reset();
                            ctx.clearRect(0, 0, w, h);
                            for (let a = 0; a < 360; a++) {
                                const start = (a - 0.7) * Math.PI / 180;
                                const end = (a + 1.2) * Math.PI / 180;
                                ctx.beginPath();
                                ctx.moveTo(cx, cy);
                                ctx.arc(cx, cy, r, start, end);
                                ctx.closePath();
                                ctx.fillStyle = Qt.hsva(a / 360, 1, 1, 1);
                                ctx.fill();
                            }
                            const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
                            g.addColorStop(0, "#ffffff");
                            g.addColorStop(1, "#00ffffff");
                            ctx.beginPath();
                            ctx.arc(cx, cy, r, 0, Math.PI * 2);
                            ctx.fillStyle = g;
                            ctx.fill();
                        }
                    }

                    // Escurecimento conforme o brilho escolhido.
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(0, 0, 0, 1 - win.pickerVal)
                    }

                    Rectangle {
                        readonly property real radius_: (parent.width / 2 - 2) * win.pickerSat
                        width: 16
                        height: 16
                        radius: 8
                        color: "transparent"
                        border.width: 3
                        border.color: "#ffffff"
                        x: parent.width / 2 + radius_ * Math.cos(win.pickerHue * 2 * Math.PI) - 8
                        y: parent.height / 2 + radius_ * Math.sin(win.pickerHue * 2 * Math.PI) - 8
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: "#000000"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        function pick(mx, my) {
                            const cx = width / 2, cy = height / 2;
                            const r = Math.min(cx, cy) - 2;
                            const dx = mx - cx, dy = my - cy;
                            const dist = Math.sqrt(dx * dx + dy * dy);
                            let ang = Math.atan2(dy, dx);
                            if (ang < 0) ang += 2 * Math.PI;
                            win.pickerHue = ang / (2 * Math.PI);
                            win.pickerSat = Math.max(0, Math.min(1, dist / r));
                        }
                        onPressed: mouse => pick(mouse.x, mouse.y)
                        onPositionChanged: mouse => { if (pressed) pick(mouse.x, mouse.y); }
                    }
                }

                // Brilho
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: Theme.t("colors.brightness", "Brilho")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.subtext
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 16
                        radius: 8
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#000000" }
                            GradientStop { position: 1; color: Qt.hsva(win.pickerHue, win.pickerSat, 1, 1) }
                        }
                        Rectangle {
                            width: 14
                            height: 22
                            radius: 7
                            y: -3
                            x: Math.max(0, Math.min(parent.width - 14, win.pickerVal * parent.width - 7))
                            color: "#ffffff"
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.outline, 0.5)
                        }
                        MouseArea {
                            anchors.fill: parent
                            function pick(mx) { win.pickerVal = Math.max(0, Math.min(1, mx / width)); }
                            onPressed: mouse => pick(mouse.x)
                            onPositionChanged: mouse => { if (pressed) pick(mouse.x); }
                        }
                    }
                }

                // Prévia + HEX digitável
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        implicitWidth: 56
                        implicitHeight: 40
                        radius: 10
                        color: win.pickerColor
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.outline, 0.4)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 10
                        color: Theme.tile
                        border.width: 1
                        border.color: hexInput.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)

                        TextInput {
                            id: hexInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Theme.monoFamily
                            font.pixelSize: 14
                            color: Theme.textColor
                            selectByMouse: true
                            maximumLength: 7
                            text: win.pickerHex
                            onTextEdited: {
                                if (/^#?[0-9a-fA-F]{6}$/.test(text)) {
                                    win.setPickerFromHex(text.charAt(0) === "#" ? text : "#" + text);
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ActionBtn {
                        icon: Theme.icons.check
                        text: Theme.t("colors.apply", "Aplicar")
                        primary: true
                        onClicked: {
                            setColorProc.command = ["rice-colors", "set", win.pickerKey, win.pickerHex];
                            setColorProc.running = true;
                            win.showToast(Theme.t("toast.color_set", "Cor aplicada: ") + win.pickerHex);
                            win.pickerKey = "";
                        }
                    }

                    ActionBtn {
                        icon: Theme.icons.refresh
                        text: Theme.t("colors.use_wallpaper", "Cor do wallpaper")
                        onClicked: {
                            setColorProc.command = ["rice-colors", "unset", win.pickerKey];
                            setColorProc.running = true;
                            win.showToast(Theme.t("toast.color_unset", "Voltando à cor do wallpaper..."));
                            win.pickerKey = "";
                        }
                    }

                    Item { Layout.fillWidth: true }

                    ActionBtn {
                        icon: Theme.icons.close
                        text: Theme.t("colors.cancel", "Cancelar")
                        onClicked: win.pickerKey = ""
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
            loadRiceUpdateProc.running = true;
        }
    }
}
