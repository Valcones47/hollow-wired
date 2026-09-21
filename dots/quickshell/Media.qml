import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "."

Item {
    id: root

    // Com Spotify e navegador abertos ao mesmo tempo, fixar em values[0] fazia a
    // aba controlar um player que não era o que estava tocando. Agora dá pra
    // escolher, e a escolha cai de volta no primeiro quando o player escolhido
    // fecha.
    property string preferredPlayer: ""
    readonly property var players: Mpris.players.values
    readonly property var player: {
        const list = root.players;
        if (list.length === 0)
            return null;
        if (root.preferredPlayer !== "") {
            for (let i = 0; i < list.length; i++) {
                if (list[i].dbusName === root.preferredPlayer)
                    return list[i];
            }
        }
        // Sem escolha explícita, prefere quem está de fato tocando.
        for (let i = 0; i < list.length; i++) {
            if (list[i].isPlaying)
                return list[i];
        }
        return list[0];
    }

    // ---------- barrinhas reagindo ao áudio (cava) ----------
    // Só roda enquanto algo está tocando de verdade — sem gastar CPU à toa
    // com o cava analisando silêncio o tempo todo.
    // 44 faixas: o suficiente para o anel em volta da capa não ficar serrilhado.
    // Ver cava.conf — mexer aqui sem mexer lá deixa o anel com buracos.
    property var barValues: []
    Process {
        id: cavaProc
        running: root.player !== null && root.player.isPlaying
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/quickshell/cava.conf"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = line.split(";").filter(s => s.length > 0).map(Number);
                if (parts.length > 0)
                    root.barValues = parts;
            }
        }
    }

    // MPRIS não empurra a posição continuamente durante a reprodução — só
    // em eventos (seek, troca de faixa). Esse timer avança a barra sozinho
    // entre eventos e resincroniza sempre que o player manda uma posição
    // nova de verdade.
    property real tickPosition: 0
    Timer {
        interval: 1000
        running: root.player !== null && root.player.isPlaying
        repeat: true
        onTriggered: root.tickPosition += 1
    }
    Connections {
        target: root.player
        function onPositionChanged() {
            root.tickPosition = root.player.position;
        }
        function onTrackTitleChanged() {
            root.tickPosition = root.player.position;
        }
    }
    onPlayerChanged: {
        if (player)
            tickPosition = player.position;
    }

    // ---------- letras ----------
    // Buscadas por rice-lyrics (LRCLIB, sem cadastro) e guardadas em cache no
    // disco, então a mesma música não vai à rede duas vezes e continua
    // aparecendo offline.
    property var lyricsLines: []
    property bool lyricsSynced: false
    property string lyricsStatus: "idle"
    // A letra só é buscada com o painel dela à vista.
    readonly property bool lyricsOpen: root.visible && root.layout === "ring" && root.sideTab === "lyrics"
    // Faixa da letra carregada: ao reabrir o painel depois de trocar de música
    // com ele fechado, a letra antiga não pode continuar ali.
    property string lyricsKey: ""
    readonly property string trackKey: root.player ? root.player.trackTitle + "\u0000" + root.player.trackArtist : ""

    // Linha que corresponde ao instante atual. -1 quando a letra não é
    // sincronizada (aí ela vira só um texto rolável).
    readonly property int lyricsIndex: {
        if (!root.lyricsSynced || root.lyricsLines.length === 0)
            return -1;
        const pos = root.tickPosition;
        let idx = -1;
        for (let i = 0; i < root.lyricsLines.length; i++) {
            if (root.lyricsLines[i].t <= pos + 0.15)
                idx = i;
            else
                break;
        }
        return idx;
    }

    Process {
        id: lyricsProc
        command: ["rice-lyrics"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.lyricsStatus = d.status || "none";
                    root.lyricsSynced = !!d.synced;
                    root.lyricsLines = d.lines || [];
                } catch (e) {
                    root.lyricsStatus = "none";
                    root.lyricsLines = [];
                }
            }
        }
    }

    // Trocar de faixa invalida a letra na hora, senão a anterior fica na tela
    // enquanto a nova é buscada.
    function reloadLyrics() {
        root.lyricsKey = root.trackKey;
        root.lyricsLines = [];
        root.lyricsStatus = "carregando";
        lyricsProc.running = false;
        lyricsProc.running = true;
    }

    Connections {
        target: root.player
        function onTrackTitleChanged() { if (root.lyricsOpen) root.reloadLyrics(); }
    }
    onLyricsOpenChanged: if (lyricsOpen && lyricsKey !== trackKey) reloadLyrics()

    function fmtTime(seconds) {
        if (!seconds || seconds < 0 || isNaN(seconds))
            return "0:00";
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // ---------- layout ----------
    // Dois jeitos de montar a aba, escolhidos pelo botão no canto (ou no painel
    // Rice). "disc": disco girando em cima e o equalizador inteiro embaixo.
    // "ring": capa com o espectro em volta, controles no meio e um painel à
    // direita que alterna entre a letra e o equalizador — assim o equalizador
    // continua a um clique de distância nos dois.
    readonly property string layout: ShellCustomization.getMediaLayout()
    property string sideTab: "lyrics"

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property string sinkName: sink ? (sink.description || sink.nickname || sink.name || "") : ""
    readonly property bool sinkIsHeadset: sink !== null && /bluez|headset|headphone|fone/i.test((sink.name || "") + " " + sinkName)

    function cyclePlayer() {
        const list = root.players;
        if (list.length < 2)
            return;
        const i = list.indexOf(root.player);
        root.preferredPlayer = list[(i + 1) % list.length].dbusName;
    }

    // ================= componentes compartilhados =================

    // Capa redonda com o espectro de áudio em volta. Com `vinyl` a capa vira um
    // disco: gira enquanto toca e ganha o furo e os sulcos no meio.
    component ArtRing: Item {
        id: ring
        required property Item m
        property bool vinyl: false
        property real artSize: width * 0.62
        readonly property real ringGap: 7
        readonly property real maxBar: (width - artSize) / 2 - ringGap

        Canvas {
            id: ringCanvas
            anchors.fill: parent
            opacity: ring.m.player && ring.m.player.isPlaying ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const bars = ring.m.barValues;
                if (!bars || bars.length === 0)
                    return;
                const cx = width / 2;
                const cy = height / 2;
                const inner = ring.artSize / 2 + ring.ringGap;
                const step = (Math.PI * 2) / bars.length;
                ctx.lineCap = "round";
                ctx.lineWidth = Math.max(2, step * inner * 0.55);
                ctx.strokeStyle = Theme.accent2;
                for (let i = 0; i < bars.length; i++) {
                    const level = Math.max(0, Math.min(100, bars[i])) / 100;
                    const len = 2 + level * ring.maxBar;
                    const a = -Math.PI / 2 + i * step;
                    const cos = Math.cos(a);
                    const sin = Math.sin(a);
                    ctx.globalAlpha = 0.35 + level * 0.65;
                    ctx.beginPath();
                    ctx.moveTo(cx + cos * inner, cy + sin * inner);
                    ctx.lineTo(cx + cos * (inner + len), cy + sin * (inner + len));
                    ctx.stroke();
                }
            }
            Connections {
                target: ring.m
                function onBarValuesChanged() { ringCanvas.requestPaint(); }
            }
        }

        // Máscara redonda fora da vista: `visible: false` não gera a textura
        // que o OpacityMask precisa, e declarar a máscara dentro do effect a
        // congela no primeiro quadro.
        Rectangle {
            id: artMask
            x: -ring.artSize * 2
            width: ring.artSize
            height: ring.artSize
            radius: width / 2
            layer.enabled: true
        }

        Rectangle {
            id: disc
            anchors.centerIn: parent
            width: ring.artSize
            height: ring.artSize
            radius: width / 2
            color: ring.vinyl ? "#0c0c10" : Theme.withAlpha(Theme.accent1, 0.15)
            border.width: 1
            border.color: Theme.withAlpha(Theme.accent1, 0.35)

            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 14000
                loops: Animation.Infinite
                running: ring.vinyl && ring.m.visible && ring.m.player !== null && ring.m.player.isPlaying
                // Parar no meio deixa o disco onde estava, como um toca-discos.
                alwaysRunToEnd: false
            }

            Image {
                id: artImage
                anchors.fill: parent
                source: ring.m.player && ring.m.player.trackArtUrl ? ring.m.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
                layer.enabled: true
                layer.effect: OpacityMask { maskSource: artMask }
            }

            Text {
                anchors.centerIn: parent
                visible: artImage.status !== Image.Ready && !ring.vinyl
                text: Theme.icons.music
                font.family: Theme.iconFontFamily
                font.pixelSize: ring.artSize * 0.3
                color: Theme.withAlpha(Theme.accent1, 0.6)
            }

            // Sulcos e furo do disco.
            Repeater {
                model: ring.vinyl ? 4 : 0
                delegate: Rectangle {
                    required property int index
                    anchors.centerIn: parent
                    width: ring.artSize * (0.92 - index * 0.14)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, artImage.visible ? 0.22 : 0.6)
                }
            }
            Rectangle {
                visible: ring.vinyl
                anchors.centerIn: parent
                width: ring.artSize * 0.3
                height: width
                radius: width / 2
                color: Qt.rgba(0.05, 0.05, 0.07, 0.85)
                border.width: 2
                border.color: Theme.withAlpha(Theme.accent2, 0.5)
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.26
                    height: width
                    radius: width / 2
                    color: Theme.withAlpha(Theme.foreground, 0.85)
                }
            }
        }
    }

    // Título que rola de lado quando não cabe, em vez de cortar com "...".
    component Marquee: Item {
        id: mq
        property string text: ""
        property int pixelSize: 15
        property color color: Theme.foreground
        implicitHeight: label.implicitHeight
        clip: true
        readonly property bool overflow: label.implicitWidth > width

        Text {
            id: label
            text: mq.text
            font.family: Theme.fontFamily
            font.pixelSize: mq.pixelSize
            font.bold: true
            color: mq.color
            x: 0
        }
        SequentialAnimation {
            running: mq.overflow && mq.visible
            loops: Animation.Infinite
            onRunningChanged: if (!running) label.x = 0
            PauseAnimation { duration: 1800 }
            NumberAnimation {
                target: label
                property: "x"
                to: mq.width - label.implicitWidth
                duration: Math.max(1500, (label.implicitWidth - mq.width) * 35)
                easing.type: Easing.InOutSine
            }
            PauseAnimation { duration: 1400 }
            NumberAnimation {
                target: label
                property: "x"
                to: 0
                duration: 600
                easing.type: Easing.OutCubic
            }
        }
        onTextChanged: label.x = 0
    }

    // Etiqueta pequena com ícone (saída de áudio, player).
    component Chip: Rectangle {
        id: chip
        property string icon: ""
        property string label: ""
        property bool clickable: false
        signal clicked()
        implicitWidth: chipRow.implicitWidth + 18
        implicitHeight: 22
        radius: 11
        color: chipMouse.containsMouse && clickable ? Theme.withAlpha(Theme.subtext, 0.2)
                                                    : Theme.withAlpha(Theme.subtext, 0.1)
        border.width: 1
        border.color: Theme.withAlpha(Theme.subtext, 0.22)
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.icon
                visible: text !== ""
                font.family: Theme.iconFontFamily
                font.pixelSize: 11
                color: Theme.accent2
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.foreground
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 170)
            }
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: chip.clickable
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    // Barra de progresso arrastável com os tempos embaixo.
    component SeekBar: ColumnLayout {
        id: seekArea
        required property Item m
        spacing: 4

        readonly property real trackLength: m.player && m.player.length > 0 ? m.player.length : 0
        readonly property bool seekable: m.player !== null && m.player.canSeek && trackLength > 0
        // Enquanto arrasta, a barra segue o mouse e ignora a posição que o
        // player continua mandando — senão ela pula de volta a cada evento.
        property bool scrubbing: false
        property real scrubFraction: 0
        readonly property real fraction: scrubbing
            ? scrubFraction
            : (trackLength > 0 ? Math.min(1, m.tickPosition / trackLength) : 0)

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 16

            Rectangle {
                id: seekTrack
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: seekMouse.containsMouse || seekArea.scrubbing ? 7 : 5
                radius: height / 2
                color: Theme.withAlpha(Theme.subtext, 0.25)
                Behavior on height { NumberAnimation { duration: 110 } }

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: Theme.accent2
                    width: parent.width * seekArea.fraction
                }
                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: Theme.accent2
                    opacity: seekMouse.containsMouse || seekArea.scrubbing ? 1 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(parent.width - width, parent.width * seekArea.fraction - width / 2))
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                }
            }

            MouseArea {
                id: seekMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: seekArea.seekable
                cursorShape: seekArea.seekable ? Qt.PointingHandCursor : Qt.ArrowCursor
                function fractionAt(px) {
                    return Math.max(0, Math.min(1, px / Math.max(1, seekTrack.width)));
                }
                onPressed: mouse => {
                    seekArea.scrubFraction = fractionAt(mouse.x);
                    seekArea.scrubbing = true;
                }
                onPositionChanged: mouse => {
                    if (seekArea.scrubbing)
                        seekArea.scrubFraction = fractionAt(mouse.x);
                }
                onReleased: mouse => {
                    if (!seekArea.scrubbing)
                        return;
                    const target = fractionAt(mouse.x) * seekArea.trackLength;
                    seekArea.scrubbing = false;
                    seekArea.m.player.position = target;
                    // O player leva um instante para confirmar a posição nova.
                    seekArea.m.tickPosition = target;
                }
                onCanceled: seekArea.scrubbing = false
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: seekArea.m.fmtTime(seekArea.scrubbing ? seekArea.scrubFraction * seekArea.trackLength
                                                            : seekArea.m.tickPosition)
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: seekArea.scrubbing ? Theme.accent2 : Theme.subtext
            }
            Item { Layout.fillWidth: true }
            Text {
                text: seekArea.m.fmtTime(seekArea.trackLength)
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.subtext
            }
        }
    }

    component RoundBtn: Rectangle {
        id: btn
        property string icon: ""
        property real size: 36
        property bool active: false
        property bool supported: true
        property bool primary: false
        signal clicked()
        implicitWidth: size
        implicitHeight: size
        radius: height / 2
        opacity: supported ? 1 : 0.3
        color: primary ? Theme.withAlpha(Theme.accent2, btnMouse.containsMouse ? 0.42 : 0.26)
             : active ? Theme.withAlpha(Theme.accent2, 0.25)
             : (btnMouse.containsMouse ? Theme.withAlpha(Theme.subtext, 0.15) : "transparent")
        border.width: 1
        border.color: primary || active ? Theme.accent2 : Theme.withAlpha(Theme.subtext, 0.35)
        scale: btnMouse.pressed ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: 100 } }
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text {
            anchors.centerIn: parent
            text: btn.icon
            font.family: Theme.iconFontFamily
            font.pixelSize: Math.round(btn.height * (btn.primary ? 0.4 : 0.38))
            color: btn.primary || btn.active ? Theme.accent2 : Theme.foreground
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.supported
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    // Aleatório, anterior, tocar, próxima, repetir. Aleatório e repetir ficam
    // apagados quando o player não suporta (o navegador, por exemplo).
    component Controls: RowLayout {
        id: ctl
        required property Item m
        property real playSize: 50
        property real playWidth: playSize
        spacing: 10

        readonly property bool loopSupported: m.player !== null && m.player.loopSupported
        readonly property int loopMode: loopSupported ? m.player.loopState : MprisLoopState.None

        RoundBtn {
            size: 32
            icon: Theme.icons.shuffle
            supported: ctl.m.player !== null && ctl.m.player.shuffleSupported
            active: supported && ctl.m.player.shuffle
            onClicked: ctl.m.player.shuffle = !ctl.m.player.shuffle
        }
        RoundBtn {
            size: 38
            icon: Theme.icons.prev
            onClicked: ctl.m.player && ctl.m.player.previous()
        }
        RoundBtn {
            primary: true
            size: ctl.playSize
            implicitWidth: ctl.playWidth
            icon: ctl.m.player && ctl.m.player.isPlaying ? Theme.icons.pause : Theme.icons.play
            onClicked: ctl.m.player && ctl.m.player.togglePlaying()
        }
        RoundBtn {
            size: 38
            icon: Theme.icons.next
            onClicked: ctl.m.player && ctl.m.player.next()
        }
        RoundBtn {
            size: 32
            icon: ctl.loopMode === MprisLoopState.Track ? Theme.icons.repeatOne : Theme.icons.repeat
            supported: ctl.loopSupported
            active: ctl.loopMode !== MprisLoopState.None
            // desligado -> playlist -> faixa, como nos players comuns
            onClicked: {
                const s = ctl.m.player.loopState;
                ctl.m.player.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist
                                       : s === MprisLoopState.Playlist ? MprisLoopState.Track
                                       : MprisLoopState.None;
            }
        }
    }

    // Letra: sincronizada (linha atual destacada e centralizada) ou texto
    // simples rolável.
    component LyricsPane: Item {
        id: lp
        required property Item m

        Text {
            anchors.centerIn: parent
            width: parent.width - 20
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: lp.m.lyricsLines.length === 0
            text: {
                const st = lp.m.lyricsStatus;
                if (st === "carregando") return Theme.t("media.lyrics_loading", "Procurando a letra...");
                if (st === "offline") return Theme.t("media.lyrics_offline", "Sem internet e sem cópia guardada.");
                if (st === "none") return Theme.t("media.lyrics_none", "Não achei a letra desta música.");
                return "";
            }
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.subtext
        }

        ListView {
            id: lyricsView
            anchors.fill: parent
            model: lp.m.lyricsLines
            spacing: 6
            clip: true
            interactive: !lp.m.lyricsSynced
            boundsBehavior: Flickable.StopAtBounds
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: height / 2 - 14
            preferredHighlightEnd: height / 2 + 14
            highlightMoveDuration: 380

            delegate: Text {
                required property var modelData
                required property int index
                readonly property bool current: index === lp.m.lyricsIndex
                width: lyricsView.width
                text: modelData.text
                horizontalAlignment: lp.m.lyricsSynced ? Text.AlignHCenter : Text.AlignLeft
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: current ? 14 : 12
                font.weight: current ? Font.DemiBold : Font.Normal
                color: !lp.m.lyricsSynced ? Theme.foreground
                     : (current ? Theme.accent2 : Theme.withAlpha(Theme.subtext, 0.7))
                Behavior on font.pixelSize { NumberAnimation { duration: 120 } }
                Behavior on color { ColorAnimation { duration: 160 } }
            }

            Connections {
                target: lp.m
                function onLyricsIndexChanged() {
                    if (lp.m.lyricsSynced && lp.m.lyricsIndex >= 0)
                        lyricsView.currentIndex = lp.m.lyricsIndex;
                }
            }
        }
    }

    // Botão que troca entre os dois layouts.
    component LayoutSwitch: RoundBtn {
        required property Item m
        size: 28
        icon: m.layout === "disc" ? Theme.icons.lyrics : Theme.icons.album
        onClicked: ShellCustomization.setMediaLayout(m.layout === "disc" ? "ring" : "disc")
    }

    // ================= layout "disc" =================
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gap + 4
        visible: root.player !== null && root.layout === "disc"

        RowLayout {
            Layout.fillWidth: true
            // Sem o teto, a coluna da direita (que preenche a altura) puxava a
            // linha para a aba inteira e o equalizador sumia embaixo.
            Layout.fillHeight: false
            Layout.preferredHeight: 150
            Layout.maximumHeight: 150
            spacing: Theme.gap * 2

            ArtRing {
                m: root
                vinyl: true
                Layout.preferredWidth: 150
                Layout.preferredHeight: 150
                artSize: 112
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Marquee {
                        Layout.fillWidth: true
                        text: root.player ? root.player.trackTitle : ""
                        pixelSize: 16
                    }
                    LayoutSwitch { m: root }
                }
                Text {
                    Layout.fillWidth: true
                    text: root.player && root.player.trackArtist
                          ? Theme.t("media.by", "Por") + " " + root.player.trackArtist : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.subtext
                    elide: Text.ElideRight
                }
                Row {
                    Layout.topMargin: 2
                    spacing: 6
                    Chip {
                        visible: root.sinkName !== ""
                        icon: root.sinkIsHeadset ? Theme.icons.headphones : Theme.icons.speaker
                        label: root.sinkName
                    }
                    Chip {
                        icon: Theme.icons.media
                        label: Theme.t("media.via", "Via") + " " + (root.player ? root.player.identity : "")
                        clickable: root.players.length > 1
                        onClicked: root.cyclePlayer()
                    }
                }
                Item { Layout.fillHeight: true }
                SeekBar {
                    m: root
                    Layout.fillWidth: true
                }
                Controls {
                    m: root
                    Layout.alignment: Qt.AlignHCenter
                    playSize: 42
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radius / 1.5
            color: Theme.tile
            border.width: 1
            border.color: Theme.withAlpha(Theme.subtext, 0.12)

            Equalizer {
                anchors.fill: parent
                anchors.margins: 12
            }
        }
    }

    // ================= layout "ring" =================
    RowLayout {
        anchors.fill: parent
        spacing: Theme.gap * 2
        visible: root.player !== null && root.layout === "ring"

        ArtRing {
            m: root
            Layout.preferredWidth: 220
            Layout.preferredHeight: 220
            Layout.alignment: Qt.AlignVCenter
            artSize: 142
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            Item { Layout.fillHeight: true }
            Marquee {
                Layout.fillWidth: true
                text: root.player ? root.player.trackTitle : ""
                pixelSize: 22
            }
            Text {
                Layout.fillWidth: true
                text: root.player ? root.player.trackArtist : ""
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.subtext
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: root.player ? root.player.trackAlbum : ""
                visible: text !== ""
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.italic: true
                color: Theme.withAlpha(Theme.subtext, 0.7)
                elide: Text.ElideRight
            }
            SeekBar {
                m: root
                Layout.fillWidth: true
                Layout.topMargin: 10
            }
            Controls {
                m: root
                Layout.alignment: Qt.AlignHCenter
                playSize: 46
                playWidth: 76
            }
            Item { Layout.fillHeight: true }
        }

        // Painel à direita: letra ou equalizador.
        Rectangle {
            Layout.preferredWidth: 300
            Layout.fillHeight: true
            radius: Theme.radius / 1.5
            color: Theme.tile
            border.width: 1
            border.color: Theme.withAlpha(Theme.subtext, 0.12)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "lyrics", icon: Theme.icons.lyrics, label: Theme.t("media.lyrics", "Letra") },
                            { id: "eq", icon: Theme.icons.equalizer, label: Theme.t("eq.short", "EQ") }
                        ]
                        delegate: Rectangle {
                            id: tabBtn
                            required property var modelData
                            readonly property bool active: root.sideTab === modelData.id
                            implicitWidth: tabRow.implicitWidth + 20
                            implicitHeight: 26
                            radius: 13
                            color: active ? Theme.withAlpha(Theme.accent2, 0.22)
                                          : (tabMouse.containsMouse ? Theme.withAlpha(Theme.subtext, 0.15) : "transparent")
                            border.width: 1
                            border.color: active ? Theme.accent2 : Theme.withAlpha(Theme.subtext, 0.25)
                            Row {
                                id: tabRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tabBtn.modelData.icon
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 12
                                    color: tabBtn.active ? Theme.accent2 : Theme.subtext
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tabBtn.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: tabBtn.active ? Theme.accent2 : Theme.subtext
                                }
                            }
                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.sideTab = tabBtn.modelData.id
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    LayoutSwitch { m: root }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    LyricsPane {
                        m: root
                        anchors.fill: parent
                        visible: root.sideTab === "lyrics"
                    }
                    Equalizer {
                        anchors.fill: parent
                        compact: true
                        visible: root.sideTab === "eq"
                    }
                }

                Chip {
                    Layout.alignment: Qt.AlignHCenter
                    icon: Theme.icons.media
                    label: (root.player ? root.player.identity : "")
                           + (root.players.length > 1 ? "  ▾" : "")
                    clickable: root.players.length > 1
                    onClicked: root.cyclePlayer()
                }
            }
        }
    }

    // ---------- estado vazio ----------
    ColumnLayout {
        anchors.centerIn: parent
        visible: root.player === null
        spacing: 12

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 72
            height: 72
            radius: 36
            color: Theme.withAlpha(Theme.subtext, 0.08)
            border.width: 1
            border.color: Theme.withAlpha(Theme.subtext, 0.2)

            Text {
                anchors.centerIn: parent
                text: ""
                font.family: Theme.iconFontFamily
                font.pixelSize: 32
                color: Theme.withAlpha(Theme.subtext, 0.6)
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Theme.t("media.no_media", "Nenhuma mídia em reprodução")
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: Theme.textColor
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Theme.t("media.no_media_sub", "Abra o Spotify, YouTube Music ou outro player de áudio")
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.subtext
        }
    }
}
