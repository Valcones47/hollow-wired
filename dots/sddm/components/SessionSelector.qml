import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

ColumnLayout {
    id: selector
    width: Config.sessionPopupWidth - (Config.menuAreaPopupsPadding * 2)

    signal sessionChanged(sessionIndex: int, iconPath: string, label: string)
    signal close

    // Sem binding de propósito: o onCurrentIndexChanged da ListView escreve
    // nesta propriedade e, com um binding aqui, a primeira escrita (disparada
    // com a lista ainda vazia, no índice 0) destruía o vínculo com o
    // lastIndex — a sessão marcada travava na primeira da lista. O valor certo
    // é definido no Component.onCompleted, quando o modelo já existe.
    property int currentSessionIndex: 0
    property string sessionName: ""
    property string sessionIconPath: ""

    function getSessionIcon(name) {
        if (!name) return "../icons/sessions/default.svg";
        const lower = name.toLowerCase();
        if (lower.includes("plasma")) return "../icons/sessions/kde.svg";
        const available_session_icons = ["hyprland", "kde", "gnome", "ubuntu", "sway", "awesome", "qtile", "i3", "bspwm", "dwm", "xfce", "cinnamon", "niri"];
        for (let i = 0; i < available_session_icons.length; i++) {
            if (lower.includes(available_session_icons[i]))
                return `../icons/sessions/${available_session_icons[i]}.svg`;
        }
        return "../icons/sessions/default.svg";
    }

    ListView {
        id: sessionList
        Layout.preferredWidth: parent.width
        Layout.preferredHeight: Math.min(sessionModel.rowCount() * (Config.menuAreaPopupsItemHeight + spacing), Config.menuAreaPopupsMaxHeight)
        orientation: ListView.Vertical
        interactive: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: Config.menuAreaPopupsSpacing
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 0
        contentHeight: sessionModel.rowCount() * (Config.menuAreaPopupsItemHeight + spacing)

        ScrollBar.vertical: ScrollBar {
            id: scrollbar
            policy: Config.menuAreaPopupsDisplayScrollbar && sessionList.contentHeight > sessionList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            contentItem: Rectangle {
                id: scrollbarBackground
                implicitWidth: 5
                radius: 5
                color: Config.menuAreaPopupsContentColor
                opacity: Config.menuAreaPopupsActiveOptionBackgroundOpacity
            }
        }

        model: sessionModel
        currentIndex: selector.currentSessionIndex
        onCurrentIndexChanged: {
            const session_name = sessionModel.data(sessionModel.index(currentIndex, 0), 260);

            selector.currentSessionIndex = currentIndex;
            selector.sessionName = session_name;
            selector.sessionChanged(selector.currentSessionIndex, getSessionIcon(session_name), session_name);
        }

        delegate: Rectangle {
            width: scrollbar.visible ? parent.width - Config.menuAreaPopupsPadding - scrollbar.width : parent.width
            height: Config.menuAreaPopupsItemHeight
            color: "transparent"
            radius: Config.menuAreaButtonsBorderRadius

            Rectangle {
                anchors.fill: parent
                color: Config.menuAreaPopupsActiveOptionBackgroundColor
                opacity: index === selector.currentSessionIndex ? Config.menuAreaPopupsActiveOptionBackgroundOpacity : (itemMouseArea.containsMouse ? Config.menuAreaPopupsActiveOptionBackgroundOpacity : 0.0)
                radius: Config.menuAreaButtonsBorderRadius
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 12
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: parent.height
                    Layout.preferredHeight: parent.height
                    Layout.alignment: Qt.AlignVCenter
                    color: "transparent"

                    Image {
                        anchors.centerIn: parent
                        source: selector.getSessionIcon(name)
                        width: Config.menuAreaPopupsIconSize
                        height: Config.menuAreaPopupsIconSize
                        sourceSize: Qt.size(width, height)
                        fillMode: Image.PreserveAspectFit

                        MultiEffect {
                            source: parent
                            anchors.fill: parent
                            colorization: 1
                            colorizationColor: index === selector.currentSessionIndex || itemMouseArea.containsMouse ? Config.menuAreaPopupsActiveContentColor : Config.menuAreaPopupsContentColor
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: parent.height
                    Layout.alignment: Qt.AlignVCenter
                    color: "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: name
                        color: index === selector.currentSessionIndex || itemMouseArea.containsMouse ? Config.menuAreaPopupsActiveContentColor : Config.menuAreaPopupsContentColor
                        font.pixelSize: Config.menuAreaPopupsFontSize
                        font.weight: index === selector.currentSessionIndex ? Font.Bold : Font.Normal
                        font.family: Config.menuAreaPopupsFontFamily
                    }
                }

                Image {
                    visible: index === selector.currentSessionIndex
                    source: "../icons/check.svg"
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    Layout.alignment: Qt.AlignVCenter
                    sourceSize: Qt.size(14, 14)
                    fillMode: Image.PreserveAspectFit

                    MultiEffect {
                        source: parent
                        anchors.fill: parent
                        colorization: 1
                        colorizationColor: Config.menuAreaPopupsActiveContentColor
                    }
                }
            }

            MouseArea {
                id: itemMouseArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    sessionList.currentIndex = index;
                    selector.close();
                }
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down) {
            sessionList.currentIndex = (sessionList.currentIndex + sessionModel.rowCount() + 1) % sessionModel.rowCount();
        } else if (event.key === Qt.Key_Up) {
            sessionList.currentIndex = (sessionList.currentIndex + sessionModel.rowCount() - 1) % sessionModel.rowCount();
        } else if (event.key == Qt.Key_Return || event.key == Qt.Key_Enter || event.key === Qt.Key_Space) {
            selector.close();
        } else if (event.key === Qt.Key_CapsLock) {
            root.capsLockOn = !root.capsLockOn;
        }
    }

    Component.onCompleted: {
        const idx = loginScreen.initialSessionIndex();
        if (sessionModel && sessionModel.rowCount() > idx) {
            selector.currentSessionIndex = idx;
            sessionList.currentIndex = idx;
            const session_name = sessionModel.data(sessionModel.index(idx, 0), 260);
            selector.sessionName = session_name;
            selector.sessionChanged(idx, getSessionIcon(session_name), session_name);
        }
    }
}
