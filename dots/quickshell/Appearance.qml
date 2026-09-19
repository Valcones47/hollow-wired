import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// Aba Aparência do Hub (Rice Settings / Customizer estilo Noctalia/Caelestia).
// Ajusta geometria das janelas, bordas, gaps, opacidade, animações e wallpaper
// em tempo real via hyprctl eval e persiste em ~/.config/hypr/user-prefs.json.
Item {
    id: root

    // Preferências em cache
    property int rounding: 6
    property int borderSize: 2
    property int gapsIn: 4
    property int gapsOut: 8
    property real inactiveOpacity: 1.0
    property bool dimInactive: false
    property real dimStrength: 0.2
    property bool animEnabled: true
    property string animPreset: "smooth"

    // Observa o arquivo de preferências
    property FileView prefsFile: FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/user-prefs.json"
        watchChanges: true
        __printErrors: false
        onLoaded: root.loadFromText(text())
        onFileChanged: reload()
    }

    function loadFromText(content) {
        try {
            const data = JSON.parse(content);
            if (data.rounding !== undefined) root.rounding = data.rounding;
            if (data.border_size !== undefined) root.borderSize = data.border_size;
            if (data.gaps_in !== undefined) root.gapsIn = data.gaps_in;
            if (data.gaps_out !== undefined) root.gapsOut = data.gaps_out;
            if (data.inactive_opacity !== undefined) root.inactiveOpacity = data.inactive_opacity;
            if (data.dim_inactive !== undefined) root.dimInactive = !!data.dim_inactive;
            if (data.dim_strength !== undefined) root.dimStrength = data.dim_strength;
            if (data.anim_enabled !== undefined) root.animEnabled = !!data.anim_enabled;
            if (data.anim_preset !== undefined) root.animPreset = data.anim_preset;
        } catch (e) {}
    }

    Timer {
        id: applyDebounce
        interval: 60
        property string targetKey: ""
        property string targetVal: ""
        onTriggered: {
            Quickshell.execDetached(["rice-hypr-prefs", "set", targetKey, targetVal]);
        }
    }

    function setPref(key, val) {
        applyDebounce.targetKey = key;
        applyDebounce.targetVal = String(val);
        applyDebounce.restart();
    }

    // Componente: Slider interativo elegante com rótulo, valor e arrasto fluido
    component SettingSlider: ColumnLayout {
        id: sld
        property string title: ""
        property real minVal: 0
        property real maxVal: 100
        property real value: 0
        property string unit: ""
        property int decimals: 0
        signal changed(real newVal)

        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: sld.title
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textColor
            }
            Item { Layout.fillWidth: true }
            Text {
                text: sld.decimals > 0 ? sld.value.toFixed(sld.decimals) + sld.unit : Math.round(sld.value) + sld.unit
                font.family: Theme.monoFamily
                font.pixelSize: 11
                color: Theme.primary
            }
        }

        Item {
            id: track
            Layout.fillWidth: true
            implicitHeight: 20

            readonly property real fraction: Math.max(0, Math.min(1, (sld.value - sld.minVal) / (sld.maxVal - sld.minVal)))

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: Theme.withAlpha(Theme.primary, 0.2)

                Rectangle {
                    width: parent.width * track.fraction
                    height: parent.height
                    radius: 3
                    color: Theme.primary
                }
            }

            Rectangle {
                x: (track.width - width) * track.fraction
                anchors.verticalCenter: parent.verticalCenter
                width: sldArea.pressed || sldArea.containsMouse ? 16 : 12
                height: width
                radius: width / 2
                color: Theme.textColor
                Behavior on width { NumberAnimation { duration: 100 } }
            }

            MouseArea {
                id: sldArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                preventStealing: true

                function updateVal(mx) {
                    const frac = Math.max(0, Math.min(1, mx / track.width));
                    const raw = sld.minVal + frac * (sld.maxVal - sld.minVal);
                    const finalVal = sld.decimals > 0 ? parseFloat(raw.toFixed(sld.decimals)) : Math.round(raw);
                    sld.changed(finalVal);
                }

                onPressed: mouse => updateVal(mouse.x)
                onPositionChanged: mouse => { if (pressed) updateVal(mouse.x); }
                onWheel: wheel => {
                    const step = (sld.maxVal - sld.minVal) / 20;
                    const delta = wheel.angleDelta.y > 0 ? step : -step;
                    const raw = Math.max(sld.minVal, Math.min(sld.maxVal, sld.value + delta));
                    const finalVal = sld.decimals > 0 ? parseFloat(raw.toFixed(sld.decimals)) : Math.round(raw);
                    sld.changed(finalVal);
                }
            }
        }
    }

    // Componente: Switch On/Off
    component SettingToggle: RowLayout {
        id: sw
        property string title: ""
        property string subtitle: ""
        property bool checked: false
        signal toggled(bool nextVal)

        Layout.fillWidth: true
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                text: sw.title
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textColor
            }
            Text {
                visible: sw.subtitle !== ""
                text: sw.subtitle
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.subtext
            }
        }

        Rectangle {
            implicitWidth: 38
            implicitHeight: 20
            radius: 10
            color: sw.checked ? Theme.primary : Theme.tileHigh

            Rectangle {
                width: 14; height: 14; radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: sw.checked ? parent.width - width - 3 : 3
                color: Theme.textColor
                Behavior on x { NumberAnimation { duration: 140 } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sw.toggled(!sw.checked)
            }
        }
    }

    // Grid principal de 2 colunas
    RowLayout {
        anchors.fill: parent
        spacing: Theme.gap * 2

        // ================= COLUNA 1: GEOMETRIA & BORDAS =================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.tileRadius
            color: Theme.tile
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.25)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                RowLayout {
                    spacing: 8
                    Text {
                        text: Theme.icons.pencil
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 16
                        color: Theme.primary
                    }
                    Text {
                        text: Theme.t("appearance.geom_title", "Geometria & Janelas")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.textColor
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.withAlpha(Theme.outline, 0.2) }

                // Arredondamento
                SettingSlider {
                    title: Theme.t("appearance.rounding", "Arredondamento das Janelas")
                    minVal: 0; maxVal: 24; value: root.rounding; unit: "px"
                    onChanged: v => { root.rounding = v; root.setPref("rounding", v); }
                }

                // Espaçamento interno (Gaps In)
                SettingSlider {
                    title: Theme.t("appearance.gaps_in", "Espaçamento Interno (Gaps In)")
                    minVal: 0; maxVal: 20; value: root.gapsIn; unit: "px"
                    onChanged: v => { root.gapsIn = v; root.setPref("gaps_in", v); }
                }

                // Espaçamento externo (Gaps Out)
                SettingSlider {
                    title: Theme.t("appearance.gaps_out", "Espaçamento Externo (Gaps Out)")
                    minVal: 0; maxVal: 30; value: root.gapsOut; unit: "px"
                    onChanged: v => { root.gapsOut = v; root.setPref("gaps_out", v); }
                }

                // Espessura da Borda
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: Theme.t("appearance.border_size", "Espessura da Borda")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textColor
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [0, 1, 2, 3, 4]
                            delegate: Rectangle {
                                required property int modelData
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 6
                                color: root.borderSize === modelData ? Theme.primary : bArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.textColor, 0.06)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData + "px"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: root.borderSize === modelData ? Theme.background : Theme.textColor
                                }
                                MouseArea {
                                    id: bArea
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.borderSize = modelData;
                                        root.setPref("border_size", modelData);
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ================= COLUNA 2: EFEITOS & ANIMAÇÕES =================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.tileRadius
            color: Theme.tile
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.25)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                RowLayout {
                    spacing: 8
                    Text {
                        text: Theme.icons.tune
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 16
                        color: Theme.primary
                    }
                    Text {
                        text: Theme.t("appearance.effects_title", "Efeitos, Animações & Wallust")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.textColor
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.withAlpha(Theme.outline, 0.2) }

                // Opacidade de Janelas Inativas
                SettingSlider {
                    title: Theme.t("appearance.inactive_opacity", "Opacidade de Janelas Inativas")
                    minVal: 0.5; maxVal: 1.0; decimals: 2; value: root.inactiveOpacity; unit: ""
                    onChanged: v => { root.inactiveOpacity = v; root.setPref("inactive_opacity", v); }
                }

                // Escurecer Janelas Inativas (Dim)
                SettingToggle {
                    title: Theme.t("appearance.dim_inactive", "Escurecer Janelas Inativas")
                    subtitle: Theme.t("appearance.dim_desc", "Destaca visualmente a janela em foco")
                    checked: root.dimInactive
                    onToggled: v => { root.dimInactive = v; root.setPref("dim_inactive", v); }
                }

                // Presets de Animação
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: Theme.t("appearance.anim_style", "Estilo & Curvas de Animação")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textColor
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [
                                { id: "snappy", name: Theme.t("appearance.anim_snappy", "Rápido"), desc: Theme.t("appearance.anim_snappy_desc", "Snap") },
                                { id: "smooth", name: Theme.t("appearance.anim_smooth", "Suave"), desc: Theme.t("appearance.anim_smooth_desc", "Padrão") },
                                { id: "bouncy", name: Theme.t("appearance.anim_bouncy", "Elástico"), desc: Theme.t("appearance.anim_bouncy_desc", "Caelestia") }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 40
                                radius: 8
                                color: root.animPreset === modelData.id ? Theme.primary : pArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.textColor, 0.06)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 0
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.name
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: root.animPreset === modelData.id ? Theme.background : Theme.textColor
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.desc
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        color: root.animPreset === modelData.id ? Theme.background : Theme.subtext
                                    }
                                }
                                MouseArea {
                                    id: pArea
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.animPreset = modelData.id;
                                        Quickshell.execDetached(["rice-hypr-prefs", "preset", modelData.id]);
                                    }
                                }
                            }
                        }
                    }
                }

                // Ações de Tema & Wallpaper
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Layout.topMargin: 4

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 8
                        color: wallArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.primary, 0.15)
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.primary, 0.4)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: Theme.icons.palette
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 14
                                color: Theme.primary
                            }
                            Text {
                                text: Theme.t("appearance.wallpapers", "Wallpapers (Super+S)")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textColor
                            }
                        }
                        MouseArea {
                            id: wallArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["waywallen-switcher"])
                        }
                    }

                    Rectangle {
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 8
                        color: rstArea.containsMouse ? Theme.critical : Theme.withAlpha(Theme.textColor, 0.08)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icons.refresh
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 15
                            color: Theme.textColor
                        }
                        MouseArea {
                            id: rstArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["rice-hypr-prefs", "reset"])
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
