pragma ComponentBehavior: Bound
import QtQuick
import "."

// Miniatura de uma tela mostrando onde ficam a barra, a dock e a central de
// ações num determinado arranjo. Usada nos cartões de arranjo do painel de
// configurações e da tela de boas-vindas, para a escolha não ser só texto.
Rectangle {
    id: prev

    // Peça apagada = existe, mas só aparece quando o mouse encosta na borda.
    property bool bar: true
    property bool dock: true
    property bool dockFull: false
    property bool side: false
    // Barra vertical: desenha a barra de pé na lateral esquerda.
    property bool vertical: false

    radius: 8
    color: Theme.withAlpha(Theme.background, 0.85)
    border.width: 1
    border.color: Theme.withAlpha(Theme.outline, 0.3)
    clip: true

    readonly property real pad: Math.max(3, width * 0.03)

    // janela de exemplo, para dar escala às barras
    Rectangle {
        x: prev.width * 0.14
        y: prev.height * 0.28
        width: prev.width * 0.5
        height: prev.height * 0.44
        radius: 3
        color: Theme.withAlpha(Theme.outline, 0.35)
    }

    // barra principal
    Rectangle {
        x: prev.pad
        y: prev.pad
        width: prev.vertical ? Math.max(5, prev.width * 0.07) : prev.width - prev.pad * 2
        height: prev.vertical ? prev.height - prev.pad * 2 : Math.max(4, prev.height * 0.08)
        radius: Math.min(width, height) / 2
        color: Theme.withAlpha(Theme.primary, prev.bar ? 0.6 : 0.18)
    }

    // dock
    Rectangle {
        height: Math.max(5, prev.height * 0.1)
        radius: height / 2
        y: prev.height - height - prev.pad
        width: prev.dockFull ? prev.width - prev.pad * 2 : prev.width * 0.42
        x: prev.dockFull ? prev.pad : (prev.width - width) / 2
        color: Theme.withAlpha(Theme.secondary, prev.dock ? 0.6 : 0.18)
    }

    // central de ações
    Rectangle {
        width: Math.max(7, prev.width * 0.09)
        radius: 3
        x: prev.width - width - prev.pad
        y: prev.height * 0.22
        height: prev.height * 0.56
        color: Theme.withAlpha(Theme.primary, prev.side ? 0.45 : 0.14)
    }
}
