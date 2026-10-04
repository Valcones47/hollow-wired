import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Modo das telas (Super + P), como o Win + P: só a tela do notebook, duplicar,
// estender ou só a tela externa. Quem aplica é o `rice-display-mode`, que
// também volta sozinho ao modo anterior se a mudança não for confirmada em
// 15 s (tela que não acendeu). Super + P com a janela aberta passa para o
// próximo modo; Enter ou clique aplica.
PanelWindow {
    id: dm

    property bool open: false
    property string mode: "extend"       // salvo
    property int highlight: 2            // índice em `modes`
    property int pending: 0              // segundos até voltar sozinho
    property string previous: ""
    property var mons: []

    readonly property var modes: [
        { id: "internal", title: Theme.t("dm.internal", "Só a tela do notebook"), a: true, b: false, same: false },
        { id: "mirror", title: Theme.t("dm.mirror", "Duplicar"), a: true, b: true, same: true },
        { id: "extend", title: Theme.t("dm.extend", "Estender"), a: true, b: true, same: false },
        { id: "external", title: Theme.t("dm.external", "Só a segunda tela"), a: false, b: true, same: false }
    ]
    readonly property bool hasTwo: dm.mons.length > 1

    function indexOf(id) {
        for (let i = 0; i < dm.modes.length; i++) if (dm.modes[i].id === id) return i;
        return 2;
    }
    function screenNamed(name) {
        const list = Quickshell.screens;
        for (let i = 0; i < list.length; i++) if (list[i].name === name) return list[i];
        return null;
    }
    // Tela que continua acesa no modo escolhido: a janela vai para ela, senão
    // sumiria junto com a tela desligada no meio da confirmação.
    function keepScreenFor(id) {
        for (const m of dm.mons) {
            if (id === "external" ? !m.internal : m.internal) return dm.screenNamed(m.name);
        }
        return null;
    }
    function choose(i) {
        const id = dm.modes[i].id;
        dm.highlight = i;
        if (id === dm.mode) { dm.open = false; return; }
        dm.previous = dm.mode;
        const s = dm.keepScreenFor(id);
        if (s) dm.targetScreen = s;
        setProc.command = ["rice-display-mode", "set", id];
        setProc.running = true;
    }

    Process {
        id: getProc
        command: ["rice-display-mode", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    dm.mode = d.mode || "extend";
                    dm.pending = d.pending || 0;
                    dm.mons = d.monitors || [];
                    if (dm.pending === 0 && !dm.firstLoad) return;
                    if (dm.firstLoad) { dm.highlight = dm.indexOf(dm.mode); dm.firstLoad = false; }
                } catch (e) {}
            }
        }
    }
    property bool firstLoad: true
    Process {
        id: setProc
        onExited: { dm.pending = 15; getProc.running = true; }
    }
    // Enquanto há confirmação pendente, acompanha a contagem.
    Timer {
        interval: 1000
        repeat: true
        running: dm.open && dm.pending > 0
        onTriggered: { dm.pending = Math.max(0, dm.pending - 1); getProc.running = true; }
    }

    // ---------------------------------------------------------- janela
    visible: dm.open
    color: "transparent"
    focusable: true
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-displaymode"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: dm.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    property var targetScreen: null
    screen: targetScreen || Theme.primaryScreen

    onOpenChanged: {
        if (!dm.open) return;
        dm.targetScreen = Theme.focusedScreen();
        dm.firstLoad = true;
        getProc.running = true;
        card.forceActiveFocus();
    }

    // Miniatura de duas telas: acesa = preenchida, apagada = só contorno.
    component ScreenPair: Item {
        id: pair
        property bool a: true
        property bool b: true
        property bool same: false
        property bool active: false
        implicitWidth: 104
        implicitHeight: 52
        Repeater {
            model: [{ on: pair.a, n: "1", x: 0 }, { on: pair.b, n: pair.same ? "1" : "2", x: 56 }]
            delegate: Rectangle {
                required property var modelData
                x: modelData.x
                y: 6
                width: 48
                height: 32
                radius: 4
                color: modelData.on ? (pair.active ? Theme.primary : Theme.withAlpha(Theme.textColor, 0.75)) : "transparent"
                border.width: modelData.on ? 0 : 1.5
                border.color: Theme.withAlpha(Theme.subtext, 0.5)
                Text {
                    anchors.centerIn: parent
                    visible: modelData.on
                    text: modelData.n
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: Theme.background
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, dm.open ? 0.45 : 0)
        MouseArea { anchors.fill: parent; onClicked: if (dm.pending === 0) dm.open = false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, cardCol.implicitWidth + 48)
        height: cardCol.implicitHeight + 44
        radius: 18
        color: Theme.background
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.35)
        focus: true
        MouseArea { anchors.fill: parent }

        Keys.onPressed: (ev) => {
            if (ev.key === Qt.Key_Escape) { if (dm.pending === 0) dm.open = false; }
            else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Down) dm.highlight = (dm.highlight + 1) % dm.modes.length;
            else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Up) dm.highlight = (dm.highlight + dm.modes.length - 1) % dm.modes.length;
            else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) dm.choose(dm.highlight);
            else return;
            ev.accepted = true;
        }

        ColumnLayout {
            id: cardCol
            anchors.centerIn: parent
            spacing: 18

            Text {
                text: Theme.t("dm.title", "Telas")
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.weight: Font.DemiBold
                color: Theme.textColor
            }

            Text {
                visible: !dm.hasTwo
                Layout.maximumWidth: 420
                wrapMode: Text.WordWrap
                text: Theme.t("dm.one_screen", "Só uma tela conectada. Ligue um monitor para escolher como usar as duas.")
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.subtext
            }

            // Grade vertical numa tela estreita (em pé), linha numa larga.
            GridLayout {
                visible: dm.hasTwo
                columns: dm.width < 760 ? 2 : 4
                columnSpacing: 10
                rowSpacing: 10
                Repeater {
                    model: dm.modes
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: dm.mode === modelData.id
                        readonly property bool isHi: dm.highlight === index
                        implicitWidth: 160
                        implicitHeight: 124
                        radius: 12
                        color: tile.isHi ? Theme.tileHigh : (tileArea.containsMouse ? Theme.withAlpha(Theme.tileHigh, 0.6) : Theme.withAlpha(Theme.tile, 0.6))
                        border.width: tile.isHi ? 1.5 : 0
                        border.color: Theme.withAlpha(Theme.primary, 0.7)
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 10
                            ScreenPair {
                                Layout.alignment: Qt.AlignHCenter
                                a: tile.modelData.a
                                b: tile.modelData.b
                                same: tile.modelData.same
                                active: tile.isCurrent
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: tile.modelData.title
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: tile.isCurrent ? Font.DemiBold : Font.Normal
                                color: tile.isCurrent ? Theme.textColor : Theme.subtext
                            }
                        }
                        MouseArea {
                            id: tileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dm.choose(tile.index)
                        }
                    }
                }
            }

            // Confirmação: sem resposta, o rice-display-mode volta sozinho.
            RowLayout {
                visible: dm.pending > 0
                Layout.fillWidth: true
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: Theme.t("dm.keep_q", "Manter esta configuração? Volta à anterior em %1 s.").replace("%1", dm.pending)
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.textColor
                }
                Rectangle {
                    implicitWidth: backText.implicitWidth + 28
                    implicitHeight: 34
                    radius: 8
                    color: backArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.8)
                    Text { id: backText; anchors.centerIn: parent; text: Theme.t("dm.revert", "Voltar"); font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.textColor }
                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(["sh", "-c", "rice-display-mode set \"$1\" && rice-display-mode keep", "_", dm.previous || "extend"]);
                            dm.pending = 0;
                            dm.open = false;
                        }
                    }
                }
                Rectangle {
                    implicitWidth: keepText.implicitWidth + 28
                    implicitHeight: 34
                    radius: 8
                    color: keepArea.pressed ? Theme.withAlpha(Theme.primary, 0.75) : Theme.primary
                    Text { id: keepText; anchors.centerIn: parent; text: Theme.t("dm.keep", "Manter"); font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Medium; color: Theme.background }
                    MouseArea {
                        id: keepArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(["rice-display-mode", "keep"]);
                            dm.pending = 0;
                            dm.open = false;
                        }
                    }
                }
            }

            Text {
                visible: dm.hasTwo && dm.pending === 0
                text: Theme.t("dm.hint", "Super + P de novo ou setas: escolher  ·  Enter: aplicar  ·  Esc: fechar")
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.withAlpha(Theme.subtext, 0.7)
            }
        }
    }

    IpcHandler {
        target: "displaymode"
        // Como o Win + P: a primeira vez abre; com a janela aberta, passa para
        // o próximo modo (Enter aplica).
        function toggle(): void {
            if (!dm.open) { dm.open = true; return; }
            if (dm.pending === 0) dm.highlight = (dm.highlight + 1) % dm.modes.length;
        }
        function open(): void { dm.open = true; }
        function hide(): void { if (dm.pending === 0) dm.open = false; }
    }
}
