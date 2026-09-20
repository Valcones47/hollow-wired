import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
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

    function fmtTime(seconds) {
        if (!seconds || seconds < 0 || isNaN(seconds))
            return "0:00";
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gap * 2
        visible: root.player !== null

        // ---------- capa + metadados ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap * 2

            // Capa redonda com o espectro de áudio desenhado em volta, como um
            // anel. Substitui as barrinhas horizontais que ficavam soltas
            // embaixo dos controles.
            Item {
                id: artRing
                Layout.preferredWidth: 168
                Layout.preferredHeight: 168
                Layout.alignment: Qt.AlignTop

                readonly property real artSize: 104
                readonly property real ringGap: 7
                readonly property real maxBar: (width - artSize) / 2 - ringGap

                Canvas {
                    id: ringCanvas
                    anchors.fill: parent
                    // Enquanto nada toca o anel some, em vez de deixar um
                    // círculo de tocos parados em volta da capa.
                    opacity: root.player && root.player.isPlaying ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220 } }

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const bars = root.barValues;
                        if (!bars || bars.length === 0)
                            return;

                        const cx = width / 2;
                        const cy = height / 2;
                        const inner = artRing.artSize / 2 + artRing.ringGap;
                        const step = (Math.PI * 2) / bars.length;
                        const thickness = Math.max(2, step * inner * 0.55);

                        ctx.lineCap = "round";
                        ctx.lineWidth = thickness;
                        ctx.strokeStyle = Theme.accent2;

                        for (let i = 0; i < bars.length; i++) {
                            const level = Math.max(0, Math.min(100, bars[i])) / 100;
                            const len = 2 + level * artRing.maxBar;
                            // Começa no topo e gira no sentido horário.
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
                }

                Connections {
                    target: root
                    function onBarValuesChanged() { ringCanvas.requestPaint(); }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: artRing.artSize
                    height: artRing.artSize
                    radius: width / 2
                    color: Theme.withAlpha(Theme.accent1, 0.15)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.accent1, 0.35)
                    clip: true

                    Image {
                        id: artImage
                        anchors.fill: parent
                        source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // O `clip` do Rectangle recorta em retângulo, não no
                        // raio: sem a máscara a capa sai quadrada por cima do
                        // círculo.
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: artRing.artSize
                                height: artRing.artSize
                                radius: width / 2
                            }
                        }
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: artImage.status !== Image.Ready
                        text: Theme.icons.music
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 34
                        color: Theme.withAlpha(Theme.accent1, 0.6)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: root.player ? root.player.trackTitle : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                    color: Theme.foreground
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: root.player ? root.player.trackArtist : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.inactive
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: root.player ? root.player.trackAlbum : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.italic: true
                    color: Theme.withAlpha(Theme.inactive, 0.7)
                    elide: Text.ElideRight
                    visible: text !== ""
                }

                Rectangle {
                    Layout.topMargin: 4
                    Layout.preferredWidth: sourceLabel.implicitWidth + 16
                    Layout.preferredHeight: 20
                    radius: 10
                    color: Theme.withAlpha(Theme.accent2, 0.2)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.accent2, 0.4)
                    visible: root.player !== null

                    Text {
                        id: sourceLabel
                        anchors.centerIn: parent
                        text: root.player ? root.player.identity : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.accent2
                    }
                }
            }
        }

        // ---------- barra de progresso (arrastável) ----------
        ColumnLayout {
            id: seekArea
            Layout.fillWidth: true
            spacing: 4
            visible: root.player !== null

            readonly property real trackLength: root.player && root.player.length > 0 ? root.player.length : 0
            readonly property bool seekable: root.player !== null && root.player.canSeek && trackLength > 0
            // Enquanto o usuário arrasta, a barra segue o dedo e ignora a
            // posição que o player continua mandando — senão ela pula de volta
            // a cada evento de MPRIS no meio do arrasto.
            property bool scrubbing: false
            property real scrubFraction: 0

            readonly property real fraction: scrubbing
                ? scrubFraction
                : (trackLength > 0 ? Math.min(1, root.tickPosition / trackLength) : 0)

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 18

                Rectangle {
                    id: seekTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: seekMouse.containsMouse || seekArea.scrubbing ? 7 : 5
                    radius: height / 2
                    color: Theme.withAlpha(Theme.inactive, 0.25)
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
                        x: Math.max(0, Math.min(parent.width - width,
                                                parent.width * seekArea.fraction - width / 2))
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
                        const frac = fractionAt(mouse.x);
                        seekArea.scrubbing = false;
                        const target = frac * seekArea.trackLength;
                        root.player.position = target;
                        // O player leva um instante para confirmar a posição
                        // nova; sem isso a barra volta para onde estava até o
                        // próximo evento chegar.
                        root.tickPosition = target;
                    }
                    onCanceled: seekArea.scrubbing = false
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.fmtTime(seekArea.scrubbing
                                       ? seekArea.scrubFraction * seekArea.trackLength
                                       : root.tickPosition)
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: seekArea.scrubbing ? Theme.accent2 : Theme.inactive
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.fmtTime(seekArea.trackLength)
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.inactive
                }
            }
        }


        // ---------- controles ----------
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.gap * 2
            visible: root.player !== null

            // Aleatório e repetir: o MPRIS avisa quando o player não suporta
            // (o navegador, por exemplo), e aí o botão fica apagado e sem
            // clique em vez de mandar um comando que não faz nada.
            Rectangle {
                id: shuffleBtn
                property bool hovered: false
                readonly property bool supported: root.player !== null && root.player.shuffleSupported
                readonly property bool active: supported && root.player.shuffle
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 17
                opacity: supported ? 1 : 0.3
                color: active ? Theme.withAlpha(Theme.accent2, 0.25)
                              : (hovered ? Theme.withAlpha(Theme.inactive, 0.15) : "transparent")
                border.width: 1
                border.color: active ? Theme.accent2 : Theme.withAlpha(Theme.inactive, 0.3)
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: Theme.icons.shuffle
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 13
                    color: shuffleBtn.active ? Theme.accent2 : Theme.inactive
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: shuffleBtn.supported
                    cursorShape: Qt.PointingHandCursor
                    onEntered: shuffleBtn.hovered = true
                    onExited: shuffleBtn.hovered = false
                    onClicked: root.player.shuffle = !root.player.shuffle
                }
            }


            Rectangle {
                id: prevBtn
                property bool hovered: false
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: hovered ? Theme.withAlpha(Theme.inactive, 0.15) : "transparent"
                border.width: 1
                border.color: Theme.withAlpha(Theme.inactive, 0.4)
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 14
                    color: Theme.foreground
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: prevBtn.hovered = true
                    onExited: prevBtn.hovered = false
                    onClicked: root.player && root.player.previous()
                }
            }

            Rectangle {
                id: playBtn
                property bool hovered: false
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                radius: 26
                color: Theme.withAlpha(Theme.accent2, hovered ? 0.4 : 0.25)
                border.width: 1
                border.color: Theme.accent2
                scale: hovered ? 1.06 : 1.0
                Behavior on color { ColorAnimation { duration: 100 } }
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }

                Text {
                    anchors.centerIn: parent
                    text: root.player && root.player.isPlaying ? "" : ""
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 18
                    color: Theme.accent2
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: playBtn.hovered = true
                    onExited: playBtn.hovered = false
                    onClicked: root.player && root.player.togglePlaying()
                }
            }

            Rectangle {
                id: nextBtn
                property bool hovered: false
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: hovered ? Theme.withAlpha(Theme.inactive, 0.15) : "transparent"
                border.width: 1
                border.color: Theme.withAlpha(Theme.inactive, 0.4)
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 14
                    color: Theme.foreground
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: nextBtn.hovered = true
                    onExited: nextBtn.hovered = false
                    onClicked: root.player && root.player.next()
                }
            }

            Rectangle {
                id: repeatBtn
                property bool hovered: false
                readonly property bool supported: root.player !== null && root.player.loopSupported
                readonly property int mode: supported ? root.player.loopState : MprisLoopState.None
                readonly property bool active: supported && mode !== MprisLoopState.None
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 17
                opacity: supported ? 1 : 0.3
                color: active ? Theme.withAlpha(Theme.accent2, 0.25)
                              : (hovered ? Theme.withAlpha(Theme.inactive, 0.15) : "transparent")
                border.width: 1
                border.color: active ? Theme.accent2 : Theme.withAlpha(Theme.inactive, 0.3)
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: repeatBtn.mode === MprisLoopState.Track ? Theme.icons.repeatOne
                                                                  : Theme.icons.repeat
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 13
                    color: repeatBtn.active ? Theme.accent2 : Theme.inactive
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: repeatBtn.supported
                    cursorShape: Qt.PointingHandCursor
                    onEntered: repeatBtn.hovered = true
                    onExited: repeatBtn.hovered = false
                    // Roda entre desligado -> playlist -> faixa, como nos
                    // players comuns.
                    onClicked: {
                        const s = root.player.loopState;
                        if (s === MprisLoopState.None)
                            root.player.loopState = MprisLoopState.Playlist;
                        else if (s === MprisLoopState.Playlist)
                            root.player.loopState = MprisLoopState.Track;
                        else
                            root.player.loopState = MprisLoopState.None;
                    }
                }
            }

        }

        // ---------- escolha do player ----------
        // Só aparece com mais de um player: com um só a linha seria um botão
        // solitário sem função.
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 6
            visible: root.players.length > 1

            Repeater {
                model: root.players

                delegate: Rectangle {
                    id: playerChip
                    required property var modelData
                    readonly property bool current: root.player === modelData

                    height: 24
                    width: chipLabel.implicitWidth + 22
                    radius: 12
                    color: current ? Theme.withAlpha(Theme.accent2, 0.22) : "transparent"
                    border.width: 1
                    border.color: current ? Theme.accent2 : Theme.withAlpha(Theme.inactive, 0.3)
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Row {
                        id: chipLabel
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: playerChip.modelData.isPlaying ? Theme.icons.play : Theme.icons.pause
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 9
                            color: playerChip.current ? Theme.accent2 : Theme.inactive
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: playerChip.modelData.identity
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: playerChip.current ? Theme.accent2 : Theme.inactive
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.preferredPlayer = playerChip.modelData.dbusName
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
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
            color: Theme.withAlpha(Theme.inactive, 0.08)
            border.width: 1
            border.color: Theme.withAlpha(Theme.inactive, 0.2)

            Text {
                anchors.centerIn: parent
                text: ""
                font.family: Theme.iconFontFamily
                font.pixelSize: 32
                color: Theme.withAlpha(Theme.inactive, 0.6)
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
