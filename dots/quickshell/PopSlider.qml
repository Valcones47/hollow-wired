import QtQuick
import QtQuick.Layouts
import "."

// Slider horizontal (0-1) com ícone clicável à esquerda e % à direita.
// `moved(v)` dispara enquanto arrasta/clica/rola; `value` é só exibição
// (quem usa amarra no valor real, ex.: volume do PipeWire).
RowLayout {
    id: root
    property real value: 0
    // Teto do slider (1 = 100%). Volume de saída usa AudioPrefs.maxVolume (até 1.5).
    property real max: 1
    property string icon: ""
    property string label: ""
    property bool dimmed: false
    readonly property bool dragging: area.pressed
    signal moved(real v)

    // O valor real (PipeWire, backlight) só volta depois de aplicado; enquanto
    // o usuário rola ou arrasta, o slider mostra e soma a partir do valor
    // local. Antes cada passo da roda partia do valor antigo ainda não
    // atualizado, e o slider "voltava" para trás.
    property real localValue: -1
    readonly property real shown: localValue >= 0 ? localValue : Math.max(0, Math.min(root.max, value))
    property real wheelAcc: 0
    function setLocal(v) {
        localValue = Math.max(0, Math.min(root.max, v));
        settleTimer.restart();
        moved(localValue);
    }
    // Roda: acumula o delta (mouse comum = 120 por clique, touchpad manda
    // vários pedacinhos) e anda 5% por clique inteiro.
    function wheelStep(dy) {
        wheelAcc += dy;
        const steps = Math.trunc(wheelAcc / 120);
        if (steps === 0) return;
        wheelAcc -= steps * 120;
        setLocal(Math.round((shown + steps * 0.05) * 20) / 20);
    }
    Timer {
        id: settleTimer
        interval: 800
        onTriggered: if (!area.pressed) { root.localValue = -1; root.wheelAcc = 0; }
    }
    signal iconClicked()

    Layout.fillWidth: true
    spacing: 10

    Rectangle {
        implicitWidth: 30
        implicitHeight: 30
        radius: 15
        color: iconArea.containsMouse ? Theme.tileHigh : "transparent"
        Text {
            anchors.centerIn: parent
            text: root.icon
            font.family: Theme.iconFontFamily
            font.pixelSize: 18
            color: root.dimmed ? Theme.subtext : Theme.primary
        }
        MouseArea {
            id: iconArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.iconClicked()
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3
        Text {
            visible: root.label !== ""
            Layout.fillWidth: true
            text: root.label
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.subtext
        }
        Item {
            id: track
            Layout.fillWidth: true
            implicitHeight: 16
            implicitWidth: 180

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: Theme.withAlpha(Theme.primary, 0.2)
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.shown / root.max))
                    height: parent.height
                    radius: 3
                    color: root.dimmed ? Theme.subtext : Theme.primary
                }
            }
            Rectangle {
                x: (track.width - width) * Math.max(0, Math.min(1, root.shown / root.max))
                anchors.verticalCenter: parent.verticalCenter
                width: area.pressed || area.containsMouse ? 16 : 12
                height: width
                radius: width / 2
                color: Theme.textColor
                Behavior on width { NumberAnimation { duration: Theme.ms(100) } }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                function set(mx) { root.setLocal((mx - 4) / track.width * root.max); }
                onPressed: mouse => set(mouse.x)
                onPositionChanged: mouse => { if (pressed) set(mouse.x); }
                onReleased: settleTimer.restart()
                onWheel: wheel => root.wheelStep(wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x)
            }
        }
    }

    Text {
        Layout.preferredWidth: 34
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.shown * 100) + "%"
        font.family: Theme.fontFamily
        font.pixelSize: 11
        color: Theme.subtext
    }
}
