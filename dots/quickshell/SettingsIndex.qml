pragma Singleton
import QtQuick
import Quickshell
import "."

// Categorias do painel de configurações (Super+I): nome, descrição, ícone,
// aba e palavras-chave. O painel monta a navegação com esta lista e a busca
// universal do launcher usa a mesma para abrir o painel direto na aba certa.
Singleton {
    readonly property var entries: [
        { group: "look", tabIndex: 9, name: Theme.t("settings.cat_effects", "Efeitos & Janelas"), icon: Theme.icons.laptop, desc: Theme.t("settings.desc_effects", "Bordas & Animações"), keywords: "efeitos effects janelas windows blur desfoque bordas borders sombras shadows sddm animacoes animations transparência luz noturna curvas bezier curves velocidade" },
        { group: "custom", tabIndex: 20, name: Theme.t("settings.cat_layout", "Organização da Interface"), icon: Theme.icons.dashboard, desc: Theme.t("settings.desc_layout", "Onde fica cada barra"), keywords: "organizacao layout arranjo interface barra topbar dock sidebar lateral taskbar windows areas de trabalho workspaces hover esconder largura total posicao preset estilo" },
        { group: "custom", tabIndex: 8, name: Theme.t("settings.cat_wallust", "Cores & Papel de Parede"), icon: Theme.icons.palette, desc: Theme.t("settings.desc_wallust", "Cores da tela toda"), keywords: "cores color colors wallust tema theme wallpaper papel de parede paleta palette dinamica accent visual fundo transicao transição transition onda wave varredura circulo fade" },
        { group: "custom", tabIndex: 21, name: Theme.t("settings.cat_binds", "Atalhos do Teclado"), icon: Theme.icons.keyboard, desc: Theme.t("settings.desc_binds", "Criar e trocar atalhos"), keywords: "atalhos shortcuts teclas binds keybinds combinacao gravar programa abrir steam heroic jogos discord mute deafen microfone push to talk user-binds" },
        { group: "custom", tabIndex: 18, name: Theme.t("settings.cat_shell_custom", "Customização do Shell"), icon: Theme.icons.tune, desc: Theme.t("settings.desc_shell_custom", "Hub, Sidebar & Dock"), keywords: "fixados fixar pinned icones apps dock shell quickshell customizacao topbar barra sidebar hub aparencia widgets glass solid glow borderless escala" },
        { group: "look", tabIndex: 2, name: Theme.t("settings.cat_mako", "Notificações"), icon: Theme.icons.bell, desc: Theme.t("settings.desc_mako", "Posição & Estilo"), keywords: "mako notificacoes notifications som posicao borda alert toast banner avisos" },
        { group: "look", tabIndex: 1, name: Theme.t("settings.cat_kitty", "Kitty Terminal"), icon: Theme.icons.console, desc: Theme.t("settings.desc_kitty", "Fonte & Opacidade"), keywords: "kitty terminal console fonte font opacidade padding cursor audio blur som transparencia" },
        { group: "look", tabIndex: 0, name: Theme.t("settings.cat_fastfetch", "Fastfetch"), icon: Theme.icons.packages, desc: Theme.t("settings.desc_fastfetch", "Logo & Módulos"), keywords: "fastfetch neofetch logo distro terminal specs cpu ram hardware modelo" },

        { group: "hardware", tabIndex: 3, name: Theme.t("settings.cat_monitors", "Tela & Monitores"), icon: Theme.icons.monitor, desc: Theme.t("settings.desc_monitors", "Resolução & Taxa"), keywords: "tela monitor monitores display resolucao resolution refresh rate hz taxa atualizacao escala zoom scale hidpi brilho brightness vrr freesync g-sync frequencia rotacao girar vertical" },
        { group: "hardware", tabIndex: 4, name: Theme.t("settings.cat_audio", "Áudio & Som"), icon: Theme.icons.volHigh, desc: Theme.t("settings.desc_audio", "Saída & Microfone"), keywords: "audio som volume microfone mic fone speaker caixa sink source pipewire dispositivos" },
        { group: "hardware", tabIndex: 5, name: Theme.t("settings.cat_input", "Teclado & Mouse"), icon: Theme.icons.cursor, desc: Theme.t("settings.desc_input", "Teclado & Sensibilidade"), keywords: "teclado mouse keyboard layout abnt2 sensibilidade aceleração accel numlock atalhos velocidade ponteiro" },
        { group: "hardware", tabIndex: 6, name: Theme.t("settings.cat_power", "Energia & Bateria"), icon: Theme.icons.bat, desc: Theme.t("settings.desc_power", "Perfis & Saúde"), keywords: "energia bateria power perfis profiles economia desempenho saude health suspender sleep carga" },
        { group: "hardware", tabIndex: 10, name: Theme.t("settings.cat_bluetooth", "Bluetooth"), icon: Theme.icons.bt, desc: Theme.t("settings.desc_bluetooth", "Controles & Fones"), keywords: "bluetooth bt fones earbuds controle joystick pareamento connect conectar dispositivos" },
        { group: "hardware", tabIndex: 11, name: Theme.t("settings.cat_network", "Rede & Wi-Fi"), icon: Theme.icons.wifi4, desc: Theme.t("settings.desc_network", "Conexões & Latência"), keywords: "rede network wifi wi-fi conexao ethernet cabo ip dns ping latencia internet speed velocidade" },
        { group: "hardware", tabIndex: 13, name: Theme.t("settings.cat_gaming", "Jogos & GPU"), icon: Theme.icons.gamepad, desc: Theme.t("settings.desc_gaming", "Placa de Vídeo & Steam"), keywords: "jogos games gaming gpu placa de video nvidia prime prime-run dgpu igpu intel amd gamemode steam mangohud fps desempenho" },

        { group: "system", tabIndex: 7, name: Theme.t("settings.cat_boot", "Inicialização"), icon: Theme.icons.speed, desc: Theme.t("settings.desc_boot", "Apps ao Iniciar"), keywords: "boot inicializacao startup autostart apps servicos sddm limine login inicio ligar" },
        { group: "system", tabIndex: 12, name: Theme.t("settings.cat_defaults", "Aplicativos Padrão"), icon: Theme.icons.dashboard, desc: Theme.t("settings.desc_defaults", "Navegador, Pastas & Vídeo"), keywords: "aplicativos padrao default apps navegador browser chrome firefox zen brave pasta dolphin nautilus video vlc player musica mpv email editor code text" },
        { group: "system", tabIndex: 17, name: Theme.t("settings.cat_store", "Programas & Atualizações"), icon: Theme.icons.packages, desc: Theme.t("settings.desc_store", "Atualizar & Instalar"), keywords: "loja store updates atualizacoes pacotes packages arch pacman aur yay flatpak programas instalar adicionar remover" },
        { group: "system", tabIndex: 14, name: Theme.t("settings.cat_storage", "Armazenamento"), icon: Theme.icons.disk, desc: Theme.t("settings.desc_storage", "Limpeza de Disco"), keywords: "armazenamento storage disco disk hd ssd espaco limpar limpeza cache lixeira logs btrfs free space" },
        { group: "system", tabIndex: 16, name: Theme.t("settings.cat_system", "Sistema & Reparo"), icon: Theme.icons.health, desc: Theme.t("settings.desc_system", "Snapshots & Auto-Reparo"), keywords: "sistema system reparo repair consertar snapshot restauracao backup btrfs auto-reparo diagnostico info logs status" },

        { group: "help", tabIndex: 15, name: Theme.t("settings.cat_shortcuts", "Todos os Atalhos"), icon: Theme.icons.magnify, desc: Theme.t("settings.desc_shortcuts", "A lista inteira, lado a lado"), keywords: "atalhos shortcuts teclas binds keybinds cheatsheet super mod custom user-binds ajuda boas-vindas" }
    ]
}
