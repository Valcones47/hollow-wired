import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "."

Item {
    id: root

    // Mapa completo dos 10 workspaces para navegação instantânea e visão panorâmica
    readonly property var allWorkspaces: {
        const activeWsId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
        const wsMap = {};
        for (const ws of Hyprland.workspaces.values) {
            if (ws.id > 0) wsMap[ws.id] = ws;
        }
        const list = [];
        for (let i = 1; i <= 10; i++) {
            const existing = wsMap[i];
            list.push({
                id: i,
                name: String(i),
                focused: activeWsId === i,
                hasWindows: existing ? existing.toplevels.values.length > 0 : false,
                toplevels: existing ? existing.toplevels.values : [],
                windowCount: existing ? existing.toplevels.values.length : 0
            });
        }
        return list;
    }

    readonly property int totalWindows: {
        let count = 0;
        for (const ws of Hyprland.workspaces.values) {
            if (ws.id > 0) count += ws.toplevels.values.length;
        }
        return count;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Barra informativa de cabeçalho
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                implicitHeight: 28
                implicitWidth: wsInfoRow.implicitWidth + 20
                radius: 14
                color: Theme.withAlpha(Theme.primary, 0.15)
                border.width: 1
                border.color: Theme.withAlpha(Theme.primary, 0.35)

                RowLayout {
                    id: wsInfoRow
                    anchors.centerIn: parent
                    spacing: 8

                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: Theme.primary
                    }
                    Text {
                        text: (Hyprland.focusedWorkspace ? ("Workspace " + Hyprland.focusedWorkspace.id) : "Workspace 1") + " " + Theme.t("common.active", "Ativo")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Theme.textColor
                    }
                }
            }

            Rectangle {
                implicitHeight: 28
                implicitWidth: winCountRow.implicitWidth + 20
                radius: 14
                color: Theme.tile
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.2)

                RowLayout {
                    id: winCountRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: Theme.icons.laptop
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 12
                        color: Theme.subtext
                    }
                    Text {
                        text: root.totalWindows + " " + (root.totalWindows === 1 ? Theme.t("workspaces.win_single", "janela aberta") : Theme.t("workspaces.win_plural", "janelas abertas"))
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: Theme.t("workspaces.hint", "Dica: Clique para alternar ou use Super + 1..9")
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.withAlpha(Theme.subtext, 0.7)
            }
        }

        // Grade 5x2 de Workspaces
        GridView {
            id: wsGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            cellWidth: width / 5
            cellHeight: height / 2
            model: root.allWorkspaces
            interactive: false

            delegate: Item {
                id: wsDelegate
                required property var modelData
                width: wsGrid.cellWidth
                height: wsGrid.cellHeight

                Rectangle {
                    id: wsCard
                    property bool hovered: false
                    anchors.fill: parent
                    anchors.margins: 5
                    radius: 12
                    color: modelData.focused
                        ? Theme.withAlpha(Theme.primary, 0.24)
                        : (wsCard.hovered
                            ? Theme.tileHigh
                            : (modelData.hasWindows ? Theme.tile : Theme.withAlpha(Theme.tile, 0.5)))
                    border.width: modelData.focused ? 1.5 : 1
                    border.color: modelData.focused
                        ? Theme.primary
                        : (wsCard.hovered
                            ? Theme.withAlpha(Theme.primary, 0.5)
                            : (modelData.hasWindows ? Theme.withAlpha(Theme.outline, 0.3) : Theme.withAlpha(Theme.outline, 0.12)))

                    scale: wsCard.hovered ? 1.02 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                    Behavior on color { ColorAnimation { duration: 120 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        // Cabeçalho do card: Número do Workspace + Badge
                        RowLayout {
                            Layout.fillWidth: true

                            Rectangle {
                                width: 26
                                height: 26
                                radius: 8
                                color: modelData.focused
                                    ? Theme.primary
                                    : (modelData.hasWindows ? Theme.withAlpha(Theme.primary, 0.2) : Theme.withAlpha(Theme.outline, 0.15))

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    font.family: Theme.monoFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: modelData.focused ? Theme.background : Theme.textColor
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                visible: modelData.focused || modelData.hasWindows
                                implicitWidth: statusTxt.implicitWidth + 10
                                implicitHeight: 18
                                radius: 9
                                color: modelData.focused
                                    ? Theme.withAlpha(Theme.primary, 0.3)
                                    : Theme.withAlpha(Theme.subtext, 0.15)

                                Text {
                                    id: statusTxt
                                    anchors.centerIn: parent
                                    text: modelData.focused
                                        ? Theme.t("workspaces.focused", "Ativo")
                                        : (modelData.windowCount + (modelData.windowCount === 1 ? " app" : " apps"))
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    color: modelData.focused ? Theme.primary : Theme.subtext
                                }
                            }
                        }

                        // Lista de janelas / títulos
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 2

                            Repeater {
                                model: modelData.toplevels.slice(0, 2)
                                delegate: Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: "• " + (modelData.title || modelData.initialTitle || modelData.initialClass || "Janela")
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: wsDelegate.modelData.focused ? Theme.textColor : Theme.subtext
                                }
                            }

                            Text {
                                visible: modelData.windowCount > 2
                                text: "+" + (modelData.windowCount - 2) + " " + Theme.t("workspaces.more", "mais...")
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                color: Theme.withAlpha(Theme.subtext, 0.6)
                            }

                            Item {
                                Layout.fillHeight: true
                                visible: !modelData.hasWindows
                            }

                            Text {
                                visible: !modelData.hasWindows
                                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                                text: Theme.t("workspaces.empty", "Livre")
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.italic: true
                                color: Theme.withAlpha(Theme.subtext, 0.4)
                            }

                            Item {
                                Layout.fillHeight: true
                                visible: !modelData.hasWindows
                            }
                        }

                        // Rodapé sutil com atalho
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: "Super+" + modelData.name
                            font.family: Theme.monoFamily
                            font.pixelSize: 8
                            color: Theme.withAlpha(Theme.subtext, 0.4)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: wsCard.hovered = true
                        onExited: wsCard.hovered = false
                        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + modelData.id + " })")
                    }
                }
            }
        }
    }
}
