import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "."

// Tela de especificações do PC (abre clicando no avatar da sidebar).
// Cartão central sobre um fundo escurecido; fecha clicando fora ou com Esc.
// Dados: fastfetch --format json (lido a cada abertura, ~20ms) + sysfs pra
// saúde da bateria + hyprctl pro Hyprland. Nada de OpenGL/Vulkan, que
// acordaria a NVIDIA só pra perguntar a versão.
PanelWindow {
    id: win

    property bool open: false
    visible: false
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: true

    WlrLayershell.namespace: "quickshell-sysinfo"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (open) {
            closeTimer.stop();
            visible = true;
            ff.running = true;
            bat.running = true;
        } else {
            closeTimer.restart();
        }
    }
    Timer { id: closeTimer; interval: 240; onTriggered: win.visible = false }

    // ================= dados =================
    property var d: ({})
    function mod(type) { return d[type] || null; }

    Process {
        id: ff
        command: ["fastfetch", "--format", "json", "-s",
            "Title:OS:Host:Kernel:Uptime:Packages:WM:Display:CPU:GPU:Memory:Swap:Disk:Battery:BIOS:Board:Locale:LocalIp:Font:Cursor:Sound"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const out = {};
                    for (const e of JSON.parse(text))
                        if (e.result !== undefined) out[e.type] = e.result;
                    win.d = out;
                } catch (err) {
                    console.log("SystemInfo: fastfetch inválido:", err);
                }
            }
        }
    }

    property real batHealth: 0
    property int batFull: 0
    property int batDesign: 0
    Process {
        id: bat
        command: ["bash", "-c", "cat /sys/class/power_supply/BAT1/charge_full /sys/class/power_supply/BAT1/charge_full_design 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split("\n").map(Number);
                if (v.length === 2 && v[1] > 0) {
                    win.batFull = v[0] / 1000;
                    win.batDesign = v[1] / 1000;
                    win.batHealth = v[0] / v[1];
                }
            }
        }
    }

    function gib(b) { return (b / 1073741824).toFixed(1) + " GiB"; }
    function fmtUptime(ms) {
        const s = Math.floor(ms / 1000);
        const dd = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (dd > 0 ? dd + "d " : "") + (h > 0 ? h + "h " : "") + m + "min";
    }

    // ================= componentes =================
    component Row2: RowLayout {
        property string label: ""
        property string value: ""
        visible: value !== ""
        Layout.fillWidth: true
        spacing: 10
        Text {
            Layout.preferredWidth: 78
            text: parent.label
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.subtext
        }
        Text {
            Layout.fillWidth: true
            text: parent.value
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.textColor
        }
    }

    component Bar2: ColumnLayout {
        property string label: ""
        property string value: ""
        property real frac: 0
        Layout.fillWidth: true
        spacing: 3
        RowLayout {
            Layout.fillWidth: true
            Text { text: parent.parent.label; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.subtext; Layout.fillWidth: true }
            Text { text: parent.parent.value; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.textColor }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 6
            radius: 3
            color: Theme.withAlpha(Theme.primary, 0.18)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, parent.parent.frac))
                height: parent.height
                radius: 3
                color: parent.parent.frac >= 0.9 ? Theme.critical : Theme.primary
                Behavior on width { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
            }
        }
    }

    component Section: Rectangle {
        property string icon: ""
        property string title: ""
        default property alias body: sectionCol.data
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.tileRadius
        color: Theme.tile

        ColumnLayout {
            id: sectionCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 5

            RowLayout {
                Layout.bottomMargin: 4
                spacing: 8
                Text {
                    text: parent.parent.parent.icon
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 18
                    color: Theme.primary
                }
                Text {
                    text: parent.parent.parent.title
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.textColor
                }
            }
        }
    }

    // ================= fundo =================
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, win.open ? 0.4 : 0)
        Behavior on color { ColorAnimation { duration: 220 } }
        MouseArea {
            anchors.fill: parent
            onClicked: win.open = false
        }
    }

    // ================= cartão =================
    Rectangle {
        id: card
        width: 980
        height: 600
        anchors.centerIn: parent
        radius: 24
        color: Theme.surface
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.25)
        focus: win.open
        Keys.onEscapePressed: win.open = false

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        // engole cliques pra não fechar ao clicar dentro do cartão
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            // ---------- cabeçalho ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: 20

                ClippingRectangle {
                    Layout.preferredWidth: 112
                    Layout.preferredHeight: 112
                    radius: 56
                    color: Theme.tileHigh
                    border.width: 3
                    border.color: Theme.primary
                    AnimatedImage {
                        anchors.fill: parent
                        source: "file://" + Quickshell.env("HOME") + "/.face.webp"
                        fillMode: Image.PreserveAspectCrop
                        playing: win.visible
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: setAvatarProc.running = true
                    }
                }

                Process {
                    id: setAvatarProc
                    command: ["rice-set-avatar"]
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: win.mod("Title") ? (win.mod("Title").fullUserName || win.mod("Title").userName) : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                        color: Theme.textColor
                    }
                    Text {
                        text: win.mod("Title") ? win.mod("Title").userName + "@" + win.mod("Title").hostName : ""
                        font.family: Theme.monoFamily
                        font.pixelSize: 13
                        color: Theme.subtext
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 6
                        Repeater {
                            model: [
                                { icon: Theme.icons.arch, text: win.mod("OS") ? win.mod("OS").prettyName : "" },
                                { icon: Theme.icons.monitor, text: win.mod("WM") ? "Hyprland " + win.mod("WM").version : "" },
                                { icon: Theme.icons.console, text: "fish · kitty" },
                                { icon: Theme.icons.clock, text: win.mod("Uptime") ? Theme.t("sysinfo.uptime_prefix", "ligado há ") + win.fmtUptime(win.mod("Uptime").uptime) : "" },
                                { icon: Theme.icons.laptop, text: win.mod("Host") ? win.mod("Host").vendor + " " + win.mod("Host").family : "" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                visible: modelData.text !== ""
                                implicitWidth: chipRow.implicitWidth + 20
                                implicitHeight: 28
                                radius: 14
                                color: Theme.tileHigh
                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.icon
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 14
                                        color: Theme.primary
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.textColor
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: 17
                    color: closeArea.containsMouse ? Theme.tileHigh : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: Theme.icons.close
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 18
                        color: Theme.subtext
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

            // ---------- grade de seções ----------
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 3
                rowSpacing: 10
                columnSpacing: 10

                Section {
                    icon: Theme.icons.info
                    title: Theme.t("sysinfo.system", "Sistema")
                    Row2 { label: "Distro"; value: win.mod("OS") ? win.mod("OS").prettyName + " (" + (win.mod("OS").buildID || "rolling") + ")" : "" }
                    Row2 { label: "Kernel"; value: win.mod("Kernel") ? win.mod("Kernel").release : "" }
                    Row2 { label: "WM"; value: win.mod("WM") ? win.mod("WM").prettyName + " " + win.mod("WM").version + " (" + win.mod("WM").protocolName + ")" : "" }
                    Row2 { label: "Shell"; value: "fish" }
                    Row2 { label: "Terminal"; value: "kitty" }
                    Row2 { label: "Idioma"; value: win.mod("Locale") || "" }
                    Row2 {
                        label: "Pacotes"
                        value: win.mod("Packages") ? win.mod("Packages").pacman + " pacman · "
                            + (win.mod("Packages").flatpakSystem + win.mod("Packages").flatpakUser) + " flatpak · "
                            + win.mod("Packages").appimage + " appimage" : ""
                    }
                }

                Section {
                    icon: Theme.icons.chip
                    title: Theme.t("sysinfo.cpu_gpu", "Processador e gráficos")
                    Row2 { label: "CPU"; value: win.mod("CPU") ? win.mod("CPU").cpu.replace("11th Gen ", "").replace("(R)", "").replace("(TM)", "") : "" }
                    Row2 { label: "Núcleos"; value: win.mod("CPU") ? win.mod("CPU").cores.physical + " núcleos · " + win.mod("CPU").cores.logical + " threads" : "" }
                    Row2 { label: "Frequência"; value: win.mod("CPU") ? (win.mod("CPU").frequency.base / 1000).toFixed(1) + " – " + (win.mod("CPU").frequency.max / 1000).toFixed(1) + " GHz" : "" }
                    Row2 { label: "Arquitetura"; value: win.mod("CPU") ? (win.mod("CPU").codeName || "") + " · " + win.mod("CPU").march : "" }
                    Repeater {
                        model: win.mod("GPU") || []
                        delegate: Row2 {
                            required property var modelData
                            required property int index
                            label: modelData.type === "Discrete" ? "GPU dedicada" : "GPU integrada"
                            value: modelData.vendor + " " + modelData.name + " · " + modelData.driver.replace(" (open source)", "")
                        }
                    }
                }

                Section {
                    icon: Theme.icons.memory
                    title: Theme.t("sysinfo.mem_storage", "Memória e armazenamento")
                    Bar2 {
                        label: "RAM"
                        value: win.mod("Memory") ? win.gib(win.mod("Memory").used) + " / " + win.gib(win.mod("Memory").total) : ""
                        frac: win.mod("Memory") ? win.mod("Memory").used / win.mod("Memory").total : 0
                    }
                    Repeater {
                        model: win.mod("Swap") || []
                        delegate: Bar2 {
                            required property var modelData
                            label: modelData.name.includes("zram") ? "zram (swap comprimido)" : "Swap"
                            value: win.gib(modelData.used) + " / " + win.gib(modelData.total)
                            frac: modelData.total > 0 ? modelData.used / modelData.total : 0
                        }
                    }
                    Repeater {
                        model: (win.mod("Disk") || []).filter(k => k.mountpoint === "/")
                        delegate: Bar2 {
                            required property var modelData
                            label: "Disco / (" + modelData.filesystem + ", " + modelData.mountFrom.replace("/dev/", "") + ")"
                            value: win.gib(modelData.bytes.used) + " / " + win.gib(modelData.bytes.total)
                            frac: modelData.bytes.used / modelData.bytes.total
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                Section {
                    icon: Theme.icons.monitor
                    title: Theme.t("sysinfo.screen_audio", "Tela e áudio")
                    Repeater {
                        model: win.mod("Display") || []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 5
                            Row2 { label: "Resolução"; value: modelData.output.width + "×" + modelData.output.height + " @ " + Math.round(modelData.output.refreshRate) + " Hz" }
                            Row2 {
                                label: "Tamanho"
                                value: modelData.physical && modelData.physical.width > 0
                                    ? (Math.sqrt(Math.pow(modelData.physical.width, 2) + Math.pow(modelData.physical.height, 2)) / 25.4).toFixed(1) + "\" · " + (modelData.type === "Builtin" ? "tela interna" : "externa")
                                    : ""
                            }
                            Row2 { label: "Painel"; value: modelData.name + (modelData.hdrStatus === "Unsupported" ? " · sem HDR" : "") }
                        }
                    }
                    Row2 { label: "Áudio"; value: win.mod("Sound") && win.mod("Sound").length ? win.mod("Sound")[0].platformApi : "" }
                    Row2 { label: "Fonte"; value: win.mod("Font") ? win.mod("Font").fonts.filter(x => x !== "")[0] || "" : "" }
                    Row2 { label: "Cursor"; value: win.mod("Cursor") ? win.mod("Cursor").theme + " (" + win.mod("Cursor").size + ")" : "" }
                }

                Section {
                    icon: (win.batDesign > 0 || (win.mod("Battery") && win.mod("Battery").length > 0)) ? Theme.icons.batHealth : Theme.icons.bolt
                    title: (win.batDesign > 0 || (win.mod("Battery") && win.mod("Battery").length > 0)) ? Theme.t("sysinfo.battery", "Bateria") : Theme.t("sysinfo.power", "Alimentação")
                    Bar2 {
                        visible: win.batDesign > 0
                        label: "Saúde (capacidade atual vs. de fábrica)"
                        value: win.batDesign > 0 ? Math.round(win.batHealth * 100) + "%" : "--"
                        frac: win.batHealth
                    }
                    Row2 {
                        visible: win.batDesign > 0
                        label: "Capacidade"
                        value: win.batDesign > 0 ? win.batFull + " / " + win.batDesign + " mAh" : ""
                    }
                    Row2 {
                        visible: win.batDesign === 0 && (!win.mod("Battery") || win.mod("Battery").length === 0)
                        label: "Tipo"
                        value: "Computador Desktop (Fonte AC contínua)"
                    }
                    Row2 {
                        visible: win.batDesign === 0 && (!win.mod("Battery") || win.mod("Battery").length === 0)
                        label: "Modo"
                        value: "Alimentação direta de alto desempenho"
                    }
                    Repeater {
                        model: win.mod("Battery") || []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 5
                            Row2 { label: "Ciclos"; value: modelData.cycleCount + " ciclos de carga" }
                            Row2 { label: "Modelo"; value: modelData.manufacturer + " " + modelData.modelName + " · " + modelData.technology }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                Section {
                    icon: Theme.icons.laptop
                    title: Theme.t("sysinfo.board_net", "Placa e rede")
                    Row2 { label: "Computador"; value: win.mod("Host") ? win.mod("Host").vendor + " " + win.mod("Host").name : "" }
                    Row2 { label: "Placa-mãe"; value: win.mod("Board") ? win.mod("Board").name + " (" + win.mod("Board").vendor + ")" : "" }
                    Row2 { label: "BIOS"; value: win.mod("BIOS") ? win.mod("BIOS").vendor + " " + win.mod("BIOS").version + " · " + win.mod("BIOS").date + " · " + win.mod("BIOS").type : "" }
                    Repeater {
                        model: win.mod("LocalIp") || []
                        delegate: Row2 {
                            required property var modelData
                            label: "IP " + modelData.name
                            value: modelData.ipv4 || ""
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    IpcHandler {
        target: "sysinfo"
        function toggle(): void { win.open = !win.open; }
    }
}
