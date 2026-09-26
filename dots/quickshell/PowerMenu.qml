import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "."

// Menu de energia (estilo Caelestia): uma barrinha própria que sai da borda
// direita só com as ações de sessão. Abre pelo botão de energia da barra ou
// `qs ipc call power toggle`.
//   - setas ↑/↓ escolhem, Enter executa, Esc (ou clique fora) fecha;
//   - sair, reiniciar e desligar pedem um segundo clique (o botão fica
//     vermelho e o rótulo avisa); bloquear e suspender vão direto.
PanelWindow {
    id: pm

    property bool open: false
    visible: open || card.opacity > 0
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-powermenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IpcHandler {
        target: "power"
        function toggle(): void { pm.open = !pm.open; }
        function hide(): void { pm.open = false; }
    }

    readonly property var actions: [
        { key: "lock", icon: Theme.icons.lock, label: Theme.t("power.lock", "Bloquear"), confirm: false },
        { key: "suspend", icon: Theme.icons.sleep, label: Theme.t("power.suspend", "Suspender"), confirm: false },
        { key: "logout", icon: Theme.icons.logout, label: Theme.t("power.logout", "Sair da sessão"), confirm: true },
        { key: "reboot", icon: Theme.icons.restart, label: Theme.t("power.reboot", "Reiniciar"), confirm: true },
        { key: "poweroff", icon: Theme.icons.power, label: Theme.t("power.off", "Desligar"), confirm: true }
    ]
    property int sel: -1
    property string armed: ""
    Timer { id: disarm; interval: 3500; onTriggered: pm.armed = "" }

    onOpenChanged: {
        armed = "";
        sel = -1;
        if (open) card.forceActiveFocus();
    }

    function run(a) {
        if (a.confirm && armed !== a.key) {
            armed = a.key;
            disarm.restart();
            return;
        }
        armed = "";
        open = false;
        Quickshell.execDetached(["rice-session-action", a.key]);
    }

    // clique fora fecha
    MouseArea { anchors.fill: parent; onClicked: pm.open = false }

    Rectangle {
        id: card
        readonly property int btn: 60
        width: btn + 24
        height: col.implicitHeight + 28
        anchors.verticalCenter: parent.verticalCenter
        x: pm.open ? parent.width - width - Theme.frameThickness : parent.width + 10
        Behavior on x { NumberAnimation { duration: Theme.ms(260); easing.type: Easing.OutCubic } }
        opacity: pm.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.ms(200) } }
        topLeftRadius: 22
        bottomLeftRadius: 22
        color: Theme.surface
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.3)
        focus: true

        Keys.onEscapePressed: pm.open = false
        Keys.onUpPressed: pm.sel = pm.sel <= 0 ? pm.actions.length - 1 : pm.sel - 1
        Keys.onDownPressed: pm.sel = (pm.sel + 1) % pm.actions.length
        Keys.onReturnPressed: if (pm.sel >= 0) pm.run(pm.actions[pm.sel])
        Keys.onEnterPressed: if (pm.sel >= 0) pm.run(pm.actions[pm.sel])

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.centerIn: parent
            spacing: 10

            // Quem está logado (só enfeite, como no Caelestia).
            ClippingRectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: card.btn - 8
                Layout.preferredHeight: card.btn - 8
                Layout.bottomMargin: 4
                radius: width / 2
                color: Theme.tileHigh
                AnimatedImage {
                    id: face
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    source: "file://" + Quickshell.env("HOME") + "/.face.webp"
                    playing: pm.open
                    onStatusChanged: if (status === Image.Error) source = "file://" + Quickshell.env("HOME") + "/.face"
                }
                Text {
                    anchors.centerIn: parent
                    visible: face.status !== Image.Ready
                    text: Theme.icons.account
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 24
                    color: Theme.subtext
                }
            }

            Repeater {
                model: pm.actions
                delegate: Rectangle {
                    id: b
                    required property var modelData
                    required property int index
                    readonly property bool hot: area.containsMouse || pm.sel === index
                    readonly property bool isArmed: pm.armed === modelData.key
                    Layout.preferredWidth: card.btn
                    Layout.preferredHeight: card.btn
                    radius: 18
                    color: isArmed ? Theme.critical
                         : hot ? (modelData.key === "poweroff" ? Theme.withAlpha(Theme.critical, 0.3) : Theme.withAlpha(Theme.primary, 0.3))
                         : Theme.tile
                    Behavior on color { ColorAnimation { duration: Theme.ms(140) } }
                    scale: area.pressed ? 0.93 : hot ? 1.05 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.ms(120); easing.type: Easing.OutCubic } }

                    // Entrada em sequência (de cima para baixo).
                    opacity: pm.open ? 1 : 0
                    Behavior on opacity { SequentialAnimation {
                        PauseAnimation { duration: pm.open ? b.index * 35 : 0 }
                        NumberAnimation { duration: Theme.ms(160) }
                    } }

                    Text {
                        anchors.centerIn: parent
                        text: b.modelData.icon
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 24
                        color: b.isArmed ? Theme.background
                             : b.modelData.key === "poweroff" ? Theme.critical
                             : b.hot ? Theme.primary : Theme.textColor
                    }

                    // Rótulo à esquerda do botão.
                    Rectangle {
                        visible: b.hot || b.isArmed
                        anchors.right: parent.left
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: lbl.implicitWidth + 20
                        height: 30
                        radius: 9
                        color: b.isArmed ? Theme.critical : Theme.surface
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.outline, 0.3)
                        Text {
                            id: lbl
                            anchors.centerIn: parent
                            text: b.isArmed ? Theme.t("power.confirm", "Clique de novo: %1").replace("%1", b.modelData.label.toLowerCase())
                                            : b.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: b.isArmed ? Theme.background : Theme.textColor
                        }
                    }

                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: pm.sel = b.index
                        onClicked: pm.run(b.modelData)
                    }
                }
            }
        }
    }
}
