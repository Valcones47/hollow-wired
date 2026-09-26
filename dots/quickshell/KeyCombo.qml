import QtQuick
import QtQuick.Layouts
import "."

// Combinação de teclas desenhada como teclas de verdade: "Super + Shift + V"
// vira três keycaps com relevo embaixo. Super, Shift, Enter e setas ganham
// símbolo; o resto aparece como texto.
RowLayout {
    id: kc
    property string combo: ""
    property bool accent: false     // destaque (atalho alterado pela pessoa)
    spacing: 3

    function parts() {
        return String(combo).split("+").map(p => p.trim()).filter(p => p !== "");
    }
    function glyph(k) {
        const u = k.toUpperCase();
        if (u === "SUPER" || u === "WIN" || u === "MOD") return { icon: "\u{F05B3}", text: "" };
        if (u === "SHIFT") return { icon: "\u{F0636}", text: "Shift" };
        if (u === "ENTER" || u === "RETURN") return { icon: "\u{F0311}", text: "" };
        if (u === "SETAS" || u === "ARROWS") return { icon: "", text: "← ↑ → ↓" };
        if (u === "ESPAÇO" || u === "SPACE") return { icon: "", text: "Espaço" };
        return { icon: "", text: k };
    }

    Repeater {
        model: kc.parts()
        delegate: RowLayout {
            id: part
            required property string modelData
            required property int index
            spacing: 3
            Text {
                visible: part.index > 0
                text: "+"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.subtext
            }
            // Alternativas na mesma posição ("Super / Super + R", "Print / Super"):
            // cada uma vira uma tecla, com "/" entre elas.
            Repeater {
                model: part.modelData.split("/").map(x => x.trim()).filter(x => x !== "")
                delegate: RowLayout {
                    id: alt
                    required property string modelData
                    required property int index
                    readonly property var g: kc.glyph(modelData)
                    spacing: 3
                    Text {
                        visible: alt.index > 0
                        text: "/"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.subtext
                    }
                    // Keycap: a face fica 2 px acima da "base", que faz o relevo.
                    Item {
                        implicitWidth: Math.max(22, capRow.implicitWidth + 12)
                        implicitHeight: 22
                        Rectangle {
                            anchors.fill: parent
                            radius: 5
                            color: Theme.withAlpha(Theme.background, 0.7)
                        }
                        Rectangle {
                            width: parent.width
                            height: parent.height - 2
                            radius: 5
                            color: Theme.tileHigh
                            border.width: 1
                            border.color: Theme.withAlpha(kc.accent ? Theme.primary : Theme.outline, kc.accent ? 0.6 : 0.3)
                            Row {
                                id: capRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    visible: alt.g.icon !== ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: alt.g.icon
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 12
                                    color: kc.accent ? Theme.primary : Theme.textColor
                                }
                                Text {
                                    visible: alt.g.text !== ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: alt.g.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: kc.accent ? Theme.primary : Theme.textColor
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
