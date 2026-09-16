import QtQuick
import QtQuick.Layouts
import "."

// Slider horizontal (0-1) com ícone clicável à esquerda e % à direita.
// `moved(v)` dispara enquanto arrasta/clica/rola; `value` é só exibição
// (quem usa amarra no valor real, ex.: volume do PipeWire).
RowLayout {
    id: root
    property real value: 0
    property string icon: ""
    property string label: ""
    property bool dimmed: false
    readonly property bool dragging: area.pressed
    signal moved(real v)
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
                    width: parent.width * Math.max(0, Math.min(1, root.value))
                    height: parent.height
                    radius: 3
                    color: root.dimmed ? Theme.subtext : Theme.primary
                }
            }
            Rectangle {
                x: (track.width - width) * Math.max(0, Math.min(1, root.value))
                anchors.verticalCenter: parent.verticalCenter
                width: area.pressed || area.containsMouse ? 16 : 12
                height: width
                radius: width / 2
                color: Theme.textColor
                Behavior on width { NumberAnimation { duration: 100 } }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                function set(mx) { root.moved(Math.max(0, Math.min(1, (mx - 4) / track.width))); }
                onPressed: mouse => set(mouse.x)
                onPositionChanged: mouse => { if (pressed) set(mouse.x); }
                onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
            }
        }
    }

    Text {
        Layout.preferredWidth: 34
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.value * 100) + "%"
        font.family: Theme.fontFamily
        font.pixelSize: 11
        color: Theme.subtext
    }
}
