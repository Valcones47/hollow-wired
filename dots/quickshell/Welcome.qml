import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Tela de boas-vindas do primeiro login.
//
// Pensada para quem está vindo do Windows e abre o computador pela primeira vez
// sem barra de tarefas, sem botão Iniciar e sem ícones na área de trabalho.
//
// Ela tem cara própria de propósito: fundo mais escuro que o resto do shell,
// marca desenhada e navegação lateral por assuntos, em vez de uma lista só que
// rolava sem fim. As cores continuam saindo do wallust, então ela acompanha o
// papel de parede como todo o resto.
//
// Aparece uma única vez (marca ~/.config/quickshell/.welcome-done) e pode ser
// reaberta com `qs ipc call welcome open` ou pelo Painel Rice.
PanelWindow {
    id: welcomeWindow

    property bool open: false
    property bool checked: false
    property int page: 0

    // Cada passo é um "e no Windows era assim" → "aqui é assim".
    readonly property var steps: [
        {
            icon: Theme.icons.arch,
            keys: ["Super"],
            title: Theme.t("welcome.step_launcher_title", "A tecla Windows abre o menu de aplicativos"),
            desc: Theme.t("welcome.step_launcher_desc", "É o seu Menu Iniciar. Aperte e comece a digitar o nome do programa.")
        },
        {
            icon: Theme.icons.console,
            keys: ["Super", "Q"],
            title: Theme.t("welcome.step_terminal_title", "Terminal"),
            desc: Theme.t("welcome.step_terminal_desc", "Abre o terminal Kitty. Super + ' abre um terminal suspenso por cima de tudo.")
        },
        {
            icon: Theme.icons.disk,
            keys: ["Super", "E"],
            title: Theme.t("welcome.step_files_title", "Gerenciador de arquivos"),
            desc: Theme.t("welcome.step_files_desc", "O mesmo Super + E do Windows abre a pasta pessoal no Dolphin.")
        },
        {
            icon: Theme.icons.close,
            keys: ["Super", "C"],
            title: Theme.t("welcome.step_close_title", "Fechar a janela atual"),
            desc: Theme.t("welcome.step_close_desc", "Alt + F4 também funciona. As janelas se organizam sozinhas na tela, sem precisar arrastar.")
        },
        {
            icon: Theme.icons.workspaces,
            keys: ["Super", "1..9"],
            title: Theme.t("welcome.step_workspaces_title", "Áreas de trabalho"),
            desc: Theme.t("welcome.step_workspaces_desc", "Cada número é uma área separada. A roda do mouse com Super pressionado também troca.")
        },
        {
            icon: Theme.icons.history,
            keys: ["Super", "V"],
            title: Theme.t("welcome.step_clipboard_title", "Tudo que você copiou"),
            desc: Theme.t("welcome.step_clipboard_desc", "Histórico da área de transferência, com busca e favoritos (Super + Ctrl + V).")
        },
        {
            icon: Theme.icons.camera,
            keys: ["Print"],
            title: Theme.t("welcome.step_screenshot_title", "Captura de tela"),
            desc: Theme.t("welcome.step_screenshot_desc", "Selecione uma área com o mouse. Ela é salva e copiada. Esc cancela.")
        },
        {
            icon: Theme.icons.workspaces,
            keys: ["Super", "Tab"],
            title: Theme.t("welcome.step_overview_title", "Ver tudo que está aberto"),
            desc: Theme.t("welcome.step_overview_desc", "Mostra as áreas de trabalho num carrossel, com os apps de cada uma. Clique numa janela para ir até ela.")
        },
        {
            icon: Theme.icons.performance,
            keys: ["Super", "Esc"],
            title: Theme.t("welcome.step_taskmgr_title", "Gerenciador de tarefas"),
            desc: Theme.t("welcome.step_taskmgr_desc", "Algum programa travou? Abre o monitor do sistema para fechá-lo. Ctrl + Shift + Esc também funciona.")
        },
        {
            icon: Theme.icons.cursor,
            keys: ["Botão direito"],
            title: Theme.t("welcome.step_rightclick_title", "Clique direito na área de trabalho"),
            desc: Theme.t("welcome.step_rightclick_desc", "Atalhos para configurações, tela, terminal, papel de parede e widgets.")
        },
        {
            icon: Theme.icons.power,
            keys: ["Ctrl", "Alt", "Del"],
            title: Theme.t("welcome.step_power_title", "Desligar, reiniciar, suspender"),
            desc: Theme.t("welcome.step_power_desc", "Abre a barra lateral de energia. Encostar o mouse na borda direita faz o mesmo.")
        }
    ]

    readonly property var pages: [
        { icon: Theme.icons.arch, name: Theme.t("welcome.nav_start", "Início") },
        { icon: Theme.icons.dashboard, name: Theme.t("welcome.nav_layout", "Interface") },
        { icon: Theme.icons.laptop, name: Theme.t("welcome.nav_windows", "Janelas") },
        { icon: Theme.icons.magnify, name: Theme.t("welcome.nav_keys", "Atalhos") },
        { icon: Theme.icons.lock, name: Theme.t("welcome.nav_login", "Tela de login") },
        { icon: Theme.icons.palette, name: Theme.t("welcome.nav_extras", "Aparência") }
    ]

    property string windowMode: "hyprland"
    Process {
        id: modeStatus
        command: ["rice-window-mode", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { welcomeWindow.windowMode = JSON.parse(text).mode || "hyprland"; } catch (e) {}
            }
        }
    }

    property bool tipsOn: true
    // Tela de login do rice (greetd): active | installed | off
    property string greeterState: "off"
    Process {
        id: greeterStatus
        command: ["rice-greeter", "state"]
        stdout: StdioCollector { onStreamFinished: welcomeWindow.greeterState = text.trim() || "off" }
    }
    Process {
        id: greeterSetup
        command: ["kitty", "--title", "Tela de login do rice", "bash", "-c",
                  "rice-greeter setup; echo; read -n 1 -s -r -p 'Pressione qualquer tecla para fechar...'"]
        onExited: greeterStatus.running = true
    }
    Process {
        id: tipsStatus
        command: ["rice-tips", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { welcomeWindow.tipsOn = JSON.parse(text).enabled !== false; } catch (e) {}
            }
        }
    }

    function markDone() {
        doneFile.setText("1\n");
    }

    FileView {
        id: doneFile
        path: Quickshell.env("HOME") + "/.config/quickshell/.welcome-done"
        onLoaded: welcomeWindow.checked = true
        onLoadFailed: {
            // Arquivo não existe = primeiro login desta instalação.
            welcomeWindow.checked = true;
            welcomeWindow.open = true;
        }
    }

    visible: true
    color: "transparent"
    focusable: true

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
        width: welcomeWindow.open ? welcomeWindow.width : 0
        height: welcomeWindow.open ? welcomeWindow.height : 0
    }

    WlrLayershell.namespace: "quickshell-welcome"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: welcomeWindow.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (open) {
            welcomeWindow.page = 0;
            tipsStatus.running = true;
            modeStatus.running = true;
            greeterStatus.running = true;
        }
        if (!open) welcomeWindow.markDone();
    }

    // ---------------------------------------------------------- componentes
    component NavItem: Rectangle {
        id: nav
        property int pageIndex: 0
        property string icon: ""
        property string label: ""
        readonly property bool active: welcomeWindow.page === nav.pageIndex

        Layout.fillWidth: true
        implicitHeight: 40
        radius: 12
        color: nav.active ? Theme.withAlpha(Theme.primary, 0.20)
             : (navArea.containsMouse ? Theme.withAlpha(Theme.outline, 0.18) : "transparent")
        Behavior on color { ColorAnimation { duration: 130 } }

        // Marca da página atual, como um marcador de livro na borda.
        Rectangle {
            visible: nav.active
            anchors.left: parent.left
            anchors.leftMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 18
            radius: 1.5
            color: Theme.primary
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: nav.icon
                font.family: Theme.iconFontFamily
                font.pixelSize: 15
                color: nav.active ? Theme.primary : Theme.subtext
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: nav.label
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: nav.active ? Font.DemiBold : Font.Normal
                color: nav.active ? Theme.textColor : Theme.subtext
            }
        }

        MouseArea {
            id: navArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: welcomeWindow.page = nav.pageIndex
        }
    }

    component PageTitle: ColumnLayout {
        property string title: ""
        property string subtitle: ""
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: parent.title
            font.family: Theme.fontFamily
            font.pixelSize: 21
            font.weight: Font.Bold
            color: Theme.textColor
        }
        Text {
            Layout.fillWidth: true
            visible: parent.subtitle !== ""
            text: parent.subtitle
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: Theme.subtext
        }
    }

    component ChoiceCard: Rectangle {
        id: cc
        property string title: ""
        property string desc: ""
        property bool active: false
        // Sem preview, o cartão vira só texto (é o caso do estilo das janelas).
        property bool showPreview: false
        property bool pvBar: true
        property bool pvDock: true
        property bool pvDockFull: false
        property bool pvSide: false
        property bool pvVertical: false
        signal picked()

        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(ccCol.implicitHeight + 26, cc.showPreview ? 96 : 0)
        radius: 14
        color: cc.active ? Theme.withAlpha(Theme.primary, 0.14) : (ccArea.containsMouse ? Theme.tileHigh : Theme.tile)
        border.width: cc.active ? 2 : 1
        border.color: cc.active ? Theme.primary : Theme.withAlpha(Theme.outline, 0.25)
        Behavior on color { ColorAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            LayoutPreview {
                visible: cc.showPreview
                Layout.preferredWidth: 118
                Layout.preferredHeight: 68
                bar: cc.pvBar
                dock: cc.pvDock
                dockFull: cc.pvDockFull
                side: cc.pvSide
                vertical: cc.pvVertical
            }

            ColumnLayout {
                id: ccCol
                Layout.fillWidth: true
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: cc.title
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Theme.textColor
                }
                Text {
                    Layout.fillWidth: true
                    visible: cc.desc !== ""
                    text: cc.desc
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.subtext
                }
            }
        }

        MouseArea {
            id: ccArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cc.picked()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.72)
        opacity: welcomeWindow.open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220 } }

        MouseArea {
            anchors.fill: parent
            onClicked: welcomeWindow.open = false
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(1040, welcomeWindow.width - 80)
        height: Math.min(660, welcomeWindow.height - 80)
        radius: 24
        // Mais escuro que o resto do shell: é o que dá a ela um ar de
        // "primeira tela", separada do desktop que está por baixo.
        color: Theme.mix(Theme.background, "#000000", 0.35)
        border.color: Theme.withAlpha(Theme.primary, 0.30)
        border.width: 1
        clip: true

        scale: welcomeWindow.open ? 1 : 0.94
        opacity: welcomeWindow.open ? 1 : 0
        visible: opacity > 0

        Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea { anchors.fill: parent }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ------------------------------------------------ navegação
            Rectangle {
                Layout.preferredWidth: 228
                Layout.fillHeight: true
                color: Theme.withAlpha("#000000", 0.25)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 10
                        spacing: 10

                        Item {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            WelcomeMark { anchors.fill: parent; alive: false }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: "hollow-wired"
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: Theme.textColor
                            }
                            Text {
                                text: Theme.t("welcome.brand_sub", "guia de primeiros passos")
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.subtext
                            }
                        }
                    }

                    Repeater {
                        model: welcomeWindow.pages
                        delegate: NavItem {
                            required property var modelData
                            required property int index
                            icon: modelData.icon
                            label: modelData.name
                            pageIndex: index
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.fillWidth: true
                        text: Theme.t("welcome.nav_footer", "Super + F1 mostra tudo isso de novo, quando quiser.")
                        wrapMode: Text.WordWrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.withAlpha(Theme.subtext, 0.85)
                    }
                }
            }

            // ------------------------------------------------ conteúdo
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Botão fechar, sempre no canto de cima.
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    z: 5
                    width: 32
                    height: 32
                    radius: 16
                    color: closeArea.containsMouse ? Theme.withAlpha(Theme.critical, 0.22) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: Theme.icons.close
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 15
                        color: closeArea.containsMouse ? Theme.critical : Theme.subtext
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: welcomeWindow.open = false
                    }
                }

                // ---------------- página 0: início ----------------
                Item {
                    id: heroPage
                    anchors.fill: parent
                    visible: welcomeWindow.page === 0
                    clip: true

                    readonly property bool live: welcomeWindow.open && welcomeWindow.page === 0

                    // Onde o olho está dentro desta página — é para cá que a
                    // chuva da frente puxa o cabo.
                    readonly property real eyeX: markHolder.x + markHolder.width / 2
                    readonly property real eyeY: markHolder.y + markHolder.height / 2
                        - markHolder.height * 0.06

                    // Planos de trás: passam por baixo do olho.
                    WiredRain {
                        anchors.fill: parent
                        z: 0
                        planes: [0, 1]
                        perPlane: 7
                        running: heroPage.live
                    }

                    // Fiação exposta do cenário, em três tamanhos.
                    CutCable {
                        x: 26
                        y: -8
                        z: 0
                        drop: 96
                        sway: 22
                        alive: heroPage.live
                    }
                    CutCable {
                        x: parent.width - 96
                        y: -6
                        z: 0
                        drop: 150
                        sway: -34
                        alive: heroPage.live
                    }
                    CutCable {
                        x: parent.width * 0.62
                        y: -4
                        z: 3
                        drop: 62
                        sway: 18
                        alive: heroPage.live
                    }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 34
                    z: 1
                    spacing: 0

                    Item { Layout.fillHeight: true }

                    Item {
                        id: markHolder
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 190
                        Layout.preferredHeight: 190
                        WelcomeMark {
                            id: eyeMark
                            anchors.fill: parent
                            alive: heroPage.live
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 18
                        text: Theme.t("welcome.hero_title", "hollow-wired")
                        font.family: Theme.fontFamily
                        font.pixelSize: 34
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        color: Theme.textColor
                    }
                    // As frases do meio são as do símbolo (Lain / the Wired, de
                    // onde vem o nome do rice) e trocam sozinhas; a de baixo é a
                    // parte prática, que fica parada.
                    GlitchText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 8
                        Layout.preferredWidth: 540
                        Layout.preferredHeight: 22
                        fontSize: 13
                        running: welcomeWindow.open && welcomeWindow.page === 0
                        baseColor: Theme.withAlpha(Theme.primary, 0.9)
                        phrases: [
                            Theme.t("welcome.motto_1", "Existe uma rede sob o vazio."),
                            Theme.t("welcome.motto_2", "Vazio por dentro. Conectado por fora."),
                            Theme.t("welcome.motto_3", "Sinal encontrado. Presença não confirmada."),
                            Theme.t("welcome.motto_4", "Você não está sozinho aqui. Só está sozinho."),
                            Theme.t("welcome.motto_5", "Nem tudo aqui está pronto. Nada aqui precisa estar."),
                            Theme.t("welcome.motto_6", "Ainda carregando. Sempre carregando."),
                            Theme.t("welcome.motto_7", "Isso aqui também é real."),
                            Theme.t("welcome.motto_8", "O vazio também transmite sinal.")
                        ]
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 10
                        Layout.maximumWidth: 430
                        horizontalAlignment: Text.AlignHCenter
                        text: Theme.t("welcome.hero_sub", "Sem barra de tarefas e sem Menu Iniciar. Em dois minutos aqui você já sabe usar tudo.")
                        wrapMode: Text.WordWrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.subtext
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 26
                        width: 210
                        height: 44
                        radius: 22
                        color: heroArea.containsMouse ? Theme.primary : Theme.withAlpha(Theme.primary, 0.88)
                        Behavior on color { ColorAnimation { duration: 130 } }

                        Text {
                            anchors.centerIn: parent
                            text: Theme.t("welcome.hero_btn", "Começar a configurar")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: Theme.background
                        }
                        MouseArea {
                            id: heroArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: welcomeWindow.page = 1
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                    // Plano da frente: passa por cima do olho e é o que
                    // encosta o cabo elétrico nele.
                    WiredRain {
                        anchors.fill: parent
                        z: 2
                        planes: [2]
                        perPlane: 6
                        running: heroPage.live
                        connects: true
                        eyeX: heroPage.eyeX
                        eyeY: heroPage.eyeY
                        linkColor: eyeMark.stateColor
                    }
                }

                // ---------------- página 1: interface ----------------
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 34
                    visible: welcomeWindow.page === 1
                    spacing: 14

                    PageTitle {
                        title: Theme.t("welcome.layout_title", "Como você quer a tela?")
                        subtitle: Theme.t("welcome.layout_sub", "Dá para trocar quando quiser, e ajustar cada peça depois em Configurações → Personalização.")
                    }

                    Repeater {
                        model: [
                            { key: "topbar", name: Theme.t("layout.preset_topbar", "Clássico"),
                              desc: Theme.t("welcome.layout_topbar_desc", "Barra fina em cima com relógio e status; a fileira de aplicativos aparece quando o mouse chega na borda de baixo."),
                              bar: true, dock: false, dockFull: false, side: false },
                            { key: "taskbar", name: Theme.t("layout.preset_taskbar", "Estilo Windows"),
                              desc: Theme.t("welcome.layout_taskbar_desc", "A fileira de aplicativos fica sempre à mostra, de ponta a ponta, e a central de ações fica aberta na direita."),
                              bar: true, dock: true, dockFull: true, side: true },
                            { key: "sidebar", name: Theme.t("layout.preset_sidebar", "Barra lateral"),
                              desc: Theme.t("welcome.layout_sidebar_desc", "A barra fica de pé na lateral esquerda, estreita, com as áreas de trabalho e os indicadores — é como a maioria dos rices de Hyprland se organiza."),
                              bar: true, dock: false, dockFull: false, side: false, vertical: true },
                            { key: "clean", name: Theme.t("layout.preset_clean", "Tela limpa"),
                              desc: Theme.t("welcome.layout_clean_desc", "Só as suas janelas. Tudo do sistema aparece ao encostar o mouse na borda da tela."),
                              bar: false, dock: false, dockFull: false, side: false }
                        ]
                        delegate: ChoiceCard {
                            required property var modelData
                            title: modelData.name
                            desc: modelData.desc
                            showPreview: true
                            pvBar: modelData.bar
                            pvDock: modelData.dock
                            pvDockFull: modelData.dockFull
                            pvSide: modelData.side
                            pvVertical: modelData.vertical === true
                            active: ShellLayout.preset === modelData.key
                            onPicked: ShellLayout.applyPreset(modelData.key)
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // ---------------- página 2: janelas ----------------
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 34
                    visible: welcomeWindow.page === 2
                    spacing: 14

                    PageTitle {
                        title: Theme.t("welcome.mode_title", "Como as janelas devem abrir?")
                        subtitle: Theme.t("welcome.mode_sub", "O jeito do Hyprland é dividir a tela sozinho. Se isso for estranho no começo, comece pelo estilo Windows.")
                    }

                    Repeater {
                        model: [
                            { mode: "windows", label: Theme.t("welcome.mode_windows", "Estilo Windows"),
                              desc: Theme.t("welcome.mode_windows_desc", "Soltas no meio da tela, como no Windows.") },
                            { mode: "hyprland", label: Theme.t("welcome.mode_hyprland", "Estilo Hyprland"),
                              desc: Theme.t("welcome.mode_hyprland_desc", "Lado a lado, dividindo a tela sozinhas.") }
                        ]
                        delegate: ChoiceCard {
                            required property var modelData
                            title: modelData.label
                            desc: modelData.desc
                            active: welcomeWindow.windowMode === modelData.mode
                            onPicked: {
                                welcomeWindow.windowMode = modelData.mode;
                                Quickshell.execDetached(["rice-window-mode", modelData.mode]);
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // ---------------- página 3: atalhos ----------------
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 34
                    visible: welcomeWindow.page === 3
                    spacing: 12

                    PageTitle {
                        title: Theme.t("welcome.keys_title", "O que substitui cada coisa")
                        subtitle: Theme.t("welcome.keys_sub", "A tecla Windows aqui se chama Super e é o centro de quase tudo.")
                    }

                    ListView {
                        id: stepList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        model: welcomeWindow.steps
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            id: stepScroll
                            policy: stepList.contentHeight > stepList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                            width: 8
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: stepScroll.pressed ? Theme.primary : Theme.withAlpha(Theme.outline, 0.55)
                            }
                        }

                        delegate: Rectangle {
                            id: stepCard
                            required property var modelData
                            required property int index

                            width: stepList.width - (stepScroll.visible ? 16 : 4)
                            height: 70
                            radius: 12
                            color: Theme.tile
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.outline, 0.18)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 14

                                Text {
                                    text: stepCard.modelData.icon
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 22
                                    color: Theme.primary
                                    Layout.preferredWidth: 26
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: stepCard.modelData.title
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: Theme.textColor
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: stepCard.modelData.desc
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.subtext
                                    }
                                }

                                Row {
                                    spacing: 5
                                    Repeater {
                                        model: stepCard.modelData.keys
                                        delegate: Rectangle {
                                            required property var modelData
                                            height: 24
                                            width: keyText.implicitWidth + 16
                                            radius: 7
                                            color: Theme.withAlpha(Theme.primary, 0.16)
                                            border.width: 1
                                            border.color: Theme.withAlpha(Theme.primary, 0.35)

                                            Text {
                                                id: keyText
                                                anchors.centerIn: parent
                                                text: modelData
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                color: Theme.primary
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---------------- página 4: tela de login ----------------
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 34
                    visible: welcomeWindow.page === 4
                    spacing: 14

                    PageTitle {
                        title: Theme.t("welcome.greeter_title", "Tela de login com a cara do rice (opcional)")
                        subtitle: welcomeWindow.greeterState === "active"
                            ? Theme.t("welcome.greeter_active", "Já ativa: o computador abre na mesma tela da tela de bloqueio.")
                            : Theme.t("welcome.greeter_desc", "Igual à tela de bloqueio, com a lista de sessões. Um assistente explica e pergunta antes de trocar.")
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: greeterCol.implicitHeight + 28
                        radius: 14
                        color: Theme.tile
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.outline, 0.22)

                        ColumnLayout {
                            id: greeterCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 16
                            spacing: 10

                            Text {
                                Layout.fillWidth: true
                                text: Theme.t("welcome.greeter_warn", "Trocar a tela de login mexe no que aparece antes da sessão abrir. O assistente faz um teste ao vivo antes de valer no boot, e dá para voltar atrás a qualquer momento.")
                                wrapMode: Text.WordWrap
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.subtext
                            }

                            Rectangle {
                                Layout.preferredWidth: 190
                                Layout.preferredHeight: 38
                                radius: 19
                                color: greeterArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.3) : Theme.withAlpha(Theme.primary, 0.18)
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.primary, 0.45)

                                Text {
                                    anchors.centerIn: parent
                                    text: welcomeWindow.greeterState === "active"
                                        ? Theme.t("welcome.greeter_btn_open", "Abrir o assistente")
                                        : Theme.t("welcome.greeter_btn", "Configurar")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: Theme.primary
                                }
                                MouseArea {
                                    id: greeterArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: greeterSetup.running = true
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // ---------------- página 5: aparência e extras ----------------
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 34
                    visible: welcomeWindow.page === 5
                    spacing: 14

                    PageTitle {
                        title: Theme.t("welcome.extras_title", "A cara do sistema é a do seu papel de parede")
                        subtitle: Theme.t("welcome.extras_sub", "As cores de tudo saem da imagem de fundo. Troque o papel de parede e o resto acompanha.")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Repeater {
                            model: [
                                { label: Theme.t("welcome.btn_wallpaper", "Papel de parede"), icon: Theme.icons.palette, action: "wallpaper" },
                                { label: Theme.t("welcome.btn_settings", "Configurações"), icon: Theme.icons.tune, action: "settings" },
                                { label: Theme.t("welcome.btn_shortcuts", "Ver todos os atalhos"), icon: Theme.icons.info, action: "cheatsheet" }
                            ]

                            delegate: Rectangle {
                                id: actBtn
                                required property var modelData

                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                radius: 20
                                color: actArea.containsMouse ? Theme.tileHigh : Theme.tile
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.outline, 0.22)
                                Behavior on color { ColorAnimation { duration: 130 } }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: actBtn.modelData.icon
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 14
                                        color: Theme.primary
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: actBtn.modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.textColor
                                    }
                                }

                                MouseArea {
                                    id: actArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        welcomeWindow.open = false;
                                        if (actBtn.modelData.action === "cheatsheet")
                                            Quickshell.execDetached(["quickshell", "ipc", "call", "cheatsheet", "toggle"]);
                                        else if (actBtn.modelData.action === "settings")
                                            Quickshell.execDetached(["quickshell", "ipc", "call", "visualconfig", "toggle"]);
                                        else if (actBtn.modelData.action === "wallpaper")
                                            Quickshell.execDetached(["sh", "-c", "if flatpak info org.waywallen.waywallen >/dev/null 2>&1; then exec waywallen-switcher; else exec rice-wallpaper-set; fi"]);
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: tipsRow.implicitHeight + 26
                        radius: 14
                        color: Theme.tile
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.outline, 0.22)

                        RowLayout {
                            id: tipsRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 16
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: Theme.t("welcome.tips_title", "Dicas enquanto você usa")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: Theme.textColor
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: Theme.t("welcome.tips_desc", "De vez em quando uma notificação ensina um atalho. Cada dica aparece no máximo 2 vezes.")
                                    wrapMode: Text.WordWrap
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.subtext
                                }
                            }

                            Rectangle {
                                implicitWidth: 43
                                implicitHeight: 20
                                radius: 10
                                color: welcomeWindow.tipsOn ? Theme.primary : Theme.tileHigh

                                Rectangle {
                                    width: 14; height: 14; radius: 7
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: welcomeWindow.tipsOn ? parent.width - width - 3 : 3
                                    color: Theme.textColor
                                    Behavior on x { NumberAnimation { duration: 140 } }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        welcomeWindow.tipsOn = !welcomeWindow.tipsOn;
                                        Quickshell.execDetached(["rice-tips", welcomeWindow.tipsOn ? "on" : "off"]);
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // ---------------- rodapé de navegação ----------------
                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 34
                    visible: welcomeWindow.page > 0
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 38
                        radius: 19
                        color: prevArea.containsMouse ? Theme.tileHigh : "transparent"
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.outline, 0.3)

                        Text {
                            anchors.centerIn: parent
                            text: Theme.t("welcome.prev", "Voltar")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.subtext
                        }
                        MouseArea {
                            id: prevArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: welcomeWindow.page = Math.max(0, welcomeWindow.page - 1)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Bolinhas de progresso, para saber quanto falta.
                    Row {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 6
                        Repeater {
                            model: welcomeWindow.pages.length
                            delegate: Rectangle {
                                required property int index
                                anchors.verticalCenter: parent.verticalCenter
                                width: welcomeWindow.page === index ? 18 : 7
                                height: 7
                                radius: 3.5
                                color: welcomeWindow.page === index ? Theme.primary : Theme.withAlpha(Theme.subtext, 0.35)
                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 150
                        Layout.preferredHeight: 38
                        radius: 19
                        color: nextArea.containsMouse ? Theme.primary : Theme.withAlpha(Theme.primary, 0.85)
                        Behavior on color { ColorAnimation { duration: 130 } }

                        Text {
                            anchors.centerIn: parent
                            text: welcomeWindow.page >= welcomeWindow.pages.length - 1
                                ? Theme.t("welcome.btn_start", "Começar a usar")
                                : Theme.t("welcome.next", "Continuar")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: Theme.background
                        }
                        MouseArea {
                            id: nextArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (welcomeWindow.page >= welcomeWindow.pages.length - 1) welcomeWindow.open = false;
                                else welcomeWindow.page++;
                            }
                        }
                    }
                }
            }
        }

        Keys.onEscapePressed: welcomeWindow.open = false
    }

    IpcHandler {
        target: "welcome"

        function open(): void { welcomeWindow.open = true; }
        function hide(): void { welcomeWindow.open = false; }
        function toggle(): void { welcomeWindow.open = !welcomeWindow.open; }
        // Faz a tela voltar a aparecer no próximo login (útil pra testar).
        function reset(): void { doneFile.setText(""); welcomeWindow.open = true; }
    }
}
