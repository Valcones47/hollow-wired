import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// Editor das animações do Hyprland (rice-anim): presets prontos e, por grupo
// (abrir janela, fechar, workspaces...), a curva de Bézier arrastável, a
// velocidade e o estilo, com uma prévia que usa a mesma curva.
ColumnLayout {
    id: root
    spacing: 12

    signal toast(string msg)

    property string preset: "smooth"
    property var groups: ({})
    property var order: ["open", "close", "move", "fade", "workspaces", "special"]
    property var styles: ({})
    property var presetCurves: ({})
    property string group: "open"

    // Curva e velocidade em edição (seguem o arrasto antes de salvar).
    property var curve: [0.25, 0.1, 0.25, 1]
    property real speed: 4
    property string style: ""

    readonly property var presetList: [
        { id: "smooth", name: Theme.t("anim.smooth", "Suave"), desc: Theme.t("anim.smooth_desc", "Fluido e equilibrado") },
        { id: "bouncy", name: Theme.t("anim.bouncy", "Elástico"), desc: Theme.t("anim.bouncy_desc", "Passa do ponto e volta") },
        { id: "snappy", name: Theme.t("anim.snappy", "Rápido"), desc: Theme.t("anim.snappy_desc", "Imediato e seco") },
        { id: "wind", name: Theme.t("anim.wind", "Vento"), desc: Theme.t("anim.wind_desc", "Desliza, estilo end-4") },
        { id: "material", name: "Material", desc: Theme.t("anim.material_desc", "Curvas do Android") },
        { id: "custom", name: Theme.t("anim.custom", "Personalizado"), desc: Theme.t("anim.custom_desc", "Ajuste abaixo") }
    ]

    function groupLabel(id) {
        const n = {
            open: Theme.t("anim.g_open", "Abrir janela"),
            close: Theme.t("anim.g_close", "Fechar janela"),
            move: Theme.t("anim.g_move", "Mover janela"),
            fade: Theme.t("anim.g_fade", "Esmaecer"),
            workspaces: Theme.t("anim.g_workspaces", "Workspaces"),
            special: Theme.t("anim.g_special", "Área especial")
        };
        return n[id] || id;
    }

    function styleLabel(s) {
        if (s === "") return Theme.t("anim.style_default", "Padrão");
        const n = {
            "popin 85%": Theme.t("anim.st_popin", "Surgir"),
            "popin 70%": Theme.t("anim.st_popin_big", "Surgir forte"),
            "slide": Theme.t("anim.st_slide", "Deslizar"),
            "gnomed": "GNOME",
            "slidefade 15%": Theme.t("anim.st_slidefade", "Deslizar + esmaecer"),
            "slidevert": Theme.t("anim.st_slidevert", "Deslizar vertical"),
            "fade": Theme.t("anim.st_fade", "Esmaecer"),
            "slidefadevert 15%": Theme.t("anim.st_slidefadevert", "Vertical + esmaecer")
        };
        return n[s] || s;
    }

    function loadGroup() {
        const g = root.groups[root.group];
        if (!g)
            return;
        root.curve = g.curve.slice();
        root.speed = g.speed;
        root.style = g.style || "";
        graph.requestPaint();
        preview.restart();
    }

    function parse(text) {
        try {
            const d = JSON.parse(text);
            root.preset = d.preset;
            root.groups = d.groups;
            root.order = d.order;
            root.styles = d.styles;
            const pc = {};
            for (const k in d.presets)
                pc[k] = d.presets[k].open.curve;
            root.presetCurves = pc;
            if (!graph.dragging)
                loadGroup();
        } catch (e) {}
    }

    function run(args) {
        proc.command = ["rice-anim"].concat(args);
        proc.running = false;
        proc.running = true;
    }

    function fmt(v) { return (Math.round(v * 100) / 100).toString(); }

    Process {
        id: proc
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    Component.onCompleted: run(["dump"])
    onGroupChanged: loadGroup()

    // ---------- presets ----------
    GridLayout {
        Layout.fillWidth: true
        columns: 6
        columnSpacing: 8

        Repeater {
            model: root.presetList
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool active: root.preset === modelData.id
                Layout.fillWidth: true
                implicitHeight: 92
                radius: 10
                color: active ? Theme.withAlpha(Theme.primary, 0.22) : (cardMouse.containsMouse ? Theme.tileHigh : Theme.tile)
                border.width: active ? 1.5 : 0
                border.color: Theme.primary

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2

                    // Miniatura da curva de abertura de janela do preset.
                    Canvas {
                        id: thumb
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        readonly property var c: card.modelData.id === "custom"
                            ? (root.groups.open ? root.groups.open.curve : null)
                            : root.presetCurves[card.modelData.id]
                        onCChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            if (!c) return;
                            const w = width, h = height;
                            const Y = y => h - 4 - (y + 0.3) / 1.9 * (h - 8);
                            ctx.strokeStyle = card.active ? Theme.primary : Theme.subtext;
                            ctx.lineWidth = 2;
                            ctx.lineCap = "round";
                            ctx.beginPath();
                            ctx.moveTo(4, Y(0));
                            ctx.bezierCurveTo(4 + c[0] * (w - 8), Y(c[1]), 4 + c[2] * (w - 8), Y(c[3]), w - 4, Y(1));
                            ctx.stroke();
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: card.modelData.name
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: card.active ? Font.DemiBold : Font.Normal
                        color: Theme.textColor
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: card.modelData.desc
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        color: card.active ? Theme.primary : Theme.subtext
                    }
                }
                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.preset = card.modelData.id;
                        root.run(["preset", card.modelData.id]);
                        root.toast(Theme.t("toast.anim_style", "Estilo de animação: ") + card.modelData.name);
                    }
                }
            }
        }
    }

    // ---------- grupos ----------
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: root.order
            delegate: Rectangle {
                id: gchip
                required property string modelData
                readonly property bool active: root.group === modelData
                width: gLabel.implicitWidth + 22
                height: 28
                radius: 14
                color: active ? Theme.primary : (gMouse.containsMouse ? Theme.tileHigh : Theme.tile)
                Text {
                    id: gLabel
                    anchors.centerIn: parent
                    text: root.groupLabel(gchip.modelData)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: gchip.active ? Theme.background : Theme.textColor
                }
                MouseArea {
                    id: gMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.group = gchip.modelData
                }
            }
        }
    }

    // ---------- editor ----------
    RowLayout {
        Layout.fillWidth: true
        spacing: 16

        // Gráfico da curva: arraste os dois pontos. O eixo horizontal é o
        // tempo, o vertical é o quanto a animação andou — passar de cima é o
        // "elástico", ficar abaixo de zero é o recuo antes de sair.
        Rectangle {
            Layout.preferredWidth: 230
            Layout.preferredHeight: 230
            radius: 12
            color: Theme.tile

            Canvas {
                id: graph
                anchors.fill: parent
                anchors.margins: 14
                property bool dragging: false
                readonly property real yMin: -0.5
                readonly property real yMax: 1.5
                function px(x) { return x * width; }
                function py(y) { return (yMax - y) / (yMax - yMin) * height; }
                function vx(px) { return Math.max(0, Math.min(1, px / width)); }
                function vy(py) { return Math.max(yMin, Math.min(yMax, yMax - py / height * (yMax - yMin))); }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const c = root.curve;
                    // grade: 0 e 1
                    ctx.strokeStyle = Theme.withAlpha(Theme.subtext, 0.25);
                    ctx.lineWidth = 1;
                    ctx.setLineDash([4, 4]);
                    for (const yv of [0, 1]) {
                        ctx.beginPath();
                        ctx.moveTo(0, py(yv));
                        ctx.lineTo(width, py(yv));
                        ctx.stroke();
                    }
                    ctx.setLineDash([]);
                    // alavancas
                    ctx.strokeStyle = Theme.withAlpha(Theme.subtext, 0.6);
                    ctx.beginPath();
                    ctx.moveTo(px(0), py(0));
                    ctx.lineTo(px(c[0]), py(c[1]));
                    ctx.moveTo(px(1), py(1));
                    ctx.lineTo(px(c[2]), py(c[3]));
                    ctx.stroke();
                    // curva
                    ctx.strokeStyle = Theme.primary;
                    ctx.lineWidth = 3;
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.moveTo(px(0), py(0));
                    ctx.bezierCurveTo(px(c[0]), py(c[1]), px(c[2]), py(c[3]), px(1), py(1));
                    ctx.stroke();
                }

                Repeater {
                    model: 2
                    delegate: Rectangle {
                        id: handle
                        required property int index
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.background
                        border.width: 3
                        border.color: Theme.primary
                        scale: hMouse.pressed || hMouse.containsMouse ? 1.25 : 1
                        x: graph.px(root.curve[index * 2]) - width / 2
                        y: graph.py(root.curve[index * 2 + 1]) - height / 2
                        Behavior on scale { NumberAnimation { duration: 90 } }

                        MouseArea {
                            id: hMouse
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.SizeAllCursor
                            preventStealing: true
                            onPressed: graph.dragging = true
                            onPositionChanged: mouse => {
                                if (!pressed) return;
                                const p = mapToItem(graph, mouse.x, mouse.y);
                                const c = root.curve.slice();
                                c[handle.index * 2] = Math.round(graph.vx(p.x) * 100) / 100;
                                c[handle.index * 2 + 1] = Math.round(graph.vy(p.y) * 100) / 100;
                                root.curve = c;
                                graph.requestPaint();
                            }
                            onReleased: {
                                graph.dragging = false;
                                const c = root.curve;
                                root.run(["set", root.group, "curve", String(c[0]), String(c[1]), String(c[2]), String(c[3])]);
                                preview.restart();
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 10

            // Prévia: um bloco que anda e uma "janela" que surge, os dois com a
            // curva e a duração de verdade (velocidade × 100 ms, como no Hyprland).
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 86
                radius: 12
                color: Theme.tile
                clip: true

                Item {
                    id: lane
                    anchors.left: parent.left
                    anchors.right: winBox.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 16
                    height: 28
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 2
                        color: Theme.withAlpha(Theme.subtext, 0.25)
                    }
                    Rectangle {
                        id: dot
                        width: 28
                        height: 28
                        radius: 8
                        color: Theme.primary
                        property real t: 0
                        x: t * (lane.width - width)
                    }
                }

                Rectangle {
                    id: winBox
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    width: 70
                    height: 52
                    radius: 8
                    color: Theme.withAlpha(Theme.primary, 0.25)
                    border.width: 1
                    border.color: Theme.primary
                    property real t: 0
                    scale: 0.55 + 0.45 * t
                    opacity: Math.max(0, Math.min(1, t))
                }

                SequentialAnimation {
                    id: preview
                    loops: Animation.Infinite
                    running: root.visible
                    ParallelAnimation {
                        NumberAnimation {
                            target: dot; property: "t"; from: 0; to: 1
                            duration: root.speed * 100
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [root.curve[0], root.curve[1], root.curve[2], root.curve[3], 1, 1]
                        }
                        NumberAnimation {
                            target: winBox; property: "t"; from: 0; to: 1
                            duration: root.speed * 100
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [root.curve[0], root.curve[1], root.curve[2], root.curve[3], 1, 1]
                        }
                    }
                    PauseAnimation { duration: 900 }
                    ScriptAction { script: { dot.t = 0; winBox.t = 0; } }
                    PauseAnimation { duration: 300 }
                }
            }

            Text {
                text: "cubic-bezier(" + root.fmt(root.curve[0]) + ", " + root.fmt(root.curve[1]) + ", "
                      + root.fmt(root.curve[2]) + ", " + root.fmt(root.curve[3]) + ")"
                font.family: "monospace"
                font.pixelSize: 11
                color: Theme.subtext
            }

            // Velocidade: no Hyprland cada unidade vale 100 ms.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: Theme.t("anim.duration", "Duração")
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.textColor
                }
                Item {
                    id: speedTrack
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    readonly property real minV: 1
                    readonly property real maxV: 12
                    readonly property real frac: (root.speed - minV) / (maxV - minV)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Theme.withAlpha(Theme.subtext, 0.25)
                        Rectangle {
                            width: parent.width * speedTrack.frac
                            height: parent.height
                            radius: 2
                            color: Theme.primary
                        }
                    }
                    Rectangle {
                        width: 14
                        height: 14
                        radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        x: speedTrack.frac * (speedTrack.width - width)
                        color: Theme.primary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true
                        function setAt(px) {
                            const f = Math.max(0, Math.min(1, px / width));
                            root.speed = Math.round((speedTrack.minV + f * (speedTrack.maxV - speedTrack.minV)) * 2) / 2;
                        }
                        onPressed: mouse => setAt(mouse.x)
                        onPositionChanged: mouse => { if (pressed) setAt(mouse.x); }
                        onReleased: {
                            root.run(["set", root.group, "speed", String(root.speed)]);
                            preview.restart();
                        }
                    }
                }
                Text {
                    Layout.preferredWidth: 52
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.speed * 100) + " ms"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.subtext
                }
            }

            // Estilo (só nos grupos que têm).
            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: (root.styles[root.group] || []).length > 1
                Repeater {
                    model: root.styles[root.group] || []
                    delegate: Rectangle {
                        id: schip
                        required property string modelData
                        readonly property bool active: root.style === modelData
                        width: sLabel.implicitWidth + 20
                        height: 26
                        radius: 13
                        color: active ? Theme.withAlpha(Theme.primary, 0.25) : (sMouse.containsMouse ? Theme.tileHigh : Theme.tile)
                        border.width: active ? 1 : 0
                        border.color: Theme.primary
                        Text {
                            id: sLabel
                            anchors.centerIn: parent
                            text: root.styleLabel(schip.modelData)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textColor
                        }
                        MouseArea {
                            id: sMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.style = schip.modelData;
                                root.run(["set", root.group, "style", schip.modelData]);
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Theme.t("anim.hint", "Arraste os pontos da curva. Mexer em qualquer grupo passa o estilo para Personalizado, partindo do preset que estava ativo.")
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.subtext
            }
        }
    }
}
