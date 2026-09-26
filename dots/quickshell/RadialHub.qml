import QtQuick
import QtQuick.Layouts
import "."

// Cena radial das páginas de Wi-Fi e Bluetooth do painel de controle:
// o aparelho no centro, ações em volta ligadas por "raios" que tremem, e
// no modo órbita as redes/aparelhos girando devagar em volta do centro.
//
//   nodes:  [{ key, icon, label, danger? }]          ações em volta
//   orbit:  [{ key, icon, label, strong? }]          itens que orbitam
//   orbitMode: mostra a órbita no lugar das ações
// Passar o mouse num botão "enche" ele da esquerda para a direita (só visual;
// a ação é no clique).
Item {
    id: rh

    property string centerIcon: ""
    property string centerTitle: ""
    property string centerSub: ""
    property bool centerActive: true
    property var nodes: []
    property var orbit: []
    // Só troca o modelo da órbita quando o conteúdo muda de verdade:
    // reatribuir o array recria os itens e eles "pulam".
    property var shownOrbit: []
    onOrbitChanged: {
        const a = JSON.stringify(orbit), b = JSON.stringify(shownOrbit);
        if (a !== b) shownOrbit = orbit.slice();
    }
    property bool orbitMode: false
    property string orbitHint: ""

    signal nodeClicked(string key)
    signal orbitClicked(string key)
    signal centerClicked()

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real centerR: Math.min(width, height) * 0.2
    readonly property real rx: width * 0.36
    readonly property real ry: height * 0.36

    // Posição de cada ação: distribuídas na elipse, começando em cima à esquerda.
    function nodePos(i, n) {
        const a = (-125 + i * 360 / Math.max(1, n)) * Math.PI / 180;
        return { x: cx + rx * Math.cos(a), y: cy + ry * Math.sin(a) };
    }

    // Entrada: as ações saem do centro em sequência.
    property real intro: 0
    NumberAnimation on intro { id: introAnim; from: 0; to: 1; duration: Theme.ms(520); easing.type: Easing.OutCubic }
    onNodesChanged: if (!orbitMode) introAnim.restart()
    onOrbitModeChanged: introAnim.restart()

    // Giro lento da órbita e do anel.
    property real spin: 0
    NumberAnimation on spin { from: 0; to: 360; duration: 90000; loops: Animation.Infinite; running: rh.visible }

    // ---------- anéis ----------
    Repeater {
        model: 3
        delegate: Rectangle {
            required property int index
            readonly property real r: rh.centerR * (1.35 + index * 0.55)
            x: rh.cx - r; y: rh.cy - r
            width: r * 2; height: r * 2; radius: r
            color: "transparent"
            border.width: 1
            border.color: Theme.withAlpha(Theme.textColor, 0.06 - index * 0.015)
        }
    }
    // Arco girando em volta do centro.
    Canvas {
        id: arc
        readonly property real r: rh.centerR * 1.35
        x: rh.cx - r - 2; y: rh.cy - r - 2
        width: r * 2 + 4; height: r * 2 + 4
        rotation: rh.spin * 4
        onPaint: {
            const c = getContext("2d");
            c.reset();
            c.lineWidth = 2;
            c.lineCap = "round";
            c.strokeStyle = Theme.withAlpha(Theme.primary, 0.55);
            c.beginPath();
            c.arc(width / 2, height / 2, r, 0, Math.PI * 0.45);
            c.stroke();
            c.strokeStyle = Theme.withAlpha(Theme.primary, 0.25);
            c.beginPath();
            c.arc(width / 2, height / 2, r, Math.PI, Math.PI * 1.2);
            c.stroke();
        }
        Connections { target: Theme; function onPrimaryChanged() { arc.requestPaint(); } }
    }

    // ---------- raios ----------
    Canvas {
        id: bolts
        anchors.fill: parent
        visible: !rh.orbitMode
        opacity: rh.intro
        property int hot: -1          // ação com o mouse em cima: raio mais forte
        onPaint: {
            const c = getContext("2d");
            c.reset();
            const n = rh.nodes.length;
            for (let i = 0; i < n; i++) {
                const p = rh.nodePos(i, n);
                const dx = p.x - rh.cx, dy = p.y - rh.cy;
                const len = Math.sqrt(dx * dx + dy * dy);
                const ux = dx / len, uy = dy / len;
                const sx = rh.cx + ux * (rh.centerR + 6), sy = rh.cy + uy * (rh.centerR + 6);
                const ex = p.x - ux * 26, ey = p.y - uy * 18;
                const seg = 7;
                c.beginPath();
                c.moveTo(sx, sy);
                for (let k = 1; k < seg; k++) {
                    const t = k / seg;
                    const j = (Math.random() - 0.5) * (i === hot ? 14 : 8);
                    c.lineTo(sx + (ex - sx) * t - uy * j, sy + (ey - sy) * t + ux * j);
                }
                c.lineTo(ex, ey);
                c.lineWidth = i === hot ? 2 : 1.2;
                c.strokeStyle = Theme.withAlpha(i === hot ? Theme.primary : Theme.textColor, i === hot ? 0.9 : 0.35);
                c.stroke();
            }
        }
        Timer {
            interval: bolts.hot >= 0 ? 90 : 420
            running: rh.visible && !rh.orbitMode
            repeat: true
            onTriggered: bolts.requestPaint()
        }
    }

    // ---------- centro ----------
    Rectangle {
        id: center
        x: rh.cx - rh.centerR; y: rh.cy - rh.centerR
        width: rh.centerR * 2; height: width; radius: width / 2
        color: rh.centerActive ? Theme.withAlpha(Theme.primary, centerArea.containsMouse ? 1 : 0.88) : (centerArea.containsMouse ? Theme.tileHigh : Theme.tile)
        border.width: 6
        border.color: Theme.withAlpha(rh.centerActive ? Theme.primary : Theme.textColor, 0.18)
        scale: centerArea.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Theme.ms(100) } }
        Behavior on color { ColorAnimation { duration: Theme.ms(160) } }

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 24
            spacing: 2
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: rh.centerIcon
                font.family: Theme.iconFontFamily
                font.pixelSize: 26
                color: rh.centerActive ? Theme.background : Theme.textColor
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: rh.centerTitle
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: rh.centerActive ? Theme.background : Theme.textColor
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: text !== ""
                text: rh.centerSub
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: rh.centerActive ? Theme.withAlpha(Theme.background, 0.75) : Theme.subtext
            }
        }
        MouseArea {
            id: centerArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rh.centerClicked()
        }
    }

    // ---------- ações ----------
    Repeater {
        model: rh.orbitMode ? [] : rh.nodes
        delegate: Rectangle {
            id: chip
            required property var modelData
            required property int index
            readonly property var p: rh.nodePos(index, rh.nodes.length)
            // Cada ação aparece um pouco depois da anterior.
            readonly property real t: Math.max(0, Math.min(1, rh.intro * 1.6 - index * 0.12))
            width: chipRow.implicitWidth + 24
            height: 34
            radius: 10
            x: rh.cx + (p.x - rh.cx) * t - width / 2
            y: rh.cy + (p.y - rh.cy) * t - height / 2
            opacity: t
            scale: 0.8 + 0.2 * t
            color: Theme.tile
            border.width: 1
            border.color: Theme.withAlpha(chip.modelData.danger ? Theme.critical : Theme.outline, chipArea.containsMouse ? 0.6 : 0.25)
            clip: true

            // "Encher" ao passar o mouse.
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: parent.radius
                color: Theme.withAlpha(chip.modelData.danger ? Theme.critical : Theme.primary, 0.3)
                width: chipArea.containsMouse ? parent.width : 0
                Behavior on width {
                    NumberAnimation { duration: chipArea.containsMouse ? Theme.ms(650) : Theme.ms(180); easing.type: Easing.OutQuad }
                }
            }
            RowLayout {
                id: chipRow
                anchors.centerIn: parent
                spacing: 7
                Text {
                    text: chip.modelData.icon
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 14
                    color: chip.modelData.danger ? Theme.critical : Theme.primary
                }
                Text {
                    text: chip.modelData.label
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.textColor
                }
            }
            MouseArea {
                id: chipArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: bolts.hot = containsMouse ? chip.index : (bolts.hot === chip.index ? -1 : bolts.hot)
                onClicked: rh.nodeClicked(chip.modelData.key)
            }
        }
    }

    // ---------- órbita ----------
    Repeater {
        model: rh.orbitMode ? rh.shownOrbit : []
        delegate: Item {
            id: oi
            required property var modelData
            required property int index
            readonly property int n: rh.shownOrbit.length
            // Duas órbitas (interna e externa) para caber mais itens sem encostar.
            readonly property bool outer: n > 7 && index % 2 === 1
            readonly property real a: (index * 360 / Math.max(1, n) + rh.spin * (outer ? -1 : 1) - 90) * Math.PI / 180
            readonly property real orx: rh.rx * (outer ? 1.12 : 0.86)
            readonly property real ory: rh.ry * (outer ? 1.12 : 0.86)
            width: oRow.implicitWidth + 16
            height: 26
            x: rh.cx + orx * Math.cos(a) * rh.intro - width / 2
            y: rh.cy + ory * Math.sin(a) * rh.intro - height / 2
            opacity: rh.intro

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: oArea.containsMouse ? Theme.tileHigh : (oi.modelData.strong ? Theme.withAlpha(Theme.primary, 0.22) : "transparent")
                Behavior on color { ColorAnimation { duration: Theme.ms(120) } }
            }
            RowLayout {
                id: oRow
                anchors.centerIn: parent
                spacing: 5
                Text {
                    text: oi.modelData.icon
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 12
                    color: oi.modelData.strong ? Theme.primary : Theme.subtext
                }
                Text {
                    text: oi.modelData.label
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: oArea.containsMouse ? Theme.textColor : Theme.withAlpha(Theme.textColor, 0.85)
                    elide: Text.ElideRight
                    Layout.maximumWidth: 130
                }
            }
            MouseArea {
                id: oArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: rh.orbitClicked(oi.modelData.key)
            }
        }
    }

    Text {
        visible: rh.orbitMode && rh.orbitHint !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        text: rh.orbitHint
        font.family: Theme.fontFamily
        font.pixelSize: 10
        color: Theme.subtext
    }
}
