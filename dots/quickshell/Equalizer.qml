import QtQuick
import QtQuick.Layouts
import "."

// Equalizador de 10 bandas: sliders verticais com uma onda luminosa passando
// pelos knobs, e os presets embaixo. `compact` é a versão estreita usada no
// painel lateral do layout "letras" (presets em duas linhas, textos menores).
Item {
    id: root

    property bool compact: false
    readonly property color accent: Theme.accent2

    // Ganhos exibidos. Ao trocar de preset eles deslizam do valor antigo para
    // o novo (knobs e onda juntos); durante o arrasto seguem o mouse direto.
    property var fromGains: EqService.gains
    property var shown: EqService.gains
    property real mix: 1
    function blend() {
        const out = [];
        for (let i = 0; i < EqService.gains.length; i++) {
            const a = root.fromGains[i] || 0;
            out.push(a + ((EqService.gains[i] || 0) - a) * root.mix);
        }
        root.shown = out;
    }
    onMixChanged: blend()
    NumberAnimation {
        id: mixAnim
        target: root
        property: "mix"
        from: 0
        to: 1
        duration: 320
        easing.type: Easing.OutCubic
    }
    Connections {
        target: EqService
        function onGainsChanged() {
            mixAnim.stop();
            if (EqService.dragging) {
                root.fromGains = EqService.gains;
                root.mix = 1;
                root.blend();
            } else {
                root.fromGains = root.shown;
                mixAnim.start();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.compact ? 8 : 10

        // ---------- cabeçalho ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: Theme.icons.equalizer
                font.family: Theme.iconFontFamily
                font.pixelSize: 14
                color: root.accent
            }
            Text {
                text: Theme.t("eq.title", "Equalizador")
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Theme.foreground
            }
            Item { Layout.fillWidth: true }

            Rectangle {
                visible: EqService.enabled
                Layout.preferredHeight: 20
                Layout.preferredWidth: presetName.implicitWidth + 16
                radius: 10
                color: Theme.withAlpha(root.accent, 0.18)
                Text {
                    id: presetName
                    anchors.centerIn: parent
                    text: EqService.presetLabel(EqService.preset)
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: root.accent
                }
            }

            // Liga/desliga. Desligado, o filtro sai do caminho do áudio de
            // vez (o processo é encerrado), não só zera os ganhos.
            Rectangle {
                id: eqSwitch
                Layout.preferredWidth: 34
                Layout.preferredHeight: 18
                radius: 9
                color: EqService.enabled ? root.accent : Theme.withAlpha(Theme.subtext, 0.3)
                Behavior on color { ColorAnimation { duration: 140 } }
                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    y: 2
                    x: EqService.enabled ? parent.width - width - 2 : 2
                    color: Theme.background
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: EqService.setEnabled(!EqService.enabled)
                }
            }
        }

        // ---------- sliders + onda ----------
        Item {
            id: bandsArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 90
            opacity: EqService.enabled ? 1 : 0.45
            Behavior on opacity { NumberAnimation { duration: 160 } }

            readonly property int count: EqService.bands.length
            readonly property real labelH: 16
            readonly property real trackTop: 8
            readonly property real trackH: height - labelH - trackTop - 8
            readonly property real colW: width / count

            function knobY(db) {
                return trackTop + (1 - (db + EqService.limit) / (2 * EqService.limit)) * trackH;
            }
            function colX(i) {
                return colW * i + colW / 2;
            }

            // Linha do 0 dB, para dar referência de onde é "neutro".
            Rectangle {
                x: 0
                width: parent.width
                height: 1
                y: bandsArea.knobY(0)
                color: Theme.withAlpha(Theme.subtext, 0.15)
            }

            // A onda: curva suave passando pelos knobs, desenhada algumas vezes
            // com espessura e transparência diferentes para parecer brilho.
            Canvas {
                id: wave
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const n = bandsArea.count;
                    const pts = [];
                    for (let i = 0; i < n; i++)
                        pts.push([bandsArea.colX(i), bandsArea.knobY(root.shown[i] || 0)]);
                    // Estende para as bordas para a onda não começar cortada.
                    pts.unshift([0, pts[0][1]]);
                    pts.push([width, pts[pts.length - 1][1]]);

                    function trace() {
                        ctx.beginPath();
                        ctx.moveTo(pts[0][0], pts[0][1]);
                        for (let i = 0; i < pts.length - 1; i++) {
                            const mx = (pts[i][0] + pts[i + 1][0]) / 2;
                            ctx.bezierCurveTo(mx, pts[i][1], mx, pts[i + 1][1], pts[i + 1][0], pts[i + 1][1]);
                        }
                    }

                    // Preenchimento até a base, bem sutil.
                    trace();
                    ctx.lineTo(width, height - bandsArea.labelH);
                    ctx.lineTo(0, height - bandsArea.labelH);
                    ctx.closePath();
                    const grad = ctx.createLinearGradient(0, 0, 0, height);
                    grad.addColorStop(0, Theme.withAlpha(root.accent, 0.22));
                    grad.addColorStop(1, Theme.withAlpha(root.accent, 0.0));
                    ctx.fillStyle = grad;
                    ctx.fill();

                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    const layers = [[14, 0.06], [8, 0.12], [4, 0.25], [1.6, 0.9]];
                    for (const l of layers) {
                        trace();
                        ctx.lineWidth = l[0];
                        ctx.strokeStyle = Theme.withAlpha(root.accent, l[1]);
                        ctx.stroke();
                    }
                }
                Connections {
                    target: root
                    function onShownChanged() { wave.requestPaint(); }
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }

            Repeater {
                model: bandsArea.count
                delegate: Item {
                    id: band
                    required property int index
                    readonly property real db: root.shown[index] || 0
                    x: bandsArea.colW * index
                    width: bandsArea.colW
                    height: bandsArea.height

                    Rectangle {
                        id: track
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: bandsArea.trackTop
                        width: root.compact ? 4 : 5
                        height: bandsArea.trackH
                        radius: width / 2
                        color: Theme.withAlpha(Theme.subtext, 0.18)

                        // Preenchimento do 0 dB até o knob: para cima é
                        // reforço, para baixo é corte.
                        Rectangle {
                            width: parent.width
                            radius: width / 2
                            readonly property real zeroY: bandsArea.knobY(0) - bandsArea.trackTop
                            readonly property real kY: bandsArea.knobY(band.db) - bandsArea.trackTop
                            y: Math.min(zeroY, kY)
                            height: Math.abs(zeroY - kY)
                            color: Theme.withAlpha(root.accent, 0.8)
                        }
                    }

                    Rectangle {
                        id: knob
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.compact ? 14 : 18
                        height: root.compact ? 8 : 10
                        radius: height / 2
                        y: bandsArea.knobY(band.db) - height / 2
                        color: Theme.foreground
                        border.width: 2
                        border.color: root.accent
                        scale: bandMouse.pressed || bandMouse.containsMouse ? 1.2 : 1
                        Behavior on scale { NumberAnimation { duration: 90 } }
                    }

                    // Valor em dB enquanto arrasta.
                    Rectangle {
                        visible: bandMouse.pressed
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: knob.y - height - 6
                        width: dbText.implicitWidth + 10
                        height: 16
                        radius: 8
                        color: root.accent
                        Text {
                            id: dbText
                            anchors.centerIn: parent
                            text: (band.db > 0 ? "+" : "") + band.db.toFixed(1)
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: Theme.background
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        text: EqService.bandLabel(band.index)
                        font.family: Theme.fontFamily
                        font.pixelSize: root.compact ? 9 : 10
                        color: Theme.subtext
                    }

                    MouseArea {
                        id: bandMouse
                        anchors.fill: parent
                        anchors.bottomMargin: bandsArea.labelH
                        hoverEnabled: true
                        cursorShape: Qt.SizeVerCursor
                        preventStealing: true

                        function dbAt(py) {
                            const t = (py - bandsArea.trackTop) / bandsArea.trackH;
                            return (1 - Math.max(0, Math.min(1, t))) * 2 * EqService.limit - EqService.limit;
                        }
                        onPressed: mouse => {
                            EqService.dragging = true;
                            EqService.setBand(band.index, dbAt(mouse.y));
                        }
                        onPositionChanged: mouse => {
                            if (pressed)
                                EqService.setBand(band.index, dbAt(mouse.y));
                        }
                        onReleased: {
                            EqService.dragging = false;
                            EqService.flush();
                        }
                        onCanceled: EqService.dragging = false
                        // Duplo clique zera a banda.
                        onDoubleClicked: {
                            EqService.setBand(band.index, 0);
                            EqService.flush();
                        }
                        onWheel: wheel => {
                            EqService.dragging = true;
                            EqService.setBand(band.index, (EqService.gains[band.index] || 0) + (wheel.angleDelta.y > 0 ? 0.5 : -0.5));
                            EqService.dragging = false;
                        }
                    }
                }
            }
        }

        // ---------- presets ----------
        GridLayout {
            Layout.fillWidth: true
            columns: root.compact ? 4 : 8
            rowSpacing: 6
            columnSpacing: 6

            Repeater {
                model: EqService.presets
                delegate: Rectangle {
                    id: presetBtn
                    required property string modelData
                    readonly property bool active: EqService.enabled && EqService.preset === modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.compact ? 24 : 28
                    radius: height / 2
                    color: active ? root.accent
                                  : (presetMouse.containsMouse ? Theme.withAlpha(Theme.subtext, 0.18)
                                                               : Theme.withAlpha(Theme.subtext, 0.08))
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: EqService.presetLabel(presetBtn.modelData)
                        font.family: Theme.fontFamily
                        font.pixelSize: root.compact ? 10 : 11
                        font.weight: presetBtn.active ? Font.DemiBold : Font.Normal
                        color: presetBtn.active ? Theme.background : Theme.foreground
                    }
                    MouseArea {
                        id: presetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: EqService.applyPreset(presetBtn.modelData)
                    }
                }
            }
        }
    }
}
