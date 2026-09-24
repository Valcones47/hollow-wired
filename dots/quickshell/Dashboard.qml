import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Widgets
import "."

// Dashboard em grade de cards, no layout da Caelestia:
//
//   ┌ clima ┐┌ usuário / sistema ────┐┌ player ┐
//   └───────┘└───────────────────────┘│        │
//   ┌hora┐┌ calendário ───────┐┌recur┐│        │
//   └────┘└───────────────────┘└─────┘└────────┘
//
// Nomes de dia/mês escritos na mão (não locale do SO — saía em inglês).
Item {
    id: root

    readonly property var dayNames: Theme.locale === "en"
        ? ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        : ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"]
    readonly property var monthNames: Theme.locale === "en"
        ? ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        : ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
           "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"]

    property date now: new Date()
    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null

    // ---------- uptime (formatado em pt, não o "up 1 hour, 23 minutes") ----------
    property string uptimeText: "..."
    Timer {
        interval: 60000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: uptimeProc.running = true
    }
    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = Math.floor(parseFloat(text.split(" ")[0]));
                const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
                root.uptimeText = d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + m + "min" : m + " min";
            }
        }
    }

    property string distroText: "..."
    Process {
        command: ["bash", "-c", "grep '^PRETTY_NAME=' /etc/os-release | cut -d'\"' -f2"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.distroText = text.trim()
        }
    }

    // ---------- clima centralizado via WeatherService ----------
    readonly property string weatherTemp: WeatherService.temp
    readonly property string weatherDesc: WeatherService.desc
    readonly property string weatherPlace: WeatherService.place
    readonly property int weatherCode: WeatherService.code
    readonly property string weatherFeels: WeatherService.feels
    readonly property string weatherHumidity: WeatherService.humidity
    readonly property string weatherWind: WeatherService.wind
    readonly property string weatherSunrise: WeatherService.sunrise
    readonly property string weatherSunset: WeatherService.sunset
    readonly property var weatherDays: WeatherService.days
    function weatherIcon(code, hour) { return WeatherService.iconFor(code, hour); }

    // ---------- grade do calendário (inclui dias dos meses vizinhos) ----------
    readonly property var monthGrid: {
        const y = now.getFullYear(), m = now.getMonth();
        const firstDow = new Date(y, m, 1).getDay();
        const numDays = new Date(y, m + 1, 0).getDate();
        const prevDays = new Date(y, m, 0).getDate();
        const cells = [];
        for (let i = firstDow - 1; i >= 0; i--)
            cells.push({ day: prevDays - i, inMonth: false, isToday: false });
        for (let d = 1; d <= numDays; d++)
            cells.push({ day: d, inMonth: true, isToday: d === now.getDate() });
        let next = 1;
        while (cells.length < 42)
            cells.push({ day: next++, inMonth: false, isToday: false });
        return cells;
    }

    component Tile: Rectangle {
        radius: Theme.tileRadius
        color: Theme.tile
    }

    component Icon: Text {
        font.family: Theme.iconFontFamily
        color: Theme.primary
    }

    // Barra vertical de recurso (bindings diretos — com Repeater sobre um
    // array JS os delegates eram recriados a cada poll e a barra zerava).
    component ResourceBar: ColumnLayout {
        id: res
        property real value: 0
        property string icon: ""
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 8

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.preferredWidth: 8
            radius: 4
            color: Theme.withAlpha(Theme.primary, 0.18)

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                radius: 4
                height: Math.max(width, parent.height * Math.min(1, res.value))
                color: res.value >= 0.9 ? Theme.critical : Theme.primary
                Behavior on height { NumberAnimation { duration: Theme.ms(600); easing.type: Easing.OutCubic } }
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: res.icon
            font.family: Theme.iconFontFamily
            font.pixelSize: 15
            color: Theme.subtext
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.gap + 2

        // ================= esquerda =================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.gap + 2

            // ---------- linha 1: clima + usuário ----------
            RowLayout {
                Layout.fillWidth: true
                // layouts aninhados têm fillHeight=true por padrão — sem isso
                // essa linha engolia a altura toda e empurrava o calendário.
                Layout.fillHeight: false
                // 116 antes: cabia só ícone e temperatura. Subiu para acomodar
                // a sensação/umidade/vento/sol e a previsão dos próximos dias,
                // que já vinham na mesma resposta e eram descartadas.
                // Cresce com o conteúdo: com outra fonte ou escala (máquina de
                // outra pessoa) os 152 fixos cortavam a previsão dos dias.
                Layout.preferredHeight: Math.max(152, weatherCol.implicitHeight + 24)
                spacing: Theme.gap + 2

                Tile {
                    Layout.preferredWidth: 300
                    Layout.fillHeight: true

                    ColumnLayout {
                        id: weatherCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14

                            Icon {
                                text: root.weatherIcon(root.weatherCode, root.now.getHours())
                                font.pixelSize: 44
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: root.weatherTemp
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 26
                                    font.weight: Font.Medium
                                    color: Theme.textColor
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.weatherDesc
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.subtext
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: root.weatherPlace
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.withAlpha(Theme.subtext, 0.7)
                                }
                            }
                        }

                        // Sensação, umidade, vento e o sol — dados que já
                        // chegavam na mesma resposta.
                        Flow {
                            Layout.fillWidth: true
                            spacing: 10

                            Repeater {
                                model: [
                                    { i: Theme.icons.thermometer, v: root.weatherFeels },
                                    { i: Theme.icons.humidity,    v: root.weatherHumidity },
                                    { i: Theme.icons.wind,        v: root.weatherWind },
                                    { i: Theme.icons.sunrise,     v: root.weatherSunrise },
                                    { i: Theme.icons.sunset,      v: root.weatherSunset }
                                ]
                                delegate: Row {
                                    required property var modelData
                                    visible: modelData.v !== ""
                                    spacing: 4
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.modelData.i
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 12
                                        color: Theme.subtext
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.modelData.v
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.textColor
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        // Previsão dos próximos dias.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: root.weatherDays.length > 0

                            Repeater {
                                model: root.weatherDays
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: parent.modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        color: Theme.subtext
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.weatherIcon(parent.modelData.code, 12)
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 16
                                        color: Theme.textColor
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: parent.modelData.max + " / " + parent.modelData.min
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        color: Theme.textColor
                                    }
                                }
                            }
                        }
                    }
                }

                Tile {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 16

                        // Avatar: usa ~/.face.webp se existir, senão ícone neutro. Clique para trocar!
                        ClippingRectangle {
                            Layout.preferredWidth: 84
                            Layout.preferredHeight: 84
                            radius: 42
                            color: Theme.tileHigh

                            AnimatedImage {
                                id: face
                                anchors.fill: parent
                                source: "file://" + Quickshell.env("HOME") + "/.face.webp"
                                playing: visible
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                                asynchronous: true
                            }
                            Icon {
                                anchors.centerIn: parent
                                visible: face.status !== Image.Ready
                                text: Theme.icons.account
                                font.pixelSize: 56
                                color: Theme.subtext
                            }

                            // Botão interativo para trocar o avatar com 1 clique
                            MouseArea {
                                id: avatarMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: setAvatarProc.running = true

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 42
                                    color: Qt.rgba(0, 0, 0, 0.45)
                                    visible: avatarMa.containsMouse
                                    Icon {
                                        anchors.centerIn: parent
                                        text: Theme.icons.pencil
                                        font.pixelSize: 22
                                        color: "#ffffff"
                                    }
                                }
                            }
                        }

                        Process {
                            id: setAvatarProc
                            command: ["rice-set-avatar"]
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: Quickshell.env("USER")
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                color: Theme.textColor
                            }
                            Repeater {
                                model: [
                                    { icon: Theme.icons.arch, text: root.distroText },
                                    { icon: Theme.icons.monitor, text: "Hyprland" },
                                    { icon: Theme.icons.clock, text: Theme.t("dashboard.uptime", "ligado há ") + root.uptimeText }
                                ]
                                delegate: RowLayout {
                                    required property var modelData
                                    spacing: 8
                                    Icon {
                                        text: modelData.icon
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        text: modelData.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.subtext
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- linha 2: hora + calendário + recursos ----------
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.gap + 2

                // Bloco Dual: Relógio / Pomodoro Timer
                Tile {
                    id: clockPomoTile
                    Layout.preferredWidth: 124
                    Layout.fillHeight: true

                    property bool showPomodoro: PomodoroService.active

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        // Seletor de modo no topo: Relógio vs Pomodoro
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            spacing: 4

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 4
                                color: !clockPomoTile.showPomodoro ? Theme.withAlpha(Theme.primary, 0.22) : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰥔 " + Theme.t("dash.clock", "Relógio")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: !clockPomoTile.showPomodoro ? Font.Bold : Font.Normal
                                    color: !clockPomoTile.showPomodoro ? Theme.primary : Theme.subtext
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: clockPomoTile.showPomodoro = false
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 4
                                color: clockPomoTile.showPomodoro ? Theme.withAlpha(Theme.primary, 0.22) : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰄉 " + Theme.t("dash.pomodoro", "Pomodoro")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: clockPomoTile.showPomodoro ? Font.Bold : Font.Normal
                                    color: clockPomoTile.showPomodoro ? Theme.primary : Theme.subtext
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: clockPomoTile.showPomodoro = true
                                }
                            }
                        }

                        // Conteúdo: Relógio (padrão)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: !clockPomoTile.showPomodoro
                            spacing: 2

                            Item { Layout.fillHeight: true }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: Qt.formatDateTime(root.now, "HH")
                                font.family: Theme.fontFamily
                                font.pixelSize: 32
                                font.weight: Font.DemiBold
                                color: Theme.primary
                            }
                            Row {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 5
                                Repeater {
                                    model: 3
                                    Rectangle {
                                        width: 4; height: 4; radius: 2
                                        color: Theme.primary
                                    }
                                }
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: Qt.formatDateTime(root.now, "mm")
                                font.family: Theme.fontFamily
                                font.pixelSize: 32
                                font.weight: Font.DemiBold
                                color: Theme.primary
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 4
                                text: root.dayNames[root.now.getDay()].slice(0, 3) + ", " + root.now.getDate()
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.subtext
                            }

                            Item { Layout.fillHeight: true }
                        }

                        // Conteúdo: Pomodoro Timer
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: clockPomoTile.showPomodoro
                            spacing: 6

                            // Chips de modo (Foco 25m / Pausa 5m / Longa 15m)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Repeater {
                                    model: [
                                        { id: "work", label: Theme.t("dash.pomo_focus", "Foco") },
                                        { id: "shortBreak", label: Theme.t("dash.pomo_short", "Pausa") },
                                        { id: "longBreak", label: Theme.t("dash.pomo_long", "Longa") }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 18
                                        radius: 4
                                        color: PomodoroService.mode === modelData.id
                                            ? Theme.withAlpha(Theme.primary, 0.3)
                                            : Theme.tileHigh
                                        border.width: 1
                                        border.color: PomodoroService.mode === modelData.id
                                            ? Theme.primary : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                            font.weight: PomodoroService.mode === parent.modelData.id ? Font.Bold : Font.Normal
                                            color: PomodoroService.mode === parent.modelData.id ? Theme.primary : Theme.subtext
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: PomodoroService.setMode(parent.modelData.id)
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }

                            // Timer decrescente grande
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: PomodoroService.timeString
                                font.family: Theme.fontFamily
                                font.pixelSize: 26
                                font.weight: Font.Bold
                                color: PomodoroService.paused ? Theme.warning : Theme.primary
                            }

                            // Barra de progresso horizontal
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 4
                                radius: 2
                                color: Theme.tileHigh
                                Rectangle {
                                    height: parent.height
                                    radius: 2
                                    width: parent.width * PomodoroService.progress
                                    color: PomodoroService.paused ? Theme.warning : Theme.primary
                                    Behavior on width { NumberAnimation { duration: 250 } }
                                }
                            }

                            // Botões Iniciar / Pausar e Resetar
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    radius: 6
                                    color: PomodoroService.running
                                        ? Theme.withAlpha(Theme.warning, 0.25)
                                        : Theme.withAlpha(Theme.primary, 0.25)
                                    border.width: 1
                                    border.color: PomodoroService.running ? Theme.warning : Theme.primary

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: PomodoroService.running ? "󰏤" : "󰐊"
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 12
                                            color: PomodoroService.running ? Theme.warning : Theme.primary
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: PomodoroService.running
                                                ? Theme.t("dash.pomo_pause", "Pausar")
                                                : Theme.t("dash.pomo_start", "Iniciar")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: Theme.textColor
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: PomodoroService.toggle()
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    radius: 6
                                    color: Theme.tileHigh

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰑐"
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 13
                                        color: Theme.subtext
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: PomodoroService.reset()
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                // calendário
                Tile {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.monthNames[root.now.getMonth()] + " " + root.now.getFullYear()
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Theme.textColor
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            columns: 7
                            rowSpacing: 0
                            columnSpacing: 0

                            Repeater {
                                model: Theme.locale === "en" ? ["S", "M", "T", "W", "T", "F", "S"] : ["D", "S", "T", "Q", "Q", "S", "S"]
                                delegate: Text {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: Theme.subtext
                                }
                            }

                            Repeater {
                                model: root.monthGrid
                                delegate: Item {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 22; height: 22; radius: 11
                                        visible: modelData.isToday
                                        color: Theme.primary
                                    }
                                    // Dia com evento nos calendários da Agenda.
                                    Rectangle {
                                        visible: modelData.inMonth && (CalendarService.byDay[CalendarService.key(root.now.getFullYear(), root.now.getMonth(), modelData.day)] || []).length > 0
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        width: 3; height: 3; radius: 1.5
                                        color: modelData.isToday ? Theme.primary : Theme.subtext
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.day
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: modelData.isToday ? Font.Bold : Font.Normal
                                        color: modelData.isToday ? Theme.background
                                            : modelData.inMonth ? Theme.textColor
                                            : Theme.withAlpha(Theme.subtext, 0.35)
                                    }
                                }
                            }
                        }
                    }
                }

                // recursos: barras verticais CPU / RAM / disco
                Tile {
                    Layout.preferredWidth: 104
                    Layout.fillHeight: true

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 0

                        ResourceBar { value: SysStats.cpuUsage; icon: Theme.icons.cpu }
                        ResourceBar { value: SysStats.ramFrac; icon: Theme.icons.memory }
                        ResourceBar { value: SysStats.diskFrac; icon: Theme.icons.disk }
                    }
                }
            }
        }

        // ================= direita: player =================
        Tile {
            id: mediaTile
            Layout.preferredWidth: 236
            Layout.fillHeight: true

            Binding { target: MediaState; property: "levelWanted"; value: true; when: root.visible && root.player !== null && root.player.isPlaying }

            // MPRIS não empurra a posição continuamente — avança local e
            // resincroniza em eventos (mesma lógica da aba Mídia).
            property real pos: 0
            Timer {
                interval: 1000
                running: root.visible && root.player !== null && root.player.isPlaying
                repeat: true
                onTriggered: mediaTile.pos = root.player.position
            }
            Connections {
                target: root.player
                function onTrackTitleChanged() { mediaTile.pos = root.player.position; }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10
                visible: root.player !== null

                // capa redonda, gira devagar enquanto toca
                ClippingRectangle {
                    id: cover
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 132
                    Layout.preferredHeight: 132
                    Layout.topMargin: 4
                    radius: 66
                    color: Theme.tileHigh

                    Image {
                        id: art
                        anchors.fill: parent
                        source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        text: Theme.icons.music
                        font.pixelSize: 48
                        color: Theme.subtext
                    }

                    RotationAnimator on rotation {
                        from: 0; to: 360
                        duration: 20000
                        loops: Animation.Infinite
                        running: root.visible && root.player !== null && root.player.isPlaying
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.player ? root.player.trackTitle : ""
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.textColor
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.player ? root.player.trackArtist : ""
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                    radius: 2
                    color: Theme.withAlpha(Theme.primary, 0.2)
                    Rectangle {
                        height: parent.height
                        radius: 2
                        color: Theme.primary
                        width: root.player && root.player.length > 0
                            ? parent.width * Math.min(1, mediaTile.pos / root.player.length) : 0
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 18

                    Repeater {
                        model: [
                            { icon: Theme.icons.prev, big: false, act: "prev" },
                            { icon: root.player && root.player.isPlaying ? Theme.icons.pause : Theme.icons.play, big: true, act: "toggle" },
                            { icon: Theme.icons.next, big: false, act: "next" }
                        ]
                        delegate: Rectangle {
                            id: ctl
                            required property var modelData
                            implicitWidth: modelData.big ? 44 : 34
                            implicitHeight: implicitWidth
                            radius: implicitWidth / 2
                            color: modelData.big
                                ? (ctlArea.containsMouse ? Theme.mix(Theme.primary, Theme.foreground, 0.15) : Theme.primary)
                                : (ctlArea.containsMouse ? Theme.tileHigh : "transparent")
                            Behavior on color { ColorAnimation { duration: Theme.ms(120) } }

                            Icon {
                                anchors.centerIn: parent
                                text: ctl.modelData.icon
                                font.pixelSize: ctl.modelData.big ? 24 : 20
                                color: ctl.modelData.big ? Theme.background : Theme.textColor
                            }
                            MouseArea {
                                id: ctlArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.player) return;
                                    if (ctl.modelData.act === "prev") root.player.previous();
                                    else if (ctl.modelData.act === "next") root.player.next();
                                    else root.player.togglePlaying();
                                }
                            }
                        }
                    }
                }

                // Visualizador de áudio Cava reativo (8 barras de frequência)
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: 18
                    spacing: 4
                    visible: root.player !== null && root.player.isPlaying

                    Repeater {
                        model: 8
                        delegate: Rectangle {
                            required property int index
                            width: 5
                            radius: 2.5
                            color: Theme.accent2
                            property real val: (MediaState.barValues && MediaState.barValues.length > index)
                                ? MediaState.barValues[index] : 0
                            height: Math.max(3, Math.min(18, val * 0.18))
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on height { NumberAnimation { duration: 60 } }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: root.player === null
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 60
                    height: 60
                    radius: 30
                    color: Theme.withAlpha(Theme.primary, 0.12)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.primary, 0.28)

                    Icon {
                        anchors.centerIn: parent
                        text: Theme.icons.music
                        font.pixelSize: 26
                        color: Theme.withAlpha(Theme.primary, 0.8)
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 2
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Theme.t("media.no_media", "Nenhuma mídia ativa")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Theme.textColor
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Theme.t("media.no_media_sub", "Player ocioso")
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.subtext
                    }
                }
            }
        }
    }
}
