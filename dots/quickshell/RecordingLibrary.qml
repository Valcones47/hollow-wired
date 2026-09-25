import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// Subaba "Gravações" da aba Gravação do Hub: todas as gravações de
// ~/Vídeos/Gravações, com assistir, copiar, mostrar na pasta, comprimir e
// apagar (vai para a lixeira). Tudo pelo rice-record.
Item {
    id: lib

    property var items: []
    property string menuPath: ""        // item com o menu de compressão aberto
    property string armedPath: ""       // item com "apagar" esperando confirmação
    property string compressingPath: ""
    readonly property real totalBytes: items.reduce((a, it) => a + (it.bytes || 0), 0)

    function refresh() { listProc.running = true; }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()

    function human(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1).replace(".", ",") + " GB";
        if (b >= 1048576) return Math.round(b / 1048576) + " MB";
        return Math.max(1, Math.round(b / 1024)) + " KB";
    }
    function duration(s) {
        s = Math.max(0, s || 0);
        const m = Math.floor(s / 60), r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }
    function run(args) { Quickshell.execDetached(["rice-record"].concat(args)); }
    function compress(path, mode) {
        if (compressProc.running) return;
        menuPath = "";
        compressProc.command = ["rice-record", "compress", path, String(mode)];
        compressingPath = path;
        compressProc.running = true;
    }

    Process {
        id: listProc
        command: ["rice-record", "list", "all"]
        stdout: StdioCollector {
            onStreamFinished: { try { lib.items = JSON.parse(text) || []; } catch (e) {} }
        }
    }
    Process {
        id: compressProc
        onExited: { lib.compressingPath = ""; lib.refresh(); }
    }
    Process {
        id: deleteProc
        onExited: lib.refresh()
    }
    Timer { id: disarm; interval: 3000; onTriggered: lib.armedPath = "" }

    component IconBtn: Rectangle {
        id: ib
        property string icon: ""
        property bool danger: false
        property bool active: false
        signal clicked()
        implicitWidth: 30
        implicitHeight: 30
        radius: 15
        color: ib.active ? (ib.danger ? Theme.withAlpha(Theme.critical, 0.25) : Theme.withAlpha(Theme.primary, 0.25))
             : (ibArea.containsMouse ? Theme.tileHigh : "transparent")
        Text {
            anchors.centerIn: parent
            text: ib.icon
            font.family: Theme.iconFontFamily
            font.pixelSize: 14
            color: ib.danger && (ib.active || ibArea.containsMouse) ? Theme.critical
                 : (ib.active ? Theme.primary : Theme.subtext)
        }
        MouseArea {
            id: ibArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.tileRadius
        color: Theme.tile
        border.color: Theme.withAlpha(Theme.outline, 0.25)
        border.width: 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gap + 4
        spacing: Theme.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: lib.items.length === 0 ? Theme.t("rec.empty", "Nenhuma gravação recente")
                    : Theme.t("rec.lib_count", "%1 gravações · %2").replace("%1", lib.items.length).replace("%2", lib.human(lib.totalBytes))
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.subtext
            }
            Item { Layout.fillWidth: true }
            IconBtn { icon: Theme.icons.folder; onClicked: lib.run(["open-folder"]) }
            IconBtn { icon: Theme.icons.refresh; onClicked: lib.refresh() }
        }

        ListView {
            id: view
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: lib.items
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool menu: lib.menuPath === modelData.path
                readonly property bool armed: lib.armedPath === modelData.path
                readonly property bool busy: lib.compressingPath === modelData.path
                width: view.width
                height: 52 + (menu ? 40 : 0)
                radius: 8
                color: rowArea.containsMouse || menu ? Theme.tileHigh : Theme.withAlpha(Theme.background, 0.45)

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onDoubleClicked: lib.run(["play", row.modelData.path])
                }

                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    height: 52
                    spacing: 6

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            elide: Text.ElideMiddle
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.textColor
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.busy ? Theme.t("hub.rec_compressing", "Comprimindo...")
                                : [row.modelData.date, lib.duration(row.modelData.duration),
                                   row.modelData.height ? row.modelData.height + "p" : "",
                                   lib.human(row.modelData.bytes || 0)].filter(x => x).join("  ·  ")
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: row.busy ? Theme.primary : Theme.subtext
                        }
                    }

                    IconBtn { icon: Theme.icons.play; onClicked: lib.run(["play", row.modelData.path]) }
                    IconBtn { icon: Theme.icons.copy; onClicked: lib.run(["copy", row.modelData.path]) }
                    IconBtn { icon: Theme.icons.folder; onClicked: lib.run(["reveal", row.modelData.path]) }
                    IconBtn {
                        icon: Theme.icons.compress
                        active: row.menu || row.busy
                        onClicked: if (!row.busy) lib.menuPath = row.menu ? "" : row.modelData.path
                    }
                    // Dois cliques: o primeiro arma (fica vermelho), o segundo apaga.
                    IconBtn {
                        icon: Theme.icons.trash
                        danger: true
                        active: row.armed
                        onClicked: {
                            if (!row.armed) { lib.armedPath = row.modelData.path; disarm.restart(); return; }
                            const p = row.modelData.path;
                            lib.armedPath = "";
                            deleteProc.command = ["rice-record", "delete", p];
                            deleteProc.running = true;
                        }
                    }
                }

                // Opções de compressão
                RowLayout {
                    visible: row.menu
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    anchors.bottomMargin: 8
                    height: 28
                    spacing: 6
                    Text {
                        text: Theme.t("rec.compress_to", "Comprimir para")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                    Item { Layout.fillWidth: true }
                    Repeater {
                        model: [
                            { mode: "10", label: "10 MB" },
                            { mode: "25", label: "25 MB" },
                            { mode: "50", label: "50 MB" },
                            { mode: "100", label: "100 MB" },
                            { mode: "720p", label: Theme.t("rec.c_720", "720p, mesma qualidade") }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            // Tamanho alvo maior que o próprio arquivo não faz sentido.
                            readonly property bool useful: modelData.mode === "720p"
                                ? (row.modelData.height || 0) > 720
                                : parseInt(modelData.mode) * 1048576 < (row.modelData.bytes || 0)
                            visible: useful
                            Layout.preferredHeight: 26
                            Layout.preferredWidth: cText.implicitWidth + 16
                            radius: 6
                            color: cArea.containsMouse ? Theme.withAlpha(Theme.textColor, 0.1) : Theme.tile
                            Text {
                                id: cText
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textColor
                            }
                            MouseArea {
                                id: cArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: lib.compress(row.modelData.path, modelData.mode)
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: Theme.t("rec.lib_hint", "Dois cliques abre o vídeo. Apagar manda para a lixeira.")
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.subtext
        }
    }
}
