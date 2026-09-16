pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Modo jogo. Quem liga/desliga o visual é o gamemode (~/.config/gamemode.ini
// → ~/.local/bin/rice-gamemode); aqui fica:
// - estado: observa $XDG_RUNTIME_DIR/rice-gamemode (existe = ativo)
// - automático: jogo aberto sem gamemoderun (Wine/.exe, osu!, Hytale, Steam)
//   → segura um `gamemoderun sleep infinity` enquanto a janela existir
// - manual: botão da sidebar segura o mesmo processo
// Jogos da Steam com "gamemoderun" nas opções de inicialização já ativam
// sozinhos; o processo daqui só soma (o gamemode conta referências).
QtObject {
    id: root

    // classes de janela reconhecidas como jogo
    readonly property var gamePatterns: [/^steam_app_\d+$/, /\.exe$/i, /^osu!?$/i, /hytale/i, /^gamescope$/i]

    readonly property var gameWindows: Hyprland.toplevels.values.filter(t => {
        const cls = t.lastIpcObject && t.lastIpcObject.class ? t.lastIpcObject.class : (t.wayland ? t.wayland.appId : "");
        return cls !== "" && root.gamePatterns.some(p => p.test(cls));
    })
    readonly property bool autoGame: gameWindows.length > 0
    property bool manual: false
    property bool active: false
    readonly property string gameTitle: gameWindows.length > 0 ? gameWindows[0].title : ""

    property Process holder: Process {
        command: ["gamemoderun", "sleep", "infinity"]
        running: root.manual || root.autoGame
    }

    property FileView stateFile: FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/rice-gamemode"
        watchChanges: true
        __printErrors: false   // arquivo ausente = modo desligado (normal)
        onLoaded: root.active = true
        onLoadFailed: root.active = false
        onFileChanged: reload()
    }
    // FileView não avisa quando o arquivo some; confere de tempos em tempos.
    property Timer poll: Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.stateFile.reload()
    }

    // lastIpcObject (class) só é preenchido depois de um refresh
    property Timer refresh: Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: Hyprland.refreshToplevels()
    }
}
