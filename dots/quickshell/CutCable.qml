pragma ComponentBehavior: Bound
import QtQuick
import "."

// Cabo cortado pendurado no cenário — fiação exposta, sem ligar em nada.
//
// Feito dos mesmos glifos da chuva (GlyphCable), para a tela inteira ser da
// mesma matéria: o que cai, o que liga no olho e o que está largado no canto
// são todos a mesma coisa. A única animação é a faísca esporádica da ponta.
Item {
    id: cable

    property real drop: 120
    property real sway: 30
    property color cableColor: Theme.withAlpha(Theme.primary, 0.5)
    property color sparkColor: "#ffd24a"
    property bool alive: true
    property real fontSize: 12

    implicitWidth: Math.abs(sway) + 40
    implicitHeight: drop + 26

    readonly property real startX: sway > 0 ? 16 : implicitWidth - 16
    readonly property real tipX: sway > 0 ? implicitWidth - 16 : 16
    readonly property real tipY: drop

    GlyphCable {
        anchors.fill: parent
        visible: cable.alive
        x0: cable.startX
        y0: 0
        x1: cable.tipX
        y1: cable.tipY
        count: Math.max(6, Math.round(cable.drop / 16))
        fontSize: cable.fontSize
        glyphColor: cable.cableColor
        amp: 10
        waves: 0.9
        // A barriga para baixo é o que faz o cabo parecer pendurado e não
        // esticado entre dois pontos.
        sag: cable.drop * 0.16
        flowing: false
    }

    // Fio desencapado saindo do corte: dois glifos soltos, mais claros.
    Text {
        x: cable.tipX - 10
        y: cable.tipY + 6
        text: "/"
        font.family: Theme.monoFamily
        font.pixelSize: cable.fontSize
        color: Theme.mix(cable.cableColor, "#ffffff", 0.5)
    }
    Text {
        x: cable.tipX + 4
        y: cable.tipY + 10
        text: "\\"
        font.family: Theme.monoFamily
        font.pixelSize: cable.fontSize
        color: Theme.mix(cable.cableColor, "#ffffff", 0.35)
    }

    // ---- faíscas ----
    property bool sparking: false

    Timer {
        running: cable.alive
        interval: 3000 + Math.random() * 6000
        repeat: true
        onTriggered: {
            cable.sparking = true;
            sparkOff.restart();
            interval = 3000 + Math.random() * 6000;
        }
    }
    Timer { id: sparkOff; interval: 420; onTriggered: cable.sparking = false }

    Rectangle {
        visible: cable.sparking
        x: cable.tipX - 4
        y: cable.tipY - 2
        width: 8
        height: 8
        radius: 4
        color: cable.sparkColor
        opacity: 0.85
    }

    Repeater {
        model: cable.sparking ? 5 : 0
        delegate: Rectangle {
            id: spark
            required property int index
            readonly property real dirX: (Math.random() * 2 - 1) * 26
            readonly property real dirY: 8 + Math.random() * 22
            width: 2 + Math.random() * 2
            height: width
            radius: width / 2
            color: spark.index % 2 === 0 ? cable.sparkColor : "#ffffff"
            x: cable.tipX
            y: cable.tipY

            ParallelAnimation {
                running: true
                NumberAnimation { target: spark; property: "x"; to: cable.tipX + spark.dirX; duration: 380; easing.type: Easing.OutQuad }
                NumberAnimation { target: spark; property: "y"; to: cable.tipY + spark.dirY; duration: 380; easing.type: Easing.InQuad }
                NumberAnimation { target: spark; property: "opacity"; from: 1; to: 0; duration: 380 }
            }
        }
    }
}
