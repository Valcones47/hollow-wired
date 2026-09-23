import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "."

// Menu de um item do tray desenhado dentro do popup da sidebar (em vez do
// menu nativo flutuante do app), como na Caelestia. Submenus abrem no mesmo
// lugar com uma linha "Voltar" no topo.
ColumnLayout {
    id: root

    property SystemTrayItem item: null
    property real maxWidth: 268
    signal triggered()

    spacing: 2

    // pilha de submenus abertos; vazia = menu raiz do item
    property var stack: []
    onItemChanged: stack = []

    QsMenuOpener {
        id: opener
        menu: root.stack.length > 0 ? root.stack[root.stack.length - 1] : (root.item ? root.item.menu : null)
    }

    // ---------- cabeçalho ----------
    Text {
        Layout.fillWidth: true
        Layout.maximumWidth: root.maxWidth
        Layout.bottomMargin: 4
        text: root.item ? (root.item.tooltipTitle || root.item.title || root.item.id) : ""
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: Theme.textColor
    }

    Text {
        visible: root.item !== null && !root.item.hasMenu
        text: Theme.t("tray.click_to_open", "Clique no ícone para abrir")
        font.family: Theme.fontFamily
        font.pixelSize: 12
        color: Theme.subtext
    }

    // ---------- voltar (dentro de submenu) ----------
    MenuRow {
        visible: root.stack.length > 0
        label: Theme.t("common.back", "Voltar")
        leadingIcon: "\u{F0141}"
        onClicked: root.stack = root.stack.slice(0, -1)
    }

    // ---------- entradas ----------
    Repeater {
        model: root.item && root.item.hasMenu ? opener.children : []
        delegate: Loader {
            id: entryLoader
            required property QsMenuEntry modelData
            Layout.fillWidth: true
            sourceComponent: modelData.isSeparator ? sepComp : rowComp

            Component {
                id: sepComp
                Rectangle {
                    implicitHeight: 9
                    color: "transparent"
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(Theme.outline, 0.35)
                    }
                }
            }
            Component {
                id: rowComp
                MenuRow {
                    entry: entryLoader.modelData
                    label: entryLoader.modelData.text.replace(/_/g, "")
                    iconSource: entryLoader.modelData.icon
                    enabled: entryLoader.modelData.enabled
                    checked: entryLoader.modelData.checkState === Qt.Checked
                    hasChildren: entryLoader.modelData.hasChildren
                    onClicked: {
                        if (entryLoader.modelData.hasChildren) {
                            root.stack = root.stack.concat([entryLoader.modelData]);
                        } else {
                            entryLoader.modelData.triggered();
                            root.triggered();
                        }
                    }
                }
            }
        }
    }

    component MenuRow: Rectangle {
        id: row
        property var entry: null
        property string label: ""
        property string iconSource: ""
        property string leadingIcon: ""
        property bool checked: false
        property bool hasChildren: false
        signal clicked()

        Layout.fillWidth: true
        implicitWidth: Math.min(root.maxWidth, rowLayout.implicitWidth + 20)
        implicitHeight: 30
        radius: 8
        color: rowArea.containsMouse && enabled ? Theme.tileHigh : "transparent"
        opacity: enabled ? 1 : 0.45
        Behavior on color { ColorAnimation { duration: Theme.ms(100) } }

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Text {
                visible: row.leadingIcon !== "" || row.checked
                text: row.checked ? Theme.icons.confirm : row.leadingIcon
                font.family: Theme.iconFontFamily
                font.pixelSize: 15
                color: Theme.primary
            }
            IconImage {
                visible: row.iconSource !== ""
                implicitSize: 16
                source: row.iconSource
            }
            Text {
                Layout.fillWidth: true
                text: row.label
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textColor
            }
            Text {
                visible: row.hasChildren
                text: "\u{F0142}"
                font.family: Theme.iconFontFamily
                font.pixelSize: 15
                color: Theme.subtext
            }
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: row.clicked()
        }
    }
}
