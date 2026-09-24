import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Janela flutuante de Nota Destacada (Sticky Note) que sobrepõe apps.
// Arrastável pelo cabeçalho, redimensionável pelo canto inferior direito.
// Auto-save contínuo sincronizado com ~/.config/hollow-wired/quicknotes.json.
PanelWindow {
    id: stickyWindow

    property bool open: false
    property var notes: []
    property var currentNote: null
    property bool ready: false
    property real cardOpacity: 0.94

    visible: true
    color: "transparent"
    focusable: true

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore

    // Máscara crucial: apenas o cartão flutuante captura cliques!
    // Todo o restante da tela atravessa para os aplicativos em segundo plano.
    mask: Region {
        item: stickyWindow.open && stickyWindow.currentNote !== null ? stickyCard : null
    }

    WlrLayershell.namespace: "quickshell-sticky-note"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: stickyWindow.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    FileView {
        id: notesFile
        path: Quickshell.env("HOME") + "/.config/hollow-wired/quicknotes.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: stickyWindow.loadFromText(text())
        onLoadFailed: stickyWindow.ready = true
    }

    function loadFromText(t) {
        if (!t) return;
        try {
            const parsed = JSON.parse(t.trim());
            if (Array.isArray(parsed) && parsed.length > 0) {
                stickyWindow.notes = parsed;
                const p = parsed.find(n => n.pinned === true);
                if (p) {
                    stickyWindow.currentNote = p;
                    stickyWindow.open = true;
                    const maxW = stickyWindow.width > 200 ? stickyWindow.width : 1920;
                    const maxH = stickyWindow.height > 200 ? stickyWindow.height : 1080;
                    if (p.pinX !== undefined && p.pinY !== undefined) {
                        stickyCard.x = Math.max(10, Math.min(maxW - 100, p.pinX));
                        stickyCard.y = Math.max(10, Math.min(maxH - 100, p.pinY));
                    }
                    if (p.pinW !== undefined && p.pinH !== undefined) {
                        stickyCard.width = Math.max(260, Math.min(maxW - 20, p.pinW));
                        stickyCard.height = Math.max(180, Math.min(maxH - 20, p.pinH));
                    }
                    if (noteArea && noteArea.text !== p.content) {
                        noteArea.text = p.content || "";
                    }
                } else {
                    stickyWindow.open = false;
                    stickyWindow.currentNote = null;
                }
            }
        } catch (e) {
            console.log("StickyNote: erro ao ler quicknotes.json:", e);
        } finally {
            stickyWindow.ready = true;
        }
    }

    Timer {
        id: autoSaveTimer
        interval: 350
        repeat: false
        onTriggered: stickyWindow.saveNotes()
    }

    function queueSave() {
        if (!stickyWindow.ready) return;
        autoSaveTimer.restart();
    }

    function saveNotes() {
        if (!stickyWindow.ready) return;
        try {
            notesFile.setText(JSON.stringify(stickyWindow.notes, null, 2) + "\n");
        } catch (e) {
            console.log("StickyNote: erro ao salvar:", e);
        }
    }

    function saveGeometry() {
        if (!stickyWindow.currentNote) return;
        stickyWindow.currentNote.pinX = stickyCard.x;
        stickyWindow.currentNote.pinY = stickyCard.y;
        stickyWindow.currentNote.pinW = stickyCard.width;
        stickyWindow.currentNote.pinH = stickyCard.height;
        stickyWindow.saveNotes();
    }

    function pinNote(note) {
        if (!note || !stickyWindow.notes) return;
        for (let i = 0; i < stickyWindow.notes.length; i++) {
            stickyWindow.notes[i].pinned = (stickyWindow.notes[i].id === note.id);
        }
        stickyWindow.currentNote = note;
        note.pinned = true;
        stickyWindow.saveNotes();
        stickyWindow.open = true;
        if (noteArea && noteArea.text !== note.content) {
            noteArea.text = note.content || "";
        }
    }

    function unpinAndClose() {
        if (stickyWindow.currentNote) {
            stickyWindow.currentNote.pinned = false;
            stickyWindow.saveNotes();
        }
        stickyWindow.open = false;
        stickyWindow.currentNote = null;
    }

    function returnToMainNotes() {
        stickyWindow.unpinAndClose();
        Quickshell.execDetached(["quickshell", "ipc", "call", "quicknotes", "open"]);
    }

    function cycleOpacity() {
        if (cardOpacity > 0.90) cardOpacity = 0.78;
        else if (cardOpacity > 0.70) cardOpacity = 0.55;
        else cardOpacity = 0.95;
    }

    // Cartão da Nota Flutuante
    Rectangle {
        id: stickyCard
        visible: stickyWindow.open && stickyWindow.currentNote !== null
        x: stickyWindow.width > 400 ? stickyWindow.width - 380 : 40
        y: 80
        width: 340
        height: 280
        radius: 14
        color: Theme.mix(Theme.background, "#000000", 0.40)
        opacity: stickyWindow.cardOpacity
        border.color: Theme.withAlpha(Theme.primary, 0.60)
        border.width: 1.5
        clip: true

        Behavior on opacity { NumberAnimation { duration: 150 } }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---------------- Barra de Título / Drag Handle ----------------
            Rectangle {
                id: titleBar
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                color: Theme.withAlpha(Theme.tile, 0.75)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.20)

                // Drag handle para arrastar a janela
                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    anchors.rightMargin: 84
                    cursorShape: Qt.SizeAllCursor
                    drag.target: stickyCard
                    drag.minimumX: 10
                    drag.maximumX: stickyWindow.width - stickyCard.width - 10
                    drag.minimumY: 10
                    drag.maximumY: stickyWindow.height - stickyCard.height - 10
                    onReleased: stickyWindow.saveGeometry()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 6

                    Text {
                        text: "󰐃"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 14
                        color: Theme.primary
                    }

                    Text {
                        Layout.fillWidth: true
                        text: stickyWindow.currentNote ? (stickyWindow.currentNote.title || "Nota rápida") : "Nota"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Theme.textColor
                        elide: Text.ElideRight
                    }

                    // Botão alternar opacidade
                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 12
                        color: opacArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "󰃞"
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 13
                            color: Theme.subtext
                        }
                        MouseArea {
                            id: opacArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: stickyWindow.cycleOpacity()
                        }
                    }

                    // Botão Voltar ao Bloco de Notas principal
                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 12
                        color: expArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "󰍍"
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 13
                            color: Theme.subtext
                        }
                        MouseArea {
                            id: expArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: stickyWindow.returnToMainNotes()
                        }
                    }

                    // Botão Fechar / Desafixar
                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 12
                        color: closePinArea.containsMouse ? Theme.withAlpha(Theme.critical, 0.25) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: closePinArea.containsMouse ? Theme.critical : Theme.subtext
                        }
                        MouseArea {
                            id: closePinArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: stickyWindow.unpinAndClose()
                        }
                    }
                }
            }

            // ---------------- Área do Editor ----------------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"

                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.margins: 10
                    contentWidth: width
                    contentHeight: noteArea.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        policy: flick.contentHeight > flick.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                        width: 5
                        contentItem: Rectangle {
                            implicitWidth: 5
                            radius: 2.5
                            color: Theme.withAlpha(Theme.primary, 0.4)
                        }
                    }

                    TextArea {
                        id: noteArea
                        width: flick.width - 8
                        wrapMode: TextArea.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textColor
                        selectionColor: Theme.primary
                        selectedTextColor: Theme.background
                        background: null
                        selectByMouse: true

                        placeholderText: Theme.t("quicknotes.placeholder", "Digite suas anotações aqui...")
                        placeholderTextColor: Theme.withAlpha(Theme.subtext, 0.5)

                        onTextChanged: {
                            if (!stickyWindow.ready || !stickyWindow.currentNote) return;
                            if (stickyWindow.currentNote.content !== text) {
                                stickyWindow.currentNote.content = text;
                                const lines = text.trim().split("\n");
                                let t = "Nova nota";
                                for (let i = 0; i < lines.length; i++) {
                                    const l = lines[i].trim().replace(/^[#\-*>\s]+/, "");
                                    if (l.length > 0) { t = l.slice(0, 28); break; }
                                }
                                stickyWindow.currentNote.title = t;
                                stickyWindow.currentNote.updatedAt = new Date().toISOString();
                                stickyWindow.queueSave();
                            }
                        }
                    }
                }
            }
        }

        // ---------------- Handle de Redimensionamento (Canto Inferior Direito) ----------------
        Item {
            id: resizeHandle
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 18
            height: 18
            z: 10

            Canvas {
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = Theme.withAlpha(Theme.subtext, 0.40);
                    ctx.lineWidth = 1.5;
                    ctx.beginPath();
                    ctx.moveTo(12, 16); ctx.lineTo(16, 12); ctx.stroke();
                    ctx.beginPath();
                    ctx.moveTo(7, 16); ctx.lineTo(16, 7); ctx.stroke();
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeFDiagCursor

                onPositionChanged: mouse => {
                    if (pressed) {
                        const winPos = mapToItem(stickyWindow, mouse.x, mouse.y);
                        const newW = Math.max(260, Math.min(stickyWindow.width - stickyCard.x - 10, winPos.x - stickyCard.x));
                        const newH = Math.max(180, Math.min(stickyWindow.height - stickyCard.y - 10, winPos.y - stickyCard.y));
                        stickyCard.width = newW;
                        stickyCard.height = newH;
                    }
                }

                onReleased: stickyWindow.saveGeometry()
            }
        }
    }

    IpcHandler {
        target: "stickynote"

        function open(): void {
            if (notesFile) {
                notesFile.reload();
                if ((!stickyWindow.notes || stickyWindow.notes.length === 0) && notesFile.text()) {
                    stickyWindow.loadFromText(notesFile.text());
                }
            }
            const p = stickyWindow.notes ? stickyWindow.notes.find(n => n.pinned === true) : null;
            if (p) {
                stickyWindow.currentNote = p;
                stickyWindow.open = true;
                if (noteArea && noteArea.text !== p.content) {
                    noteArea.text = p.content || "";
                }
            } else if (stickyWindow.notes && stickyWindow.notes.length > 0) {
                stickyWindow.pinNote(stickyWindow.notes[0]);
            } else {
                stickyWindow.open = true;
            }
        }

        function show(): void { open(); }

        function hide(): void {
            stickyWindow.open = false;
        }

        function toggle(): void {
            if (stickyWindow.open) hide();
            else open();
        }
    }
}
