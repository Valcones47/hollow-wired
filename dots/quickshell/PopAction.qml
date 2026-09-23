import QtQuick
import QtQuick.Layouts
import "."

// Linha clicável dentro de um popup (sidebar/top bar), com confirmação
// opcional em dois cliques e estado "selecionado" opcional.
Rectangle {
    id: act
    property string icon: ""
    property string label: ""
    property string detail: ""
    property bool needsConfirm: false
    property bool selected: false
    property bool armed: false
    signal activated()

    Layout.fillWidth: true
    implicitWidth: actRow.implicitWidth + 20
    implicitHeight: 32
    radius: 9
    color: armed ? Theme.withAlpha(Theme.critical, 0.5)
        : actArea.containsMouse ? Theme.tileHigh
        : selected ? Theme.withAlpha(Theme.primary, 0.22) : Theme.tile
    Behavior on color { ColorAnimation { duration: Theme.ms(120) } }

    Timer { id: actDisarm; interval: 3000; onTriggered: act.armed = false }

    RowLayout {
        id: actRow
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8
        Text {
            visible: act.icon !== "" || act.armed
            text: act.armed ? Theme.icons.confirm : act.icon
            font.family: Theme.iconFontFamily
            font.pixelSize: 16
            color: act.selected ? Theme.primary : Theme.subtext
        }
        Text {
            Layout.fillWidth: true
            text: act.armed ? "Clique de novo para confirmar" : act.label
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: act.selected ? Font.DemiBold : Font.Normal
            color: Theme.textColor
        }
        Text {
            visible: act.detail !== "" && !act.armed
            text: act.detail
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.subtext
        }
    }
    MouseArea {
        id: actArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (!act.needsConfirm || act.armed) {
                actDisarm.stop();
                act.armed = false;
                act.activated();
            } else {
                act.armed = true;
                actDisarm.restart();
            }
        }
    }
}
