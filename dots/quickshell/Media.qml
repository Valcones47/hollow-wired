import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "."

Item {
    id: root

    readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null

    // ---------- barrinhas reagindo ao áudio (cava) ----------
    // Só roda enquanto algo está tocando de verdade — sem gastar CPU à toa
    // com o cava analisando silêncio o tempo todo.
    property var barValues: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    Process {
        id: cavaProc
        running: root.player !== null && root.player.isPlaying
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/quickshell/cava.conf"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = line.split(";").filter(s => s.length > 0).map(Number);
                if (parts.length > 0)
                    root.barValues = parts;
            }
        }
    }

    // MPRIS não empurra a posição continuamente durante a reprodução — só
    // em eventos (seek, troca de faixa). Esse timer avança a barra sozinho
    // entre eventos e resincroniza sempre que o player manda uma posição
    // nova de verdade.
    property real tickPosition: 0
    Timer {
        interval: 1000
        running: root.player !== null && root.player.isPlaying
        repeat: true
        onTriggered: root.tickPosition += 1
    }
    Connections {
        target: root.player
        function onPositionChanged() {
            root.tickPosition = root.player.position;
        }
        function onTrackTitleChanged() {
            root.tickPosition = root.player.position;
        }
    }
    onPlayerChanged: {
        if (player)
            tickPosition = player.position;
    }

    function fmtTime(seconds) {
        if (!seconds || seconds < 0 || isNaN(seconds))
            return "0:00";
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gap * 2
        visible: root.player !== null

        // ---------- capa + metadados ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap * 2

            Rectangle {
                Layout.preferredWidth: 120
                Layout.preferredHeight: 120
                Layout.alignment: Qt.AlignTop
                radius: Theme.radius / 2
                color: Theme.withAlpha(Theme.accent1, 0.15)
                border.width: 1
                border.color: Theme.withAlpha(Theme.accent1, 0.35)
                clip: true

                Image {
                    anchors.fill: parent
                    source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: !root.player || !root.player.trackArtUrl
                    text: ""
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 36
                    color: Theme.withAlpha(Theme.accent1, 0.6)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: root.player ? root.player.trackTitle : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                    color: Theme.foreground
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: root.player ? root.player.trackArtist : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.inactive
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: root.player ? root.player.trackAlbum : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.italic: true
                    color: Theme.withAlpha(Theme.inactive, 0.7)
                    elide: Text.ElideRight
                    visible: text !== ""
                }

                Rectangle {
                    Layout.topMargin: 4
                    Layout.preferredWidth: sourceLabel.implicitWidth + 16
                    Layout.preferredHeight: 20
                    radius: 10
                    color: Theme.withAlpha(Theme.accent2, 0.2)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.accent2, 0.4)
                    visible: root.player !== null

                    Text {
                        id: sourceLabel
                        anchors.centerIn: parent
                        text: root.player ? root.player.identity : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.accent2
                    }
                }
            }
        }

        // ---------- barra de progresso ----------
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: root.player !== null

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 5
                radius: 2.5
                color: Theme.withAlpha(Theme.inactive, 0.25)

                Rectangle {
                    height: parent.height
                    radius: 2.5
                    color: Theme.accent2
                    width: {
                        const len = root.player && root.player.length > 0 ? root.player.length : 0;
                        if (len <= 0) return 0;
                        const frac = Math.min(1, root.tickPosition / len);
                        return parent.width * frac;
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.fmtTime(root.tickPosition)
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.inactive
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.fmtTime(root.player ? root.player.length : 0)
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.inactive
                }
            }
        }

        // ---------- barrinhas de áudio (só quando tocando) ----------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 3
            visible: root.player !== null && root.player.isPlaying

            Repeater {
                model: root.barValues
                delegate: Rectangle {
                    required property real modelData
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    radius: 2
                    color: Theme.accent2
                    implicitHeight: Math.max(3, (modelData / 100) * 36)

                    Behavior on implicitHeight {
                        NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                    }
                }
            }
        }

        // ---------- controles ----------
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.gap * 2
            visible: root.player !== null

            Rectangle {
                id: prevBtn
                property bool hovered: false
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: hovered ? Theme.withAlpha(Theme.inactive, 0.15) : "transparent"
                border.width: 1
                border.color: Theme.withAlpha(Theme.inactive, 0.4)
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 14
                    color: Theme.foreground
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: prevBtn.hovered = true
                    onExited: prevBtn.hovered = false
                    onClicked: root.player && root.player.previous()
                }
            }

            Rectangle {
                id: playBtn
                property bool hovered: false
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                radius: 26
                color: Theme.withAlpha(Theme.accent2, hovered ? 0.4 : 0.25)
                border.width: 1
                border.color: Theme.accent2
                scale: hovered ? 1.06 : 1.0
                Behavior on color { ColorAnimation { duration: 100 } }
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }

                Text {
                    anchors.centerIn: parent
                    text: root.player && root.player.isPlaying ? "" : ""
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 18
                    color: Theme.accent2
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: playBtn.hovered = true
                    onExited: playBtn.hovered = false
                    onClicked: root.player && root.player.togglePlaying()
                }
            }

            Rectangle {
                id: nextBtn
                property bool hovered: false
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: hovered ? Theme.withAlpha(Theme.inactive, 0.15) : "transparent"
                border.width: 1
                border.color: Theme.withAlpha(Theme.inactive, 0.4)
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 14
                    color: Theme.foreground
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: nextBtn.hovered = true
                    onExited: nextBtn.hovered = false
                    onClicked: root.player && root.player.next()
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    // ---------- estado vazio ----------
    ColumnLayout {
        anchors.centerIn: parent
        visible: root.player === null
        spacing: 12

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 72
            height: 72
            radius: 36
            color: Theme.withAlpha(Theme.inactive, 0.08)
            border.width: 1
            border.color: Theme.withAlpha(Theme.inactive, 0.2)

            Text {
                anchors.centerIn: parent
                text: ""
                font.family: Theme.iconFontFamily
                font.pixelSize: 32
                color: Theme.withAlpha(Theme.inactive, 0.6)
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Theme.t("media.no_media", "Nenhuma mídia em reprodução")
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: Theme.textColor
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Theme.t("media.no_media_sub", "Abra o Spotify, YouTube Music ou outro player de áudio")
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.subtext
        }
    }
}
