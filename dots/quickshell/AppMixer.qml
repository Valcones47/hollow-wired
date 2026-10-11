import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "."

// Mixer de áudio (popup da barra de cima e da barra lateral), no desenho do
// Serpentinum: quadrado com o volume da saída principal, abas Saídas / Entradas
// / Apps e um cartão por dispositivo ou app com barra larga.
//
// Os fluxos dos apps só são vinculados com o mixer aberto (`active`): vinculá-los
// o tempo todo derrubava o Quickshell ao abrir jogos (ver TopBar.qml).
ColumnLayout {
    id: mx

    property var pal: Theme
    property bool active: false
    property string tab: "apps"          // out | in | apps
    readonly property bool dragging: mx._drags > 0
    property int _drags: 0

    spacing: 10

    // ---------------------------------------------------------- dados
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink)
    readonly property var sourceCandidates: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && !n.isSink)
    readonly property var sources: mx.sourceCandidates.filter(n => (n.properties["media.class"] || "") === "Audio/Source")
    // Sem depender de `properties` (só chegam depois do vínculo).
    readonly property var streamCandidates: Pipewire.nodes.values.filter(n => n.audio && n.isStream && n.isSink)
    readonly property var streams: mx.streamCandidates.filter(n =>
        (n.properties["media.class"] || "") === "Stream/Output/Audio"
        && String(n.properties["node.virtual"] || "") !== "true"
        && n.name !== "hollow_eq_out" && !String(n.name).startsWith("output.loopback"))

    PwObjectTracker {
        objects: [mx.sink, mx.source].concat(mx.active ? mx.sinks.concat(mx.sourceCandidates, mx.streamCandidates) : [])
    }

    // Nomes genéricos que o app manda no lugar do próprio nome (o Discord
    // chega como "WEBRTC VoiceEngine"): nesses casos vale o executável.
    readonly property var _generic: ["webrtc voiceengine", "chromium", "playback", "pulseaudio", "audio-src",
                                     "alsa plug-in", "speech-dispatcher", "sdl application", "wine", ""]
    function _isGeneric(s) {
        const l = String(s || "").toLowerCase();
        for (const g of mx._generic) if (l === g || (g !== "" && l.startsWith(g))) return true;
        return false;
    }
    function nodeName(n) {
        if (!n) return "";
        const p = n.properties || {};
        return p["node.description"] || p["node.nick"] || n.description || n.nickname || n.name || "";
    }
    function appBinary(n) { return String((n.properties || {})["application.process.binary"] || ""); }
    function appLabel(n) {
        const p = n.properties || {};
        const name = p["application.name"] || n.name || "";
        if (!mx._isGeneric(name)) return name;
        const bin = mx.appBinary(n);
        if (bin !== "") {
            try {
                const e = DockConfig.entryForWindow(bin, "");
                if (e && e.name) return e.name;
            } catch (err) {}
            return bin.charAt(0).toUpperCase() + bin.slice(1);
        }
        return name || Theme.t("mixer.unknown_app", "App desconhecido");
    }
    function appIcon(n) {
        const p = n.properties || {};
        const bin = mx.appBinary(n);
        const key = bin !== "" ? bin : (p["application.name"] || n.name || "");
        try {
            if (p["application.icon_name"]) return String(DockConfig.iconSource(p["application.icon_name"], key) || "");
            return String(DockConfig.iconForWindow(key, "") || "");
        } catch (err) { return ""; }
    }

    // Um cartão por app: os vários fluxos do mesmo app (jogos abrem quatro)
    // andam juntos.
    readonly property var appGroups: {
        const out = [], idx = {};
        for (const n of mx.streams) {
            const label = mx.appLabel(n);
            if (idx[label] === undefined) {
                idx[label] = out.length;
                const media = String((n.properties || {})["media.name"] || "");
                out.push({ label: label, nodes: [n], icon: mx.appIcon(n), media: media });
            } else out[idx[label]].nodes.push(n);
        }
        return out;
    }
    function groupSub(g) {
        if (g.nodes.length > 1) return Theme.t("mixer.streams_n", "%1 fluxos").replace("%1", g.nodes.length);
        const m = g.media;
        let sub = (m === "" || m === g.label || mx._isGeneric(m) || m === "playStream") ? mx.appBinary(g.nodes[0]) : m;
        return sub.toLowerCase() === g.label.toLowerCase() ? "" : sub;
    }
    function volOf(n) { return n && n.audio ? n.audio.volume : 0; }
    function mutedOf(n) { return n && n.audio ? n.audio.muted : true; }

    // ---------------------------------------------------------- componentes
    // Barra larga sem alça, como no print. Guarda o valor local enquanto
    // arrasta e por 800 ms depois (o PipeWire demora a refletir).
    component MixSlider: Item {
        id: sl
        property real value: 0
        property real max: 1
        property color accent: Theme.primary
        property color track: Theme.tile
        property bool muted: false
        property real local: -1
        readonly property real shown: sl.local >= 0 ? sl.local : sl.value
        readonly property bool dragging: area.pressed
        signal moved(real v)
        implicitHeight: 12
        Layout.fillWidth: true

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 10
            radius: 5
            color: sl.track
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, sl.shown / sl.max))
                height: parent.height
                radius: 5
                color: sl.muted ? Theme.withAlpha(sl.accent, 0.35) : sl.accent
            }
        }
        Timer { id: settle; interval: 800; onTriggered: sl.local = -1 }
        MouseArea {
            id: area
            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -6
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            function setAt(x) {
                const v = Math.max(0, Math.min(1, x / width)) * sl.max;
                sl.local = v;
                settle.restart();
                sl.moved(v);
            }
            onPressed: (m) => setAt(m.x)
            onPositionChanged: (m) => { if (pressed) setAt(m.x); }
            onWheel: (w) => {
                const step = (w.angleDelta.y > 0 ? 0.05 : -0.05);
                const v = Math.max(0, Math.min(sl.max, sl.shown + step));
                sl.local = v;
                settle.restart();
                sl.moved(v);
            }
        }
    }

    component MuteBtn: Rectangle {
        id: mb
        property bool muted: false
        property string icon: ""
        property color fg: Theme.textColor
        signal clicked()
        implicitWidth: 28
        implicitHeight: 28
        radius: 14
        color: mbArea.containsMouse ? Theme.withAlpha(mb.fg, 0.12) : "transparent"
        Text {
            anchors.centerIn: parent
            text: mb.icon
            font.family: Theme.iconFontFamily
            font.pixelSize: 15
            color: mb.muted ? Theme.withAlpha(mb.fg, 0.45) : mb.fg
        }
        MouseArea {
            id: mbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mb.clicked()
        }
    }

    function volIcon(n) {
        if (!n || !n.audio || n.audio.muted) return Theme.icons.volOff;
        const v = n.audio.volume;
        return v > 0.66 ? Theme.icons.volHigh : v > 0.33 ? Theme.icons.volMid : Theme.icons.volLow;
    }
    function pct(v) { return Math.round(v * 100) + "%"; }

    // ---------------------------------------------------------- cabeçalho
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 104
        radius: 16
        color: Theme.withAlpha(mx.pal.tile, 0.9)
        border.width: 1
        border.color: Theme.withAlpha(mx.pal.outline, 0.25)

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 14

            // quadrado que enche com o volume
            Rectangle {
                id: bigVol
                readonly property real v: mx.volOf(mx.sink)
                Layout.preferredWidth: 80
                Layout.preferredHeight: 80
                radius: 14
                color: Theme.withAlpha(mx.pal.background, 0.6)
                border.width: 2
                border.color: Theme.withAlpha(mx.pal.primary, 0.8)
                clip: true
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 2
                    height: (parent.height - 4) * Math.max(0, Math.min(1, bigVol.v / AudioPrefs.maxVolume))
                    radius: 12
                    color: mx.mutedOf(mx.sink) ? Theme.withAlpha(mx.pal.primary, 0.3) : mx.pal.primary
                    Behavior on height { NumberAnimation { duration: Theme.ms(150) } }
                }
                Text {
                    anchors.centerIn: parent
                    text: mx.pct(bigVol.v)
                    font.family: Theme.monoFamily
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    color: bigVol.v / AudioPrefs.maxVolume > 0.55 ? mx.pal.background : mx.pal.textColor
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (mx.sink && mx.sink.audio) mx.sink.audio.muted = !mx.sink.audio.muted
                    onWheel: (w) => {
                        if (!mx.sink || !mx.sink.audio) return;
                        const v = mx.sink.audio.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05);
                        mx.sink.audio.volume = Math.max(0, Math.min(AudioPrefs.maxVolume, v));
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: mx.nodeName(mx.sink) || Theme.t("mixer.no_output", "Sem saída de áudio")
                    elide: Text.ElideRight
                    font.family: Theme.monoFamily
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    color: mx.pal.textColor
                }
                Text {
                    text: Theme.t("mixer.main_volume", "Volume da saída principal")
                    font.family: Theme.monoFamily
                    font.pixelSize: 12
                    color: mx.pal.subtext
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 8
                    MuteBtn {
                        icon: mx.volIcon(mx.sink)
                        muted: mx.mutedOf(mx.sink)
                        fg: mx.pal.textColor
                        onClicked: if (mx.sink && mx.sink.audio) mx.sink.audio.muted = !mx.sink.audio.muted
                    }
                    MixSlider {
                        value: mx.volOf(mx.sink)
                        max: AudioPrefs.maxVolume
                        accent: mx.pal.primary
                        track: Theme.withAlpha(mx.pal.subtext, 0.25)
                        muted: mx.mutedOf(mx.sink)
                        onDraggingChanged: mx._drags += dragging ? 1 : -1
                        onMoved: (v) => { if (mx.sink && mx.sink.audio) mx.sink.audio.volume = v; }
                    }
                    Text {
                        Layout.preferredWidth: 40
                        horizontalAlignment: Text.AlignRight
                        text: mx.pct(mx.volOf(mx.sink))
                        font.family: Theme.monoFamily
                        font.pixelSize: 12
                        color: mx.pal.subtext
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- abas
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 40
        radius: 12
        color: Theme.withAlpha(mx.pal.tile, 0.9)

        RowLayout {
            anchors.fill: parent
            anchors.margins: 3
            spacing: 3
            Repeater {
                model: [{ id: "out", t: Theme.t("mixer.tab_out", "Saídas") },
                        { id: "in", t: Theme.t("mixer.tab_in", "Entradas") },
                        { id: "apps", t: Theme.t("mixer.tab_apps", "Apps") }]
                delegate: Rectangle {
                    id: tabBtn
                    required property var modelData
                    readonly property bool on: mx.tab === tabBtn.modelData.id
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 10
                    color: tabBtn.on ? mx.pal.primary : (tabArea.containsMouse ? Theme.withAlpha(mx.pal.textColor, 0.06) : "transparent")
                    Behavior on color { ColorAnimation { duration: Theme.ms(120) } }
                    Text {
                        anchors.centerIn: parent
                        text: tabBtn.modelData.t
                        font.family: Theme.monoFamily
                        font.pixelSize: 13
                        color: tabBtn.on ? mx.pal.background : mx.pal.subtext
                    }
                    MouseArea {
                        id: tabArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mx.tab = tabBtn.modelData.id
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- lista
    // Cartão: ícone, nome, descrição e a barra com o botão de mudo.
    component MixCard: Rectangle {
        id: card
        property var p: Theme
        property string title: ""
        property string sub: ""
        property string iconSrc: ""
        property string glyph: ""
        property bool selected: false
        property bool selectable: false
        property real value: 0
        property real max: 1
        property bool muted: false
        property string volIconText: ""
        readonly property bool dragging: cs.dragging
        signal moved(real v)
        signal muteClicked()
        signal picked()
        Layout.fillWidth: true
        implicitHeight: 78
        radius: 14
        color: card.selected ? Theme.withAlpha(card.p.primary, 0.14) : Theme.withAlpha(card.p.tile, 0.9)
        border.width: 1
        border.color: card.selected ? Theme.withAlpha(card.p.primary, 0.6) : Theme.withAlpha(card.p.outline, 0.22)

        MouseArea {
            anchors.fill: parent
            enabled: card.selectable
            cursorShape: card.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: card.picked()
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            anchors.topMargin: 10
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: 13
                    color: Theme.withAlpha(card.p.textColor, 0.9)
                    Image {
                        anchors.centerIn: parent
                        width: 18; height: 18
                        visible: card.iconSrc !== ""
                        source: card.iconSrc
                        sourceSize: Qt.size(36, 36)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: card.iconSrc === ""
                        text: card.glyph
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 14
                        color: card.p.background
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: card.title
                        elide: Text.ElideRight
                        font.family: Theme.monoFamily
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: card.p.textColor
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: card.sub !== ""
                        text: card.sub
                        elide: Text.ElideRight
                        font.family: Theme.monoFamily
                        font.pixelSize: 11
                        color: card.p.subtext
                    }
                }
                Text {
                    visible: card.selected
                    text: Theme.icons.check
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 15
                    color: card.p.primary
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MuteBtn {
                    implicitWidth: 24
                    implicitHeight: 24
                    icon: card.volIconText
                    muted: card.muted
                    fg: card.p.textColor
                    onClicked: card.muteClicked()
                }
                MixSlider {
                    id: cs
                    value: card.value
                    max: card.max
                    accent: card.p.primary
                    track: Theme.withAlpha(card.p.subtext, 0.25)
                    muted: card.muted
                    onMoved: (v) => card.moved(v)
                }
                Text {
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(cs.shown * 100) + "%"
                    font.family: Theme.monoFamily
                    font.pixelSize: 11
                    color: card.p.subtext
                }
            }
        }
    }

    Flickable {
        id: listScroll
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(listCol.implicitHeight, 340)
        contentHeight: listCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: listCol
            width: listScroll.width
            spacing: 8

            // ---- saídas
            Repeater {
                model: mx.tab === "out" ? mx.sinks : []
                delegate: MixCard {
                    required property var modelData
                    p: mx.pal
                    title: mx.nodeName(modelData)
                    sub: modelData === mx.sink ? Theme.t("mixer.default", "Padrão") : (modelData.name || "")
                    glyph: (String((modelData.properties || {})["device.form-factor"] || "")).indexOf("head") >= 0
                           ? Theme.icons.headphones : Theme.icons.speaker
                    selected: modelData === mx.sink
                    selectable: true
                    value: mx.volOf(modelData)
                    max: AudioPrefs.maxVolume
                    muted: mx.mutedOf(modelData)
                    volIconText: mx.volIcon(modelData)
                    onDraggingChanged: mx._drags += dragging ? 1 : -1
                    onMoved: (v) => { if (modelData.audio) modelData.audio.volume = v; }
                    onMuteClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                    onPicked: Pipewire.preferredDefaultAudioSink = modelData
                }
            }

            // ---- entradas
            Repeater {
                model: mx.tab === "in" ? mx.sources : []
                delegate: MixCard {
                    required property var modelData
                    p: mx.pal
                    title: mx.nodeName(modelData)
                    sub: modelData === mx.source ? Theme.t("mixer.default", "Padrão") : (modelData.name || "")
                    glyph: Theme.icons.mic
                    selected: modelData === mx.source
                    selectable: true
                    value: mx.volOf(modelData)
                    max: 1
                    muted: mx.mutedOf(modelData)
                    volIconText: mx.mutedOf(modelData) ? Theme.icons.micOff : Theme.icons.mic
                    onDraggingChanged: mx._drags += dragging ? 1 : -1
                    onMoved: (v) => { if (modelData.audio) modelData.audio.volume = v; }
                    onMuteClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                    onPicked: Pipewire.preferredDefaultAudioSource = modelData
                }
            }

            // ---- apps
            Repeater {
                model: mx.tab === "apps" ? mx.appGroups : []
                delegate: MixCard {
                    required property var modelData
                    readonly property var first: modelData.nodes[0]
                    p: mx.pal
                    title: modelData.label
                    sub: mx.groupSub(modelData)
                    iconSrc: modelData.icon
                    glyph: Theme.icons.music
                    value: mx.volOf(first)
                    max: AudioPrefs.maxVolume
                    muted: mx.mutedOf(first)
                    volIconText: mx.volIcon(first)
                    onDraggingChanged: mx._drags += dragging ? 1 : -1
                    onMoved: (v) => { for (const n of modelData.nodes) if (n.audio) n.audio.volume = v; }
                    onMuteClicked: {
                        const m = !mx.mutedOf(first);
                        for (const n of modelData.nodes) if (n.audio) n.audio.muted = m;
                    }
                }
            }
            Text {
                visible: (mx.tab === "apps" && mx.appGroups.length === 0)
                         || (mx.tab === "in" && mx.sources.length === 0)
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.bottomMargin: 6
                horizontalAlignment: Text.AlignHCenter
                text: mx.tab === "apps" ? Theme.t("mixer.empty", "Nenhum app tocando som agora")
                                        : Theme.t("mixer.no_inputs", "Nenhuma entrada de áudio")
                font.family: Theme.monoFamily
                font.pixelSize: 12
                color: mx.pal.subtext
            }
        }
    }

    // ---- permitir 150 % (mesmo interruptor da aba Áudio das configurações)
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: Theme.t("mixer.boost", "Permitir até 150%")
            font.family: Theme.monoFamily
            font.pixelSize: 12
            color: mx.pal.subtext
        }
        Rectangle {
            id: boostSw
            readonly property bool on: AudioPrefs.maxVolume > 1
            implicitWidth: 36
            implicitHeight: 20
            radius: 10
            color: boostSw.on ? mx.pal.primary : Theme.withAlpha(mx.pal.subtext, 0.3)
            Rectangle {
                width: 14; height: 14; radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: boostSw.on ? parent.width - width - 3 : 3
                color: boostSw.on ? mx.pal.background : mx.pal.textColor
                Behavior on x { NumberAnimation { duration: Theme.ms(120) } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const on = AudioPrefs.maxVolume <= 1;
                    AudioPrefs.setMax(on ? 150 : 100);
                    if (!on) for (const n of mx.streams.concat([mx.sink]))
                        if (n && n.audio && n.audio.volume > 1) n.audio.volume = 1;
                }
            }
        }
    }
}
