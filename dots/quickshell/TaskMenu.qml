import QtQuick
import QtQuick.Layouts
import "."

// Menu de contexto (clique direito) do Gerenciador de Tarefas. Cobre a área do
// pai: clicar fora ou apertar Esc fecha. Itens:
//   { id, label }                       ação
//   { id, label, checked: true }        com marca
//   { label, enabled: false }           desabilitado
//   { header: "Texto" }                 título de grupo
//   { sep: true }                       separador
//   { id, label, danger: true }         destaque de ação destrutiva
Item {
    id: menu

    property var items: []
    property bool shown: false
    property real px: 0
    property real py: 0
    signal chosen(string id)

    visible: menu.shown
    anchors.fill: parent
    z: 100

    function openAt(x, y, list) {
        menu.items = list;
        menu.px = x;
        menu.py = y;
        menu.shown = true;
        menu.forceActiveFocus();
    }
    function close() { menu.shown = false; }

    Keys.onEscapePressed: menu.close()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: menu.close()
    }

    Rectangle {
        id: box
        width: 252
        height: col.implicitHeight + 12
        x: Math.max(6, Math.min(menu.width - width - 6, menu.px))
        y: Math.max(6, Math.min(menu.height - height - 6, menu.py))
        radius: 12
        color: Theme.background
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.45)

        Column {
            id: col
            x: 6
            y: 6
            width: parent.width - 12

            Repeater {
                model: menu.items
                delegate: Item {
                    id: it
                    required property var modelData
                    readonly property bool sep: !!modelData.sep
                    readonly property bool head: modelData.header !== undefined
                    readonly property bool live: !sep && !head && modelData.enabled !== false
                    width: col.width
                    height: sep ? 9 : (head ? 26 : 32)

                    Rectangle {
                        visible: it.sep
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8; width: parent.width - 16; height: 1
                        color: Theme.withAlpha(Theme.subtext, 0.2)
                    }
                    Text {
                        visible: it.head
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        text: it.head ? it.modelData.header : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                    Rectangle {
                        visible: it.live || (!it.sep && !it.head)
                        anchors.fill: parent
                        radius: 8
                        color: it.live && area.containsMouse
                               ? Theme.withAlpha(it.modelData.danger ? Theme.critical : Theme.primary, 0.22) : "transparent"
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!it.modelData.checked
                            text: Theme.icons.check
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 14
                            color: Theme.primary
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 32
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: it.modelData.label || ""
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: it.live ? Theme.textColor : Theme.withAlpha(Theme.subtext, 0.55)
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: it.live
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const id = it.modelData.id;
                                menu.close();
                                menu.chosen(id);
                            }
                        }
                    }
                }
            }
        }
    }
}
