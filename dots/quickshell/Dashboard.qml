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

    // ---------- clima (wttr.in, localização pelo IP) ----------
    // http (não https): o curl daqui falha a verificação TLS do wttr.in
    // (exit 60), e clima não é dado sensível. Troque weatherLocation por uma cidade ("Sao+Paulo") se o IP cair em
    // outro lugar. Consulta a cada 30 min, só enquanto a aba está visível.
    property string weatherLocation: ""
    property string weatherTemp: "--"
    property string weatherDesc: "Sem dados"
    property string weatherPlace: ""
    property int weatherCode: 0
    // A resposta do wttr.in (format=j1) já vem com sensação térmica, umidade,
    // vento, nascer/pôr do sol e a previsão de três dias. Tudo isso era baixado
    // e jogado fora: só a temperatura era lida.
    property string weatherFeels: ""
    property string weatherHumidity: ""
    property string weatherWind: ""
    property string weatherSunrise: ""
    property string weatherSunset: ""
    property var weatherDays: []
    Timer {
        interval: 30 * 60 * 1000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: weatherProc.running = true
    }
    Process {
        id: weatherProc
        command: ["curl", "-sf", "--max-time", "10", "http://wttr.in/" + root.weatherLocation + "?format=j1&lang=pt"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const cur = data.current_condition[0];
                    root.weatherTemp = cur.temp_C + "°C";
                    root.weatherCode = parseInt(cur.weatherCode);
                    root.weatherDesc = cur.lang_pt ? cur.lang_pt[0].value : cur.weatherDesc[0].value;
                    root.weatherPlace = data.nearest_area ? data.nearest_area[0].areaName[0].value : "";

                    root.weatherFeels = cur.FeelsLikeC ? cur.FeelsLikeC + "°" : "";
                    root.weatherHumidity = cur.humidity ? cur.humidity + "%" : "";
                    root.weatherWind = cur.windspeedKmph ? cur.windspeedKmph + " km/h" : "";

                    const astro = (data.weather && data.weather[0] && data.weather[0].astronomy)
                                ? data.weather[0].astronomy[0] : null;
                    // O wttr.in devolve o horário em 12h ("05:23 AM"); aqui o
                    // relógio é de 24h em todo o resto da interface.
                    root.weatherSunrise = astro ? root.to24h(astro.sunrise) : "";
                    root.weatherSunset = astro ? root.to24h(astro.sunset) : "";

                    const days = [];
                    const names = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"];
                    for (let i = 0; i < (data.weather || []).length && i < 3; i++) {
                        const w = data.weather[i];
                        const d = new Date(w.date + "T12:00:00");
                        days.push({
                            label: i === 0 ? Theme.t("dash.today", "Hoje") : names[d.getDay()],
                            min: w.mintempC + "°",
                            max: w.maxtempC + "°",
                            code: parseInt((w.hourly && w.hourly[4]) ? w.hourly[4].weatherCode : "113")
                        });
                    }
                    root.weatherDays = days;
                } catch (e) {
                    console.log("Dashboard: resposta do wttr.in inválida:", e);
                }
            }
        }
    }
    function to24h(text) {
        // "05:23 AM" / "5:23 PM" -> "05:23"
        const m = /^(\d{1,2}):(\d{2})\s*(AM|PM)?$/i.exec((text || "").trim());
        if (!m)
            return text || "";
        let h = parseInt(m[1]);
        const ampm = (m[3] || "").toUpperCase();
        if (ampm === "PM" && h !== 12) h += 12;
        if (ampm === "AM" && h === 12) h = 0;
        return ("0" + h).slice(-2) + ":" + m[2];
    }

    function weatherIcon(code, hour) {
        const night = hour < 6 || hour >= 18;
        if (code === 113) return night ? Theme.icons.night : Theme.icons.sunny;
        if (code === 116) return Theme.icons.partly;
        if (code === 119 || code === 122) return Theme.icons.cloudy;
        if ([143, 248, 260].includes(code)) return Theme.icons.fog;
        if ([200, 386, 389, 392, 395].includes(code)) return Theme.icons.lightning;
        if ([299, 302, 305, 308, 356, 359].includes(code)) return Theme.icons.pouring;
        if ([179, 182, 185, 227, 230, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377].includes(code))
            return Theme.icons.snowy;
        if (code >= 176) return Theme.icons.rainy;
        return Theme.icons.cloudy;
    }

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
                Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
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
                Layout.preferredHeight: 152
                spacing: Theme.gap + 2

                Tile {
                    Layout.preferredWidth: 300
                    Layout.fillHeight: true

                    ColumnLayout {
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

                // hora vertical: HH ••• MM
                Tile {
                    Layout.preferredWidth: 92
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Qt.formatDateTime(root.now, "HH")
                            font.family: Theme.fontFamily
                            font.pixelSize: 34
                            font.weight: Font.DemiBold
                            color: Theme.primary
                        }
                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 5
                            Repeater {
                                model: 3
                                Rectangle {
                                    width: 5; height: 5; radius: 2.5
                                    color: Theme.primary
                                }
                            }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Qt.formatDateTime(root.now, "mm")
                            font.family: Theme.fontFamily
                            font.pixelSize: 34
                            font.weight: Font.DemiBold
                            color: Theme.primary
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 6
                            text: root.dayNames[root.now.getDay()].slice(0, 3) + ", " + root.now.getDate()
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.subtext
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
                            Behavior on color { ColorAnimation { duration: 120 } }

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
