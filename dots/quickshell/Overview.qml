import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import "."

// Visão geral (Super + Tab): as áreas de trabalho num carrossel 3D, cada uma
// com as janelas ao vivo na posição em que estão, e embaixo uma fileira com
// todos os apps abertos.
//
// É o "Visão de Tarefas" do Windows: dá para ver onde cada coisa está sem
// decorar números de workspace.
//   ← → / Tab / roda do mouse / Super+Tab de novo : anda no carrossel
//   Enter ou clique na área do meio                 : vai para ela
//   clique numa janela                              : foca essa janela
//   1..9                                            : pula direto
//   Esc ou clique fora                              : fecha
PanelWindow {
    id: ov

    property bool open: false
    // 0 → 1 na abertura; os cartões entram escalonados a partir dele.
    property real shown: 0

    visible: false
    color: "transparent"
    focusable: true
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ---------- dados ----------
    // [{ kind: "ws"|"special"|"new", id, name, label, wins: [{ x, y, w, h, title, cls, top }] }]
    property var spaces: []
    property var allWins: []
    property int current: 0
    // Posição contínua do carrossel (anima com mola até `current`).
    property real pos: 0
    Behavior on pos {
        enabled: ov.open
        SpringAnimation { spring: 3.2; damping: 0.3; epsilon: 0.002 }
    }
    onCurrentChanged: pos = current

    property real monAspect: 16 / 9

    // Áreas de trabalho na vertical (rice-workspace-layout): o carrossel
    // empilha de cima para baixo e gira no eixo horizontal.
    property bool vertical: false
    FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/workspace-layout"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: ov.vertical = text().trim() === "vertical"
        onLoadFailed: ov.vertical = false
    }
    property string wallpaper: ""

    onOpenChanged: {
        if (open) {
            closeTimer.stop();
            visible = true;
            shown = 0;
            showAnim.restart();
            focusTimer.restart();
        } else {
            hideAnim.restart();
            closeTimer.restart();
        }
    }
    NumberAnimation { id: showAnim; target: ov; property: "shown"; to: 1; duration: 520; easing.type: Easing.OutCubic }
    NumberAnimation { id: hideAnim; target: ov; property: "shown"; to: 0; duration: 200; easing.type: Easing.InCubic }
    Timer { id: closeTimer; interval: 210; onTriggered: ov.visible = false }
    Timer { id: focusTimer; interval: 1; onTriggered: keys.forceActiveFocus() }

    function show() {
        if (ov.open || loadProc.running) return;
        Hyprland.refreshToplevels();
        loadProc.running = true;
    }
    function hide() { ov.open = false; }
    function step(d) {
        if (!ov.open) { ov.show(); return; }
        if (ov.spaces.length === 0) return;
        ov.current = Math.max(0, Math.min(ov.spaces.length - 1, ov.current + d));
    }

    function goTo(i) {
        const s = ov.spaces[i];
        if (!s) return;
        ov.open = false;
        if (s.kind === "special") {
            if (!s.visibleNow)
                Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + s.name.replace(/^special:/, "") + '")');
        } else {
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + s.id + " })");
        }
    }
    // Focar uma janela com o overlay ainda segurando o teclado (foco
    // exclusivo) é recusado pelo Hyprland: nada acontecia ao clicar numa
    // janela. O foco vai só depois que a camada solta o teclado.
    property var pendingWin: null
    function focusWin(w) {
        if (!w) return;
        ov.pendingWin = w;
        ov.open = false;
        focusWinTimer.restart();
    }
    Timer {
        id: focusWinTimer
        interval: 60
        onTriggered: {
            const w = ov.pendingWin;
            ov.pendingWin = null;
            if (!w) return;
            if (w.wsId < 0) {
                // Janela da área especial: abre a área se estiver fechada.
                const sp = ov.spaces.find(s => s.id === w.wsId);
                if (!sp || !sp.visibleNow) Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + w.wsName.replace(/^special:/, "") + '")');
            } else {
                Hyprland.dispatch("hl.dsp.focus({ workspace = " + w.wsId + " })");
            }
            Hyprland.dispatch('hl.dsp.focus({ window = "address:' + w.address + '" })');
        }
    }

    // Uma chamada só: workspaces, janelas e monitores (o `hyprctl --batch`
    // devolveria tudo misturado; três JSONs separados por uma linha marcada é
    // mais simples de separar).
    Process {
        id: loadProc
        command: ["sh", "-c", "hyprctl workspaces -j; echo '@@'; hyprctl clients -j; echo '@@'; hyprctl monitors -j; echo '@@'; "
            + "f=\"${XDG_CACHE_HOME:-$HOME/.cache}/hollow-wired/sddm-background.png\"; "
            + "if [ -f \"$f\" ]; then echo \"$f\"; else rice-wallpaper-current 2>/dev/null; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parts = text.split("@@");
                    ov.build(JSON.parse(parts[0]), JSON.parse(parts[1]), JSON.parse(parts[2]),
                             (parts[3] || "").trim());
                } catch (e) {
                    console.log("Overview: leitura falhou:", e);
                }
            }
        }
    }

    function build(workspaces, clients, monitors, wall) {
        const mons = {};
        let focused = monitors[0];
        for (const m of monitors) {
            mons[m.name] = m;
            if (m.focused) focused = m;
        }
        if (focused) {
            const rot = (focused.transform || 0) % 2 === 1;
            ov.monAspect = rot ? focused.height / focused.width : focused.width / focused.height;
        }
        ov.wallpaper = wall ? "file://" + wall : "";

        const tops = Hyprland.toplevels.values;
        const findTop = addr => tops.find(t => "0x" + t.address === addr || t.address === addr) || null;

        const wsMon = {};
        for (const w of workspaces) wsMon[w.id] = w.monitor;

        const byWs = {};
        const all = [];
        for (const c of clients) {
            if (!c.mapped || c.hidden || c.class === "dropterm") continue;
            const m = mons[wsMon[c.workspace.id]] || focused;
            const lw = m ? m.width / m.scale : 1920, lh = m ? m.height / m.scale : 1080;
            const w = {
                address: c.address,
                x: (c.at[0] - (m ? m.x : 0)) / lw, y: (c.at[1] - (m ? m.y : 0)) / lh,
                w: c.size[0] / lw, h: c.size[1] / lh,
                floating: c.floating,
                title: c.title || c.class,
                cls: c.class,
                wsId: c.workspace.id,
                wsName: c.workspace.name,
                top: findTop(c.address)
            };
            (byWs[c.workspace.id] = byWs[c.workspace.id] || []).push(w);
            all.push(w);
        }
        // Flutuantes por cima, como na tela.
        for (const k in byWs) byWs[k].sort((a, b) => (a.floating ? 1 : 0) - (b.floating ? 1 : 0));

        const activeId = focused && focused.activeWorkspace ? focused.activeWorkspace.id : 1;
        const specialOpen = focused && focused.specialWorkspace ? focused.specialWorkspace.name : "";

        const list = [];
        const normal = workspaces.filter(w => w.id > 0 && (w.windows > 0 || w.id === activeId))
            .sort((a, b) => a.id - b.id);
        for (const w of normal)
            list.push({ kind: "ws", id: w.id, name: w.name, wins: byWs[w.id] || [] });

        for (const w of workspaces.filter(w => w.id < 0 && w.windows > 0))
            list.push({ kind: "special", id: w.id, name: w.name, wins: byWs[w.id] || [],
                        visibleNow: specialOpen === w.name });

        // "Nova área": o primeiro número livre.
        const used = new Set(normal.map(w => w.id));
        let free = 1;
        while (used.has(free)) free++;
        list.push({ kind: "new", id: free, name: String(free), wins: [] });

        ov.spaces = list;
        ov.allWins = all.sort((a, b) => a.wsId - b.wsId);
        let cur = list.findIndex(s => s.kind === "ws" && s.id === activeId);
        if (specialOpen) {
            const si = list.findIndex(s => s.name === specialOpen);
            if (si >= 0) cur = si;
        }
        ov.current = Math.max(0, cur);
        // Sem mola na abertura: o carrossel já nasce no lugar certo.
        ov.pos = ov.current;
        ov.open = true;
    }

    function spaceLabel(s) {
        if (!s) return "";
        if (s.kind === "special") return Theme.t("overview.special", "Área especial");
        if (s.kind === "new") return Theme.t("overview.new", "Nova área de trabalho");
        return Theme.t("overview.workspace", "Área de trabalho") + " " + s.name;
    }
    function iconFor(cls) {
        const e = DesktopEntries.byId(cls) || DesktopEntries.heuristicLookup(cls);
        return Quickshell.iconPath(e ? e.icon : cls, "application-x-executable");
    }

    // ================= fundo =================
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5 * ov.shown)
        MouseArea {
            anchors.fill: parent
            onClicked: ov.hide()
            onWheel: wheel => ov.step(wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? -1 : 1)
        }
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            const k = event.key;
            const next = ov.vertical ? [Qt.Key_Down, Qt.Key_J, Qt.Key_S] : [Qt.Key_Right, Qt.Key_L, Qt.Key_D];
            const prev = ov.vertical ? [Qt.Key_Up, Qt.Key_K, Qt.Key_W] : [Qt.Key_Left, Qt.Key_H, Qt.Key_A];
            if (k === Qt.Key_Tab || next.includes(k)) ov.step(1);
            else if (k === Qt.Key_Backtab || prev.includes(k)) ov.step(-1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) ov.goTo(ov.current);
            else if (k === Qt.Key_Escape) ov.hide();
            else if (k >= Qt.Key_1 && k <= Qt.Key_9) {
                const i = ov.spaces.findIndex(s => s.kind === "ws" && s.id === k - Qt.Key_0);
                if (i >= 0) {
                    ov.goTo(i);
                } else {
                    ov.hide();
                    Hyprland.dispatch("hl.dsp.focus({ workspace = " + (k - Qt.Key_0) + " })");
                }
            } else return;
            event.accepted = true;
        }
    }

    // ================= título =================
    Column {
        id: titleCol
        // Horizontal: em cima do cartão do meio. Vertical: ao lado dele.
        x: ov.vertical ? stage.width / 2 + stage.cardW / 2 + 48 - (1 - ov.shown) * 20
                       : (parent.width - width) / 2
        y: ov.vertical ? stage.y + stage.height * 0.5 - height / 2
                       : stage.y + stage.height * 0.5 - cardH * 0.5 - height - 34 - (1 - ov.shown) * 20
        opacity: ov.shown
        spacing: 4
        readonly property real cardH: stage.cardW / ov.monAspect

        Text {
            anchors.horizontalCenter: ov.vertical ? undefined : parent.horizontalCenter
            text: ov.spaceLabel(ov.spaces[ov.current])
            font.family: Theme.fontFamily
            font.pixelSize: 22
            font.weight: Font.DemiBold
            color: "white"
        }
        Text {
            anchors.horizontalCenter: ov.vertical ? undefined : parent.horizontalCenter
            readonly property var s: ov.spaces[ov.current]
            text: !s ? "" : s.kind === "new" ? Theme.t("overview.new_hint", "Enter para abrir uma área vazia")
                : s.wins.length === 0 ? Theme.t("overview.empty", "Vazia")
                : s.wins.length === 1 ? Theme.t("overview.one_window", "1 janela")
                : s.wins.length + " " + Theme.t("overview.windows", "janelas")
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: Qt.rgba(1, 1, 1, 0.65)
        }
    }

    // ================= carrossel =================
    Item {
        id: stage
        anchors.left: parent.left
        anchors.right: parent.right
        y: parent.height * 0.1
        height: parent.height * 0.62
        readonly property real cardW: ov.vertical ? Math.min(width * 0.42, height * 0.5 * ov.monAspect)
                                                  : Math.min(width * 0.5, height * 0.86 * ov.monAspect)

        Repeater {
            model: ov.spaces
            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property real d: index - ov.pos
                readonly property real ad: Math.abs(d)
                readonly property bool centered: ov.current === index
                // Entrada escalonada: os do meio chegam primeiro.
                readonly property real enter: Math.max(0, Math.min(1, ov.shown * 1.7 - ad * 0.22))

                width: stage.cardW
                height: stage.cardW / ov.monAspect
                readonly property real offset: Math.sign(d) * (Math.min(ad, 1) * 0.74 + Math.max(ad - 1, 0) * 0.4)
                x: stage.width / 2 - width / 2 + (ov.vertical ? 0 : offset * width)
                y: stage.height / 2 - height / 2 + (ov.vertical ? offset * height : 0) + (1 - enter) * 70
                z: 100 - ad * 10
                scale: (1 - Math.min(ad, 2.5) * 0.17) * (0.85 + 0.15 * enter)
                opacity: enter * Math.max(0, 1 - Math.max(0, ad - 2.2))
                visible: opacity > 0.01

                transform: Rotation {
                    origin.x: card.width / 2
                    origin.y: card.height / 2
                    axis { x: ov.vertical ? 1 : 0; y: ov.vertical ? 0 : 1; z: 0 }
                    angle: (ov.vertical ? 28 : -32) * Math.max(-1, Math.min(1, card.d))
                }

                // sombra
                Rectangle {
                    anchors.fill: frame
                    anchors.margins: -10
                    anchors.topMargin: 4
                    radius: frame.radius + 10
                    color: Qt.rgba(0, 0, 0, 0.35 * (1 - Math.min(card.ad, 1) * 0.5))
                }

                ClippingRectangle {
                    id: frame
                    anchors.fill: parent
                    radius: 18
                    color: Theme.mix(Theme.background, "black", 0.3)

                    Image {
                        anchors.fill: parent
                        source: card.modelData.kind === "new" ? "" : ov.wallpaper
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        sourceSize.width: 960
                        opacity: card.modelData.kind === "special" ? 0.45 : 1
                    }
                    // Escurece os de fora para o do meio saltar aos olhos.
                    Rectangle {
                        anchors.fill: parent
                        color: "black"
                        opacity: Math.min(card.ad, 1) * 0.35
                        z: 5
                    }

                    // Janelas na posição real.
                    Repeater {
                        model: card.modelData.wins
                        delegate: Item {
                            id: mini
                            required property var modelData
                            x: modelData.x * frame.width
                            y: modelData.y * frame.height
                            width: Math.max(24, modelData.w * frame.width)
                            height: Math.max(18, modelData.h * frame.height)
                            z: modelData.floating ? 2 : 1

                            ClippingRectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: 8
                                color: Theme.withAlpha(Theme.background, 0.85)
                                border.width: miniArea.containsMouse && card.centered ? 2 : 1
                                border.color: miniArea.containsMouse && card.centered
                                    ? Theme.primary : Theme.withAlpha("white", 0.18)

                                ScreencopyView {
                                    id: shot
                                    anchors.fill: parent
                                    captureSource: mini.modelData.top ? mini.modelData.top.wayland : null
                                    // Só o cartão do meio fica ao vivo; os vizinhos
                                    // capturam um quadro e param. Antes eram até três
                                    // áreas de trabalho recopiando todas as janelas a
                                    // cada quadro, o que travava a GPU integrada.
                                    live: ov.open && card.centered && Theme.overviewLive
                                    paintCursor: false
                                }
                                IconImage {
                                    anchors.centerIn: parent
                                    visible: !shot.hasContent
                                    implicitSize: Math.min(parent.width, parent.height) * 0.4
                                    source: ov.iconFor(mini.modelData.cls)
                                }
                            }
                            // selo do app no canto
                            IconImage {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 6
                                visible: parent.width > 70
                                implicitSize: 20
                                source: ov.iconFor(mini.modelData.cls)
                            }

                            MouseArea {
                                id: miniArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: card.centered
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ov.focusWin(mini.modelData)
                            }
                        }
                    }

                    // Nova área: um "+" grande.
                    Column {
                        visible: card.modelData.kind === "new"
                        anchors.centerIn: parent
                        spacing: 10
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Theme.icons.plus
                            font.family: Theme.iconFontFamily
                            font.pixelSize: frame.height * 0.22
                            color: Theme.withAlpha("white", 0.8)
                        }
                    }

                    // Área especial: estrela no canto.
                    Rectangle {
                        visible: card.modelData.kind === "special"
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 12
                        width: 34; height: 34; radius: 17
                        color: Theme.withAlpha(Theme.background, 0.8)
                        z: 6
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icons.star
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 18
                            color: Theme.primary
                        }
                    }
                }

                // Moldura (fora do recorte para não ser cortada).
                Rectangle {
                    anchors.fill: frame
                    radius: frame.radius
                    color: "transparent"
                    border.width: card.centered ? 3 : 1
                    border.color: card.centered ? Theme.primary : Theme.withAlpha("white", 0.15)
                    Behavior on border.width { NumberAnimation { duration: Theme.ms(150) } }
                }

                // Número da área embaixo.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: frame.bottom
                    anchors.topMargin: 14
                    visible: card.modelData.kind === "ws"
                    width: 34; height: 26; radius: 13
                    color: card.centered ? Theme.primary : Theme.withAlpha(Theme.background, 0.7)
                    Text {
                        anchors.centerIn: parent
                        text: card.modelData.name
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: card.centered ? Theme.background : "white"
                    }
                }

                // Clique no fundo do cartão: o do meio abre, os de lado giram até ele.
                MouseArea {
                    anchors.fill: frame
                    z: -1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.centered ? ov.goTo(card.index) : (ov.current = card.index)
                    onWheel: wheel => ov.step(wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? -1 : 1)
                }
            }
        }
    }

    // ================= todos os apps abertos =================
    Rectangle {
        id: appsBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 36 - (1 - ov.shown) * 60
        opacity: ov.shown
        visible: ov.allWins.length > 0
        width: Math.min(parent.width - 80, appsRow.implicitWidth + 24)
        height: 68
        radius: 22
        color: Theme.withAlpha(Theme.background, 0.82)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.3)

        Flickable {
            anchors.fill: parent
            anchors.margins: 10
            contentWidth: appsRow.implicitWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: appsRow
                spacing: 6
                height: parent.height

                Repeater {
                    model: ov.allWins
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property var sp: ov.spaces[ov.current]
                        readonly property bool here: !!sp && sp.id === modelData.wsId
                        height: 48
                        width: chipRow.implicitWidth + 20
                        radius: 14
                        color: chipArea.containsMouse ? Theme.tileHigh
                             : here ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                        border.width: here ? 1 : 0
                        border.color: Theme.withAlpha(Theme.primary, 0.6)
                        Behavior on color { ColorAnimation { duration: Theme.ms(140) } }

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 8
                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 28
                                source: ov.iconFor(chip.modelData.cls)
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    width: Math.min(implicitWidth, 150)
                                    text: chip.modelData.title
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: Theme.textColor
                                }
                                Text {
                                    text: chip.modelData.wsId < 0 ? Theme.t("overview.special", "Área especial")
                                        : Theme.t("overview.workspace", "Área de trabalho") + " " + chip.modelData.wsName
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.subtext
                                }
                            }
                        }

                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // Passar o mouse leva o carrossel até a área do app.
                            onEntered: {
                                const i = ov.spaces.findIndex(s => s.id === chip.modelData.wsId);
                                if (i >= 0) ov.current = i;
                            }
                            onClicked: ov.focusWin(chip.modelData)
                        }
                    }
                }
            }
        }
    }

    // dica de teclas
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: appsBar.top
        anchors.bottomMargin: 14
        opacity: ov.shown * 0.7
        text: ov.vertical
              ? Theme.t("overview.keys_vertical", "↑ ↓ navegar  ·  Enter abrir  ·  clique numa janela para ir até ela  ·  Esc fechar")
              : Theme.t("overview.keys", "← → navegar  ·  Enter abrir  ·  clique numa janela para ir até ela  ·  Esc fechar")
        font.family: Theme.fontFamily
        font.pixelSize: 12
        color: "white"
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "overview"
        description: "Visão geral das áreas de trabalho (Super+Tab)"
        onPressed: ov.open ? ov.step(1) : ov.show()
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { ov.open ? ov.hide() : ov.show(); }
        function open(): void { ov.show(); }
        function close(): void { ov.hide(); }
        // Foca o app de número N da fileira de baixo (0 = primeiro).
        function focusApp(n: string): void { if (ov.open) ov.focusWin(ov.allWins[parseInt(n) || 0]); }
    }
}
