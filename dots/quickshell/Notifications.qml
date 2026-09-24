import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "."

// Aba Notificações do hub: histórico do mako (`makoctl history -j`, até 100
// — max-history no ~/.config/mako/config) + notificações ainda na tela
// (`makoctl list -j`) + modo não perturbe.
//
// O mako não tem comando pra apagar o histórico, então "Limpar" guarda o
// maior id visto em ~/.cache/quickshell/notif-cleared e esconde tudo até
// ele (ids do mako só crescem na sessão; zera ao reiniciar o mako).
// O mako também não guarda horário das notificações.
Item {
    id: root

    property var items: []
    property int clearedUpTo: NotifService.clearedUpTo
    onClearedUpToChanged: root.items = root.items.filter(n => n.id > root.clearedUpTo)
    property bool dnd: NotifService.dnd

    function refresh() {
        if (NotifService.currentOwner === "quickshell") {
            const list = (NotifService.history || []).map(n => {
                return {
                    id: n.id,
                    app_name: n.appName,
                    app_icon: n.appIcon,
                    desktop_entry: n.appIcon,
                    summary: n.summary,
                    body: n.body,
                    urgency: n.urgency === 2 ? "critical" : "normal",
                    onScreen: NotifService.activeToasts.some(t => t.id === n.id),
                    timeStr: n.time ? new Date(n.time).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : ""
                };
            });
            root.items = list.filter(n => n.id > root.clearedUpTo);
        } else {
            histProc.running = true;
            modeProc.running = true;
        }
    }
    onVisibleChanged: if (visible) refresh()
    Timer { interval: 3000; running: root.visible; repeat: true; onTriggered: root.refresh() }

    Process {
        id: histProc
        command: ["bash", "-c", "echo \"{\\\"active\\\": $(makoctl list -j), \\\"history\\\": $(makoctl history -j)}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    const act = (d.active || []).map(n => Object.assign({ onScreen: true }, n));
                    const hist = (d.history || []).map(n => Object.assign({ onScreen: false }, n));
                    const maxId = Math.max(0, ...act.concat(hist).map(n => n.id));
                    // mako reiniciou (ids voltaram a ser menores): zera o "limpar"
                    if (maxId < root.clearedUpTo)
                        root.setCleared(0);
                    root.items = act.concat(hist).filter(n => n.id > root.clearedUpTo).sort((a, b) => b.id - a.id);
                } catch (e) {
                    console.log("Notifications: saída do makoctl inválida:", e);
                }
            }
        }
    }
    Process {
        id: modeProc
        command: ["makoctl", "mode"]
        stdout: StdioCollector { onStreamFinished: root.dnd = text.includes("do-not-disturb") }
    }
    Process { id: mkdirProc; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.cache/quickshell"] }
    Component.onCompleted: mkdirProc.running = true

    function setCleared(id) {
        items = [];
        NotifService.setCleared(id);
    }

    function iconSource(n) {
        return NotifService.iconSource(n);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gap + 2

        // ---------- cabeçalho ----------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PopTitle { text: root.items.length === 0 ? Theme.t("notif.empty", "Nenhuma notificação") : root.items.length + (root.items.length === 1 ? Theme.t("notif.single", " notificação") : Theme.t("notif.plural", " notificações")) }
                PopText {
                    text: root.dnd ? Theme.t("notif.dnd_sub", "Não perturbe ligado — elas chegam aqui, mas não aparecem na tela") : (NotifService.currentOwner === "quickshell" ? Theme.t("notif.sub_native", "Servidor nativo com horário e suporte a ações") : Theme.t("notif.sub_mako", "Histórico do mako"))
                    font.pixelSize: 11
                }
            }

            PopAction {
                Layout.fillWidth: false
                icon: root.dnd ? Theme.icons.bellOff : Theme.icons.bell
                label: root.dnd ? Theme.t("notif.dnd_on", "Não perturbe: ligado") : Theme.t("notif.dnd_btn", "Não perturbe")
                selected: root.dnd
                onActivated: NotifService.toggleDnd()
            }
            PopAction {
                Layout.fillWidth: false
                visible: root.items.length > 0
                icon: Theme.icons.trash
                label: "Limpar"
                onActivated: root.setCleared(Math.max(...root.items.map(n => n.id)))
            }
        }

        // ---------- lista ----------
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.items
            boundsBehavior: Flickable.StopAtBounds

            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }

            delegate: Rectangle {
                id: card
                required property var modelData
                width: list.width
                implicitHeight: cardRow.implicitHeight + 20
                radius: Theme.tileRadius
                color: modelData.urgency === "critical" ? Theme.withAlpha(Theme.critical, 0.3) : Theme.tile
                border.width: modelData.onScreen ? 1 : 0
                border.color: Theme.primary

                RowLayout {
                    id: cardRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 12
                    spacing: 12

                    ClippingRectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Layout.alignment: Qt.AlignTop
                        radius: 10
                        color: Theme.tileHigh
                        IconImage {
                            id: appIcon
                            anchors.centerIn: parent
                            implicitSize: 26
                            source: root.iconSource(card.modelData)
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !appIcon.visible
                            text: Theme.icons.bell
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 18
                            color: Theme.subtext
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.summary || ""
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: Theme.textColor
                            }
                            Text {
                                text: (card.modelData.timeStr ? card.modelData.timeStr + " · " : "") + (card.modelData.app_name || card.modelData.desktop_entry || "") + (card.modelData.onScreen ? " · " + Theme.t("notif.on_screen", "na tela") : "")
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.subtext
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: (card.modelData.body || "").replace(/<[^>]+>/g, "")
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.subtext
                        }
                    }
                }
            }
        }
    }
}
