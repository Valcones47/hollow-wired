import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: lockScreen
    signal loginRequested

    // Véu escuro em degradê partindo da base: garante que o relógio, a data e o
    // aviso "pressione qualquer tecla" continuem legíveis em qualquer wallpaper,
    // inclusive nos claros, sem precisar escurecer a imagem inteira.
    Rectangle {
        anchors.fill: parent
        z: -2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.45) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.12) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
        }
    }

    // Animação de entrada: o conteúdo sobe e aparece suavemente quando a tela
    // de bloqueio surge, em vez de simplesmente piscar na tela.
    property real introProgress: 0.0
    NumberAnimation on introProgress {
        running: true
        from: 0.0
        to: 1.0
        duration: Config.enableAnimations ? 650 : 0
        easing.type: Easing.OutCubic
    }

    ColumnLayout {
        id: timePositioner
        opacity: lockScreen.introProgress
        transform: Translate { y: (1.0 - lockScreen.introProgress) * 18 }
        spacing: Config.dateMarginTop
        Text {
            id: time
            visible: Config.clockDisplay
            font.pixelSize: Config.clockFontSize
            font.weight: Config.clockFontWeight
            font.family: Config.clockFontFamily
            color: Config.clockColor
            Layout.alignment: Config.clockAlign === "left" ? Qt.AlignLeft : (Config.clockAlign === "right" ? Qt.AlignRight : Qt.AlignHCenter)

            function updateTime() {
                text = new Date().toLocaleString(Qt.locale(""), Config.clockFormat);
            }
        }

        Text {
            id: date
            Layout.alignment: Config.clockAlign === "left" ? Qt.AlignLeft : (Config.clockAlign === "right" ? Qt.AlignRight : Qt.AlignHCenter)
            visible: Config.dateDisplay
            font.pixelSize: Config.dateFontSize
            font.family: Config.dateFontFamily
            font.weight: Config.dateFontWeight
            color: Config.dateColor

            function updateDate() {
                // Qt.locale() = idioma do sistema. Fixar "pt_BR" aqui fazia a
                // tela de login de quem instala o rice em outro idioma mostrar
                // a data em português.
                var dStr = new Date().toLocaleString(Qt.locale(), Config.dateFormat);
                if (dStr && dStr.length > 0) {
                    text = dStr.charAt(0).toUpperCase() + dStr.slice(1);
                } else {
                    text = dStr;
                }
            }
        }

        Timer {
            interval: 1000
            repeat: true
            running: true
            onTriggered: {
                time.updateTime();
                date.updateDate();
            }
        }

        anchors {
            topMargin: Config.lockScreenPaddingTop || lockScreen.height / 10
            rightMargin: Config.lockScreenPaddingRight || lockScreen.height / 10
            bottomMargin: Config.lockScreenPaddingBottom || lockScreen.height / 10
            leftMargin: Config.lockScreenPaddingLeft || lockScreen.height / 10
        }
        Component.onCompleted: {
            lockScreen.alignItem(timePositioner, Config.clockPosition);
            time.updateTime();
            date.updateDate();
        }
    }

    ColumnLayout {
        id: messagePositioner
        visible: Config.lockMessageDisplay
        spacing: Config.lockMessageSpacing

        // "Respiração" no aviso de destravar: deixa claro que a tela está viva
        // e esperando uma tecla — especialmente pra quem vem do Windows e não
        // sabe que basta apertar qualquer coisa.
        opacity: Config.enableAnimations ? 0 : 1
        SequentialAnimation on opacity {
            running: Config.enableAnimations
            PauseAnimation { duration: 400 }
            NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.OutCubic }
            SequentialAnimation {
                loops: Animation.Infinite
                NumberAnimation { to: 0.55; duration: 1600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0;  duration: 1600; easing.type: Easing.InOutSine }
            }
        }
        Image {
            id: lockIcon
            source: Config.getIcon(Config.lockMessageIcon)
            Layout.alignment: Config.lockMessageAlign === "left" ? Qt.AlignLeft : (Config.lockMessageAlign === "right" ? Qt.AlignRight : Qt.AlignHCenter)
            visible: Config.lockMessageDisplayIcon

            Layout.preferredWidth: Config.lockMessageIconSize
            Layout.preferredHeight: Config.lockMessageIconSize
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit

            MultiEffect {
                source: lockIcon
                anchors.fill: lockIcon
                colorization: Config.lockMessagePaintIcon ? 1 : 0
                colorizationColor: Config.lockMessageColor
            }
        }
        Text {
            id: lockMessage
            Layout.alignment: Config.lockMessageAlign === "left" ? Qt.AlignLeft : (Config.lockMessageAlign === "right" ? Qt.AlignRight : Qt.AlignHCenter)
            font.pixelSize: Config.lockMessageFontSize
            font.family: Config.lockMessageFontFamily
            font.weight: Config.lockMessageFontWeight
            color: Config.lockMessageColor
            text: Config.lockMessageText
        }

        anchors {
            topMargin: Config.lockScreenPaddingTop || lockScreen.height / 10
            rightMargin: Config.lockScreenPaddingRight || lockScreen.height / 10
            bottomMargin: Config.lockScreenPaddingBottom || lockScreen.height / 10
            leftMargin: Config.lockScreenPaddingLeft || lockScreen.height / 10
        }
        Component.onCompleted: lockScreen.alignItem(messagePositioner, Config.lockMessagePosition)
    }

    function alignItem(item, pos) {
        switch (pos) {
        case "top-left":
            item.anchors.top = lockScreen.top;
            item.anchors.left = lockScreen.left;
            break;
        case "top-center":
            item.anchors.top = lockScreen.top;
            item.anchors.horizontalCenter = lockScreen.horizontalCenter;
            break;
        case "top-right":
            item.anchors.top = lockScreen.top;
            item.anchors.right = lockScreen.right;
            break;
        case "center-left":
            item.anchors.verticalCenter = lockScreen.verticalCenter;
            item.anchors.left = lockScreen.left;
            break;
        case "center":
            item.anchors.verticalCenter = lockScreen.verticalCenter;
            item.anchors.horizontalCenter = lockScreen.horizontalCenter;
            break;
        case "center-right":
            item.anchors.verticalCenter = lockScreen.verticalCenter;
            item.anchors.right = lockScreen.right;
            break;
        case "bottom-left":
            item.anchors.bottom = lockScreen.bottom;
            item.anchors.left = lockScreen.left;
            break;
        case "bottom-center":
            item.anchors.bottom = lockScreen.bottom;
            item.anchors.horizontalCenter = lockScreen.horizontalCenter;
            break;
        default:
            item.anchors.bottom = lockScreen.bottom;
            item.anchors.right = lockScreen.right;
        }
    }

    MouseArea {
        id: lockScreenMouseArea
        hoverEnabled: true
        z: -1
        anchors.fill: lockScreen
        onClicked: lockScreen.loginRequested()
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_CapsLock) {
            root.capsLockOn = !root.capsLockOn;
        }

        if (event.key === Qt.Key_Escape) {
            event.accepted = false;
            return;
        } else {
            lockScreen.loginRequested();
        }
        event.accepted = true;
    }
}
