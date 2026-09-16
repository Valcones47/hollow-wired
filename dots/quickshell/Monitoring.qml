import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "."

// Aba Performance — layout da Caelestia: GPU | CPU (maior, no meio) |
// Memória Real & Cache. Chips embaixo com os números absolutos e
// botão de limpeza de caches / processos órfãos.
Item {
    id: root

    property bool showCacheExplanation: false

    function severity(frac) {
        if (frac >= 0.9)
            return Theme.critical;
        if (frac >= 0.7)
            return Theme.warning;
        return Theme.primary;
    }

    // Temperatura vira fração numa escala 30-100°C pro arco; cor muda a
    // partir de 70/90°C, mesmos limiares dos percentuais.
    function tempFrac(t) {
        return Math.max(0, Math.min(1, (t - 30) / 70));
    }

    Process {
        id: cleanProc
        command: ["rice-ram-cleaner"]
        onExited: {
            SysStats.ramProc.running = true;
            SysStats.zramProc.running = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gap * 2

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.gap * 5

            Item { Layout.fillWidth: true }

            Gauge {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 200
                Layout.preferredHeight: 200
                value: root.tempFrac(SysStats.gpuTemp)
                color: root.severity(SysStats.gpuTemp / 100)
                valueText: SysStats.gpuTemp > 0 ? SysStats.gpuTemp.toFixed(0) + "°C" : "--"
                label: "GPU temp"
                secondaryValue: SysStats.gpuUsage
                secondaryText: Math.round(SysStats.gpuUsage * 100) + "%"
                secondaryLabel: "uso"
            }

            Gauge {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 256
                Layout.preferredHeight: 256
                value: root.tempFrac(SysStats.cpuTemp)
                color: root.severity(SysStats.cpuTemp / 100)
                valueText: SysStats.cpuTemp > 0 ? SysStats.cpuTemp.toFixed(0) + "°C" : "--"
                label: "CPU temp"
                secondaryValue: SysStats.cpuUsage
                secondaryText: Math.round(SysStats.cpuUsage * 100) + "%"
                secondaryLabel: "uso"
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 8

                Gauge {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: 200
                    value: SysStats.ramRealFrac
                    color: root.severity(SysStats.ramRealFrac)
                    valueText: SysStats.ramRealGiB.toFixed(1) + "GiB"
                    label: "RAM (Apps)"
                    secondaryValue: SysStats.ramCacheFrac
                    secondaryColor: Theme.subtext
                    secondaryText: SysStats.ramCacheGiB.toFixed(1) + "GiB"
                    secondaryLabel: "cache"
                }

                Rectangle {
                    id: cleanBtn
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: cleanRow.implicitWidth + 24
                    implicitHeight: 28
                    radius: 14
                    color: cleanArea.containsMouse ? Theme.primary : Theme.tileHigh
                    border.color: cleanArea.containsMouse ? Theme.primary : Theme.withAlpha(Theme.primary, 0.4)
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        id: cleanRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.icons.broom
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 13
                            color: cleanArea.containsMouse ? Theme.background : Theme.primary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: cleanProc.running ? "Limpando..." : "Limpar Caches"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: cleanArea.containsMouse ? Theme.background : Theme.textColor
                        }
                    }

                    MouseArea {
                        id: cleanArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !cleanProc.running
                        onClicked: cleanProc.running = true
                    }
                }

                // Botão explicativo "Não necessário"
                Rectangle {
                    id: whyBtn
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: whyRow.implicitWidth + 16
                    implicitHeight: 22
                    radius: 11
                    color: whyArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.15) : "transparent"
                    border.color: whyArea.containsMouse ? Theme.primary : Theme.withAlpha(Theme.subtext, 0.3)
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Row {
                        id: whyRow
                        anchors.centerIn: parent
                        spacing: 5
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.icons.info
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 11
                            color: whyArea.containsMouse ? Theme.primary : Theme.subtext
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Não necessário"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            color: whyArea.containsMouse ? Theme.textColor : Theme.subtext
                        }
                    }

                    MouseArea {
                        id: whyArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showCacheExplanation = true
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ---------- chips com valores absolutos ----------
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: false
            spacing: Theme.gap

            Repeater {
                model: [
                    { icon: Theme.icons.cpu, text: "CPU " + Math.round(SysStats.cpuUsage * 100) + "%" },
                    { icon: Theme.icons.gpu, text: SysStats.gpuName + " " + Math.round(SysStats.gpuUsage * 100) + "%" },
                    { icon: Theme.icons.memory, text: "RAM " + SysStats.ramRealGiB.toFixed(1) + " / " + SysStats.ramTotalGiB.toFixed(1) + " GiB" },
                    { icon: Theme.icons.broom, text: "Cache " + SysStats.ramCacheGiB.toFixed(1) + " GiB" },
                    { icon: Theme.icons.memory, text: "zram " + SysStats.zramUsedGiB.toFixed(2) + " / " + SysStats.zramTotalGiB.toFixed(0) + " GiB" },
                    { icon: Theme.icons.disk, text: SysStats.diskUsedGiB.toFixed(0) + " / " + SysStats.diskTotalGiB.toFixed(0) + " GiB" }
                ]
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    implicitWidth: chipRow.implicitWidth + 24
                    implicitHeight: 30
                    radius: 15
                    color: Theme.tile

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.icon
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 14
                            color: Theme.primary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textColor
                        }
                    }
                }
            }
        }
    }

    // ---------- Modal Explicativo: Por que limpar cache não é necessário ----------
    Rectangle {
        id: explanationOverlay
        anchors.fill: parent
        visible: opacity > 0
        opacity: root.showCacheExplanation ? 1 : 0
        color: Qt.rgba(0, 0, 0, 0.72)
        radius: Theme.radius

        Behavior on opacity { NumberAnimation { duration: 180 } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.showCacheExplanation = false
        }

        Rectangle {
            id: modalBox
            width: Math.min(parent.width - 40, 520)
            implicitHeight: modalCol.implicitHeight + 36
            anchors.centerIn: parent
            radius: 16
            color: Theme.tile
            border.width: 1
            border.color: Theme.withAlpha(Theme.primary, 0.4)

            // Engole cliques dentro do card
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: modalCol
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                // Cabeçalho
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: Theme.withAlpha(Theme.primary, 0.2)
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icons.info
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 16
                            color: Theme.primary
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Por que limpar cache não é necessário?"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: Theme.textColor
                    }

                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: closeArea.containsMouse ? Theme.withAlpha(Theme.critical, 0.25) : Theme.tileHigh

                        Text {
                            anchors.centerIn: parent
                            text: Theme.icons.close
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 12
                            color: closeArea.containsMouse ? Theme.critical : Theme.subtext
                        }

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showCacheExplanation = false
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.withAlpha(Theme.outline, 0.2)
                }

                // Conteúdo explicativo
                Text {
                    Layout.fillWidth: true
                    text: "Essa RAM \"usada\" é <b>cache de página do kernel</b> — arquivos que já foram lidos do disco e ficaram guardados na memória pra não precisar ler de novo. Não é memória alocada por nenhum processo, é <b>RAM livre sendo reaproveitada</b>."
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    lineHeight: 1.35
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    color: Theme.textColor
                }

                Text {
                    Layout.fillWidth: true
                    text: "Quando algum programa pede mais memória, o kernel libera esse cache <b>automaticamente e na hora</b>, antes de precisar usar swap. Não tem cenário onde limpar isso manualmente ajuda — só descarta o cache e força o próximo acesso a disco de novo, o que deixa as coisas mais lentas, não mais rápidas."
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    lineHeight: 1.35
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    color: Theme.textColor
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: noteText.implicitHeight + 16
                    radius: 8
                    color: Theme.withAlpha(Theme.primary, 0.08)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.primary, 0.25)

                    Text {
                        id: noteText
                        anchors.fill: parent
                        anchors.margins: 10
                        text: "O botão fica disponível mesmo assim para testes, mas não faz o que o nome sugere."
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.italic: true
                        wrapMode: Text.Wrap
                        color: Theme.subtext
                    }
                }

                // Rodapé com botão Entendi
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: 84
                        implicitHeight: 28
                        radius: 14
                        color: okArea.containsMouse ? Theme.primary : Theme.tileHigh
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.primary, 0.4)

                        Text {
                            anchors.centerIn: parent
                            text: "Entendi"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: okArea.containsMouse ? Theme.background : Theme.textColor
                        }

                        MouseArea {
                            id: okArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showCacheExplanation = false
                        }
                    }
                }
            }
        }
    }
}
