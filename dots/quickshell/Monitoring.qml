import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "."

// Aba Performance — layout da Caelestia: GPU | CPU (maior, no meio) |
// Memória Real & Cache. Chips embaixo com os números absolutos e
// botão de limpeza de caches / processos órfãos.
Item {
    id: root

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
}
