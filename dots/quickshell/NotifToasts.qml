import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "."

// Janela flutuante de Toasts de Notificação Nativos do Quickshell
// Integrada com as cores do wallust, animações de entrada/saída,
// pausa no hover, botões de ação e suporte ao modo Não Perturbe.
PanelWindow {
    id: root

    // Posição ancorada (canto superior direito por padrão)
    anchors.top: true
    anchors.right: true
    margins.top: (ShellLayout.barEnabled && !ShellLayout.barVertical) ? Theme.waybarHeight + 12 : 16
    margins.right: 16

    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    focusable: false

    // Só fica visível enquanto houver toasts ativos e o DND estiver desligado
    visible: NotifService.activeToasts.length > 0 && !NotifService.dnd

    implicitWidth: 380
    implicitHeight: toastList.implicitHeight

    ColumnLayout {
        id: toastList
        width: parent.width
        spacing: 10

        Repeater {
            model: NotifService.activeToasts

            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index

                Layout.preferredWidth: 380
                Layout.preferredHeight: contentCol.implicitHeight + 24
                radius: Theme.tileRadius
                color: modelData.urgency === 2 ? Theme.withAlpha(Theme.critical, 0.25) : Theme.tile
                border.width: modelData.urgency === 2 ? 1.5 : 1
                border.color: modelData.urgency === 2 ? Theme.critical : Theme.border

                // Arrastar para a direita dispensa (o layout controla o x, então
                // o deslocamento vai num Translate).
                property real dragX: 0
                transform: Translate { x: card.dragX }
                opacity: 1 - Math.min(0.8, card.dragX / 300)

                // Pausa o fechamento automático enquanto o cursor estiver sobre a notificação
                Timer {
                    id: dismissTimer
                    interval: modelData.expireTimeout > 0 ? modelData.expireTimeout : (modelData.urgency === 2 ? 15000 : NotifService.defaultTimeout)
                    running: !hoverArea.containsMouse
                    repeat: false
                    onTriggered: NotifService.dismissToast(card.modelData.id)
                }

                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    property real pressX: 0
                    property bool swiped: false
                    onPressed: mouse => { pressX = mouse.x; swiped = false; }
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        card.dragX = Math.max(0, mouse.x - pressX);
                        if (card.dragX > 8) swiped = true;
                    }
                    onReleased: {
                        if (card.dragX > 120) NotifService.dismissToast(card.modelData.id);
                        else card.dragX = 0;
                    }
                    onClicked: {
                        if (swiped) return;
                        // Se houver ação default, dispara
                        if (card.modelData.actions && card.modelData.actions.length > 0) {
                            const def = card.modelData.actions.find(a => a.identifier === "default");
                            if (def && typeof def.invoke === "function") {
                                def.invoke();
                            }
                        }
                        NotifService.dismissToast(card.modelData.id);
                    }
                }

                ColumnLayout {
                    id: contentCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 8

                    // Linha principal: Ícone + Textos + Botão Fechar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // Ícone do Aplicativo
                        ClippingRectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            Layout.alignment: Qt.AlignTop
                            radius: 8
                            color: Theme.tileHigh

                            IconImage {
                                id: notifIcon
                                anchors.centerIn: parent
                                width: 24
                                height: 24
                                source: NotifService.iconSource(card.modelData)
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !notifIcon.visible
                                text: Theme.icons.bell
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 18
                                color: card.modelData.urgency === 2 ? Theme.critical : Theme.primary
                            }
                        }

                        // Textos (App, Título, Mensagem)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: card.modelData.appName || "Sistema"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: card.modelData.urgency === 2 ? Theme.critical : Theme.primary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: (card.modelData.count || 1) > 1
                                        ? Theme.t("notif.more", "+%1").arg(card.modelData.count - 1)
                                        : Theme.t("notif.just_now", "Agora")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.subtext
                                }
                            }

                            Text {
                                text: card.modelData.summary || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: Theme.textColor
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                visible: text.length > 0
                            }

                            Text {
                                text: card.modelData.body || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.subtext
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                textFormat: Text.StyledText
                                Layout.fillWidth: true
                                visible: text.length > 0
                            }
                        }

                        // Botão Fechar (X)
                        Rectangle {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignTop
                            radius: 12
                            color: closeArea.containsMouse ? Theme.tileHigh : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: Theme.icons.close
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 12
                                color: closeArea.containsMouse ? Theme.textColor : Theme.subtext
                            }

                            MouseArea {
                                id: closeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: NotifService.dismissToast(card.modelData.id)
                            }
                        }
                    }

                    // Imagem anexa (se presente e for arquivo de imagem)
                    Image {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 120
                        fillMode: Image.PreserveAspectCrop
                        source: card.modelData.image ? (card.modelData.image.startsWith("/") ? "file://" + card.modelData.image : card.modelData.image) : ""
                        visible: card.modelData.image && (card.modelData.image.includes("/") || card.modelData.image.match(/\.(png|jpg|jpeg|webp)$/i))
                    }

                    // Barra de progresso (se fornecida via hint "value")
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 4
                        radius: 2
                        color: Theme.tileHigh
                        visible: card.modelData.progress >= 0

                        Rectangle {
                            width: parent.width * Math.min(1.0, Math.max(0.0, card.modelData.progress / 100))
                            height: parent.height
                            radius: 2
                            color: Theme.primary
                        }
                    }

                    // Botões de Ação Interativos
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: card.modelData.actions && card.modelData.actions.filter(a => a.identifier !== "default").length > 0

                        Repeater {
                            model: card.modelData.actions ? card.modelData.actions.filter(a => a.identifier !== "default") : []

                            delegate: Rectangle {
                                required property var modelData
                                Layout.preferredHeight: 26
                                Layout.fillWidth: true
                                radius: 6
                                color: actMouse.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.tileHigh, 0.5)

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.text || parent.modelData.identifier
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Theme.textColor
                                }

                                MouseArea {
                                    id: actMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (parent.modelData && typeof parent.modelData.invoke === "function") {
                                            parent.modelData.invoke();
                                        }
                                        NotifService.dismissToast(card.modelData.id);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
