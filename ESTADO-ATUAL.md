# Estado Atual do Setup (ESTADO-ATUAL.md)

> **Documento de referência primária do rice.**  
> Atualizado em: **2026-09-16**  
> *Regra para agentes e desenvolvedores: Sempre que fizer alterações no rice, atualize este arquivo para refletir o estado vigente.*

---

## 1. Arquitetura Core

- **Sistema Operacional:** CachyOS (base Arch Linux, Kernel Linux 7.2.4-cachyos, FS Btrfs com Snapper/Limine).
- **Compositor:** Hyprland 0.56.2 com backend Aquamarine 0.15.0 (`configProvider: lua`).
- **Arquivo de Configuração Ativo:** [`~/.config/hypr/hyprland.lua`](file:///home/val47/.config/hypr/hyprland.lua).
  > ⚠️ **IMPORTANTE:** O arquivo `hyprland.conf` está **deprecado e não é carregado**. Todas as configurações do compositor estão centralizadas no `hyprland.lua`.
- **Shell e Widgets:** **Quickshell** (QML nativo com Wayland layer-shell) em [`~/.config/quickshell/`](file:///home/val47/.config/quickshell/).
- **Wallpaper Engine:** **Waywallen** (Flatpak + helper nativo `~/.local/bin/waywallen-layer-shell`). Pausa automaticamente quando janelas estão em tela cheia.
- **Cores & Tema:** Dinâmico via **Wallust** lendo o wallpaper atual e gerando `~/.config/hypr/colors.conf`, que é importado pelo `hyprland.lua` e consumido pelos componentes.
- **Terminal:** Kitty (`~/.config/kitty/kitty.conf`) com blur e opacidade 0.64.
- **Bloqueio de Tela:** `hyprlock` (`~/.config/hypr/hyprlock.conf`).
- **Ociosidade:** `hypridle` (`~/.config/hypr/hypridle.conf`).
- **Documento Dedicado de Revisão & Auditoria:** [`MELHORIAS-E-REVISAO.md`](file:///home/val47/projetos/hyprland-setup/MELHORIAS-E-REVISAO.md).

---

## 2. Componentes de Interface (Quickshell)

Todos os elementos de interface gráfica do desktop são gerenciados pelo Quickshell:

| Componente | Arquivo Principal | Descrição |
|---|---|---|
| **Barra Superior** | `TopBar.qml` | Substitui a antiga Waybar. Workspaces animados em formato pill, título da janela ativa, relógio central que abre o Hub ao clicar, e popups com cantos invertidos para Áudio, Wi-Fi, Bluetooth e Bateria. Na aba de **Bateria**, além dos perfis de energia (`Economia`, `Equilíbrio`, `Desempenho`), inclui 3 toggles rápidos de **Otimizações de GPU & Tela**: **Modo Jogo** (`GameMode.qml`), **Toggle de Blur** (`rice-blur-toggle`) e **Super Desempenho** (`rice-perf-mode` com 0% overhead na iGPU). |
| **Hub Central** | `Dashboard.qml` e módulos | Aberto pelo relógio da TopBar. Janela flutuante com abas: Dashboard (visão geral, avatar animado `.face.webp` da Rem, player de áudio/cava), Mídia, **Performance** (`Monitoring.qml` e `SysStats.qml` com medidor de RAM Real deduzindo buffers/cache, chips de disco/swap e botão **Limpar Caches & Otimizar** via `rice-ram-cleaner`), Workspaces, **Aparência** (`Appearance.qml`), Notificações e **Gravação de Tela** (`Recording.qml`). Fecha ao clicar fora. |
| **Estúdio de Gravação** | `Recording.qml`, `rice-record` | Aba de gravação de tela estilo OBS no Hub central (substituiu a aba de Snapshots). Utiliza a **dGPU NVIDIA RTX 3050 com NVENC por padrão** (`h264_nvenc`) com 0% de impacto na CPU/iGPU, permitindo alternar também para Intel (VAAPI) ou CPU. Permite gravar **Tela Inteira** (`eDP-1`), **Aplicativo / Janela** específica (com chips interativos das janelas abertas) ou **Região livre** da tela via `slurp`. Suporta toggles independentes de **Áudio do Sistema** e **Microfone** com mixagem automática estéreo via PipeWire (`module-null-sink`). 100% harmonizada com a paleta escura do Wallust (`Theme.tile`). Grava diretamente em `/home/val47/Vídeos/Gravações` com botão rápido "Abrir Pasta", mini-galeria de vídeos recentes, botão de reprodução, exclusão e contador de tempo decorrido ao vivo. |
| **OSD Flutuante** | `OSD.qml` | Pílula flutuante animada estilo Caelestia / Dynamic Island logo abaixo da TopBar. Substituiu o `swayosd`. Exibe feedback em tempo real para Volume, Mute do Microfone e Brilho. Totalmente click-through (`mask: Region {}`). |
| **Cheatsheet de Atalhos** | `Cheatsheet.qml` | Modal central translúcido acionado por `Super + F1` exibindo todos os atalhos organizados por categorias, busca instantânea e fechamento suave via Esc ou clique fora. |
| **Gerenciador de Clipboard** | `Clipboard.qml` | Gerenciador nativo de área de transferência integrado no Quickshell acionado por `Super + V`. **Aposentou completamente o Rofi**. Suporta busca em tempo real, visualização de imagens cacheadas, cópia rápida e limpeza do `cliphist`. |
| **Widgets de Desktop Nativos** | `DesktopWidgets.qml` | Motor avançado de widgets na camada `WlrLayer.Bottom` (acima do wallpaper, abaixo das janelas). Permite arrastar livremente, ordenar por grade magnética (*Snap to Grid* de 20px), customizar via **Inspector visual** (4 estilos: `glass`, `solid`, `glow`, `borderless`; 3 escalas: 80%, 100%, 120%; 4 opacidades de fundo; 6 cores de destaque), duplicar e deletar. Inclui **13 widgets nativos**: Relógio Digital, Relógio Analógico Minimalista, Player de Mídia com vinil giratório animado, Medidores de Sistema (CPU, RTX 3050, RAM Real), Top Processos, Velocidade de Rede em tempo real, Calendário Mensal em grade, Monitor de Bateria, Uso de Armazenamento Btrfs, Timer Pomodoro, Bloco de Notas persistente, Previsão do Tempo (`wttr.in`) e Frase do Dia. Configurações salvas e isoladas por workspace em `~/.config/quickshell/desktop-widgets.json`. Modo de edição entra/sai com `Super + W` ou clique direito no desktop. |
| **Notificações & Modo DND** | `NotifService.qml`, `TopBar.qml`, `Notifications.qml` | Sistema unificado de notificações com suporte a Modo Não Perturbe (*Do Not Disturb*). Badge dinâmico na TopBar com contagem de não-lidas, popup expansível e atalho `Super + N`. |
| **Aparência & Customizer** | `Appearance.qml`, `rice-hypr-prefs` | Aba de personalização ao vivo do Hyprland no Hub central (inspirada no Noctalia/Caelestia). Permite ajustar em tempo real: arredondamento das janelas (0 a 24px), espessura das bordas (0 a 4px), gaps internos e externos, opacidade de janelas inativas, escurecimento (dim) e curvas de animação (**Rápido/Snap**, **Suave/Padrão**, **Elástico/Caelestia**). Persiste em `~/.config/hypr/user-prefs.json`. |
| **Launcher de Apps** | `Launcher.qml` | Abre com `Super + R` ou tecla `Super` isolada. Lista vertical alfabética (A → Z) de cima para baixo com scrollbar sutil de 4px, sensibilidade de rolagem rápida, pesquisa instantânea, menu de contexto com botão direito (fixar na dock, adicionar aos jogos). |
| **Dock Inferior** | `Dock.qml`, `DockConfig.qml` | Retrátil com auto-hide (revela ao encostar o mouse na borda inferior). Exibe os apps fixados e abertos com badges do workspace atual (`1·3` ou `✦`), reordenação por arrasto e popup de Jogos sincronizados em `~/.config/quickshell/dock.json`. |
| **Barra de Energia** | `EnergySidebar.qml` | Barra retrátil na borda lateral direita (gatilho no hover). Contém avatar animado, contagem de atualizações de pacotes, atalhos de luz noturna e status da dGPU NVIDIA, system trays integrados e controles de energia com confirmação em duas etapas. |
| **Alternador Alt+Tab** | `AltTab.qml` | Switcher central com miniaturas ao vivo (`ScreencopyView`) ordenadas pelo histórico de foco do Hyprland. Permite navegar com Tab/setas e fechar janelas com `Q`. |
| **Moldura de Tela** | `Frame.qml` | Borda estética de 10px nas laterais e base com cantos internos arredondados (raio 20). |

---

## 3. Gestão de Gráficos e Otimizações de Latência/Frametime

- **Compositor e Desktop:** Forçados a rodar na iGPU Intel via Mesa (`__NV_PRIME_RENDER_OFFLOAD=0`, `__GLX_VENDOR_LIBRARY_NAME=mesa`).
- **Direct Scanout Ativo (`render:direct_scanout = 1`):** Em jogos fullscreen na dGPU NVIDIA, o Hyprland entrega o buffer diretamente ao KMS/display controller da Intel, **bypasando a composição 3D da iGPU** e eliminando latência.
- **Zero Blur no Layer de Widgets (`namespace = "quickshell-desktop-widgets"`):** Regra `blur = false` no `hyprland.lua`, impedindo que o Hyprland execute passadas de blur de 1920x1080 em tela cheia na Intel UHD sob os widgets do desktop. Economiza 15-25% de taxa de preenchimento a 144Hz.
- **Otimizações de Render & XWayland:** `misc:disable_splash_rendering = true` (elimina alocação de splash) e `xwayland:force_zero_scaling = true` (elimina passadas bilineares de reescalonamento em apps legados).
- **VRR Habilitado (`misc:vrr = 1`):** Sincronização de taxa de atualização variável ativa no monitor 144Hz.
- **Tearing Imediato Opcional (`general:allow_tearing = true`):** Destrava o triple-buffering forçado do Wayland para jogos com foco em latência de entrada.
- **Sombras Desativadas (`decoration:shadow:enabled = false`):** Alivia a taxa de preenchimento (fillrate) da iGPU Intel a 144Hz.
- **Jogos e Apps 3D:** Executados via wrapper `~/.local/bin/game-run`, isolando a RTX 3050 via camada `MESA_VK_DEVICE_SELECT=10de:25a2` e ativando DLSS via `PROTON_ENABLE_NVAPI=1`.
- **Limpeza de Memória e Background:** Aba de Performance do Hub conta com medidor de RAM Real (AnonPages puro sem inflar com cache) e botão "Limpar Caches & Otimizar" que executa o `rice-ram-cleaner` (expurga drop_caches de forma segura e finaliza processos zumbis/órfãos do KDE).
- **Correção Automática do Mod2 / NumLock no XWayland:** Utilitário `~/.local/bin/rice-fix-xwayland-numlock` disparado no autostart do `hyprland.lua` desvincula o `Num_Lock` do modificador `Mod2` no XWayland, eliminando bugs onde o Discord, Steam ou jogos capturam `NumLock` fantasma em atalhos ou push-to-talk.

---

## 4. Atalhos Globais Ativos (`hyprland.lua`)

| Atalho | Ação |
|---|---|
| `Super` (solto) | Abre/Fecha o Launcher do Quickshell |
| `Super + R` | Abre/Fecha o Launcher do Quickshell |
| `Super + Q` | Abre o terminal Kitty |
| `Super + E` | Abre o gerenciador de arquivos Dolphin |
| `Super + F1` | Cheatsheet completa de atalhos (`Cheatsheet.qml`) |
| `Super + V` | Histórico do clipboard nativo no Quickshell (`Clipboard.qml`) |
| `Super + W` | Ativa/Desativa o modo de edição dos Widgets de Desktop (`DesktopWidgets.qml`) |
| `Super + N` | Abre a Central de Notificações no Hub |
| `Super + Shift + N` | Alterna o Modo Não Perturbe (DND) (`rice-dnd` / `makoctl`) |
| `Super + B` | Alterna o Blur ligado/desligado (`rice-blur-toggle`) |
| `Super + Shift + B` | Alterna o **Modo Ultra-Desempenho** (Blur e Animações OFF para 0% overhead na iGPU) (`rice-perf-mode`) |
| `Super + '` | Abre/oculta o terminal suspenso (*dropterm*) |
| `Super + S` | Abre o carrossel seletor de wallpapers (`waywallen-switcher`) |
| `Super + L` | Bloqueia a sessão (`hyprlock`) |
| `Super + M` | Encerra a sessão Hyprland |
| `Alt + Tab` | Alternador de janelas com miniaturas ao vivo |
| `Super + Shift + S` | Captura de tela interativa com anotação (grim + slurp + swappy) |
| `Super + Shift + R` | Inicia/para gravação de região da tela (`rice-record`) |
| `Super + Ctrl + Shift + R` | Grava a tela inteira |
| `Super + Shift + C` | Conta-gotas de cores (`hyprpicker`) |
| `Super + Shift + X` | Força encerramento de janela travada (`hyprctl kill`) |
| `Super + Ctrl + R` | Reinício de emergência do Quickshell (`rice-restart`) |
| `XF86Audio*` | Controle de volume (+ / - / mute) com feedback visual no OSD flutuante |
| `XF86MonBrightness*` | Controle de brilho de tela (+ / -) com feedback visual no OSD flutuante |
| `Num_Lock` | Mute de microfone no PipeWire com feedback visual no OSD flutuante |
| `XF86AudioPlay` / `XF86AudioPrev` / `XF86AudioNext` | Botões de mídia do teclado (play/pause, anterior, próximo) via `playerctl`, controlando o player MPRIS ativo |

---

## 5. Papel das Ferramentas Auxiliares

- **Rofi:** Totalmente descontinuado e substituído pelo `Clipboard.qml` nativo no Quickshell.
- **SwayOSD:** Totalmente desativado e removido do autostart (substituído pelo `OSD.qml` nativo no Quickshell).
- **Wofi:** Totalmente descartado/desnecessário.
- **Waybar:** Desativada do autostart (substituída pela `TopBar.qml` do Quickshell).
- **Hyprpaper:** Não utilizado (o wallpaper dinâmico é provido pelo Waywallen).
- **Mako:** Daemon de notificações Wayland ativo, sincronizado com o `NotifService.qml` no Quickshell.
- **Documentação de Revisão:** Detalhada em [`MELHORIAS-E-REVISAO.md`](file:///home/val47/projetos/hyprland-setup/MELHORIAS-E-REVISAO.md).
