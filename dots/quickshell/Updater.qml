import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Janela de atualizações: lista o que está pendente em cada origem
// (repositórios do CachyOS, AUR, Flatpak e o próprio rice), a pessoa desmarca
// o que não quer e atualiza o resto sem nenhuma pergunta.
//
// Quem faz o trabalho é o `rice-software update-selected`/`run-job`, solto do
// Quickshell: fechar a janela ou recarregar o shell não interrompe o pacman.
// A janela só acompanha pelo update-job.json e pelo log.
//
// Abre pelo ícone de atualizações da sidebar ou `qs ipc call updater open`.
PanelWindow {
    id: upd

    property bool open: false
    // loading | list | auth | running | done
    property string view: "loading"
    property var info: ({ repo: [], aur: [], flatpak: [], rice: {}, aur_helper: "", checked_at: "" })
    property var sel: ({ repo: true, aur: true, flatpak: true, rice: true })
    property string where: "window"      // window | terminal
    property var job: null               // conteúdo do update-job.json
    property bool sudoNeeded: true
    property string authError: ""
    property string logText: ""
    property var logBuf: []

    readonly property string jobDir: Quickshell.env("XDG_RUNTIME_DIR") + "/hollow-wired"
    readonly property bool jobRunning: !!upd.job && upd.job.state === "running"

    function riceCommits() { return (upd.info.rice && upd.info.rice.commits) ? upd.info.rice.commits : []; }
    function riceCount() { return (upd.info.rice && upd.info.rice.count) ? upd.info.rice.count : 0; }
    function countOf(id) { return id === "rice" ? upd.riceCount() : (upd.info[id] || []).length; }

    // Origens com algo pendente, na ordem em que são atualizadas.
    readonly property var sources: {
        const all = [
            { id: "repo", title: Theme.t("updater.repo", "Repositórios do CachyOS"), sub: "pacman" },
            { id: "aur", title: "AUR", sub: upd.info.aur_helper || "" },
            { id: "flatpak", title: "Flatpak", sub: "" },
            { id: "rice", title: Theme.t("updater.rice", "hollow-wired (o rice)"), sub: "rice-update" }
        ];
        // Mostra toda origem que existe nesta máquina, mesmo em dia: sumir com
        // ela fazia parecer que o Flatpak não era verificado.
        return all.filter(s => s.id === "aur" ? upd.info.aur_helper !== ""
                              : s.id === "flatpak" ? upd.info.has_flatpak !== false : true);
    }
    readonly property int totalCount: {
        let n = 0;
        for (const s of upd.sources) n += upd.countOf(s.id);
        return n;
    }
    readonly property var chosen: upd.sources.filter(s => upd.sel[s.id] && upd.countOf(s.id) > 0).map(s => s.id)
    readonly property int chosenCount: {
        let n = 0;
        for (const id of upd.chosen) n += upd.countOf(id);
        return n;
    }

    function titleOf(id) {
        switch (id) {
        case "repo": return Theme.t("updater.repo", "Repositórios do CachyOS");
        case "aur": return "AUR";
        case "flatpak": return "Flatpak";
        case "rice": return Theme.t("updater.rice", "hollow-wired (o rice)");
        }
        return id;
    }

    function toggleSel(id) {
        const s = Object.assign({}, upd.sel);
        s[id] = !s[id];
        upd.sel = s;
    }

    function refresh() {
        if (listProc.running) return;
        upd.view = "loading";
        listProc.running = true;
    }

    function startUpdate() {
        if (upd.chosen.length === 0 || upd.jobRunning) return;
        const needsSudo = upd.chosen.indexOf("repo") >= 0 || upd.chosen.indexOf("aur") >= 0;
        if (upd.where === "terminal") {
            startProc.pendingInput = "";
            startProc.command = ["rice-software", "update-selected", upd.chosen.join(","), "--terminal"];
            startProc.stdinEnabled = true;
            startProc.running = true;
        } else if (needsSudo && upd.sudoNeeded) {
            upd.authError = "";
            upd.view = "auth";
            pwField.text = "";
            pwField.forceActiveFocus();
        } else {
            upd.submit("");
        }
    }

    function submit(pw) {
        if (startProc.running) return;
        upd.authError = "";
        startProc.pendingInput = pw + "\n";
        startProc.command = ["rice-software", "update-selected", upd.chosen.join(",")];
        startProc.stdinEnabled = true;
        startProc.running = true;
    }

    function resetLog() {
        upd.logBuf = [];
        upd.logText = "";
    }

    // ---------------------------------------------------------- processos
    Process {
        id: listProc
        command: ["rice-software", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { upd.info = JSON.parse(text); } catch (e) {}
                const s = {};
                for (const k of ["repo", "aur", "flatpak", "rice"]) s[k] = true;
                upd.sel = s;
                if (upd.view === "loading") upd.view = "list";
                Qt.callLater(() => listScroll.ScrollBar.vertical.position = 0);
            }
        }
    }
    Process {
        id: sudoProc
        command: ["sudo", "-n", "true"]
        onExited: (code) => upd.sudoNeeded = code !== 0
    }
    Process {
        id: startProc
        property string pendingInput: ""
        stdinEnabled: true
        onStarted: { write(startProc.pendingInput); startProc.pendingInput = ""; stdinEnabled = false; }
        onExited: (code) => {
            if (code === 2) {
                upd.authError = Theme.t("updater.wrong_pw", "Senha incorreta.");
                upd.view = "auth";
                pwField.text = "";
                pwField.forceActiveFocus();
            } else if (code === 0 || code === 3) {
                pwField.text = "";
                upd.resetLog();
                upd.view = "running";
                jobFile.reload();
                if (upd.where === "window") logProc.running = true;
            }
        }
    }
    // Saída do trabalho, só no modo dentro da janela (no terminal ela vai para lá).
    Process {
        id: logProc
        command: ["tail", "-n", "400", "-F", upd.jobDir + "/update-job.log"]
        stdout: SplitParser {
            onRead: (line) => {
                const clean = line.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").replace(/\r/g, "");
                const b = upd.logBuf;
                b.push(clean);
                if (b.length > 400) b.splice(0, b.length - 400);
                upd.logText = b.join("\n");
            }
        }
    }
    FileView {
        id: jobFile
        path: upd.jobDir + "/update-job.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let j = null;
            try { j = JSON.parse(text()); } catch (e) { return; }
            const was = upd.jobRunning;
            upd.job = j;
            if (j.state === "running" && upd.view !== "running") {
                upd.view = "running";
                if (j.mode === "window" && !logProc.running) { upd.resetLog(); logProc.running = true; }
            } else if (j.state !== "running" && (was || upd.view === "running")) {
                upd.view = "done";
                // dá tempo do tail ler as últimas linhas
                logStop.restart();
                Quickshell.execDetached(["qs", "ipc", "call", "sidebar", "check"]);
            }
        }
    }
    Timer { id: logStop; interval: 1500; onTriggered: logProc.running = false }
    // Reserva do watcher: o arquivo só passa a existir no primeiro trabalho
    // depois do boot (/run é tmpfs), e aí o FileView ainda não o observa.
    Timer {
        interval: 2000
        repeat: true
        running: upd.jobRunning || upd.view === "running"
        onTriggered: jobFile.reload()
    }

    // ---------------------------------------------------------- janela
    visible: upd.open
    color: "transparent"
    focusable: true
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-updater"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: upd.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (!upd.open) return;
        sudoProc.running = true;
        jobFile.reload();
        if (upd.jobRunning) {
            upd.view = "running";
            if (upd.job.mode === "window" && !logProc.running) { upd.resetLog(); logProc.running = true; }
        } else if (upd.view !== "done" && upd.view !== "auth") {
            upd.refresh();
        }
        card.forceActiveFocus();
    }

    // ---------------------------------------------------------- componentes
    component Btn: Rectangle {
        id: btn
        property string icon: ""
        property string text: ""
        property bool primary: false
        property bool enabledBtn: true
        signal clicked()
        implicitHeight: 36
        implicitWidth: btn.text === "" ? implicitHeight : btnRow.implicitWidth + 28
        radius: 8
        opacity: btn.enabledBtn ? 1 : 0.45
        color: btn.primary ? (btnArea.pressed ? Theme.withAlpha(Theme.primary, 0.75) : Theme.primary)
                           : (btnArea.containsMouse ? Theme.tileHigh : Theme.withAlpha(Theme.tile, 0.8))
        Behavior on color { ColorAnimation { duration: Theme.ms(120) } }
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 8
            Text {
                visible: btn.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: btn.icon
                font.family: Theme.iconFontFamily
                font.pixelSize: 15
                color: btn.primary ? Theme.background : Theme.textColor
            }
            Text {
                visible: btn.text !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: btn.text
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Medium
                color: btn.primary ? Theme.background : Theme.textColor
            }
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enabledBtn
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    component CheckBox: Rectangle {
        id: cb
        property bool checked: false
        width: 18; height: 18; radius: 5
        color: cb.checked ? Theme.primary : "transparent"
        border.width: cb.checked ? 0 : 1.5
        border.color: Theme.withAlpha(Theme.subtext, 0.6)
        Behavior on color { ColorAnimation { duration: Theme.ms(120) } }
        Text {
            anchors.centerIn: parent
            visible: cb.checked
            text: Theme.icons.check
            font.family: Theme.iconFontFamily
            font.pixelSize: 12
            color: Theme.background
        }
    }

    component SmallText: Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: 12
        color: Theme.withAlpha(Theme.subtext, 0.85)
    }

    // ---------------------------------------------------------- fundo
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, upd.open ? 0.6 : 0)
        Behavior on color { ColorAnimation { duration: Theme.ms(200) } }
        MouseArea { anchors.fill: parent; onClicked: upd.open = false }
    }

    // ---------------------------------------------------------- cartão
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(760, parent.width - 80)
        height: Math.min(680, parent.height - 100)
        radius: 18
        color: Theme.background
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.35)
        focus: true
        Keys.onEscapePressed: upd.open = false
        MouseArea { anchors.fill: parent }   // não fecha ao clicar dentro

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16

            // ---------------- cabeçalho
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text {
                        text: Theme.t("updater.title", "Atualizações")
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        color: Theme.textColor
                    }
                    Text {
                        Layout.fillWidth: true
                        text: {
                            if (upd.view === "loading") return Theme.t("updater.checking", "Procurando atualizações…");
                            if (upd.view === "done") return "";
                            if (upd.view === "running") return Theme.t("updater.sub_running", "Atualizando sem perguntas. Pode fechar esta janela: a atualização continua.");
                            if (upd.totalCount === 0) return Theme.t("updater.none", "Tudo em dia.") + (upd.info.checked_at ? " · " + Theme.t("updater.checked_at", "verificado às %1").replace("%1", upd.info.checked_at) : "");
                            return Theme.t("updater.pending", "%1 pendentes").replace("%1", upd.totalCount)
                                + (upd.info.checked_at ? " · " + Theme.t("updater.checked_at", "verificado às %1").replace("%1", upd.info.checked_at) : "");
                        }
                        wrapMode: Text.WordWrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.withAlpha(Theme.subtext, 0.85)
                    }
                }
                Btn {
                    visible: upd.view === "list" || upd.view === "done"
                    icon: Theme.icons.refresh
                    onClicked: upd.refresh()
                }
                Btn {
                    icon: Theme.icons.close
                    onClicked: upd.open = false
                }
            }

            // ---------------- lista
            ScrollView {
                id: listScroll
                visible: upd.view === "list" || upd.view === "auth" || upd.view === "loading"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: listScroll.availableWidth
                    spacing: 6

                    Text {
                        visible: upd.view === "loading"
                        Layout.topMargin: 40
                        Layout.alignment: Qt.AlignHCenter
                        text: Theme.t("updater.checking_long", "Consultando os repositórios, o AUR e o Flatpak…")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.subtext
                    }

                    Repeater {
                        model: upd.view === "loading" ? [] : upd.sources
                        delegate: ColumnLayout {
                            id: srcBlock
                            required property var modelData
                            readonly property string sid: modelData.id
                            readonly property bool pending: upd.countOf(srcBlock.sid) > 0
                            readonly property bool on: srcBlock.pending && !!upd.sel[srcBlock.sid]
                            // Lista longa começa fechada, para todas as origens caberem na tela.
                            property bool expanded: false
                            readonly property int cap: 6
                            readonly property var items: srcBlock.sid === "rice" ? upd.riceCommits() : (upd.info[srcBlock.sid] || [])
                            Layout.fillWidth: true
                            Layout.bottomMargin: srcBlock.pending ? 10 : 0
                            spacing: 6

                            // Cabeçalho da origem: caixa, nome e contagem.
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 40
                                radius: 10
                                color: headArea.containsMouse ? Theme.withAlpha(Theme.tile, 0.55) : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 12
                                    spacing: 12
                                    CheckBox { checked: srcBlock.on; opacity: srcBlock.pending ? 1 : 0.35 }
                                    Text {
                                        text: srcBlock.modelData.title
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                        color: srcBlock.on ? Theme.textColor : Theme.subtext
                                    }
                                    Text {
                                        visible: srcBlock.modelData.sub !== ""
                                        text: srcBlock.modelData.sub
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.withAlpha(Theme.subtext, 0.7)
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: srcBlock.pending ? upd.countOf(srcBlock.sid) : Theme.t("updater.up_to_date", "em dia")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        color: Theme.subtext
                                    }
                                }
                                MouseArea {
                                    id: headArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: upd.view === "list" && srcBlock.pending
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: upd.toggleSel(srcBlock.sid)
                                }
                            }

                            // Pacotes: nome à esquerda, versões à direita.
                            Rectangle {
                                visible: srcBlock.pending
                                Layout.fillWidth: true
                                implicitHeight: pkgCol.implicitHeight + 12
                                radius: 12
                                color: Theme.withAlpha(Theme.tile, 0.55)
                                opacity: srcBlock.on ? 1 : 0.5
                                ColumnLayout {
                                    id: pkgCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.topMargin: 6
                                    spacing: 0
                                    Repeater {
                                        model: srcBlock.expanded ? srcBlock.items : srcBlock.items.slice(0, srcBlock.cap)
                                        delegate: RowLayout {
                                            id: pkgRow
                                            required property var modelData
                                            readonly property bool isText: typeof pkgRow.modelData === "string"
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 16
                                            Layout.rightMargin: 16
                                            Layout.topMargin: 5
                                            Layout.bottomMargin: 5
                                            spacing: 16
                                            Text {
                                                Layout.fillWidth: true
                                                text: pkgRow.isText ? pkgRow.modelData : pkgRow.modelData.name
                                                elide: Text.ElideRight
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                color: Theme.textColor
                                            }
                                            Text {
                                                visible: !pkgRow.isText
                                                text: pkgRow.isText ? "" : ((pkgRow.modelData.old ? pkgRow.modelData.old + "  →  " : "") + pkgRow.modelData.new)
                                                font.family: Theme.monoFamily
                                                font.pixelSize: 11
                                                color: Theme.withAlpha(Theme.subtext, 0.85)
                                            }
                                        }
                                    }
                                    Text {
                                        visible: srcBlock.items.length > srcBlock.cap
                                        Layout.leftMargin: 16
                                        Layout.topMargin: 5
                                        Layout.bottomMargin: 5
                                        text: srcBlock.expanded ? Theme.t("updater.show_less", "mostrar menos")
                                            : Theme.t("updater.show_all", "mostrar todos os %1").replace("%1", srcBlock.items.length)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.underline: moreArea.containsMouse
                                        color: Theme.subtext
                                        MouseArea {
                                            id: moreArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: srcBlock.expanded = !srcBlock.expanded
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------------- andamento
            ColumnLayout {
                visible: upd.view === "running" || upd.view === "done"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                Repeater {
                    model: upd.job ? upd.job.steps : []
                    delegate: RowLayout {
                        id: stepRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            Layout.preferredWidth: 18
                            horizontalAlignment: Text.AlignHCenter
                            text: stepRow.modelData.state === "ok" ? Theme.icons.check
                                : stepRow.modelData.state === "error" ? Theme.icons.alert
                                : stepRow.modelData.state === "running" ? Theme.icons.refresh : "·"
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 14
                            color: stepRow.modelData.state === "running" ? Theme.primary
                                 : stepRow.modelData.state === "error" ? Theme.critical : Theme.subtext
                            RotationAnimation on rotation {
                                running: stepRow.modelData.state === "running"
                                from: 0; to: 360; duration: 1400; loops: Animation.Infinite
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: upd.titleOf(stepRow.modelData.id)
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: stepRow.modelData.state === "running" ? Font.DemiBold : Font.Normal
                            color: stepRow.modelData.state === "pending" ? Theme.subtext : Theme.textColor
                        }
                        Text {
                            text: stepRow.modelData.state === "ok" ? Theme.t("updater.step_ok", "concluído")
                                : stepRow.modelData.state === "error" ? Theme.t("updater.step_error", "falhou")
                                : stepRow.modelData.state === "running" ? Theme.t("updater.step_running", "atualizando")
                                : Theme.t("updater.step_pending", "na fila")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: stepRow.modelData.state === "error" ? Theme.critical : Theme.subtext
                        }
                    }
                }

                SmallText {
                    visible: !!upd.job && upd.job.mode === "terminal"
                    text: Theme.t("updater.in_terminal", "A atualização está rodando na janela do terminal.")
                }

                // Saída do pacman/yay/flatpak.
                Rectangle {
                    visible: !!upd.job && upd.job.mode === "window"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: Theme.withAlpha(Theme.tile, 0.55)
                    ScrollView {
                        id: logScroll
                        anchors.fill: parent
                        anchors.margins: 12
                        clip: true
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        Text {
                            id: logView
                            width: logScroll.availableWidth
                            text: upd.logText
                            wrapMode: Text.WrapAnywhere
                            font.family: Theme.monoFamily
                            font.pixelSize: 11
                            color: Theme.withAlpha(Theme.textColor, 0.85)
                            onTextChanged: Qt.callLater(() => {
                                const f = logScroll.ScrollBar.vertical;
                                f.position = Math.max(0, 1 - f.size);
                            })
                        }
                    }
                }

                SmallText {
                    visible: upd.view === "done" && !!upd.job
                    color: upd.job && upd.job.state === "error" ? Theme.critical : Theme.textColor
                    text: !upd.job ? "" : (upd.job.state === "error"
                        ? Theme.t("updater.done_error", "Alguma etapa falhou (veja a saída acima). Se o pacman precisava de uma resposta, o cachy-update pergunta em cada passo.")
                        : Theme.t("updater.done_ok", "Atualização concluída."))
                        + (upd.job && upd.job.kernel ? " " + Theme.t("updater.kernel", "O kernel foi atualizado: reinicie para usar a versão nova.") : "")
                }
            }

            // ---------------- rodapé
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                SmallText {
                    visible: upd.view === "list" && upd.sel.aur && !upd.sel.repo && upd.countOf("aur") > 0 && upd.countOf("repo") > 0
                    text: Theme.t("updater.partial_warn", "Atualizar o AUR sem os repositórios pode deixar pacotes compilados contra bibliotecas antigas.")
                }

                // Senha do sudo (só no modo dentro da janela).
                RowLayout {
                    visible: upd.view === "auth"
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: Theme.t("updater.pw_label", "Senha de administrador")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textColor
                    }
                    TextField {
                        id: pwField
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        enabled: !startProc.running
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textColor
                        placeholderText: upd.authError !== "" ? upd.authError : ""
                        placeholderTextColor: upd.authError !== "" ? Theme.critical : Theme.subtext
                        background: Rectangle {
                            radius: 8
                            color: Theme.withAlpha(Theme.tile, 0.8)
                            border.width: pwField.activeFocus ? 1 : 0
                            border.color: Theme.withAlpha(Theme.primary, 0.6)
                        }
                        onAccepted: if (text !== "") upd.submit(text)
                        Keys.onEscapePressed: upd.view = "list"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Onde rodar: dentro da janela (padrão) ou no terminal.
                    Rectangle {
                        visible: upd.view === "list"
                        implicitWidth: whereRow.implicitWidth + 6
                        implicitHeight: 32
                        radius: 9
                        color: Theme.withAlpha(Theme.tile, 0.8)
                        Row {
                            id: whereRow
                            anchors.centerIn: parent
                            spacing: 2
                            Repeater {
                                model: [
                                    { value: "window", label: Theme.t("updater.where_window", "Nesta janela") },
                                    { value: "terminal", label: Theme.t("updater.where_terminal", "No terminal") }
                                ]
                                delegate: Rectangle {
                                    id: segItem
                                    required property var modelData
                                    readonly property bool active: upd.where === segItem.modelData.value
                                    width: segText.implicitWidth + 24
                                    height: 26
                                    radius: 7
                                    color: segItem.active ? Theme.tileHigh : (segArea.containsMouse ? Theme.withAlpha(Theme.tileHigh, 0.45) : "transparent")
                                    Text {
                                        id: segText
                                        anchors.centerIn: parent
                                        text: segItem.modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: segItem.active ? Font.DemiBold : Font.Normal
                                        color: segItem.active ? Theme.textColor : Theme.subtext
                                    }
                                    MouseArea {
                                        id: segArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: upd.where = segItem.modelData.value
                                    }
                                }
                            }
                        }
                    }

                    // Caminho completo, com perguntas (órfãos, cache, .pacnew).
                    Text {
                        visible: upd.view === "list" || (upd.view === "done" && !!upd.job && upd.job.state === "error")
                        text: Theme.t("updater.open_cachy", "Abrir cachy-update")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.underline: cachyArea.containsMouse
                        color: Theme.subtext
                        MouseArea {
                            id: cachyArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached(["kitty", "--class", "cachy-update", "--title", "cachy-update", "-e", "cachy-update"]);
                                upd.open = false;
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Btn {
                        visible: upd.view === "auth"
                        text: Theme.t("updater.cancel", "Voltar")
                        onClicked: upd.view = "list"
                    }
                    Btn {
                        visible: upd.view === "auth"
                        primary: true
                        enabledBtn: pwField.text !== "" && !startProc.running
                        text: Theme.t("updater.confirm", "Atualizar")
                        onClicked: upd.submit(pwField.text)
                    }
                    Btn {
                        visible: upd.view === "list" && upd.totalCount > 0
                        primary: true
                        enabledBtn: upd.chosen.length > 0 && !startProc.running
                        icon: Theme.icons.update
                        text: Theme.t("updater.update_n", "Atualizar (%1)").replace("%1", upd.chosenCount)
                        onClicked: upd.startUpdate()
                    }
                    Btn {
                        visible: upd.view === "done" && !!upd.job && upd.job.kernel
                        text: Theme.t("updater.reboot", "Reiniciar")
                        onClicked: Quickshell.execDetached(["systemctl", "reboot"])
                    }
                    Btn {
                        visible: upd.view === "running" || upd.view === "done"
                        primary: upd.view === "done"
                        text: Theme.t("updater.close", "Fechar")
                        onClicked: {
                            upd.open = false;
                            if (upd.view === "done") upd.view = "loading";
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "updater"
        function open(): void { upd.open = true; }
        function hide(): void { upd.open = false; }
        function toggle(): void { upd.open = !upd.open; }
    }
}
