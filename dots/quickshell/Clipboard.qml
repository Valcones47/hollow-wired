import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Modal nativo de Histórico da Área de Transferência (Super + V) no Quickshell.
// Substitui o Rofi completamente.
// Suporta busca instantânea, distinção de textos e imagens, cópia ao clicar/Enter,
// exclusão individual e limpeza geral com wipe.
PanelWindow {
    id: clipWindow

    property bool open: false
    property var allItems: []
    property var filteredItems: []
    property int selectedIndex: 0

    function updateFiltered() {
        const q = searchField ? searchField.text.trim().toLowerCase() : "";
        if (!q) {
            filteredItems = allItems;
        } else {
            filteredItems = allItems.filter(it => it.content.toLowerCase().includes(q));
        }
        selectedIndex = 0;
    }

    visible: true
    color: "transparent"
    focusable: true

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
        width: clipWindow.open ? clipWindow.width : 0
        height: clipWindow.open ? clipWindow.height : 0
    }

    WlrLayershell.namespace: "quickshell-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: clipWindow.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (open) {
            searchField.text = "";
            selectedIndex = 0;
            loadProc.running = true;
            searchField.forceActiveFocus();
        }
    }

    Process {
        id: loadProc
        command: ["bash", "-c", "cliphist list | head -n 60"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const items = [];
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i];
                    if (!line) continue;
                    const tabIdx = line.indexOf("\t");
                    if (tabIdx === -1) continue;
                    const id = line.substring(0, tabIdx);
                    const content = line.substring(tabIdx + 1);
                    const isImage = content.startsWith("[[ binary data");
                    items.push({
                        raw: line,
                        id: id,
                        content: content,
                        isImage: isImage
                    });
                }
                clipWindow.allItems = items;
                clipWindow.updateFiltered();
            }
        }
    }

    Process {
        id: copyProc
        property string rawLine: ""
        command: ["bash", "-c", "printf '%s' \"$RAW\" | cliphist decode | wl-copy"]
        environment: ({ RAW: rawLine })
        onExited: clipWindow.open = false
    }

    Process {
        id: deleteProc
        property string rawLine: ""
        command: ["bash", "-c", "printf '%s' \"$RAW\" | cliphist delete"]
        environment: ({ RAW: rawLine })
        onExited: loadProc.running = true
    }

    Process {
        id: wipeProc
        command: ["cliphist", "wipe"]
        onExited: {
            clipWindow.allItems = [];
            loadProc.running = true;
        }
    }

    function copyItem(raw) {
        copyProc.rawLine = raw;
        copyProc.running = true;
    }

    function deleteItem(raw) {
        deleteProc.rawLine = raw;
        deleteProc.running = true;
    }

    // Fundo escuro clicável
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: clipWindow.open ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: clipWindow.open = false
        }
    }

    // Janela Central
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 640
        height: 520
        radius: Theme.radius
        color: Theme.surface
        border.color: Theme.withAlpha(Theme.outline, 0.35)
        border.width: 1

        scale: clipWindow.open ? 1 : 0.94
        opacity: clipWindow.open ? 1 : 0
        visible: opacity > 0

        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Row {
                    spacing: 10
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{F02DA}"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 20
                        color: Theme.primary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.t("clipboard.title", "Área de Transferência")
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: Theme.textColor
                    }
                }

                Item { Layout.fillWidth: true }

                // Botão Limpar Tudo
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: wipeArea.containsMouse ? Theme.withAlpha(Theme.critical, 0.2) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: Theme.icons.trash
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 15
                        color: wipeArea.containsMouse ? Theme.critical : Theme.subtext
                    }

                    MouseArea {
                        id: wipeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: wipeProc.running = true
                    }
                }

                // Botão Fechar
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: closeArea.containsMouse ? Theme.tileHigh : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\u{F0156}"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 15
                        color: closeArea.containsMouse ? Theme.primary : Theme.subtext
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: clipWindow.open = false
                    }
                }
            }

            // Campo de busca
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: 19
                color: Theme.tile
                border.color: searchField.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    Text {
                        text: Theme.icons.magnify
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 15
                        color: Theme.subtext
                    }

                    TextInput {
                        id: searchField
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textColor
                        onTextChanged: clipWindow.updateFiltered()

                        Text {
                            visible: !searchField.text
                            text: Theme.t("clipboard.search_placeholder", "Filtrar histórico...")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.withAlpha(Theme.subtext, 0.6)
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                clipWindow.open = false;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down) {
                                if (clipWindow.selectedIndex < clipWindow.filteredItems.length - 1) {
                                    clipWindow.selectedIndex++;
                                    clipList.positionViewAtIndex(clipWindow.selectedIndex, ListView.Contain);
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up) {
                                if (clipWindow.selectedIndex > 0) {
                                    clipWindow.selectedIndex--;
                                    clipList.positionViewAtIndex(clipWindow.selectedIndex, ListView.Contain);
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (clipWindow.filteredItems.length > 0 && clipWindow.selectedIndex < clipWindow.filteredItems.length) {
                                    const item = clipWindow.filteredItems[clipWindow.selectedIndex];
                                    clipWindow.copyItem(item.raw);
                                }
                                event.accepted = true;
                            }
                        }

                        Text {
                            text: "Pesquisar no histórico..."
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.withAlpha(Theme.subtext, 0.6)
                            visible: !searchField.text && !searchField.activeFocus
                        }
                    }
                }
            }

            // Lista de itens
            ListView {
                id: clipList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: clipWindow.filteredItems

                ScrollBar.vertical: ScrollBar {
                    active: true
                    width: 4
                }

                delegate: Rectangle {
                    id: rowRect
                    required property var modelData
                    required property int index

                    width: clipList.width - 8
                    height: 48
                    radius: 10
                    color: {
                        if (clipWindow.selectedIndex === index) return Theme.tileHigh;
                        if (itemArea.containsMouse) return Theme.withAlpha(Theme.tileHigh, 0.7);
                        return Theme.tile;
                    }
                    border.color: clipWindow.selectedIndex === index ? Theme.primary : "transparent"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 10

                        // Ícone (Texto vs Imagem)
                        Text {
                            text: rowRect.modelData.isImage ? "\u{F0D5D}" : "\u{F018D}"
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 16
                            color: rowRect.modelData.isImage ? Theme.accent1 : Theme.primary
                        }

                        // Conteúdo
                        Text {
                            Layout.fillWidth: true
                            text: rowRect.modelData.content
                            font.family: rowRect.modelData.isImage ? Theme.fontFamily : Theme.monoFamily
                            font.pixelSize: 12
                            color: Theme.textColor
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        // Botão Excluir
                        Rectangle {
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            radius: 13
                            color: delArea.containsMouse ? Theme.withAlpha(Theme.critical, 0.2) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: Theme.icons.close
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 12
                                color: delArea.containsMouse ? Theme.critical : Theme.subtext
                            }

                            MouseArea {
                                id: delArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: clipWindow.deleteItem(rowRect.modelData.raw)
                            }
                        }
                    }

                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        anchors.rightMargin: 32
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: clipWindow.copyItem(rowRect.modelData.raw)
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            clipWindow.open = !clipWindow.open;
        }

        function show(): void {
            clipWindow.open = true;
        }

        function hide(): void {
            clipWindow.open = false;
        }
    }
}
