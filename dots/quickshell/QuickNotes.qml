import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Modal flutuante de Bloco de Notas Rápido (Super + G) com múltiplas notas.
// Auto-save contínuo em ~/.config/hollow-wired/quicknotes.json.
PanelWindow {
    id: notesWindow

    property bool open: false
    property var notes: []
    property int activeIndex: 0
    property bool ready: false

    visible: true
    color: "transparent"
    focusable: true

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
        width: notesWindow.open ? notesWindow.width : 0
        height: notesWindow.open ? notesWindow.height : 0
    }

    WlrLayershell.namespace: "quickshell-quicknotes"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: notesWindow.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Persistência das notas em JSON
    FileView {
        id: notesFile
        path: Quickshell.env("HOME") + "/.config/hollow-wired/quicknotes.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = text().trim();
                if (t) {
                    const parsed = JSON.parse(t);
                    if (Array.isArray(parsed) && parsed.length > 0) {
                        notesWindow.notes = parsed;
                    } else {
                        notesWindow.initDefaultNote();
                    }
                } else {
                    notesWindow.initDefaultNote();
                }
            } catch (e) {
                console.log("QuickNotes: erro ao ler quicknotes.json:", e);
                notesWindow.initDefaultNote();
            } finally {
                notesWindow.ready = true;
                if (notesWindow.notes.length > 0 && noteArea) {
                    noteArea.text = notesWindow.notes[notesWindow.activeIndex]?.content || "";
                }
            }
        }
        onLoadFailed: {
            notesWindow.ready = true;
            notesWindow.initDefaultNote();
        }
    }

    function initDefaultNote() {
        notesWindow.notes = [
            {
                id: Date.now().toString(),
                title: "Nota rápida",
                content: "Bem-vindo ao Quick Notes!\n\n• Suas notas salvam sozinhas continuamente.\n• Use Super + G para abrir ou fechar de qualquer lugar.\n• Crie novas notas e organize seus rascunhos na barra lateral.",
                updatedAt: new Date().toISOString()
            }
        ];
        notesWindow.activeIndex = 0;
        notesWindow.saveNotes();
    }

    Timer {
        id: autoSaveTimer
        interval: 350
        repeat: false
        onTriggered: notesWindow.saveNotes()
    }

    function queueSave() {
        if (!notesWindow.ready) return;
        autoSaveTimer.restart();
    }

    function saveNotes() {
        if (!notesWindow.ready) return;
        try {
            notesFile.setText(JSON.stringify(notesWindow.notes, null, 2) + "\n");
        } catch (e) {
            console.log("QuickNotes: erro ao salvar:", e);
        }
    }

    function createNote() {
        const newNote = {
            id: Date.now().toString(),
            title: "Nova nota",
            content: "",
            updatedAt: new Date().toISOString()
        };
        const updated = [newNote].concat(notesWindow.notes);
        notesWindow.notes = updated;
        notesWindow.activeIndex = 0;
        if (noteArea) {
            noteArea.text = "";
            noteArea.forceActiveFocus();
        }
        notesWindow.saveNotes();
    }

    function deleteNote(idx) {
        if (idx < 0 || idx >= notesWindow.notes.length) return;
        const copy = notesWindow.notes.slice();
        copy.splice(idx, 1);
        if (copy.length === 0) {
            copy.push({
                id: Date.now().toString(),
                title: "Nova nota",
                content: "",
                updatedAt: new Date().toISOString()
            });
        }
        notesWindow.notes = copy;
        if (notesWindow.activeIndex >= copy.length) {
            notesWindow.activeIndex = Math.max(0, copy.length - 1);
        }
        if (noteArea) {
            noteArea.text = notesWindow.notes[notesWindow.activeIndex]?.content || "";
        }
        notesWindow.saveNotes();
    }

    function pinCurrentNote() {
        if (!notesWindow.notes || notesWindow.notes.length === 0) return;
        const cur = notesWindow.notes[notesWindow.activeIndex];
        if (!cur) return;
        const isPinned = cur.pinned === true;
        if (isPinned) {
            cur.pinned = false;
            notesWindow.saveNotes();
            Quickshell.execDetached(["quickshell", "ipc", "call", "stickynote", "hide"]);
            return;
        }
        for (let i = 0; i < notesWindow.notes.length; i++) {
            notesWindow.notes[i].pinned = (i === notesWindow.activeIndex);
        }
        notesWindow.saveNotes();
        notesWindow.open = false;
        Quickshell.execDetached(["quickshell", "ipc", "call", "stickynote", "open"]);
    }

    function extractTitle(content) {
        if (!content) return "Nova nota";
        const lines = content.trim().split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim().replace(/^[#\-*>\s]+/, "");
            if (line.length > 0) {
                return line.slice(0, 28);
            }
        }
        return "Nova nota";
    }

    onOpenChanged: {
        if (open) {
            if (notesWindow.notes.length > 0 && noteArea) {
                noteArea.text = notesWindow.notes[notesWindow.activeIndex]?.content || "";
                noteArea.forceActiveFocus();
            }
        }
    }

    // Fundo escuro semitransparente para fechar ao clicar fora
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: notesWindow.open ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: notesWindow.open = false
        }
    }

    // Card flutuante central
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(760, parent.width - 40)
        height: Math.min(500, parent.height - 60)
        radius: 20
        color: Theme.mix(Theme.background, "#000000", 0.40)
        border.color: Theme.withAlpha(Theme.primary, 0.35)
        border.width: 1
        clip: true

        scale: notesWindow.open ? 1 : 0.94
        opacity: notesWindow.open ? 1 : 0
        visible: opacity > 0

        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---------------- Cabeçalho ----------------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                color: Theme.withAlpha(Theme.tile, 0.50)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.15)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 14
                    spacing: 10

                    Text {
                        text: "󰠮"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 18
                        color: Theme.primary
                    }

                    Text {
                        text: Theme.t("quicknotes.title", "Bloco de Notas Rápido")
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: Theme.textColor
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 20
                        radius: 5
                        color: Theme.tileHigh
                        Text {
                            anchors.centerIn: parent
                            text: "Super + G"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Theme.subtext
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Botão Destacar em Janela Flutuante (Sticky Note)
                    Rectangle {
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: pinRow.implicitWidth + 18
                        radius: 6
                        color: pinBtnArea.containsMouse ? Theme.tileHigh : Theme.tile

                        readonly property bool isCurrentPinned: {
                            if (!notesWindow.notes || notesWindow.notes.length === 0) return false;
                            const cur = notesWindow.notes[notesWindow.activeIndex];
                            return cur && cur.pinned === true;
                        }

                        Row {
                            id: pinRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰐃"
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 13
                                color: Theme.primary
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.isCurrentPinned
                                    ? Theme.t("quicknotes.unpin", "Desafixar")
                                    : Theme.t("quicknotes.pin_window", "Destacar em Janela")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: Theme.textColor
                            }
                        }

                        MouseArea {
                            id: pinBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notesWindow.pinCurrentNote()
                        }
                    }

                    // Botão Fechar
                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: 15
                        color: closeArea.containsMouse ? Theme.withAlpha(Theme.critical, 0.22) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: closeArea.containsMouse ? Theme.critical : Theme.subtext
                        }

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notesWindow.open = false
                        }
                    }
                }
            }

            // ---------------- Corpo Principal (Split: Lista + Editor) ----------------
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Barra Lateral de Notas
                Rectangle {
                    Layout.preferredWidth: 220
                    Layout.fillHeight: true
                    color: Theme.withAlpha("#000000", 0.25)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outline, 0.12)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        // Botão Nova Nota
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 8
                            color: newNoteArea.containsMouse ? Theme.tileHigh : Theme.tile
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "+"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: Theme.primary
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Theme.t("quicknotes.new_note", "Nova nota")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: Theme.textColor
                                }
                            }

                            MouseArea {
                                id: newNoteArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: notesWindow.createNote()
                            }
                        }

                        // Lista de Notas
                        ListView {
                            id: notesListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 4
                            model: notesWindow.notes
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: noteItem
                                required property var modelData
                                required property int index

                                width: notesListView.width
                                height: 48
                                radius: 8
                                color: notesWindow.activeIndex === index
                                    ? Theme.tileHigh
                                    : (itemMouse.containsMouse ? Theme.withAlpha(Theme.tileHigh, 0.5) : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4

                                            Text {
                                                text: "󰐃"
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: 11
                                                color: Theme.primary
                                                visible: noteItem.modelData.pinned === true
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: noteItem.modelData.title || notesWindow.extractTitle(noteItem.modelData.content)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.weight: notesWindow.activeIndex === noteItem.index ? Font.DemiBold : Font.Normal
                                                color: notesWindow.activeIndex === noteItem.index ? Theme.textColor : Theme.subtext
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Text {
                                            text: {
                                                const d = new Date(noteItem.modelData.updatedAt || Date.now());
                                                return Qt.formatDateTime(d, "dd/MM hh:mm");
                                            }
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.withAlpha(Theme.subtext, 0.65)
                                        }
                                    }

                                    // Botão Excluir
                                    Rectangle {
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        radius: 11
                                        color: delArea.containsMouse ? Theme.withAlpha(Theme.critical, 0.25) : "transparent"
                                        visible: itemMouse.containsMouse || notesWindow.activeIndex === noteItem.index

                                        Text {
                                            anchors.centerIn: parent
                                            text: "×"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            color: delArea.containsMouse ? Theme.critical : Theme.subtext
                                        }

                                        MouseArea {
                                            id: delArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: notesWindow.deleteNote(noteItem.index)
                                        }
                                    }
                                }

                                MouseArea {
                                    id: itemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        notesWindow.activeIndex = noteItem.index;
                                        if (noteArea) {
                                            noteArea.text = noteItem.modelData.content || "";
                                            noteArea.forceActiveFocus();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Editor de Texto
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "transparent"

                    Flickable {
                        id: flick
                        anchors.fill: parent
                        anchors.margins: 16
                        contentWidth: width
                        contentHeight: noteArea.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            policy: flick.contentHeight > flick.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                            width: 6
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: Theme.withAlpha(Theme.primary, 0.4)
                            }
                        }

                        TextArea {
                            id: noteArea
                            width: flick.width - 12
                            wrapMode: TextArea.Wrap
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.textColor
                            selectionColor: Theme.primary
                            selectedTextColor: Theme.background
                            background: null
                            selectByMouse: true

                            placeholderText: Theme.t("quicknotes.placeholder", "Digite suas anotações aqui...")
                            placeholderTextColor: Theme.withAlpha(Theme.subtext, 0.5)

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    notesWindow.open = false;
                                    event.accepted = true;
                                }
                            }

                            onTextChanged: {
                                if (!notesWindow.ready) return;
                                if (notesWindow.activeIndex >= 0 && notesWindow.activeIndex < notesWindow.notes.length) {
                                    const cur = notesWindow.notes[notesWindow.activeIndex];
                                    if (cur && cur.content !== text) {
                                        cur.content = text;
                                        cur.title = notesWindow.extractTitle(text);
                                        cur.updatedAt = new Date().toISOString();
                                        notesWindow.queueSave();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "quicknotes"

        function toggle(): void {
            if (notesWindow.open) hide();
            else open();
        }

        function open(): void {
            if (notesFile) notesFile.reload();
            notesWindow.open = true;
        }

        function show(): void {
            open();
        }

        function hide(): void {
            notesWindow.open = false;
        }
    }
}
