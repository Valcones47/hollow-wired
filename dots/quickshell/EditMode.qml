pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "."

// Modo edição, como o do KDE: mexer na interface direto na tela.
//
// Entra pelo botão direito no fundo da barra, pelo menu da área de trabalho ou
// `qs ipc call layout edit`. Enquanto ShellLayout.editing:
//   - a barra mostra os módulos escondidos apagados, e um clique liga/desliga;
//   - uma alça permite arrastar a barra para outra borda (encaixa na mais perto);
//   - a dock fica à mostra e os widgets entram no modo de edição deles;
//   - esta aba flutuante tem os arranjos prontos e as opções mais usadas.
//
// A camada cobre a tela, mas a máscara só aceita clique na aba e na alça: o
// resto (barra, dock, widgets, janelas) continua recebendo o mouse normalmente.
PanelWindow {
    id: edit

    visible: ShellLayout.editing
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-editmode"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: ShellLayout.editing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    readonly property int stripW: 52 + Theme.frameThickness
    readonly property bool barTop: ShellLayout.barEnabled && !ShellLayout.barVertical
    readonly property bool barLeft: ShellLayout.barEnabled && ShellLayout.barPosition === "left"
    readonly property bool barRight: ShellLayout.barEnabled && ShellLayout.barPosition === "right"

    property bool dragging: false

    mask: Region {
        item: edit.dragging ? fullArea : null
        Region { item: tab }
        Region { item: handle }
    }
    Item { id: fullArea; anchors.fill: parent }

    onVisibleChanged: if (visible) tab.forceActiveFocus()

    // ---- escurece tudo, menos a barra (que é onde se clica) ----
    Rectangle {
        x: edit.barLeft ? edit.stripW : 0
        y: edit.barTop ? Theme.waybarHeight : 0
        width: parent.width - (edit.barLeft || edit.barRight ? edit.stripW : 0)
        height: parent.height - y
        color: Qt.rgba(0, 0, 0, 0.28)
    }

    // ---- zonas de encaixe, só enquanto arrasta ----
    Repeater {
        model: edit.dragging ? [
            { pos: "top",   x: 0, y: 0, w: edit.width, h: 90, label: Theme.t("layout.pos_top", "Em cima") },
            { pos: "left",  x: 0, y: 0, w: 110, h: edit.height, label: Theme.t("layout.pos_left", "À esquerda") },
            { pos: "right", x: edit.width - 110, y: 0, w: 110, h: edit.height, label: Theme.t("layout.pos_right", "À direita") }
        ] : []
        delegate: Rectangle {
            id: zone
            required property var modelData
            readonly property bool hot: edit.nearestEdge() === zone.modelData.pos
            x: zone.modelData.x; y: zone.modelData.y
            width: zone.modelData.w; height: zone.modelData.h
            color: Theme.withAlpha(Theme.primary, zone.hot ? 0.28 : 0.1)
            border.width: zone.hot ? 2 : 1
            border.color: Theme.withAlpha(Theme.primary, zone.hot ? 0.9 : 0.4)
            Text {
                anchors.centerIn: parent
                text: zone.modelData.label
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Theme.textColor
            }
        }
    }

    function nearestEdge() {
        const cx = handle.x + handle.width / 2, cy = handle.y + handle.height / 2;
        const d = { top: cy, left: cx, right: edit.width - cx };
        let best = "top";
        for (const k in d) if (d[k] < d[best]) best = k;
        return best;
    }

    // ---- alça para arrastar a barra ----
    Rectangle {
        id: handle
        visible: ShellLayout.barEnabled
        width: handleRow.implicitWidth + 24
        height: 32
        radius: 16
        color: Theme.primary
        function home() {
            handle.x = Qt.binding(() => edit.barTop ? (edit.width - handle.width) / 2
                : edit.barLeft ? edit.stripW + 10 : edit.width - edit.stripW - 10 - handle.width);
            handle.y = Qt.binding(() => edit.barTop ? Theme.waybarHeight + 10 : (edit.height - handle.height) / 2);
        }
        Component.onCompleted: home()

        Row {
            id: handleRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "⠿"
                font.pixelSize: 15
                color: Theme.background
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.t("edit.handle", "Arraste a barra")
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: Theme.background
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            drag.target: handle
            onPressed: edit.dragging = true
            onReleased: {
                const pos = edit.nearestEdge();
                edit.dragging = false;
                if (pos !== ShellLayout.barPosition) ShellLayout.set("bar", "position", pos);
                handle.home();
            }
        }
    }

    // ---- aba flutuante ----
    Rectangle {
        id: tab
        width: Math.min(640, edit.width - 80)
        height: tabCol.implicitHeight + 32
        x: (edit.width - width) / 2
        y: Math.round(edit.height * 0.2)
        radius: 16
        // Opaca: por cima de janelas, a surface translúcida deixava o texto de
        // trás aparecer.
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 1)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.3)
        focus: true
        Keys.onEscapePressed: ShellLayout.editing = false

        ColumnLayout {
            id: tabCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: Theme.t("edit.title", "Modo edição")
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: Theme.textColor
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Theme.t("edit.hint", "Clique nos itens da barra para esconder ou mostrar. Arraste a alça para mudar a barra de borda. Esc sai.")
                        wrapMode: Text.WordWrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                }
                Rectangle {
                    implicitWidth: doneText.implicitWidth + 28
                    implicitHeight: 34
                    radius: 9
                    color: doneArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.85) : Theme.primary
                    Text {
                        id: doneText
                        anchors.centerIn: parent
                        text: Theme.t("edit.done", "Concluir")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.background
                    }
                    MouseArea {
                        id: doneArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellLayout.editing = false
                    }
                }
            }

            // arranjos prontos + personalizado
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: [
                        { key: "topbar", name: Theme.t("layout.preset_topbar", "Clássico"), bar: true, dock: false, dockFull: false, side: false, vertical: false },
                        { key: "taskbar", name: Theme.t("layout.preset_taskbar", "Estilo Windows"), bar: true, dock: true, dockFull: true, side: true, vertical: false },
                        { key: "sidebar", name: Theme.t("layout.preset_sidebar", "Barra lateral"), bar: true, dock: false, dockFull: false, side: false, vertical: true },
                        { key: "clean", name: Theme.t("layout.preset_clean", "Tela limpa"), bar: false, dock: false, dockFull: false, side: false, vertical: false }
                    ]
                    delegate: Rectangle {
                        id: pc
                        required property var modelData
                        readonly property bool active: ShellLayout.preset === pc.modelData.key
                        Layout.fillWidth: true
                        implicitHeight: pcCol.implicitHeight + 16
                        radius: 10
                        color: pcArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.6)
                        border.width: pc.active ? 2 : 0
                        border.color: Theme.primary
                        ColumnLayout {
                            id: pcCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            spacing: 6
                            LayoutPreview {
                                Layout.fillWidth: true
                                Layout.preferredHeight: width * 0.52
                                bar: pc.modelData.bar
                                dock: pc.modelData.dock
                                dockFull: pc.modelData.dockFull
                                side: pc.modelData.side
                                vertical: pc.modelData.vertical
                            }
                            Text {
                                Layout.fillWidth: true
                                text: pc.modelData.name
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textColor
                            }
                        }
                        MouseArea {
                            id: pcArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                ShellLayout.applyPreset(pc.modelData.key);
                                handle.home();
                            }
                        }
                    }
                }
                // Personalizado: abre a aba completa
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 10
                    color: cuArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.6)
                    border.width: ShellLayout.preset === "custom" ? 2 : 0
                    border.color: Theme.primary
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Theme.icons.tune
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 20
                            color: Theme.textColor
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Theme.t("edit.custom", "Personalizado")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textColor
                        }
                    }
                    MouseArea {
                        id: cuArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ShellLayout.editing = false;
                            Quickshell.execDetached(["quickshell", "ipc", "call", "visualconfig", "tab", "20"]);
                        }
                    }
                }
            }

            // opções rápidas
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [
                        { g: "bar", p: "autohide", label: Theme.t("edit.bar_autohide", "Barra só com o mouse"), on: ShellLayout.barAutohide },
                        { g: "dock", p: "enabled", label: Theme.t("edit.dock_on", "Usar a dock"), on: ShellLayout.dockEnabled },
                        { g: "dock", p: "autohide", label: Theme.t("edit.dock_autohide", "Dock só com o mouse"), on: ShellLayout.dockAutohide },
                        { g: "dock", p: "fullWidth", label: Theme.t("edit.dock_full", "Dock de ponta a ponta"), on: ShellLayout.dockFullWidth },
                        { g: "sidebar", p: "enabled", label: Theme.t("edit.side_on", "Central de ações"), on: ShellLayout.sidebarEnabled }
                    ]
                    delegate: Rectangle {
                        id: qo
                        required property var modelData
                        width: qoRow.implicitWidth + 20
                        height: 30
                        radius: 8
                        color: qo.modelData.on ? Theme.tileHigh : (qoArea.containsMouse ? Theme.withAlpha(Theme.tileHigh, 0.5) : "transparent")
                        border.width: qo.modelData.on ? 0 : 1
                        border.color: Theme.withAlpha(Theme.outline, 0.25)
                        Row {
                            id: qoRow
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8; height: 8; radius: 4
                                color: qo.modelData.on ? Theme.primary : Theme.withAlpha(Theme.subtext, 0.5)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qo.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: qo.modelData.on ? Theme.textColor : Theme.subtext
                            }
                        }
                        MouseArea {
                            id: qoArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellLayout.set(qo.modelData.g, qo.modelData.p, !qo.modelData.on)
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: Theme.t("edit.widgets_hint", "Widgets: arraste pela área de trabalho; use a barra de edição deles para adicionar ou remover.")
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.withAlpha(Theme.subtext, 0.8)
            }
        }

        // arrastar a própria aba pelo título
        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 14
            cursorShape: Qt.SizeAllCursor
            drag.target: tab
        }
    }
}
