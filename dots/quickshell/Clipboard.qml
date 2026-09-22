import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Modal nativo de Histórico da Área de Transferência (Super + V) no Quickshell.
// Substitui o Rofi completamente.
//
// Duas abas:
//   • Histórico  — o que o cliphist guardou (texto e imagens), com busca.
//   • Favoritos  — itens fixados pelo usuário, guardados fora do cliphist em
//                  ~/.config/quickshell/clipboard-favorites.json (texto) e em
//                  ~/.local/share/hollow-wired/clipboard-favorites/ (imagens),
//                  então sobrevivem ao "limpar histórico" e ao reboot.
PanelWindow {
    id: clipWindow

    property bool open: false
    property var allItems: []
    property var filteredItems: []
    property int selectedIndex: 0
    property int tab: 0          // 0 = histórico, 1 = favoritos
    property var favorites: []
    property var filteredFavorites: []

    readonly property int rowH: 48
    readonly property string favDir: Quickshell.env("HOME") + "/.local/share/hollow-wired/clipboard-favorites"

    // Só libera o save() depois que o arquivo de favoritos terminar de carregar
    // (leitura é assíncrona). Sem isso, favoritar algo logo após o Quickshell
    // reiniciar gravaria uma lista vazia por cima dos favoritos reais.
    property bool favReady: false

    // Escolher um item cola direto no campo em foco (como no Windows) em vez de
    // só devolver o conteúdo pro clipboard. Ctrl+clique / Ctrl+Enter continua
    // fazendo só a cópia, para quem quer colar depois no lugar que decidir.
    property bool pasteOnPick: true
    property bool prefsReady: false

    function currentList() {
        return clipWindow.tab === 0 ? clipWindow.filteredItems : clipWindow.filteredFavorites;
    }

    function updateFiltered() {
        const q = searchField ? searchField.text.trim().toLowerCase() : "";
        if (!q) {
            filteredItems = allItems;
            filteredFavorites = favorites;
        } else {
            filteredItems = allItems.filter(it => it.content.toLowerCase().includes(q));
            filteredFavorites = favorites.filter(it => (it.preview || "").toLowerCase().includes(q));
        }
        selectedIndex = 0;
    }

    // ---------------------------------------------------------- favoritos
    function isFavorited(content) {
        for (let i = 0; i < favorites.length; i++) {
            if (favorites[i].preview === content) return true;
        }
        return false;
    }

    function saveFavorites() {
        if (!clipWindow.favReady) return;
        favFile.setText(JSON.stringify(favorites, null, 2) + "\n");
        clipWindow.updateFiltered();
    }

    function addFavorite(entry) {
        const list = favorites.slice();
        list.unshift(entry);
        favorites = list;
        saveFavorites();
    }

    function removeFavoriteById(id) {
        const removed = favorites.filter(f => f.id === id);
        favorites = favorites.filter(f => f.id !== id);
        saveFavorites();
        for (let i = 0; i < removed.length; i++) {
            if (removed[i].kind === "image" && removed[i].file) {
                rmProc.path = removed[i].file;
                rmProc.running = true;
            }
        }
    }

    function toggleFavorite(item) {
        // Já favoritado: desfavorita pelo conteúdo mostrado na lista.
        for (let i = 0; i < favorites.length; i++) {
            if (favorites[i].preview === item.content) {
                removeFavoriteById(favorites[i].id);
                return;
            }
        }
        if (item.isImage) {
            favImageProc.pending = item;
            favImageProc.outFile = clipWindow.favDir + "/fav-" + Date.now() + ".png";
            favImageProc.rawLine = item.raw;
            favImageProc.running = true;
        } else {
            favTextProc.pending = item;
            favTextProc.rawLine = item.raw;
            favTextProc.running = true;
        }
    }

    function copyFavorite(fav, alsoPaste) {
        const paste = alsoPaste === undefined ? clipWindow.pasteOnPick : alsoPaste;
        if (fav.kind === "image") {
            copyFavImageProc.paste = paste;
            copyFavImageProc.path = fav.file;
            copyFavImageProc.running = true;
        } else {
            copyFavTextProc.paste = paste;
            copyFavTextProc.payload = fav.text;
            copyFavTextProc.running = true;
        }
        clipWindow.open = false;
    }

    FileView {
        id: favFile
        path: Quickshell.env("HOME") + "/.config/quickshell/clipboard-favorites.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = text().trim();
                if (t) {
                    const parsed = JSON.parse(t);
                    if (Array.isArray(parsed)) clipWindow.favorites = parsed;
                }
            } catch (e) {
                console.log("Clipboard: clipboard-favorites.json inválido:", e);
            } finally {
                clipWindow.favReady = true;
                clipWindow.updateFiltered();
            }
        }
        onLoadFailed: {
            // Primeira execução: arquivo ainda não existe.
            clipWindow.favReady = true;
        }
    }

    FileView {
        id: clipPrefsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/clipboard-prefs.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = text().trim();
                if (t) {
                    const parsed = JSON.parse(t);
                    if (typeof parsed.pasteOnPick === "boolean") clipWindow.pasteOnPick = parsed.pasteOnPick;
                }
            } catch (e) {
                console.log("Clipboard: clipboard-prefs.json inválido:", e);
            } finally {
                clipWindow.prefsReady = true;
            }
        }
        onLoadFailed: clipWindow.prefsReady = true
    }

    // Mesma guarda dos favoritos: sem ela, alternar a opção logo após o
    // Quickshell reiniciar gravaria o valor padrão por cima do escolhido.
    function saveClipPrefs() {
        if (!clipWindow.prefsReady) return;
        clipPrefsFile.setText(JSON.stringify({ pasteOnPick: clipWindow.pasteOnPick }, null, 2));
    }

    // O Ctrl+V sintético sai do rice-paste, que espera o compositor devolver o
    // foco à janela antes de enviar (o modal fica com foco exclusivo).
    Process {
        id: pasteProc
        command: [Quickshell.env("HOME") + "/.local/bin/rice-paste"]
    }

    visible: true
    color: "transparent"
    focusable: true

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
        width: clipWindow.open ? clipWindow.width : 0
        height: clipWindow.open ? clipWindow.height : 0
    }

    WlrLayershell.namespace: "quickshell-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: clipWindow.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (open) {
            searchField.text = "";
            selectedIndex = 0;
            tab = 0;
            loadProc.running = true;
            favFile.reload();
            searchField.forceActiveFocus();
        }
    }

    Process {
        id: loadProc
        // 200 itens: com a barra de rolagem e a busca, a lista curta de 60 só
        // escondia histórico que o cliphist já tinha guardado.
        command: ["bash", "-c", "cliphist list | head -n 200"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const items = [];
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i];
                    if (!line) continue;
                    const tabIdx = line.indexOf("\t");
                    if (tabIdx === -1) continue;
                    const id = line.substring(0, tabIdx);
                    const content = line.substring(tabIdx + 1);
                    const isImage = content.startsWith("[[ binary data");
                    items.push({
                        raw: line,
                        id: id,
                        content: content,
                        isImage: isImage
                    });
                }
                clipWindow.allItems = items;
                clipWindow.updateFiltered();
            }
        }
    }

    Process {
        id: copyProc
        property string rawLine: ""
        property bool paste: false
        command: ["bash", "-c", "printf '%s' \"$RAW\" | cliphist decode | wl-copy"]
        environment: ({ RAW: rawLine })
        // Só manda colar depois que o wl-copy terminou: o contrário colaria o
        // conteúdo antigo, que ainda era o dono da seleção.
        onExited: {
            clipWindow.open = false;
            if (copyProc.paste) pasteProc.running = true;
        }
    }

    Process {
        id: deleteProc
        property string rawLine: ""
        command: ["bash", "-c", "printf '%s' \"$RAW\" | cliphist delete"]
        environment: ({ RAW: rawLine })
        onExited: loadProc.running = true
    }

    Process {
        id: wipeProc
        command: ["cliphist", "wipe"]
        onExited: {
            clipWindow.allItems = [];
            loadProc.running = true;
        }
    }

    // Favoritar texto: decodifica o item e guarda o conteúdo de verdade, não o
    // id do cliphist (que some quando o histórico é limpo).
    Process {
        id: favTextProc
        property string rawLine: ""
        property var pending: null
        command: ["bash", "-c", "printf '%s' \"$RAW\" | cliphist decode"]
        environment: ({ RAW: rawLine })
        stdout: StdioCollector {
            onStreamFinished: {
                if (!favTextProc.pending) return;
                clipWindow.addFavorite({
                    id: "fav-" + Date.now(),
                    kind: "text",
                    preview: favTextProc.pending.content,
                    text: text
                });
                favTextProc.pending = null;
            }
        }
    }

    // Favoritar imagem: copia os bytes para uma pasta própria.
    Process {
        id: favImageProc
        property string rawLine: ""
        property string outFile: ""
        property var pending: null
        command: ["bash", "-c", "mkdir -p \"$(dirname \"$OUT\")\" && printf '%s' \"$RAW\" | cliphist decode > \"$OUT\""]
        environment: ({ RAW: rawLine, OUT: outFile })
        onExited: (code) => {
            if (code === 0 && favImageProc.pending) {
                clipWindow.addFavorite({
                    id: "fav-" + Date.now(),
                    kind: "image",
                    preview: favImageProc.pending.content,
                    file: favImageProc.outFile
                });
            }
            favImageProc.pending = null;
        }
    }

    Process {
        id: copyFavTextProc
        property string payload: ""
        property bool paste: false
        command: ["bash", "-c", "printf '%s' \"$PAYLOAD\" | wl-copy"]
        environment: ({ PAYLOAD: payload })
        onExited: if (copyFavTextProc.paste) pasteProc.running = true
    }

    Process {
        id: copyFavImageProc
        property string path: ""
        property bool paste: false
        command: ["bash", "-c", "wl-copy --type image/png < \"$F\""]
        environment: ({ F: path })
        onExited: if (copyFavImageProc.paste) pasteProc.running = true
    }

    Process {
        id: rmProc
        property string path: ""
        command: ["bash", "-c", "rm -f \"$F\""]
        environment: ({ F: path })
    }

    function copyItem(raw, alsoPaste) {
        copyProc.paste = alsoPaste === undefined ? clipWindow.pasteOnPick : alsoPaste;
        copyProc.rawLine = raw;
        copyProc.running = true;
    }

    function deleteItem(raw) {
        deleteProc.rawLine = raw;
        deleteProc.running = true;
    }

    // Fundo escuro clicável
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: clipWindow.open ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: clipWindow.open = false
        }
    }

    // Janela Central
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 660
        height: 560
        radius: Theme.radius
        color: Theme.surface
        border.color: Theme.withAlpha(Theme.outline, 0.35)
        border.width: 1

        scale: clipWindow.open ? 1 : 0.94
        opacity: clipWindow.open ? 1 : 0
        visible: opacity > 0

        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Row {
                    spacing: 10
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.icons.history
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 20
                        color: Theme.primary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.t("clipboard.title", "Área de Transferência")
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: Theme.textColor
                    }
                }

                Item { Layout.fillWidth: true }

                // Liga/desliga o colar direto. Quando está ligado, escolher um
                // item já digita o Ctrl+V na janela de trás.
                Rectangle {
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: pasteToggleRow.implicitWidth + 20
                    radius: 16
                    color: clipWindow.pasteOnPick
                        ? Theme.withAlpha(Theme.primary, pasteToggleArea.containsMouse ? 0.30 : 0.18)
                        : (pasteToggleArea.containsMouse ? Theme.tileHigh : "transparent")
                    border.width: 1
                    border.color: clipWindow.pasteOnPick ? Theme.withAlpha(Theme.primary, 0.45) : Theme.withAlpha(Theme.subtext, 0.25)

                    Row {
                        id: pasteToggleRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.icons.paste
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 14
                            color: clipWindow.pasteOnPick ? Theme.primary : Theme.subtext
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.t("clipboard.paste_direct", "Colar direto")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: clipWindow.pasteOnPick ? Theme.primary : Theme.subtext
                        }
                    }

                    MouseArea {
                        id: pasteToggleArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            clipWindow.pasteOnPick = !clipWindow.pasteOnPick;
                            clipWindow.saveClipPrefs();
                        }
                    }
                }

                // Botão Limpar Tudo (só faz sentido no histórico)
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    visible: clipWindow.tab === 0
                    color: wipeArea.containsMouse ? Theme.withAlpha(Theme.critical, 0.2) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: Theme.icons.trash
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 15
                        color: wipeArea.containsMouse ? Theme.critical : Theme.subtext
                    }

                    MouseArea {
                        id: wipeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: wipeProc.running = true
                    }
                }

                // Botão Fechar
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: closeArea.containsMouse ? Theme.tileHigh : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: Theme.icons.close
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 15
                        color: closeArea.containsMouse ? Theme.primary : Theme.subtext
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: clipWindow.open = false
                    }
                }
            }

            // ---------------------------------------------------- abas
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { icon: Theme.icons.history, label: Theme.t("clipboard.tab_history", "Histórico") },
                        { icon: Theme.icons.star, label: Theme.t("clipboard.tab_favorites", "Favoritos") }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 17
                        color: clipWindow.tab === index
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (tabArea.containsMouse ? Theme.tileHigh : Theme.tile)
                        border.width: 1
                        border.color: clipWindow.tab === index ? Theme.withAlpha(Theme.primary, 0.55) : "transparent"

                        Behavior on color { ColorAnimation { duration: 140 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.icon
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 14
                                color: clipWindow.tab === index ? Theme.primary : Theme.subtext
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label + (index === 1 && clipWindow.favorites.length > 0
                                    ? "  " + clipWindow.favorites.length : "")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: clipWindow.tab === index ? Font.Bold : Font.Normal
                                color: clipWindow.tab === index ? Theme.textColor : Theme.subtext
                            }
                        }

                        MouseArea {
                            id: tabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                clipWindow.tab = index;
                                clipWindow.selectedIndex = 0;
                                searchField.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // Campo de busca
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: 19
                color: Theme.tile
                border.color: searchField.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.2)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    Text {
                        text: Theme.icons.magnify
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 15
                        color: Theme.subtext
                    }

                    TextInput {
                        id: searchField
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textColor
                        onTextChanged: clipWindow.updateFiltered()

                        Text {
                            visible: !searchField.text
                            text: clipWindow.tab === 0
                                ? Theme.t("clipboard.search_placeholder", "Filtrar histórico...")
                                : Theme.t("clipboard.search_favorites", "Filtrar favoritos...")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.withAlpha(Theme.subtext, 0.6)
                        }

                        Keys.onPressed: event => {
                            const list = clipWindow.currentList();
                            if (event.key === Qt.Key_Escape) {
                                clipWindow.open = false;
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_D || event.key === Qt.Key_S) && (event.modifiers & Qt.ControlModifier)) {
                                // Ctrl+D / Ctrl+S: favorita (ou desfavorita) o item
                                // selecionado sem precisar tirar a mão do teclado.
                                if (list.length > 0 && clipWindow.selectedIndex < list.length) {
                                    const sel = list[clipWindow.selectedIndex];
                                    if (clipWindow.tab === 1) clipWindow.removeFavoriteById(sel.id);
                                    else clipWindow.toggleFavorite(sel);
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab) {
                                clipWindow.tab = clipWindow.tab === 0 ? 1 : 0;
                                clipWindow.selectedIndex = 0;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down) {
                                if (clipWindow.selectedIndex < list.length - 1) {
                                    clipWindow.selectedIndex++;
                                    clipList.positionViewAtIndex(clipWindow.selectedIndex, ListView.Contain);
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up) {
                                if (clipWindow.selectedIndex > 0) {
                                    clipWindow.selectedIndex--;
                                    clipList.positionViewAtIndex(clipWindow.selectedIndex, ListView.Contain);
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (list.length > 0 && clipWindow.selectedIndex < list.length) {
                                    const item = list[clipWindow.selectedIndex];
                                    const paste = !(event.modifiers & Qt.ControlModifier) && clipWindow.pasteOnPick;
                                    if (clipWindow.tab === 0) clipWindow.copyItem(item.raw, paste);
                                    else clipWindow.copyFavorite(item, paste);
                                }
                                event.accepted = true;
                            }
                        }
                    }
                }
            }

            // Aviso de lista vazia
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 40
                visible: clipWindow.currentList().length === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: clipWindow.tab === 0
                    ? Theme.t("clipboard.empty_history", "Nada copiado ainda.")
                    : Theme.t("clipboard.empty_favorites", "Nenhum favorito ainda.\nClique na estrela de um item do histórico para guardá-lo aqui para sempre.")
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.withAlpha(Theme.subtext, 0.8)
            }

            // Lista de itens
            ListView {
                id: clipList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: clipWindow.currentList().length > 0
                clip: true
                spacing: 6
                model: clipWindow.currentList()
                boundsBehavior: Flickable.StopAtBounds

                // Barra de rolagem sempre visível quando há o que rolar: sem ela
                // não dava pra perceber que a lista continuava embaixo.
                ScrollBar.vertical: ScrollBar {
                    id: clipScroll
                    policy: clipList.contentHeight > clipList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                    width: 8
                    padding: 1

                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: clipScroll.pressed
                            ? Theme.primary
                            : (clipScroll.hovered ? Theme.withAlpha(Theme.primary, 0.75) : Theme.withAlpha(Theme.outline, 0.55))
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    background: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: Theme.withAlpha(Theme.outline, 0.12)
                    }
                }

                // Rolagem mais rápida: 3 itens por clique da roda em vez de 1.
                WheelHandler {
                    target: clipList
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        const delta = event.angleDelta.y;
                        if (delta !== 0) {
                            const step = (delta / 120) * ((clipWindow.rowH + clipList.spacing) * 3);
                            const maxY = Math.max(0, clipList.contentHeight - clipList.height);
                            clipList.contentY = Math.max(0, Math.min(maxY, clipList.contentY - step));
                        }
                    }
                }

                delegate: Rectangle {
                    id: rowRect
                    required property var modelData
                    required property int index

                    readonly property bool isFav: clipWindow.tab === 1
                    readonly property string label: isFav ? (modelData.preview || modelData.text || "") : modelData.content
                    readonly property bool isImage: isFav ? modelData.kind === "image" : modelData.isImage
                    readonly property bool starred: isFav || clipWindow.isFavorited(modelData.content)

                    width: clipList.width - (clipScroll.visible ? 16 : 8)
                    height: clipWindow.rowH
                    radius: 10
                    color: {
                        if (clipWindow.selectedIndex === index) return Theme.tileHigh;
                        if (itemArea.containsMouse) return Theme.withAlpha(Theme.tileHigh, 0.7);
                        return Theme.tile;
                    }
                    border.color: clipWindow.selectedIndex === index ? Theme.primary : "transparent"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 10

                        // Ícone (Texto vs Imagem)
                        Text {
                            text: rowRect.isImage ? Theme.icons.camera : Theme.icons.console
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 16
                            color: rowRect.isImage ? Theme.accent1 : Theme.primary
                        }

                        // Conteúdo
                        Text {
                            Layout.fillWidth: true
                            text: rowRect.label
                            font.family: rowRect.isImage ? Theme.fontFamily : Theme.monoFamily
                            font.pixelSize: 12
                            color: Theme.textColor
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        // Botão Favoritar
                        Rectangle {
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            radius: 13
                            color: favArea.containsMouse ? Theme.withAlpha(Theme.accent1, 0.2) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: rowRect.starred ? Theme.icons.star : Theme.icons.starOutline
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 13
                                color: rowRect.starred ? Theme.accent1 : Theme.subtext

                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: favArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (rowRect.isFav) clipWindow.removeFavoriteById(rowRect.modelData.id);
                                    else clipWindow.toggleFavorite(rowRect.modelData);
                                }
                            }
                        }

                        // Botão Excluir
                        Rectangle {
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            radius: 13
                            color: delArea.containsMouse ? Theme.withAlpha(Theme.critical, 0.2) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: Theme.icons.close
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 12
                                color: delArea.containsMouse ? Theme.critical : Theme.subtext
                            }

                            MouseArea {
                                id: delArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (rowRect.isFav) clipWindow.removeFavoriteById(rowRect.modelData.id);
                                    else clipWindow.deleteItem(rowRect.modelData.raw);
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        anchors.rightMargin: 64
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            // Ctrl segurado: só copia, não cola.
                            const paste = !(mouse.modifiers & Qt.ControlModifier) && clipWindow.pasteOnPick;
                            if (rowRect.isFav) clipWindow.copyFavorite(rowRect.modelData, paste);
                            else clipWindow.copyItem(rowRect.modelData.raw, paste);
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            clipWindow.open = !clipWindow.open;
        }

        function open(): void {
            clipWindow.open = true;
        }

        // Abre direto na aba de favoritos (Super + Shift + V).
        function favoritesTab(): void {
            clipWindow.open = true;
            clipWindow.tab = 1;
            clipWindow.selectedIndex = 0;
        }

        function hide(): void {
            clipWindow.open = false;
        }

        function favorites(): string {
            return "" + clipWindow.favorites.length;
        }

        // Favorita o item selecionado (usado pelo atalho Ctrl+D e por scripts).
        function favoriteSelected(): string {
            const list = clipWindow.currentList();
            if (list.length === 0 || clipWindow.selectedIndex >= list.length) return "vazio";
            const sel = list[clipWindow.selectedIndex];
            if (clipWindow.tab === 1) clipWindow.removeFavoriteById(sel.id);
            else clipWindow.toggleFavorite(sel);
            return "ok";
        }
    }
}
