import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import "."

// Alt+Tab com miniaturas ao vivo das janelas.
//
// Alt+Tab (bind do Hyprland → `qs ipc call alttab next`) abre já na janela
// anterior; Tab/Shift+Tab/setas andam; soltar o Alt troca pra selecionada.
// Enter também troca, Esc cancela, clique numa miniatura troca, Q fecha a
// janela selecionada. Ordem = histórico de foco do Hyprland (mais recente
// primeiro). Miniaturas via ScreencopyView (captura ao vivo da janela).
PanelWindow {
    id: sw

    property bool open: false
    // Sempre mapeada (sem input quando fechada): abrir é só trocar o foco de
    // teclado, sem esperar a superfície nascer — num Alt+Tab rápido o Alt
    // pode ser solto em ~100ms e o overlay precisa já estar com o teclado.
    visible: true
    mask: Region { width: sw.open ? sw.width : 0; height: sw.open ? sw.height : 0 }
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: true

    WlrLayershell.namespace: "quickshell-alttab"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property var wins: []        // HyprlandToplevel, na ordem de foco
    property int index: 0

    onOpenChanged: if (open) focusTimer.restart()
    Timer { id: focusTimer; interval: 1; onTriggered: keyCatcher.forceActiveFocus() }

    // Ordem por focusHistoryID (hyprctl), ligada aos HyprlandToplevel pelo endereço.
    property int pendingStep: 1
    Process {
        id: orderProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    list = JSON.parse(text)
                        .filter(c => c.mapped && c.workspace.id > 0 && c.class !== "dropterm")
                        .sort((a, b) => a.focusHistoryID - b.focusHistoryID);
                } catch (e) {
                    console.log("AltTab: hyprctl inválido:", e);
                }
                const tops = Hyprland.toplevels.values;
                sw.wins = list.map(c => tops.find(t => "0x" + t.address === c.address || t.address === c.address))
                    .filter(t => t && t.wayland);
                if (sw.wins.length === 0) return;
                sw.index = sw.wins.length > 1 ? (sw.pendingStep > 0 ? 1 : sw.wins.length - 1) : 0;
                sw.open = true;
                // Dica (no máximo 2 vezes): o Super+Tab mostra tudo de uma vez.
                Quickshell.execDetached(["rice-tips", "show", "alttab_overview"]);
            }
        }
    }

    function step(d) {
        if (!open) {
            if (orderProc.running) return;
            pendingStep = d;
            Hyprland.refreshToplevels();
            orderProc.running = true;
            return;
        }
        if (wins.length > 0)
            index = (index + d + wins.length) % wins.length;
    }
    function commit() {
        if (!open) return;
        const t = wins[index];
        open = false;
        if (t && t.wayland) DockConfig.focusWindow(t.wayland);
    }
    function cancel() { open = false; }

    // ================= fundo =================
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, sw.open ? 0.3 : 0)
        Behavior on color { ColorAnimation { duration: 160 } }
        MouseArea { anchors.fill: parent; onClicked: sw.cancel() }
    }

    Item {
        id: keyCatcher
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                sw.step(1); event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                sw.step(-1); event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                sw.commit(); event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                sw.cancel(); event.accepted = true;
            } else if (event.key === Qt.Key_Q) {
                const t = sw.wins[sw.index];
                if (t && t.wayland) t.wayland.close();
                sw.wins = sw.wins.filter((_, i) => i !== sw.index);
                if (sw.wins.length === 0) sw.cancel();
                else sw.index = Math.min(sw.index, sw.wins.length - 1);
                event.accepted = true;
            }
        }
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr || event.key === Qt.Key_Meta) {
                sw.commit();
                event.accepted = true;
            }
        }
    }

    // ================= cartão =================
    Rectangle {
        id: card
        anchors.centerIn: parent
        readonly property int tileW: 272
        readonly property int tileH: 208
        readonly property int cols: Math.max(1, Math.min(sw.wins.length, 5))
        width: cols * (tileW + 10) + 30
        height: grid.implicitHeight + 30
        radius: 24
        color: Theme.surface
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.25)
        opacity: sw.open ? 1 : 0
        scale: sw.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        GridLayout {
            id: grid
            anchors.centerIn: parent
            columns: card.cols
            rowSpacing: 10
            columnSpacing: 10

            Repeater {
                model: card.opacity > 0 ? sw.wins : []
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool sel: sw.index === index
                    implicitWidth: card.tileW
                    implicitHeight: card.tileH
                    radius: 16
                    color: sel ? Theme.withAlpha(Theme.primary, 0.22) : tileArea.containsMouse ? Theme.tileHigh : Theme.tile
                    border.width: sel ? 2 : 0
                    border.color: Theme.primary
                    scale: sel ? 1.03 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 120 } }

                    readonly property var entry: modelData.wayland ? (DesktopEntries.byId(modelData.wayland.appId)
                        || DesktopEntries.heuristicLookup(modelData.wayland.appId)) : null

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        ClippingRectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 10
                            color: Theme.withAlpha(Theme.background, 0.6)

                            ScreencopyView {
                                id: shot
                                anchors.centerIn: parent
                                captureSource: tile.modelData.wayland
                                live: sw.open
                                paintCursor: false
                                constraintSize: Qt.size(parent.width, parent.height)
                                width: hasContent && sourceSize.width > 0
                                    ? Math.min(parent.width, parent.height * sourceSize.width / sourceSize.height) : parent.width
                                height: hasContent && sourceSize.width > 0
                                    ? Math.min(parent.height, parent.width * sourceSize.height / sourceSize.width) : parent.height
                            }
                            IconImage {
                                anchors.centerIn: parent
                                visible: !shot.hasContent
                                implicitSize: 56
                                source: Quickshell.iconPath(tile.entry ? tile.entry.icon : "", "application-x-executable")
                            }
                            // workspace
                            Rectangle {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 6
                                width: wsText.implicitWidth + 12
                                height: 20
                                radius: 10
                                color: Theme.withAlpha(Theme.background, 0.8)
                                Text {
                                    id: wsText
                                    anchors.centerIn: parent
                                    text: tile.modelData.workspace ? tile.modelData.workspace.name : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.textColor
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            IconImage {
                                implicitSize: 18
                                source: Quickshell.iconPath(tile.entry ? tile.entry.icon : "", "application-x-executable")
                            }
                            Text {
                                Layout.fillWidth: true
                                text: tile.modelData.title
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: tile.sel ? Font.DemiBold : Font.Normal
                                color: Theme.textColor
                            }
                        }
                    }

                    MouseArea {
                        id: tileArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: sw.index = tile.index
                        onClicked: {
                            sw.index = tile.index;
                            sw.commit();
                        }
                    }
                }
            }
        }
    }

    // Atalhos globais (hyprland.lua: hl.dsp.global("quickshell:alttab-next")) —
    // sem abrir processo a cada toque, como o `qs ipc call` faria.
    GlobalShortcut {
        appid: "quickshell"
        name: "alttab-next"
        description: "Alt+Tab: próxima janela"
        onPressed: sw.step(1)
    }
    GlobalShortcut {
        appid: "quickshell"
        name: "alttab-prev"
        description: "Alt+Tab: janela anterior"
        onPressed: sw.step(-1)
    }

    IpcHandler {
        target: "alttab"
        function next(): void { sw.step(1); }
        function prev(): void { sw.step(-1); }
        function commit(): void { sw.commit(); }
        function cancel(): void { sw.cancel(); }
    }
}
