import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "."

Item {
    id: root

    // Só workspaces "normais" (id positivo) — os especiais (scratchpad
    // etc, id negativo) não entram na grade.
    readonly property var normalWorkspaces: {
        const list = [];
        for (const ws of Hyprland.workspaces.values) {
            if (ws.id > 0)
                list.push(ws);
        }
        list.sort((a, b) => a.id - b.id);
        return list;
    }

    GridView {
        anchors.fill: parent
        cellWidth: width / 3
        cellHeight: 110
        model: root.normalWorkspaces
        interactive: false

        delegate: Item {
            required property var modelData
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight

            Rectangle {
                id: card
                property bool hovered: false
                anchors.fill: parent
                anchors.margins: 6
                radius: Theme.radius / 2
                color: modelData.focused
                    ? Theme.withAlpha(Theme.accent2, 0.25)
                    : Theme.withAlpha(Theme.inactive, hovered ? 0.16 : 0.08)
                border.width: 1
                border.color: modelData.focused
                    ? Theme.accent2
                    : Theme.withAlpha(Theme.inactive, hovered ? 0.5 : 0.3)
                scale: hovered && !modelData.focused ? 1.02 : 1.0

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.name
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                        color: modelData.focused ? Theme.foreground : Theme.inactive
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 2

                        Repeater {
                            model: modelData.toplevels.values.slice(0, 3)
                            delegate: Text {
                                required property var modelData
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.title
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                color: Theme.withAlpha(Theme.inactive, 0.9)
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            visible: modelData.toplevels.values.length === 0
                            text: "vazio"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.italic: true
                            color: Theme.withAlpha(Theme.inactive, 0.5)
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            visible: modelData.toplevels.values.length > 3
                            text: "+" + (modelData.toplevels.values.length - 3)
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Theme.withAlpha(Theme.inactive, 0.6)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: card.hovered = true
                    onExited: card.hovered = false
                    // activate() usa a sintaxe antiga de dispatch, que quebra
                    // com o config em Lua do Hyprland.
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + modelData.id + " })")
                }
            }
        }
    }
}
