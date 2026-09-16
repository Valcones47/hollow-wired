import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// Aba Snapshots do hub: navegador do snapper (config root).
//
// COMO O ROLLBACK FUNCIONA NESSA MÁQUINA (importante): o fstab monta
// `subvol=/@` fixo e o boot é pelo Limine com limine-snapper-sync. Por isso
// `snapper rollback N` NÃO muda nada no próximo boot. O caminho certo é:
//   1. reiniciar e escolher o snapshot no menu "Snapshots" do Limine
//      (só os MAX_SNAPSHOT_ENTRIES=8 mais recentes aparecem lá);
//   2. já rodando dentro do snapshot, rodar `limine-snapper-restore`, que
//      substitui o @ pelo snapshot (RESTORE_METHOD=replace);
//   3. reiniciar de novo.
// Esta aba guia esses passos e detecta quando o sistema está rodando dentro
// de um snapshot pra oferecer o passo 2 num botão.
//
// sudo sem senha só existe pra pacman e snapper — listar/criar/apagar/status
// usam `sudo -n snapper`. O limine-snapper-restore pede senha num kitty.
Item {
    id: root

    readonly property int bootEntries: 8

    property var snaps: []          // mais novos primeiro, pre+post juntos
    property var selected: null
    property string bootedFrom: ""   // "" = sistema normal; senão número do snapshot em uso
    property string changedCount: ""
    property bool loading: false

    function refresh() {
        loading = true;
        listProc.running = true;
        mountProc.running = true;
    }
    onVisibleChanged: if (visible) refresh()

    Process {
        id: listProc
        command: ["sudo", "-n", "snapper", "--jsonout", "-c", "root", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    const all = JSON.parse(text).root.filter(s => s.number !== 0);
                    const rows = [];
                    for (const s of all) {
                        if (s.type === "post" && all.some(p => p.number === s["pre-number"]))
                            continue;   // aparece junto com o "pre"
                        const post = s.type === "pre" ? all.find(p => p.type === "post" && p["pre-number"] === s.number) : null;
                        rows.push({
                            number: post ? post.number : s.number,
                            pre: s.type === "pre" ? s.number : null,
                            date: (post || s).date,
                            description: s.description || (post ? post.description : "") || "(sem descrição)",
                            kind: s.type === "pre" ? "pacman" : (s.cleanup === "timeline" ? "timeline" : "manual"),
                            userdata: s.userdata
                        });
                    }
                    rows.sort((a, b) => b.number - a.number);
                    const recent = all.map(s => s.number).sort((a, b) => b - a).slice(0, root.bootEntries);
                    for (const r of rows)
                        r.bootable = recent.includes(r.number) || (r.pre !== null && recent.includes(r.pre));
                    root.snaps = rows;
                    if (root.selected)
                        root.selected = rows.find(r => r.number === root.selected.number) || null;
                } catch (e) {
                    console.log("Snapshots: falha ao ler snapper:", e, text.slice(0, 200));
                }
            }
        }
    }

    // Rodando de dentro de um snapshot? (subvol montado em / contém .snapshots/N)
    Process {
        id: mountProc
        command: ["findmnt", "-no", "OPTIONS", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/subvol=\/@\/\.snapshots\/(\d+)\/snapshot/);
                root.bootedFrom = m ? m[1] : "";
            }
        }
    }

    Process {
        id: statusProc
        property int num: 0
        command: ["bash", "-c", "sudo -n snapper -c root status " + num + "..0 2>/dev/null | wc -l"]
        stdout: StdioCollector { onStreamFinished: root.changedCount = text.trim() }
    }
    Process {
        id: diffProc
        property int num: 0
        command: ["kitty", "--class", "rice-snapper", "--title", "Snapshot #" + num + " → agora", "-e", "bash", "-c",
            "echo 'Arquivos alterados desde o snapshot #" + num + " (+ criado, - apagado, c conteúdo, p permissão):'; echo; sudo -n snapper -c root status " + num + "..0 | less"]
    }
    Process {
        id: createProc
        property string desc: ""
        command: ["sudo", "-n", "snapper", "-c", "root", "create", "--cleanup-algorithm", "number", "--description", desc]
        onExited: root.refresh()
    }
    Process {
        id: deleteProc
        property int num: 0
        property var pre: null
        command: pre !== null ? ["sudo", "-n", "snapper", "-c", "root", "delete", String(pre) + "-" + String(num)]
                              : ["sudo", "-n", "snapper", "-c", "root", "delete", String(num)]
        onExited: { root.selected = null; root.refresh(); }
    }
    Process {
        id: restoreProc
        command: ["kitty", "--class", "rice-snapper", "--title", "Restaurar snapshot", "-e", "bash", "-c",
            "sudo limine-snapper-restore; echo; read -rp 'Enter para fechar (reinicie para concluir)'"]
    }

    function select(row) {
        selected = row;
        changedCount = "";
        restoreGuide = false;
        statusProc.num = row.number;
        statusProc.running = true;
    }
    property bool restoreGuide: false

    function fmtDate(s) {
        // "2026-09-15 13:51:26" -> "15/09 13:51"
        const m = s.match(/(\d+)-(\d+)-(\d+) (\d+):(\d+)/);
        return m ? m[3] + "/" + m[2] + "/" + m[1].slice(2) + " " + m[4] + ":" + m[5] : s;
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.gap + 2

        // ================= lista =================
        Rectangle {
            Layout.preferredWidth: 470
            Layout.fillHeight: true
            radius: Theme.tileRadius
            color: Theme.tile

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                // aviso quando rodando de dentro de um snapshot
                Rectangle {
                    visible: root.bootedFrom !== ""
                    Layout.fillWidth: true
                    implicitHeight: bootedCol.implicitHeight + 16
                    radius: 10
                    color: Theme.withAlpha(Theme.critical, 0.35)
                    ColumnLayout {
                        id: bootedCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4
                        PopTitle { text: "Você está rodando o snapshot #" + root.bootedFrom }
                        PopText { text: "Nada aqui é permanente até restaurar."; color: Theme.textColor }
                        PopAction {
                            icon: Theme.icons.restore
                            label: "Tornar este snapshot permanente"
                            needsConfirm: true
                            onActivated: restoreProc.running = true
                        }
                    }
                }

                // criar
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: 9
                        color: Theme.tileHigh
                        border.width: descInput.activeFocus ? 1 : 0
                        border.color: Theme.primary
                        TextInput {
                            id: descInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.textColor
                            clip: true
                            onAccepted: createBtn.activated()
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: descInput.text === "" && !descInput.activeFocus
                                text: "Descrição do novo snapshot…"
                                font: descInput.font
                                color: Theme.subtext
                            }
                        }
                    }
                    PopAction {
                        id: createBtn
                        Layout.fillWidth: false
                        icon: Theme.icons.plus
                        label: createProc.running ? "Criando…" : "Criar"
                        onActivated: {
                            if (createProc.running) return;
                            createProc.desc = descInput.text.trim() || "manual-" + Qt.formatDateTime(new Date(), "yyyy-MM-dd-HHmm");
                            descInput.text = "";
                            createProc.running = true;
                        }
                    }
                }

                PopText {
                    text: root.loading && root.snaps.length === 0 ? "Carregando…"
                        : root.snaps.length + " snapshots · ícone de boot = aparece no menu do Limine"
                    font.pixelSize: 11
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 3
                    model: root.snaps
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: rowItem
                        required property var modelData
                        readonly property bool isSel: root.selected && root.selected.number === modelData.number
                        width: list.width
                        implicitHeight: 42
                        radius: 9
                        color: isSel ? Theme.withAlpha(Theme.primary, 0.25) : rowArea.containsMouse ? Theme.tileHigh : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10
                            Text {
                                Layout.preferredWidth: 42
                                text: "#" + rowItem.modelData.number
                                font.family: Theme.monoFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: rowItem.isSel ? Theme.primary : Theme.textColor
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: rowItem.modelData.description
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.textColor
                                }
                                Text {
                                    text: root.fmtDate(rowItem.modelData.date) + " · " + rowItem.modelData.kind
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.subtext
                                }
                            }
                            Text {
                                visible: rowItem.modelData.bootable
                                text: Theme.icons.power
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 14
                                color: Theme.primary
                            }
                        }
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.select(rowItem.modelData)
                        }
                    }
                }
            }
        }

        // ================= detalhes =================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.tileRadius
            color: Theme.tile

            PopText {
                anchors.centerIn: parent
                visible: root.selected === null
                text: "Selecione um snapshot"
            }

            Flickable {
                anchors.fill: parent
                anchors.margins: 14
                visible: root.selected !== null
                contentHeight: detail.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: detail
                    width: parent.width
                    spacing: 5

                    PopTitle {
                        Layout.fillWidth: true
                        text: root.selected ? "#" + root.selected.number + (root.selected.pre !== null ? " (antes: #" + root.selected.pre + ")" : "") : ""
                        font.pixelSize: 16
                    }
                    PopText {
                        Layout.fillWidth: true
                        text: root.selected ? root.selected.description : ""
                        wrapMode: Text.Wrap
                        color: Theme.textColor
                    }
                    PopText { text: root.selected ? root.fmtDate(root.selected.date) + " · " + root.selected.kind : "" }
                    PopText {
                        text: root.changedCount === "" ? "Contando arquivos alterados desde então…"
                            : root.changedCount + " arquivos mudaram desde então"
                    }
                    PopText {
                        visible: root.selected !== null && root.selected.pre !== null
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "Snapshot automático do pacman: o #" + (root.selected ? root.selected.pre : "") + " é o estado antes da instalação."
                    }

                    PopAction {
                        Layout.topMargin: 8
                        icon: Theme.icons.fileCompare
                        label: "Ver arquivos alterados"
                        onActivated: {
                            diffProc.num = root.selected.pre !== null ? root.selected.pre : root.selected.number;
                            diffProc.running = true;
                        }
                    }
                    PopAction {
                        icon: Theme.icons.restore
                        label: "Restaurar este snapshot…"
                        selected: root.restoreGuide
                        onActivated: root.restoreGuide = !root.restoreGuide
                    }

                    // passo a passo do restore via Limine
                    Rectangle {
                        visible: root.restoreGuide
                        Layout.fillWidth: true
                        implicitHeight: guide.implicitHeight + 20
                        radius: 10
                        color: Theme.tileHigh
                        ColumnLayout {
                            id: guide
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4
                            PopTitle { text: root.selected && root.selected.bootable ? "Como restaurar" : "Esse snapshot não está no menu de boot" }
                            PopText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: Theme.textColor
                                text: root.selected && root.selected.bootable
                                    ? "1. Reinicie e, no menu do Limine, abra “Snapshots” e escolha o #" + (root.selected.pre !== null ? root.selected.pre + " (antes) ou #" + root.selected.number : root.selected.number) + ".\n"
                                      + "2. Com o sistema aberto nele, volte nesta aba: vai aparecer “Tornar este snapshot permanente”.\n"
                                      + "3. Reinicie de novo. Pronto."
                                    : "O Limine só guarda os 8 snapshots mais recentes. Pra voltar a um mais antigo, use o btrfs-assistant (instalado) ou peça ajuda."
                            }
                            PopText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: 11
                                text: "Obs.: “snapper rollback” não funciona nesse sistema (fstab monta subvol=/@ fixo)."
                            }
                        }
                    }

                    PopAction {
                        visible: root.selected !== null && root.selected.number !== Number(root.bootedFrom)
                        icon: Theme.icons.trash
                        label: root.selected && root.selected.pre !== null ? "Apagar par #" + root.selected.pre + "–#" + root.selected.number : "Apagar snapshot"
                        needsConfirm: true
                        onActivated: {
                            deleteProc.num = root.selected.number;
                            deleteProc.pre = root.selected.pre;
                            deleteProc.running = true;
                        }
                    }
                }
            }
        }
    }
}
