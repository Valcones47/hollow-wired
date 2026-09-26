pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Services.UPower
import "."

// Visual da tela de bloqueio, no estilo do Caelestia: um quadradinho com o
// cadeado entra girando, se abre no cartão com clima, fetch, mídia, relógio,
// foto, senha, recursos e notificações; ao desbloquear o cartão encolhe de
// volta para o cadeado e some.
//
// Não sabe nada de PAM nem de sessão: tudo vem do `ctl` (LockScreen.qml hoje,
// e o greeter do greetd depois), que expõe o estado e as ações.
Item {
    id: view

    required property var ctl
    property real screenH: 1080
    // No greeter (greetd) não há sessão aberta: sem mídia, notificações nem
    // controles do usuário; no lugar entra o seletor de WM.
    readonly property bool greeter: ctl.isGreeter === true

    readonly property real s: Math.max(0.6, screenH / 1080)
    readonly property real fullH: screenH * 0.7
    readonly property real fullW: fullH * 16 / 9
    readonly property real centerScale: Math.min(1, screenH / 1440)
    readonly property int centerWidth: 600 * centerScale

    // ---------- cores ----------
    readonly property color pri: Theme.mix(Theme.primary, Theme.foreground, 0.35)
    readonly property color sec: Theme.mix(Theme.secondary, Theme.foreground, 0.35)
    readonly property color ter: Theme.mix(Theme.accent2, Theme.foreground, 0.35)
    readonly property color onSurf: Theme.foreground
    readonly property color onSurfVar: Theme.withAlpha(Theme.foreground, 0.7)
    readonly property color outline: Theme.withAlpha(Theme.foreground, 0.45)
    readonly property color cardColor: Theme.withAlpha(Theme.background, 0.88)
    readonly property color tileColor: Theme.withAlpha(Theme.mix(Theme.background, Theme.foreground, 0.06), 0.92)
    readonly property color tileHigh: Theme.mix(Theme.background, Theme.foreground, 0.13)
    readonly property color errorColor: Theme.mix(Theme.critical, Theme.foreground, 0.25)

    readonly property string clockFont: "Open Sans Condensed"

    property date now: new Date()
    property bool noteEditing: false
    readonly property string greeting: {
        const h = now.getHours();
        const en = Theme.locale === "en";
        const g = h < 6 ? (en ? "Good night" : "Boa madrugada") : h < 12 ? (en ? "Good morning" : "Bom dia")
                : h < 18 ? (en ? "Good afternoon" : "Boa tarde") : (en ? "Good evening" : "Boa noite");
        return view.ctl.firstName ? g + ", " + view.ctl.firstName : g;
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: view.now = new Date()
    }

    // ---------- animações (curvas do Material 3 Expressive) ----------
    component FastSpatial: NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 1.67, 0.21, 0.9, 1, 1] }
    component DefSpatial: NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1] }
    component DefEffects: NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.34, 0.8, 0.34, 1, 1, 1] }
    component Std: NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
    component StdSmall: NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
    component StdLarge: NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }

    component Glyph: Text {
        property real px: 20
        font.family: Theme.iconFontFamily
        font.pixelSize: px
        color: view.onSurfVar
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    component Label: Text {
        property real px: 14
        font.family: Theme.fontFamily
        font.pixelSize: px
        color: view.onSurf
        elide: Text.ElideRight
    }
    component Tile: Rectangle {
        color: view.tileColor
        radius: 28 * view.s
    }

    Connections {
        target: view.ctl
        function onUnlockingChanged() {
            if (view.ctl.unlocking) {
                initAnim.stop();
                unlockAnim.start();
            }
        }
    }

    ParallelAnimation {
        id: initAnim
        running: true

        StdLarge { target: background; property: "opacity"; to: 1 }
        SequentialAnimation {
            ParallelAnimation {
                FastSpatial { target: lockContent; property: "scale"; to: 1 }
                NumberAnimation {
                    target: lockContent; property: "rotation"; to: 360; duration: 350
                    easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0, 1, 1, 1, 1]
                }
            }
            ParallelAnimation {
                NumberAnimation {
                    target: lockIcon; property: "rotation"; to: 360; duration: 500
                    easing.type: Easing.BezierSpline; easing.bezierCurve: [0, 0, 0, 1, 1, 1]
                }
                DefEffects { target: lockIcon; property: "opacity"; to: 0 }
                DefEffects { target: content; property: "opacity"; to: 1 }
                DefSpatial { target: content; property: "scale"; to: 1 }
                DefSpatial { target: lockBg; property: "radius"; to: 42 * view.s }
                DefSpatial { target: lockContent; property: "width"; to: view.fullW }
                DefSpatial { target: lockContent; property: "height"; to: view.fullH }
            }
        }
    }

    SequentialAnimation {
        id: unlockAnim

        ParallelAnimation {
            DefSpatial { target: lockContent; properties: "width,height"; to: lockContent.size }
            DefSpatial { target: lockBg; property: "radius"; to: lockContent.size / 4 }
            DefSpatial { target: content; property: "scale"; to: 0 }
            StdSmall { target: content; property: "opacity"; to: 0 }
            StdLarge { target: lockIcon; property: "opacity"; to: 1 }
            StdLarge { target: background; property: "opacity"; to: 0 }
            SequentialAnimation {
                PauseAnimation { duration: 200 }
                Std { target: lockContent; property: "opacity"; to: 0 }
            }
        }
        ScriptAction { script: view.ctl.unlockFinished() }
    }

    // ---------- fundo: wallpaper (vídeo se for vídeo) desfocado ----------
    // Zoom lento contínuo e um leve parallax seguindo o mouse.
    property real parX: 0
    property real parY: 0

    Item {
        id: background
        anchors.fill: parent
        opacity: 0
        clip: true

        Rectangle { anchors.fill: parent; color: Theme.background }

        Item {
            id: bgSource
            width: parent.width * 1.08
            height: parent.height * 1.08
            x: (parent.width - width) / 2 + view.parX
            y: (parent.height - height) / 2 + view.parY
            visible: false
            layer.enabled: true
            Behavior on x { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }

            SequentialAnimation on scale {
                loops: Animation.Infinite
                running: view.visible
                NumberAnimation { from: 1.0; to: 1.07; duration: 24000; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.07; to: 1.0; duration: 24000; easing.type: Easing.InOutSine }
            }

            Image {
                id: wallImg
                anchors.fill: parent
                source: view.ctl.wallpaper ? "file://" + view.ctl.wallpaper : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: 960
            }
            Video {
                id: wallVideo
                anchors.fill: parent
                source: view.ctl.wallVideo ? "file://" + view.ctl.wallVideo : ""
                fillMode: VideoOutput.PreserveAspectCrop
                loops: MediaPlayer.Infinite
                muted: true
                autoPlay: true
                opacity: playbackState === MediaPlayer.PlayingState ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 600 } }
            }
        }
        MultiEffect {
            anchors.fill: parent
            source: bgSource
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 64
            blurMultiplier: 1
            saturation: 0.1
        }
        Rectangle { anchors.fill: parent; color: Theme.withAlpha(Theme.background, 0.22) }
    }

    // Parallax e clique em qualquer lugar devolve o foco para a senha.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: mouse => {
            view.parX = (mouse.x / width - 0.5) * -28 * view.s;
            view.parY = (mouse.y / height - 0.5) * -18 * view.s;
        }
        onClicked: passwordBox.forceActiveFocus()
    }

    // ---------- cartão central ----------
    Item {
        id: lockContent

        readonly property real size: lockIcon.implicitHeight + 72 * view.s

        anchors.centerIn: parent
        width: size
        height: size
        rotation: 180
        scale: 0

        Rectangle {
            id: lockBg
            anchors.fill: parent
            color: view.cardColor
            radius: lockContent.size / 4

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                blurMax: 15
                shadowColor: Qt.rgba(0, 0, 0, 0.55)
            }
        }

        Glyph {
            id: lockIcon
            anchors.centerIn: parent
            text: Theme.icons.lock
            px: 96 * view.s
            color: view.onSurf
            rotation: 180
        }

        RowLayout {
            id: content

            anchors.centerIn: parent
            width: view.fullW - 56 * view.s
            height: view.fullH - 56 * view.s
            opacity: 0
            scale: 0
            spacing: 36 * view.s

            // ===== coluna esquerda =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                spacing: 12 * view.s

                WeatherTile { Layout.fillWidth: true }
                FetchTile { Layout.fillWidth: true; Layout.fillHeight: view.greeter }
                MediaTile { Layout.fillWidth: true; Layout.fillHeight: true; visible: !view.greeter }
            }

            // ===== centro =====
            ColumnLayout {
                Layout.preferredWidth: view.centerWidth
                Layout.fillWidth: false
                Layout.fillHeight: true
                spacing: 20 * view.s

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4 * view.s
                    text: view.greeting
                    color: view.onSurfVar
                    px: 18 * view.s
                }
                Clock {
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: Theme.formatDate(view.now, "dddd • d MMM").replace(".", "").toUpperCase()
                    px: 17 * view.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.5
                }
                ProfilePic {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 16 * view.s * view.centerScale
                    Layout.bottomMargin: 12 * view.s * view.centerScale
                }
                PasswordBox {
                    id: passwordBox
                    Layout.alignment: Qt.AlignHCenter
                }
                StateMessage { Layout.fillWidth: true }
                NoteLabel { Layout.fillWidth: true; Layout.topMargin: 6 * view.s; visible: !view.greeter || view.ctl.note !== "" }
                Item { Layout.fillHeight: true }
            }

            // ===== coluna direita =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                spacing: 12 * view.s

                ResourcesTile { Layout.fillWidth: true }
                QuickTile { Layout.fillWidth: true; visible: !view.greeter }
                NotifTile { Layout.fillWidth: true; Layout.fillHeight: true; visible: !view.greeter }
                SessionTile { Layout.fillWidth: true; Layout.fillHeight: true; visible: view.greeter }
            }
        }
    }

    // ======================================================================
    // Relógio
    // ======================================================================
    component Clock: Row {
        id: clock
        readonly property string hh: ("0" + view.now.getHours()).slice(-2)
        readonly property string mm: ("0" + view.now.getMinutes()).slice(-2)
        readonly property real px: 190 * view.s * view.centerScale / 0.75
        spacing: 0

        Digit { ch: clock.hh[0]; col: view.pri; px: clock.px }
        Digit { ch: clock.hh[1]; col: view.pri; px: clock.px }
        Item {
            id: colon
            width: colonWidth.advanceWidth
            height: colonMetrics.tightBoundingRect.height
            TextMetrics { id: colonMetrics; text: "0"; font.family: view.clockFont; font.pixelSize: clock.px; font.weight: Font.DemiBold }
            TextMetrics { id: colonWidth; text: ":"; font: colonMetrics.font }
            Text {
                y: -(colonMetrics.tightBoundingRect.y - colonMetrics.boundingRect.y)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: ":"
                color: Theme.mix(view.pri, view.sec, 0.5)
                font: colonMetrics.font
                // pisca devagar, como relógio digital
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: view.visible
                    NumberAnimation { to: 0.35; duration: 1000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 1000; easing.type: Easing.InOutSine }
                }
            }
        }
        Digit { ch: clock.mm[0]; col: view.sec; px: clock.px }
        Digit { ch: clock.mm[1]; col: view.sec; px: clock.px }
    }

    // Um dígito do relógio: quando muda, o antigo sobe e some e o novo entra
    // por baixo (flip clock deslizante).
    component Digit: Item {
        id: dg
        property string ch: "0"
        property color col: "white"
        property real px: 100
        property string shown: ""
        property string leaving: ""
        property real t: 1

        function topOff() { return metrics.tightBoundingRect.y - metrics.boundingRect.y; }

        TextMetrics { id: metrics; text: "0"; font.family: view.clockFont; font.pixelSize: dg.px; font.weight: Font.DemiBold }
        implicitWidth: metrics.advanceWidth
        implicitHeight: metrics.tightBoundingRect.height
        clip: true

        Component.onCompleted: shown = ch
        onChChanged: {
            if (shown === "" || ch === shown) { shown = ch; return; }
            leaving = shown;
            shown = ch;
            flip.restart();
        }
        NumberAnimation {
            id: flip
            target: dg; property: "t"; from: 0; to: 1; duration: 650
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
        }

        Text {
            y: -dg.topOff() - dg.t * dg.height
            opacity: 1 - dg.t
            visible: dg.t < 1
            text: dg.leaving
            color: dg.col
            font: metrics.font
            width: dg.width
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            y: -dg.topOff() + (1 - dg.t) * dg.height
            opacity: Math.min(1, dg.t * 1.5)
            text: dg.shown
            color: dg.col
            font: metrics.font
            width: dg.width
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ======================================================================
    // Foto do usuário numa forma de concha
    // ======================================================================
    component ProfilePic: Item {
        id: pfp
        readonly property real w: Math.round(view.centerWidth * 0.5)
        readonly property bool gif: view.ctl.avatarIsGif
        implicitWidth: w
        implicitHeight: w

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: view.tileHigh
        }
        Glyph {
            anchors.centerIn: parent
            text: Theme.icons.account
            px: pfp.w / 3
            visible: avatarImg.status !== Image.Ready
        }
        // AnimatedImage também abre imagem parada; só anima quando é GIF.
        AnimatedImage {
            id: avatarImg
            anchors.fill: parent
            source: view.ctl.avatar ? "file://" + view.ctl.avatar : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            playing: pfp.gif && view.visible
            visible: false
        }
        Rectangle {
            id: pfpMask
            anchors.fill: parent
            radius: width / 2
            layer.enabled: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: avatarImg
            visible: avatarImg.status === Image.Ready
            maskEnabled: true
            maskSource: pfpMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        // anel fino na cor de destaque
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4 * view.s
            radius: width / 2
            color: "transparent"
            border.width: 2 * view.s
            border.color: Theme.withAlpha(view.pri, 0.6)
        }
    }

    // ======================================================================
    // Campo de senha: cada caractere vira uma forma aleatória que se
    // transforma num círculo
    // ======================================================================
    component PasswordBox: Rectangle {
        id: box

        readonly property real sc: Math.max(0.8, view.centerScale) * view.s
        readonly property bool hasText: view.ctl.buffer.length > 0
        property bool showPassword: false
        readonly property var shapeQueue: {
            const shapes = ["slanted", "arrow", "pentagon", "triangle", "diamond", "gem", "sunny",
                            "verySunny", "cookie4", "cookie6", "softBurst", "square"];
            for (let i = shapes.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                [shapes[i], shapes[j]] = [shapes[j], shapes[i]];
            }
            return shapes;
        }
        readonly property string placeholderText: {
            if (view.ctl.busy) return Theme.t("lock.checking", "Verificando...");
            if (view.ctl.pamState === 2) return Theme.t("lock.maxtries", "Muitas tentativas");
            return Theme.t("lock.placeholder", "Digite sua senha");
        }

        implicitWidth: {
            const w = view.centerWidth * 0.8;
            return hasText ? w : Math.min(w, placeholderMetrics.width + height * 2 + 24 * sc + 32 * sc);
        }
        implicitHeight: 50 * sc
        radius: height / 2
        color: view.tileColor

        focus: true
        Component.onCompleted: forceActiveFocus()
        onActiveFocusChanged: if (!activeFocus && !view.noteEditing) forceActiveFocus()
        Keys.onPressed: event => {
            view.ctl.handleKey(event);
            event.accepted = true;
        }

        Behavior on implicitWidth { DefSpatial {} }

        // Sincroniza a lista de formas com o texto digitado: só acrescenta ou
        // tira do fim, assim cada forma anima uma vez só.
        Connections {
            target: view.ctl
            function onBufferChanged() {
                const n = view.ctl.buffer.length;
                if (n === 0) {
                    charModel.clear();
                    box.showPassword = false;
                    return;
                }
                while (charModel.count < n) charModel.append({ ch: view.ctl.buffer[charModel.count] });
                while (charModel.count > n) charModel.remove(charModel.count - 1);
            }
        }
        ListModel { id: charModel }

        TextMetrics {
            id: placeholderMetrics
            text: box.placeholderText
            font.family: Theme.fontFamily
            font.pixelSize: 15 * box.sc
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: box.forceActiveFocus()
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 5 * box.sc
            spacing: 10 * box.sc

            // ícone da esquerda: cadeado (clique mostra a senha) ou carregando
            Item {
                Layout.fillHeight: true
                implicitWidth: height

                Glyph {
                    anchors.centerIn: parent
                    visible: !view.ctl.busy
                    text: box.showPassword ? "\u{F0208}" : Theme.icons.lock
                    px: 20 * box.sc
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: box.showPassword = !box.showPassword
                    }
                }
                LockShape {
                    anchors.centerIn: parent
                    visible: view.ctl.busy
                    size: 20 * box.sc
                    shape: "softBurst"
                    color: view.sec
                    RotationAnimation on rotation {
                        running: view.ctl.busy
                        from: 0; to: 360; duration: 1100
                        loops: Animation.Infinite
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 1
                    text: box.placeholderText
                    color: view.ctl.busy ? view.sec : view.outline
                    font: placeholderMetrics.font
                    opacity: box.hasText ? 0 : 1
                    Behavior on opacity { DefEffects {} }
                }

                ListView {
                    id: charList
                    readonly property real dot: 15 * box.sc
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: width > parent.width ? -(width - parent.width) / 2 : 0
                    width: Math.max(0, contentWidth)
                    height: dot
                    orientation: ListView.Horizontal
                    spacing: 3 * box.sc
                    interactive: false
                    model: charModel

                    delegate: Item {
                        id: charItem
                        required property int index
                        required property string ch
                        implicitHeight: charList.dot
                        implicitWidth: charList.dot
                        opacity: 0
                        scale: 0

                        ListView.onRemove: removeAnim.start()

                        SequentialAnimation {
                            running: true
                            ParallelAnimation {
                                DefEffects { target: charItem; property: "opacity"; to: 1 }
                                FastSpatial { target: charItem; property: "scale"; to: 1 }
                                DefEffects { target: charItem; property: "implicitWidth"; from: charList.dot; to: charList.dot * 1.3 }
                            }
                            PauseAnimation { duration: 180 }
                            PropertyAction { target: charShape; property: "shape"; value: "circle" }
                            ParallelAnimation {
                                FastSpatial { target: charShape; property: "scale"; to: 2 / 3 }
                                DefEffects { target: charItem; property: "implicitWidth"; to: charList.dot }
                            }
                        }
                        SequentialAnimation {
                            id: removeAnim
                            PropertyAction { target: charItem; property: "ListView.delayRemove"; value: true }
                            ParallelAnimation {
                                DefEffects { target: charItem; property: "opacity"; to: 0 }
                                DefSpatial { target: charItem; property: "scale"; to: 0.5 }
                            }
                            PropertyAction { target: charItem; property: "ListView.delayRemove"; value: false }
                        }

                        LockShape {
                            id: charShape
                            anchors.centerIn: parent
                            size: charList.dot * 1.5
                            shape: box.shapeQueue[Math.max(0, charItem.index) % box.shapeQueue.length] ?? "circle"
                            color: view.onSurf
                            opacity: box.showPassword ? 0 : 1
                            Behavior on opacity { DefEffects {} }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: charItem.ch
                            color: view.onSurf
                            font.family: Theme.fontFamily
                            font.pixelSize: 15 * box.sc
                            opacity: box.showPassword ? 1 : 0
                            Behavior on opacity { DefEffects {} }
                        }
                    }
                }
            }

            // botão de entrar: círculo que vira seta quando há texto
            Item {
                Layout.fillHeight: true
                implicitWidth: height

                LockShape {
                    anchors.centerIn: parent
                    size: parent.height
                    shape: box.hasText ? "arrow" : "circle"
                    color: box.hasText ? view.pri : view.tileHigh
                    scale: !box.hasText ? 1 : enterMouse.pressed ? 0.6 : enterMouse.containsMouse ? 0.8 : 0.7
                    Behavior on scale { FastSpatial {} }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                Glyph {
                    anchors.centerIn: parent
                    text: "\u{F0054}"
                    px: 22 * box.sc
                    opacity: box.hasText ? 0 : 1
                    Behavior on opacity { DefEffects {} }
                }
                MouseArea {
                    id: enterMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: box.hasText ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (box.hasText) view.ctl.submit()
                }
            }
        }
    }

    // ======================================================================
    // Mensagem de erro / Caps Lock embaixo da senha
    // ======================================================================
    component StateMessage: Item {
        id: sm
        readonly property string msg: {
            if (view.ctl.lockMessage) return view.ctl.lockMessage;
            if (view.ctl.pamState === 1) return Theme.t("lock.error", "Erro ao verificar a senha");
            if (view.ctl.pamState === 2) return Theme.t("lock.maxtries_long", "Muitas tentativas erradas. Espere um pouco e tente de novo.");
            if (view.ctl.pamState === 3) {
                const n = view.ctl.failCount;
                return n > 1 ? Theme.t("lock.wrong_n", "Senha incorreta (%1 tentativas). Tente de novo.").arg(n)
                             : Theme.t("lock.wrong", "Senha incorreta. Tente de novo.");
            }
            return "";
        }
        readonly property string hint: view.ctl.capsLock ? Theme.t("lock.caps", "Caps Lock está ativado") : ""

        implicitHeight: Math.max(errText.implicitHeight, hintText.implicitHeight)

        Label {
            id: hintText
            anchors.left: parent.left
            anchors.right: parent.right
            horizontalAlignment: Text.AlignHCenter
            text: sm.hint
            color: view.onSurfVar
            px: 13 * view.s
            scale: sm.hint && !sm.msg ? 1 : 0.7
            opacity: sm.hint && !sm.msg ? 1 : 0
            Behavior on scale { DefSpatial {} }
            Behavior on opacity { DefEffects {} }
        }
        Label {
            id: errText
            anchors.left: parent.left
            anchors.right: parent.right
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: sm.msg
            color: view.errorColor
            px: 13 * view.s
            scale: sm.msg ? 1 : 0.7
            opacity: sm.msg ? 1 : 0
            Behavior on scale { DefSpatial {} }
            Behavior on opacity { DefEffects {} }

            SequentialAnimation {
                id: flashAnim
                loops: 2
                NumberAnimation { target: errText; property: "opacity"; to: 0.3; duration: 200 }
                NumberAnimation { target: errText; property: "opacity"; to: 1; duration: 200 }
            }
            Connections {
                target: view.ctl
                function onFlash() { flashAnim.restart(); }
            }
        }
    }

    // ======================================================================
    // Clima
    // ======================================================================
    component WeatherTile: Tile {
        id: wt
        readonly property var w: view.ctl.weather
        radius: 36 * view.s
        implicitHeight: wcol.implicitHeight + 48 * view.s

        ColumnLayout {
            id: wcol
            anchors.centerIn: parent
            spacing: 4 * view.s

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: wt.w ? wt.w.desc : Theme.t("lock.no_weather", "Sem dados do clima")
                color: view.onSurfVar
                px: 16 * view.s
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12 * view.s
                visible: !!wt.w
                Label {
                    text: wt.w ? wt.w.temp + "°C" : ""
                    color: view.pri
                    px: 46 * view.s
                    font.weight: Font.DemiBold
                }
                Glyph {
                    text: wt.w ? view.ctl.weatherIcon(wt.w.code, view.now.getHours()) : ""
                    color: view.sec
                    px: 46 * view.s
                }
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                visible: !!wt.w && view.screenH > 550
                text: wt.w ? Theme.t("lock.feels", "Sensação de %1").arg(wt.w.feels + "°C") : ""
                color: view.onSurfVar
                px: 16 * view.s
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                visible: !!wt.w && view.screenH > 550
                text: wt.w ? Theme.t("lock.highlow", "Máx %1 • Mín %2").arg(wt.w.max + "°C").arg(wt.w.min + "°C") : ""
                color: view.onSurfVar
                px: 14 * view.s
            }
        }
    }

    // ======================================================================
    // "fetch" do sistema
    // ======================================================================
    component FetchTile: Tile {
        id: ft
        radius: 14 * view.s
        implicitHeight: fcol.implicitHeight + 44 * view.s

        readonly property bool hasBatt: UPower.displayDevice.isLaptopBattery
        readonly property var lines: {
            const up = view.ctl.uptimeText(view.now);
            const items = [];
            if (!hasBatt) items.push("OS  : " + view.ctl.osName);
            items.push("WM  : Hyprland");
            items.push("USER: " + view.ctl.userName);
            items.push("UP  : " + up);
            if (hasBatt) {
                const pct = Math.round(UPower.displayDevice.percentage * 100);
                const charging = [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state);
                items.push("BAT : " + (charging ? "(+) " : "") + pct + "%");
            }
            return items;
        }

        ColumnLayout {
            id: fcol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 22 * view.s
            spacing: 8 * view.s

            RowLayout {
                spacing: 10 * view.s
                Rectangle {
                    implicitWidth: promptTxt.implicitWidth + 16 * view.s
                    implicitHeight: promptTxt.implicitHeight + 8 * view.s
                    radius: 10 * view.s
                    color: view.pri
                    Text {
                        id: promptTxt
                        anchors.centerIn: parent
                        text: ">"
                        color: Theme.background
                        font.family: Theme.monoFamily
                        font.pixelSize: 14 * view.s
                        font.bold: true
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: "hollowfetch.sh"
                    color: view.onSurf
                    font.family: Theme.monoFamily
                    font.pixelSize: 14 * view.s
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 22 * view.s

                Item {
                    implicitWidth: 92 * view.s
                    implicitHeight: 92 * view.s
                    visible: ft.width > 320 * view.s
                    Image {
                        id: logoImg
                        anchors.fill: parent
                        source: view.ctl.osLogo ? "file://" + view.ctl.osLogo : ""
                        sourceSize: Qt.size(184, 184)
                        fillMode: Image.PreserveAspectFit
                        visible: false
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: logoImg
                        visible: logoImg.status === Image.Ready
                        colorization: 1
                        colorizationColor: view.pri
                        brightness: 0.25
                    }
                    Glyph {
                        anchors.centerIn: parent
                        visible: logoImg.status !== Image.Ready
                        text: Theme.icons.arch
                        px: 72 * view.s
                        color: view.pri
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8 * view.s
                    Repeater {
                        model: ft.lines
                        Text {
                            required property string modelData
                            Layout.fillWidth: true
                            text: modelData
                            color: view.onSurf
                            font.family: Theme.monoFamily
                            font.pixelSize: 14 * view.s
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4 * view.s
                spacing: 16 * view.s
                visible: view.screenH > 700
                Repeater {
                    model: [Theme.color0, Theme.color1, Theme.color2, Theme.color3, Theme.color4, Theme.color5, Theme.color6]
                    Rectangle {
                        required property color modelData
                        width: 28 * view.s
                        height: width
                        radius: 10 * view.s
                        color: modelData
                    }
                }
            }
        }
    }

    // ======================================================================
    // Mídia
    // ======================================================================
    component MediaTile: Tile {
        id: mt
        radius: 28 * view.s
        clip: true
        implicitHeight: mcol.implicitHeight + 40 * view.s

        readonly property var player: view.ctl.player
        readonly property real len: player && player.length > 0 ? player.length : 0
        readonly property real frac: len > 0 ? Math.max(0, Math.min(1, view.ctl.tickPosition / len)) : 0
        function fmt(t) {
            t = Math.max(0, Math.floor(t));
            return Math.floor(t / 60) + ":" + ("0" + (t % 60)).slice(-2);
        }

        // capa desfocada de fundo
        Image {
            id: artBg
            anchors.fill: parent
            source: mt.player?.trackArtUrl ?? ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 320
            visible: false
        }
        Rectangle { id: artMask; anchors.fill: parent; radius: mt.radius; layer.enabled: true; visible: false }
        MultiEffect {
            anchors.fill: parent
            source: artBg
            visible: artBg.status === Image.Ready
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 0.8
            blurMax: 48
            maskEnabled: true
            maskSource: artMask
        }
        Rectangle {
            anchors.fill: parent
            radius: mt.radius
            color: Theme.background
            opacity: artBg.status === Image.Ready ? 0.72 : 0
        }

        // cava: barrinhas no rodapé do cartão
        Row {
            id: cavaRow
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            height: parent.height * 0.45
            spacing: 2 * view.s
            opacity: 0.35
            Repeater {
                model: view.ctl.cavaBars.length
                Rectangle {
                    required property int index
                    anchors.bottom: parent.bottom
                    width: Math.max(2, (mt.width - 40 * view.s) / Math.max(1, view.ctl.cavaBars.length) - 2 * view.s)
                    height: Math.max(2, cavaRow.height * (view.ctl.cavaBars[index] || 0) / 100)
                    radius: width / 2
                    color: view.pri
                    Behavior on height { NumberAnimation { duration: 90 } }
                }
            }
        }

        ColumnLayout {
            id: mcol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 20 * view.s
            spacing: 8 * view.s

            RowLayout {
                Layout.fillWidth: true
                spacing: 14 * view.s

                // capa em forma de disco, girando enquanto toca
                Item {
                    implicitWidth: 72 * view.s
                    implicitHeight: 72 * view.s
                    Rectangle { anchors.fill: parent; radius: width / 2; color: view.tileHigh }
                    Glyph { anchors.centerIn: parent; text: Theme.icons.music; px: 26 * view.s; visible: discImg.status !== Image.Ready }
                    Item {
                        id: disc
                        anchors.fill: parent
                        NumberAnimation on rotation {
                            running: mt.player?.isPlaying ?? false
                            from: 0; to: 360
                            duration: 9000
                            loops: Animation.Infinite
                        }
                        Image {
                            id: discImg
                            anchors.fill: parent
                            source: mt.player?.trackArtUrl ?? ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(144, 144)
                            asynchronous: true
                            visible: false
                        }
                        Rectangle { id: discMask; anchors.fill: parent; radius: width / 2; layer.enabled: true; visible: false }
                        MultiEffect {
                            anchors.fill: parent
                            source: discImg
                            visible: discImg.status === Image.Ready
                            maskEnabled: true
                            maskSource: discMask
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.18; height: width; radius: width / 2
                            color: Theme.withAlpha(Theme.background, 0.85)
                            visible: discImg.status === Image.Ready
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2 * view.s
                    Label {
                        Layout.fillWidth: true
                        text: mt.player ? (mt.player.trackTitle || Theme.t("lock.unknown_track", "Faixa desconhecida")) : Theme.t("lock.nothing_playing", "Nada tocando")
                        color: view.pri
                        px: 16 * view.s
                        font.weight: Font.Medium
                    }
                    Label {
                        Layout.fillWidth: true
                        text: mt.player ? (mt.player.trackArtist || Theme.t("lock.unknown_artist", "Artista desconhecido")) : Theme.t("lock.try_music", "Que tal uma música?")
                        color: view.onSurfVar
                        px: 13 * view.s
                    }
                    // trocar de player quando há mais de um
                    Label {
                        visible: view.ctl.players.length > 1
                        text: (mt.player?.identity ?? "") + "  \u{F0142}"
                        color: view.outline
                        px: 11 * view.s
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.ctl.nextPlayer()
                        }
                    }
                }
            }

            // linha atual da letra
            Label {
                id: lyricLabel
                Layout.fillWidth: true
                visible: view.ctl.lyricLine !== ""
                horizontalAlignment: Text.AlignHCenter
                text: view.ctl.lyricLine
                color: view.onSurf
                px: 14 * view.s
                font.italic: true
                onTextChanged: lyricFade.restart()
                NumberAnimation { id: lyricFade; target: lyricLabel; property: "opacity"; from: 0; to: 1; duration: 300 }
            }

            // barra de progresso arrastável
            ColumnLayout {
                Layout.fillWidth: true
                visible: mt.len > 0
                spacing: 2 * view.s
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 14 * view.s
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 5 * view.s
                        radius: height / 2
                        color: Theme.withAlpha(view.pri, 0.2)
                        Rectangle {
                            width: parent.width * (seekArea.pressed ? seekArea.dragFrac : mt.frac)
                            height: parent.height
                            radius: height / 2
                            color: view.pri
                        }
                    }
                    Rectangle {
                        x: (parent.width - width) * (seekArea.pressed ? seekArea.dragFrac : mt.frac)
                        anchors.verticalCenter: parent.verticalCenter
                        width: (seekArea.pressed || seekArea.containsMouse ? 14 : 10) * view.s
                        height: width
                        radius: width / 2
                        color: view.onSurf
                        visible: mt.player?.canSeek ?? false
                    }
                    MouseArea {
                        id: seekArea
                        property real dragFrac: 0
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        enabled: mt.player?.canSeek ?? false
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true
                        onPressed: mouse => dragFrac = Math.max(0, Math.min(1, (mouse.x - 6) / (width - 12)))
                        onPositionChanged: mouse => { if (pressed) dragFrac = Math.max(0, Math.min(1, (mouse.x - 6) / (width - 12))); }
                        onReleased: view.ctl.seek(dragFrac)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: mt.fmt(seekArea.pressed ? seekArea.dragFrac * mt.len : view.ctl.tickPosition); px: 11 * view.s; color: view.outline }
                    Item { Layout.fillWidth: true }
                    Label { text: mt.fmt(mt.len); px: 11 * view.s; color: view.outline }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6 * view.s

                MediaButton {
                    icon: Theme.icons.prev
                    enabled: mt.player?.canGoPrevious ?? false
                    onClicked: mt.player.previous()
                }
                MediaButton {
                    main: true
                    icon: mt.player?.isPlaying ? Theme.icons.pause : Theme.icons.play
                    enabled: mt.player?.canTogglePlaying ?? false
                    onClicked: mt.player.togglePlaying()
                }
                MediaButton {
                    icon: Theme.icons.next
                    enabled: mt.player?.canGoNext ?? false
                    onClicked: mt.player.next()
                }
            }
        }
    }

    // ======================================================================
    // Recursos (CPU/RAM/disco) — ao passar o mouse vira os botões de sessão
    // ======================================================================
    component ResourcesTile: Tile {
        id: rt
        radius: 28 * view.s
        clip: true
        implicitHeight: resRow.implicitHeight + 40 * view.s

        readonly property bool showSession: hover.hovered

        HoverHandler { id: hover }

        RowLayout {
            id: resRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20 * view.s
            spacing: 18 * view.s
            opacity: rt.showSession ? 0 : 1
            transform: Translate {
                y: rt.showSession ? rt.height : 0
                Behavior on y { DefSpatial {} }
            }
            Behavior on opacity { DefEffects {} }

            // Medidores no estilo "líquido": o nível sobe de baixo com a borda
            // ondulando, o valor grande no canto. Embaixo, disco e rede.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10 * view.s
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10 * view.s
                    LiquidMeter {
                        label: "CPU"
                        icon: Theme.icons.speed
                        frac: SysStats.cpuUsage
                        value: Math.round(SysStats.cpuUsage * 100) + "%"
                        tint: view.pri
                    }
                    LiquidMeter {
                        label: "RAM"
                        icon: Theme.icons.memory
                        frac: SysStats.ramFrac
                        value: SysStats.ramRealGiB.toFixed(1).replace(".", ",") + "G"
                        tint: view.ter
                    }
                    LiquidMeter {
                        label: Theme.t("lock.temp", "Temp")
                        icon: Theme.icons.temp || Theme.icons.speed
                        frac: Math.max(0, Math.min(1, (SysStats.cpuTemp - 25) / 75))
                        value: SysStats.cpuTemp > 0 ? Math.round(SysStats.cpuTemp) + "°" : "--"
                        tint: SysStats.cpuTemp > 90 ? view.errorColor : view.sec
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10 * view.s
                    // Disco: barra horizontal com o espaço usado.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 64 * view.s
                        radius: 16 * view.s
                        color: Theme.withAlpha(view.sec, 0.08)
                        clip: true
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * SysStats.diskFrac
                            color: Theme.withAlpha(view.sec, 0.28)
                            Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 12 * view.s
                            text: Theme.icons.disk + "  " + Theme.t("lock.disk", "Disco")
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 11 * view.s
                            color: Theme.withAlpha(view.sec, 0.9)
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 10 * view.s
                            text: Math.round(SysStats.diskUsedGiB) + " / " + Math.round(SysStats.diskTotalGiB) + " G"
                            font.family: Theme.fontFamily
                            font.pixelSize: 15 * view.s
                            font.weight: Font.DemiBold
                            color: view.sec
                        }
                    }
                    // Rede: velocidade agora.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 64 * view.s
                        radius: 16 * view.s
                        color: Theme.withAlpha(view.pri, 0.08)
                        function speed(b) {
                            return b >= 1048576 ? (b / 1048576).toFixed(1).replace(".", ",") + " MB/s"
                                 : Math.round(b / 1024) + " KB/s";
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 12 * view.s
                            text: Theme.icons.wifi4 + "  " + Theme.t("lock.net", "Rede")
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 11 * view.s
                            color: Theme.withAlpha(view.pri, 0.9)
                        }
                        Column {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 10 * view.s
                            spacing: 0
                            Text {
                                anchors.right: parent.right
                                text: "↓ " + parent.parent.speed(SysStats.netDown)
                                font.family: Theme.fontFamily
                                font.pixelSize: 13 * view.s
                                font.weight: Font.DemiBold
                                color: view.pri
                            }
                            Text {
                                anchors.right: parent.right
                                text: "↑ " + parent.parent.speed(SysStats.netUp)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11 * view.s
                                color: Theme.withAlpha(view.pri, 0.75)
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 20 * view.s
            spacing: 14 * view.s
            opacity: rt.showSession ? 1 : 0
            visible: opacity > 0
            transform: Translate {
                y: rt.showSession ? 0 : -rt.height
                Behavior on y { DefSpatial {} }
            }
            Behavior on opacity { DefEffects {} }

            SessionButton { icon: Theme.icons.logout; label: Theme.t("lock.switch_wm", "Trocar de WM"); action: "switch-wm"; visible: !view.greeter }
            SessionButton { icon: Theme.icons.sleep; label: Theme.t("lock.suspend", "Suspender"); action: "suspend" }
            SessionButton { icon: Theme.icons.restart; label: Theme.t("lock.reboot", "Reiniciar"); action: "reboot" }
            SessionButton { icon: Theme.icons.power; label: Theme.t("lock.poweroff", "Desligar"); action: "poweroff" }
        }
    }

    component SessionButton: Rectangle {
        id: sb
        property string icon
        property string label
        property string action

        Layout.fillWidth: true
        Layout.preferredHeight: width
        radius: sbMouse.pressed ? 14 * view.s : sbMouse.containsMouse ? 32 * view.s : 22 * view.s
        color: sbMouse.containsMouse ? Theme.mix(Theme.background, view.sec, 0.35) : view.tileHigh
        Behavior on radius { FastSpatial {} }
        Behavior on color { ColorAnimation { duration: 150 } }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4 * view.s
            Glyph {
                Layout.alignment: Qt.AlignHCenter
                text: sb.icon
                px: 28 * view.s
                color: view.onSurf
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: sb.width - 8
                text: sb.label
                px: 11 * view.s
                color: view.onSurfVar
            }
        }
        MouseArea {
            id: sbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: view.ctl.sessionAction(sb.action)
        }
    }

    // Cartão com "líquido": o nível (frac) sobe de baixo e a borda de cima
    // ondula devagar. Nome no alto, valor grande embaixo à direita.
    component LiquidMeter: Rectangle {
        id: lm
        property string label: ""
        property string icon: ""
        property real frac: 0
        property string value: ""
        property color tint: view.pri
        Layout.fillWidth: true
        implicitHeight: 118 * view.s
        radius: 16 * view.s
        color: Theme.withAlpha(tint, 0.08)
        clip: true
        Behavior on frac { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

        property real phase: 0
        NumberAnimation on phase { from: 0; to: Math.PI * 2; duration: 2600; loops: Animation.Infinite; running: lm.visible }
        Canvas {
            id: liquid
            anchors.fill: parent
            onPaint: {
                const c = getContext("2d");
                c.reset();
                const top = height * (1 - Math.max(0.02, Math.min(1, lm.frac)));
                const amp = 3 * view.s;
                c.beginPath();
                c.moveTo(0, height);
                for (let x = 0; x <= width; x += 4)
                    c.lineTo(x, top + Math.sin(x / width * Math.PI * 2 + lm.phase) * amp);
                c.lineTo(width, height);
                c.closePath();
                c.fillStyle = Theme.withAlpha(lm.tint, 0.35);
                c.fill();
                c.beginPath();
                for (let x = 0; x <= width; x += 4) {
                    const y = top + Math.sin(x / width * Math.PI * 2 + lm.phase) * amp;
                    if (x === 0) c.moveTo(x, y); else c.lineTo(x, y);
                }
                c.lineWidth = 2;
                c.strokeStyle = Theme.withAlpha(lm.tint, 0.8);
                c.stroke();
            }
        }
        onPhaseChanged: liquid.requestPaint()
        onFracChanged: liquid.requestPaint()
        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 12 * view.s
            text: lm.icon + "  " + lm.label
            font.family: Theme.iconFontFamily
            font.pixelSize: 11 * view.s
            color: Theme.withAlpha(lm.tint, 0.95)
        }
        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 10 * view.s
            text: lm.value
            font.family: Theme.fontFamily
            font.pixelSize: 22 * view.s
            font.weight: Font.DemiBold
            color: Theme.foreground
        }
    }

    component Resource: Item {
        id: res
        property string icon
        property real frac: 0
        property string shape: "circle"
        property color valueColor
        property color shapeColor
        property color fillColor
        default property alias extra: extraHolder.data

        Layout.fillWidth: true
        implicitHeight: width

        Behavior on frac { DefSpatial {} }

        LockShape {
            id: resShape
            anchors.centerIn: parent
            size: res.width
            shape: res.shape
            color: res.shapeColor
        }
        LockShape {
            id: resMask
            anchors.fill: resShape
            size: res.width
            shape: res.shape
            color: "white"
            layer.enabled: true
            visible: false
        }
        // Onda subindo até a porcentagem, recortada pela forma.
        Item {
            id: waveHolder
            anchors.fill: resShape
            layer.enabled: true
            visible: false
            clip: true

            Item {
                id: wave
                readonly property real amp: 4 * view.s
                readonly property real period: res.width / 2
                width: res.width * 2
                height: res.width + amp * 2
                y: waveHolder.height * (1 - res.frac) - amp

                NumberAnimation on x {
                    from: 0; to: -wave.period
                    duration: 1600
                    loops: Animation.Infinite
                    running: res.visible
                }
                LockWave {
                    anchors.fill: parent
                    amp: wave.amp
                    period: wave.period
                    color: res.fillColor
                }
            }
        }
        MultiEffect {
            anchors.fill: resShape
            source: waveHolder
            maskEnabled: true
            maskSource: resMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: -2 * view.s
            Glyph {
                Layout.alignment: Qt.AlignHCenter
                text: res.icon
                px: 20 * view.s
                color: view.sec
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: Math.round(res.frac * 100) + "%"
                color: res.valueColor
                px: 24 * view.s
                font.weight: Font.DemiBold
                font.family: view.clockFont
            }
        }
        Item { id: extraHolder; anchors.fill: parent }
    }

    // ======================================================================
    // Notificações agrupadas por app
    // ======================================================================
    component MediaButton: Rectangle {
        id: mb
        property string icon
        property bool main: false
        signal clicked

        implicitHeight: 44 * view.s
        implicitWidth: main ? implicitHeight + 36 * view.s : implicitHeight
        radius: mbMouse.pressed ? 12 * view.s : height / 2
        color: main ? view.pri : view.tileHigh
        opacity: enabled ? 1 : 0.4
        Behavior on radius { FastSpatial {} }

        Glyph {
            anchors.centerIn: parent
            text: mb.icon
            px: 20 * view.s
            color: mb.main ? Theme.background : view.onSurf
        }
        MouseArea {
            id: mbMouse
            anchors.fill: parent
            enabled: mb.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: mb.clicked()
        }
    }

    component NotifTile: Rectangle {
        id: nt
        color: view.tileColor
        radius: 14 * view.s
        bottomRightRadius: 28 * view.s
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16 * view.s
            spacing: 10 * view.s

            // "Enquanto você estava fora"
            Rectangle {
                Layout.fillWidth: true
                visible: view.ctl.awayNotifs > 0 || view.ctl.awayDownloads.length > 0
                implicitHeight: awayCol.implicitHeight + 16 * view.s
                radius: 16 * view.s
                color: Theme.withAlpha(view.pri, 0.14)
                border.width: 1
                border.color: Theme.withAlpha(view.pri, 0.3)
                ColumnLayout {
                    id: awayCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 12 * view.s
                    spacing: 2 * view.s
                    Label {
                        text: Theme.t("lock.away_title", "Enquanto você estava fora")
                        color: view.pri
                        px: 13 * view.s
                        font.weight: Font.DemiBold
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: view.ctl.awayNotifs > 0
                        text: view.ctl.awayNotifs === 1 ? Theme.t("lock.away_notif_one", "1 notificação nova")
                              : Theme.t("lock.away_notifs", "%1 notificações novas").arg(view.ctl.awayNotifs)
                        color: view.onSurfVar
                        px: 12 * view.s
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: view.ctl.awayDownloads.length > 0
                        text: (view.ctl.awayDownloads.length === 1 ? Theme.t("lock.away_dl_one", "1 download concluído")
                              : Theme.t("lock.away_dls", "%1 downloads concluídos").arg(view.ctl.awayDownloads.length))
                              + ": " + view.ctl.awayDownloads.slice(0, 3).join(", ")
                        color: view.onSurfVar
                        px: 12 * view.s
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: {
                        const n = view.ctl.notifTotal;
                        if (n === 0) return Theme.t("lock.no_notifs", "Nenhuma notificação");
                        if (n === 1) return Theme.t("lock.notif_one", "1 notificação");
                        return Theme.t("lock.notifs", "%1 notificações").arg(n);
                    }
                    color: view.onSurfVar
                    font.family: Theme.monoFamily
                    font.pixelSize: 13 * view.s
                }
                Rectangle {
                    visible: view.ctl.notifTotal > 0
                    implicitWidth: clearTxt.implicitWidth + 18 * view.s
                    implicitHeight: clearTxt.implicitHeight + 8 * view.s
                    radius: height / 2
                    color: clearMouse.containsMouse ? view.tileHigh : "transparent"
                    border.width: 1
                    border.color: Theme.withAlpha(view.onSurf, 0.15)
                    Text {
                        id: clearTxt
                        anchors.centerIn: parent
                        text: Theme.t("lock.clear_all", "Limpar tudo")
                        color: view.onSurfVar
                        font.family: Theme.fontFamily
                        font.pixelSize: 11 * view.s
                    }
                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.ctl.clearAll()
                    }
                }
            }

            // aviso de que uma notificação vai abrir ao desbloquear
            Label {
                Layout.fillWidth: true
                visible: !!view.ctl.pendingOpen
                text: Theme.t("lock.will_open", "Abre ao desbloquear: %1").arg(view.ctl.pendingOpen ? (view.ctl.pendingOpen.s || view.ctl.pendingOpen.app) : "")
                color: view.sec
                px: 12 * view.s
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: view.ctl.notifTotal === 0
                Glyph {
                    anchors.centerIn: parent
                    text: Theme.icons.bellOff
                    px: 48 * view.s
                    color: Theme.withAlpha(view.onSurf, 0.25)
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: view.ctl.notifTotal > 0
                clip: true
                spacing: 8 * view.s
                boundsBehavior: Flickable.StopAtBounds
                model: view.ctl.notifGroups

                delegate: Rectangle {
                    id: grp
                    required property var modelData
                    required property int index
                    readonly property bool expanded: view.ctl.expandedApp === modelData.app
                    readonly property var visibleItems: expanded ? modelData.items : modelData.items.slice(0, 3)
                    width: ListView.view.width
                    implicitHeight: grow.implicitHeight + 20 * view.s
                    height: implicitHeight
                    radius: 18 * view.s
                    color: grpHover.hovered ? Theme.withAlpha(view.tileHigh, 0.85) : Theme.withAlpha(view.tileHigh, 0.6)
                    opacity: 0
                    Component.onCompleted: appear.start()
                    NumberAnimation { id: appear; target: grp; property: "opacity"; to: 1; duration: 300; easing.type: Easing.OutCubic }
                    Behavior on height { DefSpatial {} }
                    HoverHandler { id: grpHover }

                    RowLayout {
                        id: grow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10 * view.s
                        spacing: 10 * view.s

                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 38 * view.s
                            implicitHeight: implicitWidth
                            radius: width / 2
                            color: Theme.mix(Theme.background, view.pri, 0.25)
                            clip: true
                            Text {
                                anchors.centerIn: parent
                                visible: appIcon.status !== Image.Ready
                                text: (grp.modelData.app || "?").charAt(0).toUpperCase()
                                color: view.pri
                                font.family: Theme.fontFamily
                                font.pixelSize: 16 * view.s
                                font.bold: true
                            }
                            Image {
                                id: appIcon
                                anchors.fill: parent
                                source: view.ctl.iconSource(grp.modelData.icon)
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(76, 76)
                                asynchronous: true
                                visible: status === Image.Ready
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2 * view.s

                            // cabeçalho: clique expande/recolhe o grupo
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: headRow.implicitHeight
                                RowLayout {
                                    id: headRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    Label {
                                        Layout.fillWidth: true
                                        text: grp.modelData.app || "?"
                                        px: 14 * view.s
                                        font.weight: Font.Medium
                                    }
                                    Rectangle {
                                        implicitWidth: cntRow.implicitWidth + 12 * view.s
                                        implicitHeight: cntRow.implicitHeight + 4 * view.s
                                        radius: height / 2
                                        color: view.tileHigh
                                        visible: grp.modelData.count > 1
                                        Row {
                                            id: cntRow
                                            anchors.centerIn: parent
                                            spacing: 2
                                            Text {
                                                text: grp.modelData.count
                                                color: view.onSurf
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11 * view.s
                                            }
                                            Text {
                                                visible: grp.modelData.count > 3
                                                text: grp.expanded ? "\u{F0143}" : "\u{F0140}"
                                                color: view.onSurf
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 12 * view.s
                                            }
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: grp.modelData.count > 3
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: view.ctl.toggleGroup(grp.modelData.app)
                                }
                            }

                            Repeater {
                                model: grp.visibleItems
                                Rectangle {
                                    id: nItem
                                    required property var modelData
                                    readonly property bool pending: !!view.ctl.pendingOpen && view.ctl.pendingOpen.id === modelData.id
                                    Layout.fillWidth: true
                                    implicitHeight: nRow.implicitHeight + 2 * view.s
                                    radius: 8 * view.s
                                    color: pending ? Theme.withAlpha(view.sec, 0.22) : nHover.hovered ? Theme.withAlpha(view.onSurf, 0.06) : "transparent"
                                    HoverHandler { id: nHover }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: view.ctl.markOpen(Object.assign({ app: grp.modelData.app }, nItem.modelData))
                                    }
                                    RowLayout {
                                        id: nRow
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 4 * view.s
                                        spacing: 4 * view.s
                                        Text {
                                            Layout.fillWidth: true
                                            textFormat: Text.StyledText
                                            text: "<b>" + view.ctl.esc(nItem.modelData.s) + "</b> <font color='" + view.outline + "'>" + view.ctl.esc(nItem.modelData.b) + "</font>"
                                            color: view.onSurf
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13 * view.s
                                            elide: Text.ElideRight
                                            wrapMode: grp.expanded ? Text.Wrap : Text.NoWrap
                                            maximumLineCount: grp.expanded ? 3 : 1
                                        }
                                        // dispensar
                                        Rectangle {
                                            implicitWidth: 22 * view.s
                                            implicitHeight: implicitWidth
                                            radius: width / 2
                                            opacity: nHover.hovered ? 1 : 0
                                            color: xMouse.containsMouse ? view.tileHigh : "transparent"
                                            Behavior on opacity { DefEffects {} }
                                            Glyph { anchors.centerIn: parent; text: Theme.icons.close; px: 13 * view.s }
                                            MouseArea {
                                                id: xMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: view.ctl.dismiss(nItem.modelData)
                                            }
                                        }
                                    }
                                }
                            }
                            Label {
                                visible: grp.modelData.count > 3
                                text: grp.expanded ? Theme.t("lock.show_less", "Mostrar menos") : Theme.t("lock.show_more", "Mostrar mais %1").arg(grp.modelData.count - 3)
                                color: view.sec
                                px: 12 * view.s
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: view.ctl.toggleGroup(grp.modelData.app)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ======================================================================
    // Controles rápidos: volume, brilho, Wi-Fi, Bluetooth, Não perturbe
    // ======================================================================
    component QuickTile: Tile {
        id: qt
        radius: 20 * view.s
        implicitHeight: qcol.implicitHeight + 28 * view.s

        ColumnLayout {
            id: qcol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 14 * view.s
            spacing: 10 * view.s

            MiniSlider {
                Layout.fillWidth: true
                icon: !view.ctl.sink || !view.ctl.sink.audio || view.ctl.sink.audio.muted ? Theme.icons.volOff : Theme.icons.volHigh
                value: view.ctl.sink && view.ctl.sink.audio ? view.ctl.sink.audio.volume : 0
                dimmed: view.ctl.sink && view.ctl.sink.audio ? view.ctl.sink.audio.muted : true
                onMoved: v => view.ctl.setVolume(v)
                onIconClicked: view.ctl.toggleMute()
            }
            MiniSlider {
                Layout.fillWidth: true
                visible: view.ctl.brightness >= 0
                icon: Theme.icons.brightness
                value: Math.max(0, view.ctl.brightness)
                onMoved: v => view.ctl.setBrightness(v)
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8 * view.s
                QuickToggle {
                    visible: view.ctl.hasWifi
                    icon: view.ctl.wifiOn ? Theme.icons.wifi4 : Theme.icons.wifiOff
                    label: "Wi-Fi"
                    on: view.ctl.wifiOn
                    onClicked: view.ctl.toggleWifi()
                }
                QuickToggle {
                    visible: !!view.ctl.btAdapter
                    icon: view.ctl.btAdapter && view.ctl.btAdapter.enabled ? Theme.icons.bt : Theme.icons.btOff
                    label: "Bluetooth"
                    on: !!view.ctl.btAdapter && view.ctl.btAdapter.enabled
                    onClicked: view.ctl.toggleBluetooth()
                }
                QuickToggle {
                    icon: NotifService.dnd ? Theme.icons.bellOff : Theme.icons.bell
                    label: Theme.t("lock.dnd", "Não perturbe")
                    on: NotifService.dnd
                    onClicked: NotifService.toggleDnd()
                }
            }
        }
    }

    component QuickToggle: Rectangle {
        id: qtg
        property string icon
        property string label
        property bool on: false
        signal clicked
        Layout.fillWidth: true
        implicitHeight: 36 * view.s
        radius: qtgMouse.pressed ? 10 * view.s : height / 2
        color: on ? Theme.withAlpha(view.pri, 0.9) : qtgMouse.containsMouse ? view.tileHigh : Theme.withAlpha(view.tileHigh, 0.6)
        Behavior on radius { FastSpatial {} }
        Behavior on color { ColorAnimation { duration: 150 } }
        Row {
            anchors.centerIn: parent
            spacing: 6 * view.s
            Glyph { text: qtg.icon; px: 16 * view.s; color: qtg.on ? Theme.background : view.onSurf }
            Label {
                text: qtg.label
                px: 12 * view.s
                color: qtg.on ? Theme.background : view.onSurf
                width: Math.min(implicitWidth, qtg.width - 40 * view.s)
            }
        }
        MouseArea {
            id: qtgMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: qtg.clicked()
        }
    }

    // Slider compacto: arrastar, clicar ou rolar (5% por clique da roda,
    // somando a partir do valor local para não "voltar" enquanto o sistema
    // aplica a mudança).
    component MiniSlider: RowLayout {
        id: ms
        property string icon
        property real value: 0
        property bool dimmed: false
        property real localValue: -1
        property real acc: 0
        readonly property real shown: localValue >= 0 ? localValue : Math.max(0, Math.min(1, value))
        signal moved(real v)
        signal iconClicked
        spacing: 10 * view.s

        function setLocal(v) {
            localValue = Math.max(0, Math.min(1, v));
            settle.restart();
            moved(localValue);
        }
        Timer { id: settle; interval: 800; onTriggered: if (!msArea.pressed) { ms.localValue = -1; ms.acc = 0; } }

        Glyph {
            text: ms.icon
            px: 18 * view.s
            color: ms.dimmed ? view.outline : view.pri
            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: ms.iconClicked() }
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: 18 * view.s
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 8 * view.s
                radius: height / 2
                color: Theme.withAlpha(view.pri, 0.18)
                Rectangle {
                    width: Math.max(height, parent.width * ms.shown)
                    height: parent.height
                    radius: height / 2
                    color: ms.dimmed ? view.outline : view.pri
                }
            }
            MouseArea {
                id: msArea
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                onPressed: mouse => ms.setLocal((mouse.x - 6) / (width - 12))
                onPositionChanged: mouse => { if (pressed) ms.setLocal((mouse.x - 6) / (width - 12)); }
                onReleased: settle.restart()
                onWheel: wheel => {
                    ms.acc += wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                    const steps = Math.trunc(ms.acc / 120);
                    if (steps === 0) return;
                    ms.acc -= steps * 120;
                    ms.setLocal(Math.round((ms.shown + steps * 0.05) * 20) / 20);
                }
            }
        }
        Label {
            Layout.preferredWidth: 34 * view.s
            horizontalAlignment: Text.AlignRight
            text: Math.round(ms.shown * 100) + "%"
            px: 11 * view.s
            color: view.onSurfVar
        }
    }

    // ======================================================================
    // Lembrete embaixo da senha (clique para editar; Enter salva, Esc cancela)
    // ======================================================================
    component NoteLabel: Item {
        id: nl
        property bool editing: false
        onEditingChanged: view.noteEditing = editing
        implicitHeight: editing ? 34 * view.s : noteText.implicitHeight

        Label {
            id: noteText
            anchors.left: parent.left
            anchors.right: parent.right
            visible: !nl.editing
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            text: view.ctl.note || Theme.t("lock.note_hint", "+ adicionar um lembrete")
            color: view.ctl.note ? view.onSurfVar : Theme.withAlpha(view.onSurf, noteMouse.containsMouse ? 0.5 : 0.22)
            font.italic: !!view.ctl.note
            px: 13 * view.s
            MouseArea {
                id: noteMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !view.greeter
                onClicked: {
                    nl.editing = true;
                    noteInput.text = view.ctl.note;
                    noteInput.forceActiveFocus();
                }
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 40 * view.s
            anchors.rightMargin: 40 * view.s
            visible: nl.editing
            height: parent.height
            radius: height / 2
            color: view.tileColor
            TextInput {
                id: noteInput
                anchors.fill: parent
                anchors.leftMargin: 14 * view.s
                anchors.rightMargin: 14 * view.s
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                color: view.onSurf
                font.family: Theme.fontFamily
                font.pixelSize: 13 * view.s
                maximumLength: 140
                clip: true
                function finish(save) {
                    if (!nl.editing) return;
                    if (save) view.ctl.saveNote(text);
                    nl.editing = false;
                    passwordBox.forceActiveFocus();
                }
                Keys.onReturnPressed: finish(true)
                Keys.onEnterPressed: finish(true)
                Keys.onEscapePressed: finish(false)
                onActiveFocusChanged: if (!activeFocus) finish(true)
            }
        }
    }

    // ======================================================================
    // Seletor de sessão (só no greeter)
    // ======================================================================
    component SessionTile: Rectangle {
        id: st
        color: view.tileColor
        radius: 14 * view.s
        bottomRightRadius: 28 * view.s
        clip: true

        function iconFor(name) {
            const n = (name || "").toLowerCase();
            if (n.includes("plasma") || n.includes("kde")) return "\u{F0C9E}";
            if (n.includes("gamescope") || n.includes("steam")) return Theme.icons.gamepad;
            if (n.includes("gnome")) return "\u{F02A0}";
            return Theme.icons.monitor;
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16 * view.s
            spacing: 8 * view.s

            Text {
                text: Theme.t("greeter.session", "Sessão")
                color: view.onSurfVar
                font.family: Theme.monoFamily
                font.pixelSize: 13 * view.s
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6 * view.s
                boundsBehavior: Flickable.StopAtBounds
                model: view.ctl.sessions

                delegate: Rectangle {
                    id: sess
                    required property var modelData
                    required property int index
                    readonly property bool selected: view.ctl.sessionIndex === index
                    width: ListView.view.width
                    implicitHeight: 48 * view.s
                    radius: sessMouse.pressed ? 12 * view.s : height / 2
                    color: selected ? Theme.withAlpha(view.pri, 0.9) : sessMouse.containsMouse ? view.tileHigh : Theme.withAlpha(view.tileHigh, 0.5)
                    Behavior on radius { FastSpatial {} }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16 * view.s
                        anchors.rightMargin: 16 * view.s
                        spacing: 12 * view.s
                        Glyph {
                            text: st.iconFor(sess.modelData.name + " " + sess.modelData.key)
                            px: 20 * view.s
                            color: sess.selected ? Theme.background : view.onSurf
                        }
                        Label {
                            Layout.fillWidth: true
                            text: sess.modelData.name
                            px: 14 * view.s
                            font.weight: sess.selected ? Font.DemiBold : Font.Normal
                            color: sess.selected ? Theme.background : view.onSurf
                        }
                        Glyph {
                            visible: sess.selected
                            text: Theme.icons.check
                            px: 18 * view.s
                            color: Theme.background
                        }
                    }
                    MouseArea {
                        id: sessMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.ctl.selectSession(sess.index)
                    }
                }
            }
        }
    }
}
