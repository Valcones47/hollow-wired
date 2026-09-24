import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Barra de IA (Super + Ctrl + A): conversa e tradução pelo rice-ai.
// Provedores: Ollama (local) ou Gemini/OpenAI com a chave do usuário, que o
// rice-ai guarda em ~/.config/hollow-wired/ai-keys.json (600). A conversa fica
// só na memória: fechar o shell apaga.
PanelWindow {
    id: ai

    property bool open: false
    visible: open || slide.x < slide.width
    color: "transparent"
    focusable: true
    anchors { top: true; bottom: true; right: true }
    implicitWidth: 440
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-ai"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property string tab: "chat"              // chat | translate
    property var messages: []                // [{ role, content }]
    property bool busy: false
    property string provider: "ollama"
    property string model: ""
    property var hasKey: ({})
    property string target: "pt"
    property string translation: ""

    onOpenChanged: if (open) { statusProc.running = true; focusTimer.restart(); }
    Timer { id: focusTimer; interval: 60; onTriggered: (ai.tab === "chat" ? chatInput : trInput).forceActiveFocus() }

    // ---------- rice-ai ----------
    Process {
        id: statusProc
        command: ["rice-ai", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    ai.provider = d.provider;
                    ai.model = d.model || "";
                    ai.hasKey = d.hasKey || {};
                } catch (e) {}
            }
        }
    }
    Process {
        id: setProc
        onExited: statusProc.running = true
    }
    function run(args) { setProc.command = ["rice-ai"].concat(args); setProc.running = true; }

    // Pedido com a entrada padrão (a conversa e a chave não vão para a linha
    // de comando, que outros processos conseguem ler).
    property string pendingInput: ""
    property string pendingKind: ""
    Process {
        id: askProc
        stdinEnabled: true
        onStarted: { write(ai.pendingInput); stdinEnabled = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                if (ai.pendingKind === "chat") {
                    ai.messages = ai.messages.concat([{ role: out.startsWith("ERRO:") ? "error" : "assistant", content: out.replace(/^ERRO: /, "") }]);
                    chatList.positionViewAtEnd();
                } else if (ai.pendingKind === "translate") {
                    ai.translation = out;
                } else if (ai.pendingKind === "key") {
                    statusProc.running = true;
                }
                ai.busy = false;
            }
        }
        onExited: ai.busy = false
    }
    function start(kind, args, input) {
        if (askProc.running) return;
        ai.pendingKind = kind;
        ai.pendingInput = input;
        askProc.stdinEnabled = true;
        askProc.command = ["rice-ai"].concat(args);
        ai.busy = kind !== "key";
        askProc.running = true;
    }
    function send(text) {
        const t = text.trim();
        if (t === "" || ai.busy) return;
        ai.messages = ai.messages.concat([{ role: "user", content: t }]);
        const history = ai.messages.filter(m => m.role === "user" || m.role === "assistant");
        start("chat", ["ask"], JSON.stringify(history));
        chatList.positionViewAtEnd();
    }

    IpcHandler {
        target: "ai"
        function toggle(): void { ai.open = !ai.open; }
        function open(): void { ai.open = true; }
        function close(): void { ai.open = false; }
    }

    // ---------- componentes ----------
    component Seg: Rectangle {
        id: seg
        property var options: []
        property string current: ""
        signal picked(string value)
        implicitWidth: segRow.implicitWidth + 6
        implicitHeight: 30
        radius: 9
        color: Theme.withAlpha(Theme.background, 0.55)
        Row {
            id: segRow
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: seg.options
                delegate: Rectangle {
                    id: si
                    required property var modelData
                    readonly property bool on: seg.current === si.modelData.value
                    width: siText.implicitWidth + 20
                    height: 24
                    radius: 7
                    color: si.on ? Theme.tileHigh : (siArea.containsMouse ? Theme.withAlpha(Theme.tileHigh, 0.45) : "transparent")
                    Text {
                        id: siText
                        anchors.centerIn: parent
                        text: si.modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: si.on ? Font.DemiBold : Font.Normal
                        color: si.on ? Theme.textColor : Theme.subtext
                    }
                    MouseArea {
                        id: siArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(si.modelData.value)
                    }
                }
            }
        }
    }
    component Btn: Rectangle {
        id: b
        property string label: ""
        property bool accent: false
        signal clicked()
        implicitWidth: bText.implicitWidth + 24
        implicitHeight: 30
        radius: 8
        color: b.accent ? (bArea.containsMouse ? Theme.primary : Theme.withAlpha(Theme.primary, 0.85))
                        : (bArea.containsMouse ? Theme.tileHigh : Theme.tile)
        opacity: b.enabled ? 1 : 0.5
        Text {
            id: bText
            anchors.centerIn: parent
            text: b.label
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: b.accent ? Theme.background : Theme.textColor
        }
        MouseArea {
            id: bArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (b.enabled) b.clicked()
        }
    }
    component Box: Rectangle {
        radius: 10
        color: Theme.withAlpha(Theme.background, 0.55)
    }

    // ---------- cartão ----------
    Item {
        id: slide
        width: parent.width
        height: parent.height
        x: ai.open ? 0 : width
        Behavior on x { NumberAnimation { duration: Theme.ms(240); easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: Theme.waybarHeight + 8
            anchors.bottomMargin: 10
            anchors.rightMargin: 10
            radius: Theme.radius + 4
            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.96)
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.3)

            Keys.onEscapePressed: ai.open = false

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // cabeçalho
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: Theme.t("ai.title", "Assistente")
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Theme.textColor
                    }
                    Seg {
                        options: [{ value: "chat", label: Theme.t("ai.tab_chat", "Conversa") },
                                  { value: "translate", label: Theme.t("ai.tab_translate", "Tradução") }]
                        current: ai.tab
                        onPicked: v => { ai.tab = v; focusTimer.restart(); }
                    }
                    Text {
                        text: Theme.icons.close
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 14
                        color: closeArea.containsMouse ? Theme.textColor : Theme.subtext
                        MouseArea { id: closeArea; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: ai.open = false }
                    }
                }

                // provedor e chave
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Seg {
                        options: [{ value: "ollama", label: "Ollama" }, { value: "gemini", label: "Gemini" }, { value: "openai", label: "OpenAI" }]
                        current: ai.provider
                        onPicked: v => { ai.provider = v; ai.run(["set-provider", v]); }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: ai.model || (ai.provider === "ollama" ? Theme.t("ai.no_model", "sem modelo") : "")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: ai.provider !== "ollama"
                    spacing: 8
                    Box {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        visible: !ai.hasKey[ai.provider]
                        TextInput {
                            id: keyInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.textColor
                            clip: true
                            onAccepted: { ai.start("key", ["set-key", ai.provider], text); text = ""; }
                        }
                        Text {
                            anchors.fill: keyInput
                            verticalAlignment: Text.AlignVCenter
                            visible: keyInput.text === ""
                            text: Theme.t("ai.key_ph", "Chave de API (Enter salva)")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.withAlpha(Theme.subtext, 0.7)
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!ai.hasKey[ai.provider]
                        text: Theme.t("ai.key_saved", "Chave salva neste computador")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                    Text {
                        visible: !!ai.hasKey[ai.provider]
                        text: Theme.t("ai.key_forget", "esquecer")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.underline: forgetArea.containsMouse
                        color: Theme.subtext
                        MouseArea { id: forgetArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ai.run(["forget-key", ai.provider]) }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.outline, 0.25) }

                // ================= conversa =================
                ListView {
                    id: chatList
                    visible: ai.tab === "chat"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 10
                    model: ai.messages
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Item {
                        id: msg
                        required property var modelData
                        readonly property bool mine: msg.modelData.role === "user"
                        width: chatList.width
                        height: msgBox.height
                        Rectangle {
                            id: msgBox
                            anchors.right: msg.mine ? parent.right : undefined
                            anchors.left: msg.mine ? undefined : parent.left
                            width: msg.mine ? Math.min(parent.width * 0.85, msgText.implicitWidth + 24) : parent.width
                            height: msgText.implicitHeight + (msg.mine ? 16 : 4)
                            radius: 10
                            color: msg.mine ? Theme.tileHigh : "transparent"
                            TextEdit {
                                id: msgText
                                anchors.fill: parent
                                anchors.leftMargin: msg.mine ? 12 : 2
                                anchors.rightMargin: msg.mine ? 12 : 2
                                anchors.topMargin: msg.mine ? 8 : 2
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                text: msg.modelData.content
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: msg.modelData.role === "error" ? Theme.critical : Theme.textColor
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 20
                        visible: chatList.count === 0
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: ai.provider === "ollama"
                            ? Theme.t("ai.empty_local", "Pergunte qualquer coisa. Com o Ollama, tudo roda neste computador.")
                            : Theme.t("ai.empty_cloud", "Pergunte qualquer coisa. O texto vai para o serviço escolhido.")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.subtext
                    }
                }
                Text {
                    visible: ai.tab === "chat" && ai.busy
                    text: Theme.t("ai.thinking", "respondendo…")
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.subtext
                }
                RowLayout {
                    visible: ai.tab === "chat"
                    Layout.fillWidth: true
                    spacing: 8
                    Box {
                        Layout.fillWidth: true
                        implicitHeight: Math.min(120, Math.max(36, chatInput.implicitHeight + 16))
                        TextEdit {
                            id: chatInput
                            anchors.fill: parent
                            anchors.margins: 8
                            wrapMode: TextEdit.Wrap
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.textColor
                            Keys.onPressed: event => {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                    ai.send(text);
                                    text = "";
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape) {
                                    ai.open = false;
                                    event.accepted = true;
                                }
                            }
                        }
                        Text {
                            anchors.fill: chatInput
                            visible: chatInput.text === ""
                            text: Theme.t("ai.input_ph", "Mensagem (Enter envia, Shift+Enter quebra linha)")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.withAlpha(Theme.subtext, 0.7)
                        }
                    }
                    Btn {
                        label: Theme.t("ai.clear", "Limpar")
                        enabled: ai.messages.length > 0 && !ai.busy
                        onClicked: ai.messages = []
                    }
                }

                // ================= tradução =================
                Box {
                    visible: ai.tab === "translate"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    TextEdit {
                        id: trInput
                        anchors.fill: parent
                        anchors.margins: 10
                        wrapMode: TextEdit.Wrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textColor
                        Keys.onEscapePressed: ai.open = false
                    }
                    Text {
                        anchors.fill: trInput
                        visible: trInput.text === ""
                        text: Theme.t("ai.tr_ph", "Cole o texto aqui")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.withAlpha(Theme.subtext, 0.7)
                    }
                }
                RowLayout {
                    visible: ai.tab === "translate"
                    Layout.fillWidth: true
                    spacing: 8
                    Seg {
                        options: [{ value: "pt", label: "PT" }, { value: "en", label: "EN" }, { value: "es", label: "ES" }, { value: "ja", label: "JA" }]
                        current: ai.target
                        onPicked: v => ai.target = v
                    }
                    Item { Layout.fillWidth: true }
                    Btn {
                        label: ai.busy ? Theme.t("ai.translating", "Traduzindo…") : Theme.t("ai.translate", "Traduzir")
                        accent: true
                        enabled: !ai.busy && trInput.text.trim() !== ""
                        onClicked: ai.start("translate", ["translate", ai.target], trInput.text)
                    }
                }
                Box {
                    visible: ai.tab === "translate"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    TextEdit {
                        anchors.fill: parent
                        anchors.margins: 10
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        text: ai.translation.replace(/^ERRO: /, "")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: ai.translation.startsWith("ERRO:") ? Theme.critical : Theme.textColor
                    }
                }
                RowLayout {
                    visible: ai.tab === "translate" && ai.translation !== "" && !ai.translation.startsWith("ERRO:")
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Btn {
                        label: Theme.t("ai.copy", "Copiar")
                        onClicked: Quickshell.execDetached(["wl-copy", "--", ai.translation])
                    }
                }
            }
        }
    }
}
