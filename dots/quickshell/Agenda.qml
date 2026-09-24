import QtQuick
import QtQuick.Layouts
import Quickshell
import "."

// Aba "Agenda" do Hub: calendário do mês com os dias que têm evento, os
// eventos do dia escolhido (calendários .ics, arquivo ou link) e a lista de
// tarefas. Fontes e tarefas são estado do usuário (CalendarService,
// TodoService).
Item {
    id: root

    readonly property var monthNames: Theme.locale === "en"
        ? ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        : ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho", "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"]

    property date today: new Date()
    // Mês mostrado (muda com ‹ ›) e dia escolhido (AAAA-MM-DD).
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()
    property string selected: CalendarService.key(today.getFullYear(), today.getMonth(), today.getDate())

    // Ao abrir de novo, volta para hoje.
    onVisibleChanged: if (visible) {
        today = new Date();
        viewYear = today.getFullYear();
        viewMonth = today.getMonth();
        selected = CalendarService.key(viewYear, viewMonth, today.getDate());
    }

    readonly property var grid: {
        const y = viewYear, m = viewMonth;
        const firstDow = new Date(y, m, 1).getDay();
        const numDays = new Date(y, m + 1, 0).getDate();
        const cells = [];
        for (let i = 0; i < firstDow; i++) {
            const d = new Date(y, m, i - firstDow + 1);
            cells.push({ d: d.getDate(), k: CalendarService.key(d.getFullYear(), d.getMonth(), d.getDate()), inMonth: false });
        }
        for (let d = 1; d <= numDays; d++)
            cells.push({ d: d, k: CalendarService.key(y, m, d), inMonth: true });
        while (cells.length < 42) {
            const d = new Date(y, m + 1, cells.length - firstDow - numDays + 1);
            cells.push({ d: d.getDate(), k: CalendarService.key(d.getFullYear(), d.getMonth(), d.getDate()), inMonth: false });
        }
        return cells;
    }
    readonly property string todayKey: CalendarService.key(today.getFullYear(), today.getMonth(), today.getDate())

    function shiftMonth(delta) {
        const d = new Date(viewYear, viewMonth + delta, 1);
        viewYear = d.getFullYear();
        viewMonth = d.getMonth();
    }
    function dayLabel(k) {
        if (k === todayKey) return Theme.t("agenda.today", "Hoje");
        const p = k.split("-");
        return Number(p[2]) + " " + root.monthNames[Number(p[1]) - 1].toLowerCase();
    }

    component Tile: Rectangle {
        radius: Theme.tileRadius
        color: Theme.tile
    }
    component SmallTitle: Text {
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
        color: Theme.subtext
    }
    component IconBtn: Rectangle {
        id: ib
        property string icon: ""
        signal clicked()
        implicitWidth: 24
        implicitHeight: 24
        radius: 6
        color: ibArea.containsMouse ? Theme.tileHigh : "transparent"
        Text {
            anchors.centerIn: parent
            text: ib.icon
            font.family: Theme.iconFontFamily
            font.pixelSize: 13
            color: ibArea.containsMouse ? Theme.textColor : Theme.subtext
        }
        MouseArea {
            id: ibArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }
    // Campo de texto de uma linha: Enter confirma.
    component Field: Rectangle {
        id: fld
        property string placeholder: ""
        signal submitted(string text)
        implicitHeight: 30
        radius: 8
        color: Theme.withAlpha(Theme.background, 0.55)
        border.width: 1
        border.color: fldInput.activeFocus ? Theme.withAlpha(Theme.primary, 0.6) : "transparent"
        TextInput {
            id: fldInput
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.textColor
            clip: true
            selectByMouse: true
            onAccepted: { fld.submitted(text); text = ""; }
            Keys.onEscapePressed: { text = ""; focus = false; }
        }
        Text {
            anchors.fill: fldInput
            verticalAlignment: Text.AlignVCenter
            visible: fldInput.text === "" && !fldInput.activeFocus
            text: fld.placeholder
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.withAlpha(Theme.subtext, 0.7)
            elide: Text.ElideRight
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.gap

        // ================= mês =================
        Tile {
            Layout.preferredWidth: 270
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    IconBtn { icon: "\u{F0141}"; onClicked: root.shiftMonth(-1) }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.monthNames[root.viewMonth] + " " + root.viewYear
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.textColor
                    }
                    IconBtn { icon: "\u{F0142}"; onClicked: root.shiftMonth(1) }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 7
                    rowSpacing: 0
                    columnSpacing: 0

                    Repeater {
                        model: Theme.locale === "en" ? ["S", "M", "T", "W", "T", "F", "S"] : ["D", "S", "T", "Q", "Q", "S", "S"]
                        delegate: Text {
                            required property string modelData
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Theme.subtext
                        }
                    }
                    Repeater {
                        model: root.grid
                        delegate: Item {
                            id: cell
                            required property var modelData
                            readonly property bool isToday: cell.modelData.k === root.todayKey
                            readonly property bool isSel: cell.modelData.k === root.selected
                            readonly property bool hasEv: (CalendarService.byDay[cell.modelData.k] || []).length > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26; height: 26; radius: 13
                                color: cell.isToday ? Theme.primary
                                    : cell.isSel ? Theme.tileHigh
                                    : cellArea.containsMouse ? Theme.withAlpha(Theme.tileHigh, 0.5) : "transparent"
                            }
                            Text {
                                anchors.centerIn: parent
                                text: cell.modelData.d
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: cell.isToday || cell.isSel ? Font.Bold : Font.Normal
                                color: cell.isToday ? Theme.background
                                    : cell.modelData.inMonth ? Theme.textColor : Theme.withAlpha(Theme.subtext, 0.35)
                            }
                            Rectangle {
                                visible: cell.hasEv
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 1
                                width: 4; height: 4; radius: 2
                                color: cell.isToday ? Theme.primary : Theme.subtext
                            }
                            MouseArea {
                                id: cellArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selected = cell.modelData.k;
                                    if (!cell.modelData.inMonth) {
                                        const p = cell.modelData.k.split("-");
                                        root.viewYear = Number(p[0]);
                                        root.viewMonth = Number(p[1]) - 1;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ================= eventos do dia + calendários =================
        Tile {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                SmallTitle { text: root.dayLabel(root.selected) }

                ListView {
                    id: evList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: CalendarService.eventsOn(root.selected)
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: RowLayout {
                        id: evRow
                        required property var modelData
                        width: evList.width
                        spacing: 10
                        Text {
                            Layout.preferredWidth: 44
                            Layout.alignment: Qt.AlignTop
                            text: evRow.modelData.allDay ? Theme.t("agenda.all_day", "dia todo") : evRow.modelData.start
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.subtext
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: evRow.modelData.title || "—"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.textColor
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: [evRow.modelData.allDay ? "" : evRow.modelData.start + "–" + evRow.modelData.end, evRow.modelData.location]
                                    .filter(s => s).join(" · ")
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.subtext
                                elide: Text.ElideRight
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: evList.count === 0
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: CalendarService.sources.length === 0
                            ? Theme.t("agenda.no_sources", "Adicione um calendário .ics abaixo para ver seus eventos")
                            : Theme.t("agenda.no_events", "Nenhum evento")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.outline, 0.25) }

                SmallTitle { text: Theme.t("agenda.calendars", "Calendários") }
                Repeater {
                    model: CalendarService.sources
                    delegate: RowLayout {
                        id: srcRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: srcRow.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.subtext
                            elide: Text.ElideMiddle
                        }
                        IconBtn { icon: Theme.icons.close; onClicked: CalendarService.remove(srcRow.modelData) }
                    }
                }
                Field {
                    Layout.fillWidth: true
                    placeholder: Theme.t("agenda.add_source", "Arquivo .ics ou link (Enter adiciona)")
                    onSubmitted: t => CalendarService.add(t)
                }
            }
        }

        // ================= tarefas =================
        Tile {
            Layout.preferredWidth: 280
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    SmallTitle {
                        Layout.fillWidth: true
                        text: Theme.t("agenda.tasks", "Tarefas") + (TodoService.openCount > 0 ? "  " + TodoService.openCount : "")
                    }
                    Text {
                        visible: TodoService.items.some(i => i.done)
                        text: Theme.t("agenda.clear_done", "Limpar feitas")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: clearArea.containsMouse ? Theme.textColor : Theme.subtext
                        MouseArea {
                            id: clearArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: TodoService.clearDone()
                        }
                    }
                }

                Field {
                    Layout.fillWidth: true
                    placeholder: Theme.t("agenda.new_task", "Nova tarefa (Enter adiciona)")
                    onSubmitted: t => TodoService.add(t)
                }

                ListView {
                    id: todoList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 0
                    model: TodoService.items
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Item {
                        id: todoRow
                        required property var modelData
                        required property int index
                        width: todoList.width
                        height: Math.max(30, todoText.implicitHeight + 10)

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: rowHover.hovered ? Theme.withAlpha(Theme.tileHigh, 0.5) : "transparent"
                        }
                        HoverHandler { id: rowHover }

                        Rectangle {
                            id: box
                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16; radius: 5
                            color: todoRow.modelData.done ? Theme.primary : "transparent"
                            border.width: todoRow.modelData.done ? 0 : 1.5
                            border.color: Theme.withAlpha(Theme.subtext, 0.7)
                            Text {
                                anchors.centerIn: parent
                                visible: todoRow.modelData.done
                                text: Theme.icons.check
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 11
                                color: Theme.background
                            }
                        }
                        Text {
                            id: todoText
                            anchors.left: box.right
                            anchors.leftMargin: 10
                            anchors.right: delBtn.left
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: todoRow.modelData.text
                            wrapMode: Text.Wrap
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.strikeout: todoRow.modelData.done
                            color: todoRow.modelData.done ? Theme.subtext : Theme.textColor
                        }
                        MouseArea {
                            anchors.left: parent.left
                            anchors.right: delBtn.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            cursorShape: Qt.PointingHandCursor
                            onClicked: TodoService.toggle(todoRow.index)
                        }
                        IconBtn {
                            id: delBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: rowHover.hovered ? 1 : 0
                            icon: Theme.icons.close
                            onClicked: TodoService.remove(todoRow.index)
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: todoList.count === 0
                        text: Theme.t("agenda.no_tasks", "Nada pendente")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                }
            }
        }
    }
}
