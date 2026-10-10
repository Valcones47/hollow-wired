import QtQuick
import QtQuick.Layouts
import "."

// Propriedades de um processo/app: lista de pares nome/valor. O pai preenche
// `rows` e chama `show()`. Fechar: botão, Esc ou clique fora.
Item {
    id: dlg

    property string title: ""
    property var rows: []        // [{ k, v }]
    property bool shown: false
    signal copyCommand()
    signal closed()

    visible: dlg.shown
    anchors.fill: parent
    z: 110

    function show() { dlg.shown = true; dlg.forceActiveFocus(); }
    function close() { dlg.shown = false; dlg.closed(); }
    Keys.onEscapePressed: dlg.close()

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: dlg.close() }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(620, parent.width - 60)
        height: Math.min(box.implicitHeight + 40, parent.height - 60)
        radius: 16
        color: Theme.background
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.45)
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: box
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Text {
                text: dlg.title
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.weight: Font.Medium
                color: Theme.textColor
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: list.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: list
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: dlg.rows
                        delegate: Column {
                            required property var modelData
                            width: list.width
                            spacing: 1
                            Text {
                                text: modelData.k
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.subtext
                            }
                            Text {
                                width: parent.width
                                text: modelData.v
                                wrapMode: Text.WrapAnywhere
                                font.family: modelData.mono ? Theme.monoFamily : Theme.fontFamily
                                font.pixelSize: 13
                                color: Theme.textColor
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.preferredWidth: cp.implicitWidth + 28
                    Layout.preferredHeight: 34
                    radius: 10
                    color: cpArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.9)
                    Text {
                        id: cp
                        anchors.centerIn: parent
                        text: Theme.t("taskman.copy_cmd", "Copiar comando")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textColor
                    }
                    MouseArea {
                        id: cpArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dlg.copyCommand()
                    }
                }
                Rectangle {
                    Layout.preferredWidth: cl.implicitWidth + 28
                    Layout.preferredHeight: 34
                    radius: 10
                    color: Theme.primary
                    Text {
                        id: cl
                        anchors.centerIn: parent
                        text: Theme.t("common.close", "Fechar")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: Theme.background
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dlg.close()
                    }
                }
            }
        }
    }
}
