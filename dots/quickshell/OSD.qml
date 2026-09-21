import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects
import "."

// OSD flutuante estilo Caelestia / Dynamic Island.
// Pílula centralizada abaixo da TopBar com animação fluida (OutBack/OutCubic).
// 100% click-through (mask vazia) para não interceptar cliques em jogos ou janelas.
// Suporta Volume, Brilho e Microfone tanto por eventos PipeWire/Sysfs quanto por IPC.
PanelWindow {
    id: osdWindow

    anchors { top: true; left: true; right: true }
    implicitHeight: 110
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    mask: Region {}

    WlrLayershell.namespace: "quickshell-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property bool open: false
    property bool ready: false
    property string osdType: "volume"    // "volume", "brightness", "mic"
    property string osdIcon: Theme.icons.volHigh
    property string osdTitle: "Volume"
    property string osdValueText: "100%"
    property real osdValue: 1.0
    property bool isMuted: false

    // ---------- faixa nova ----------
    // Ao trocar de música a pílula alarga e mostra capa, título e artista — o
    // aviso que o Windows e os rices de referência dão. Não aparece por cima
    // de janela em tela cheia (jogo, vídeo), nem no boot, nem repetindo a
    // mesma faixa quando o player reemite o título.
    property string mediaTitle: ""
    property string mediaArtist: ""
    property string mediaArt: ""
    property bool mediaPlaying: false
    property string lastMediaKey: ""

    readonly property var mediaPlayer: {
        const list = Mpris.players.values;
        for (let i = 0; i < list.length; i++)
            if (list[i].isPlaying)
                return list[i];
        return list.length > 0 ? list[0] : null;
    }

    function showMedia() {
        const pl = osdWindow.mediaPlayer;
        if (!pl || !pl.trackTitle)
            return;
        const key = pl.trackTitle + "\u0000" + pl.trackArtist;
        if (key === osdWindow.lastMediaKey)
            return;
        osdWindow.lastMediaKey = key;
        if (!osdWindow.ready || !pl.isPlaying)
            return;
        const ws = Hyprland.focusedWorkspace;
        if (ws && ws.hasFullscreen)
            return;
        // Não Perturbe cala também este aviso: é uma notificação como outra.
        if (NotifService.dnd)
            return;
        osdType = "media";
        isMuted = false;
        mediaTitle = pl.trackTitle;
        mediaArtist = pl.trackArtist || pl.identity || "";
        mediaArt = pl.trackArtUrl || "";
        mediaPlaying = pl.isPlaying;
        open = true;
        hideTimer.interval = 3400;
        hideTimer.restart();
    }

    Connections {
        target: osdWindow.mediaPlayer
        function onTrackTitleChanged() { mediaDebounce.restart(); }
        function onIsPlayingChanged() {
            osdWindow.mediaPlaying = osdWindow.mediaPlayer ? osdWindow.mediaPlayer.isPlaying : false;
        }
    }
    // Players costumam emitir o título antes do artista e da capa; esperar um
    // instante evita mostrar a pílula com metade dos dados.
    Timer {
        id: mediaDebounce
        interval: 350
        onTriggered: osdWindow.showMedia()
    }

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [osdWindow.sink, osdWindow.source] }

    Timer {
        id: startupTimer
        interval: 800
        running: true
        onTriggered: osdWindow.ready = true
    }

    Timer {
        id: hideTimer
        interval: 1800
        onTriggered: osdWindow.open = false
    }

    function volIcon(v, muted) {
        if (muted) return Theme.icons.volOff;
        if (v > 0.66) return Theme.icons.volHigh;
        if (v > 0.33) return Theme.icons.volMid;
        return Theme.icons.volLow;
    }

    function showVolume() {
        hideTimer.interval = 1800;
        if (!sink || !sink.audio) return;
        osdType = "volume";
        isMuted = sink.audio.muted;
        osdValue = Math.max(0, Math.min(1, sink.audio.volume));
        osdIcon = volIcon(osdValue, isMuted);
        osdTitle = isMuted ? Theme.t("osd.audio_muted", "Áudio Mutado") : Theme.t("osd.volume", "Volume");
        osdValueText = isMuted ? Theme.t("osd.muted", "Mudo") : Math.round(osdValue * 100) + "%";
        open = true;
        hideTimer.restart();
    }

    function showMic() {
        hideTimer.interval = 1800;
        if (!source || !source.audio) return;
        osdType = "mic";
        isMuted = source.audio.muted;
        osdValue = isMuted ? 0 : 1;
        osdIcon = isMuted ? Theme.icons.micOff : Theme.icons.mic;
        osdTitle = isMuted ? Theme.t("osd.mic_muted", "Microfone Mutado") : Theme.t("osd.mic_active", "Microfone Ativo");
        osdValueText = isMuted ? Theme.t("osd.mutado_short", "Mutado") : Theme.t("osd.active_short", "Ativo");
        open = true;
        hideTimer.restart();
    }

    function showBrightness(val) {
        hideTimer.interval = 1800;
        osdType = "brightness";
        isMuted = false;
        osdValue = Math.max(0, Math.min(1, val));
        osdIcon = Theme.icons.brightness;
        osdTitle = Theme.t("osd.brightness", "Brilho");
        osdValueText = Math.round(osdValue * 100) + "%";
        open = true;
        hideTimer.restart();
    }

    Process {
        id: brUp
        command: ["bash", "-c", "brightnessctl -q set 5%+ && brightnessctl -m | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseInt(text.trim());
                if (!isNaN(val)) osdWindow.showBrightness(val / 100.0);
            }
        }
    }

    Process {
        id: brDown
        command: ["bash", "-c", "brightnessctl -q set 5%- && brightnessctl -m | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseInt(text.trim());
                if (!isNaN(val)) osdWindow.showBrightness(val / 100.0);
            }
        }
    }

    Connections {
        target: osdWindow.sink && osdWindow.sink.audio ? osdWindow.sink.audio : null
        function onVolumeChanged() {
            if (!osdWindow.ready) return;
            osdWindow.showVolume();
        }
        function onMutedChanged() {
            if (!osdWindow.ready) return;
            osdWindow.showVolume();
        }
    }

    Connections {
        target: osdWindow.source && osdWindow.source.audio ? osdWindow.source.audio : null
        function onMutedChanged() {
            if (!osdWindow.ready) return;
            osdWindow.showMic();
        }
    }

    IpcHandler {
        target: "osd"

        function volumeUp(): void {
            if (!osdWindow.sink || !osdWindow.sink.audio) return;
            osdWindow.sink.audio.muted = false;
            osdWindow.sink.audio.volume = Math.min(1.0, Math.round((osdWindow.sink.audio.volume + 0.05) * 100) / 100);
            osdWindow.showVolume();
        }

        function volumeDown(): void {
            if (!osdWindow.sink || !osdWindow.sink.audio) return;
            osdWindow.sink.audio.volume = Math.max(0.0, Math.round((osdWindow.sink.audio.volume - 0.05) * 100) / 100);
            osdWindow.showVolume();
        }

        function volumeMute(): void {
            if (!osdWindow.sink || !osdWindow.sink.audio) return;
            osdWindow.sink.audio.muted = !osdWindow.sink.audio.muted;
            osdWindow.showVolume();
        }

        function micMute(): void {
            if (!osdWindow.source || !osdWindow.source.audio) return;
            osdWindow.source.audio.muted = !osdWindow.source.audio.muted;
            osdWindow.showMic();
        }

        function brightnessUp(): void {
            brUp.running = true;
        }

        function brightnessDown(): void {
            brDown.running = true;
        }

        function test(): void {
            osdWindow.showVolume();
        }

        // Teste do aviso de faixa sem precisar de um player tocando.
        function testMedia(title: string, artist: string): void {
            osdWindow.osdType = "media";
            osdWindow.mediaTitle = title;
            osdWindow.mediaArtist = artist;
            osdWindow.mediaArt = "";
            osdWindow.mediaPlaying = true;
            osdWindow.open = true;
            hideTimer.interval = 3400;
            hideTimer.restart();
        }
    }

    // Pílula flutuante (Caelestia Pill)
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: osdWindow.open ? (Theme.waybarHeight + 14) : (Theme.waybarHeight - 30)
        opacity: osdWindow.open ? 1 : 0
        scale: osdWindow.open ? 1 : 0.88

        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        readonly property bool media: osdWindow.osdType === "media"
        width: media ? 380 : 280
        height: media ? 62 : 46
        radius: height / 2
        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        color: Theme.surface
        border.color: Theme.withAlpha(Theme.primary, 0.45)
        border.width: 1

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.withAlpha(Theme.tileHigh, 0.5)
        }

        // Máscara redonda da capa. Fica fora da vista com layer próprio, em vez
        // de `visible: false`, que não gera a textura que o OpacityMask usa.
        Rectangle {
            id: artMask
            width: 46
            height: 46
            radius: 23
            x: -200
            layer.enabled: true
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 20
            spacing: 12
            visible: pill.media

            Item {
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 23
                    color: Theme.withAlpha(Theme.primary, 0.18)
                    Text {
                        anchors.centerIn: parent
                        text: Theme.icons.music
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 20
                        color: Theme.primary
                        visible: osdArt.status !== Image.Ready
                    }
                }

                Image {
                    id: osdArt
                    anchors.fill: parent
                    source: osdWindow.mediaArt
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                    layer.enabled: true
                    layer.effect: OpacityMask { maskSource: artMask }

                    // Gira como um disco enquanto a música toca.
                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 9000
                        loops: Animation.Infinite
                        running: osdWindow.open && osdWindow.mediaPlaying && pill.media
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: osdWindow.mediaTitle
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.textColor
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: osdWindow.mediaArtist
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.subtext
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: osdWindow.mediaPlaying ? Theme.icons.play : Theme.icons.pause
                font.family: Theme.iconFontFamily
                font.pixelSize: 14
                color: Theme.primary
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12
            visible: !pill.media

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: osdWindow.osdIcon
                font.family: Theme.iconFontFamily
                font.pixelSize: 18
                color: osdWindow.isMuted ? Theme.warning : Theme.primary
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6
                    radius: 3
                    color: Theme.tile
                    visible: osdWindow.osdType !== "mic"

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: 3
                        width: Math.max(0, Math.min(parent.width, parent.width * osdWindow.osdValue))
                        color: osdWindow.isMuted ? Theme.subtext : Theme.primary

                        Behavior on width {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: osdWindow.osdTitle
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: Theme.textColor
                    visible: osdWindow.osdType === "mic"
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: osdWindow.osdValueText
                font.family: Theme.monoFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: osdWindow.isMuted ? Theme.warning : Theme.textColor
                visible: osdWindow.osdType !== "mic"
            }
        }
    }
}
