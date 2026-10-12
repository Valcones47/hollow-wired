pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Quem está usando microfone, câmera ou compartilhando a tela, pelas ligações
// do PipeWire (medido: PwNodeType Audio 1, Video 2, Stream 4, Source 8,
// Sink 16):
//  - microfone: fonte de áudio de dispositivo (não stream) → stream. O cava
//    e o loopback de chamada leem do monitor de uma saída (Sink), não contam.
//  - câmera: fonte de vídeo de dispositivo → qualquer consumidor.
//  - tela: fluxo de vídeo (o xdg-desktop-portal compartilhando) → consumidor.
// Gravadores por wlr-screencopy (gpu-screen-recorder, wf-recorder) não passam
// pelo PipeWire e não aparecem aqui.
Singleton {
    id: root

    readonly property var groups: Pipewire.linkGroups.values

    function appOf(n) {
        if (!n) return "";
        const p = n.properties || {};
        return p["application.name"] || n.description || n.nickname || n.name || "";
    }
    function usersOf(pred) {
        const out = [];
        for (const g of root.groups) {
            const s = g.source, t = g.target;
            if (!s || !t || !pred(s, t)) continue;
            const a = root.appOf(t);
            if (a && !out.includes(a)) out.push(a);
        }
        return out;
    }

    readonly property var micApps: usersOf((s, t) => s.type === PwNodeType.AudioSource && !s.isStream && t.isStream)
    readonly property var camApps: usersOf((s, t) => s.type === PwNodeType.VideoSource && !s.isStream)
    readonly property var screenApps: usersOf((s, t) => (s.type & PwNodeType.Video) && s.isStream)
    readonly property bool active: micApps.length + camApps.length + screenApps.length > 0

    // `qs ipc call privacy state`: o que o indicador está vendo (testes).
    IpcHandler {
        target: "privacy"
        function state(): string {
            return JSON.stringify({ groups: root.groups.length, mic: root.micApps, cam: root.camApps, screen: root.screenApps });
        }
    }

    // O nome do app (application.name) só vem com o nó rastreado.
    // Vínculo só depois de 1,5 s sem mudança nos links: ao abrir jogo, o Proton
    // cria e destrói fluxos em milissegundos; vincular um deles na hora fazia o
    // PipeWire responder "no global N any more" e o Quickshell cair em
    // pw_proxy_destroy (coredumps de 2026-10-11 e 2026-10-12).
    property var stableTargets: []
    onGroupsChanged: settle.restart()
    Component.onCompleted: settle.start()
    Timer {
        id: settle
        interval: 1500
        onTriggered: root.stableTargets = root.groups.map(g => g.target).filter(t => t && t.isStream)
    }
    PwObjectTracker { objects: root.stableTargets }
}
