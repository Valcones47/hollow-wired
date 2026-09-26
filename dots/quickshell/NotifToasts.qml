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
                readonly property string imageSource: {
                    const im = modelData.image || "";
                    if (!im || !(im.includes("/") || /\.(png|jpe?g|webp)$/i.test(im))) return "";
                    return im.startsWith("/") ? "file://" + im : im;
                }
                readonly property bool hasImage: imageSource !== ""

                Layout.preferredWidth: 380
                Layout.preferredHeight: contentCol.implicitHeight + 24
                radius: Theme.tileRadius
                color: modelData.urgency === 2 ? Theme.withAlpha(Theme.critical, 0.25) : Theme.tile
                border.width: modelData.urgency === 2 ? 1.5 : 1
                border.color: modelData.urgency === 2 ? Theme.critical : Theme.border

                // Arrastar para a direita dispensa (o layout controla o x, então
                // o deslocamento vai num Translate).
                // Arrastar para baixo expande (texto inteiro, para de sumir
                // sozinha); para cima recolhe. A direção sai dos primeiros 8 px.
                property real dragX: 0
                property real dragY: 0
                property bool expanded: false
                transform: Translate { x: card.dragX; y: card.dragY * 0.4 }
                opacity: 1 - Math.min(0.8, card.dragX / 300)
                Behavior on dragX { enabled: !hoverArea.pressed; NumberAnimation { duration: Theme.ms(180); easing.type: Easing.OutCubic } }
                Behavior on dragY { enabled: !hoverArea.pressed; NumberAnimation { duration: Theme.ms(180); easing.type: Easing.OutCubic } }
                Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.ms(200); easing.type: Easing.OutCubic } }
                // Dispensar desliza para fora antes de sumir.
                Timer { id: goAway; interval: 170; onTriggered: NotifService.dismissToast(card.modelData.id) }
                function swipeAway() { card.dragX = 440; goAway.start(); }

                // Pausa o fechamento automático enquanto o cursor estiver sobre a notificação
                Timer {
                    id: dismissTimer
                    interval: modelData.expireTimeout > 0 ? modelData.expireTimeout : (modelData.urgency === 2 ? 15000 : NotifService.defaultTimeout)
                    running: !hoverArea.containsMouse && !card.expanded
                    repeat: false
                    onTriggered: NotifService.dismissToast(card.modelData.id)
                }

                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    property real pressX: 0
                    property real pressY: 0
                    property string dir: ""
                    property bool swiped: false
                    onPressed: mouse => { pressX = mouse.x; pressY = mouse.y; dir = ""; swiped = false; }
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        const dx = mouse.x - pressX, dy = mouse.y - pressY;
                        if (dir === "" && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) {
                            dir = Math.abs(dx) > Math.abs(dy) ? "x" : "y";
                            swiped = true;
                        }
                        if (dir === "x") card.dragX = Math.max(0, dx);
                        else if (dir === "y") card.dragY = Math.max(-50, Math.min(80, dy));
                    }
                    onReleased: {
                        if (dir === "x") {
                            if (card.dragX > 120) card.swipeAway();
                            else card.dragX = 0;
                        } else if (dir === "y") {
                            if (card.dragY > 30) card.expanded = true;
                            else if (card.dragY < -20) card.expanded = false;
                            card.dragY = 0;
                        }
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

                        // Quadrado da esquerda: a imagem da notificação (capa, print,
                        // prévia) recortada; sem imagem, o ícone do app. Antes a
                        // imagem vinha esticada embaixo do texto.
                        Item {
                            Layout.preferredWidth: card.hasImage ? 48 : 36
                            Layout.preferredHeight: card.hasImage ? 48 : 36
                            Layout.alignment: Qt.AlignTop

                        ClippingRectangle {
                            visible: card.hasImage
                            anchors.fill: parent
                            radius: 8
                            color: Theme.tileHigh
                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 96
                                sourceSize.height: 96
                                source: card.imageSource
                            }
                        }

                        ClippingRectangle {
                            // Com imagem, o ícone do app vira um selo no canto.
                            width: card.hasImage ? 20 : parent.width
                            height: width
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: card.hasImage ? -4 : 0
                            anchors.bottomMargin: card.hasImage ? -4 : 0
                            visible: !card.hasImage || notifIcon.visible
                            radius: card.hasImage ? 6 : 8
                            color: Theme.tileHigh

                            IconImage {
                                id: notifIcon
                                anchors.centerIn: parent
                                width: card.hasImage ? 16 : 24
                                height: width
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
                                wrapMode: card.expanded ? Text.Wrap : Text.NoWrap
                                Layout.fillWidth: true
                                visible: text.length > 0
                            }

                            Text {
                                id: bodyText
                                text: card.modelData.body || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.subtext
                                wrapMode: Text.Wrap
                                maximumLineCount: card.expanded ? 40 : 3
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

                    // Setinha: há texto cortado (ou já está expandida). Clique ou
                    // arraste para baixo/cima.
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: -4
                        visible: bodyText.truncated || card.expanded
                        text: Theme.icons.chevronRight
                        rotation: card.expanded ? -90 : 90
                        Behavior on rotation { NumberAnimation { duration: Theme.ms(160) } }
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 16
                        color: chevArea.containsMouse ? Theme.textColor : Theme.subtext
                        MouseArea {
                            id: chevArea
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.expanded = !card.expanded
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
