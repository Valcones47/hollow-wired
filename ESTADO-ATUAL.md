# Estado Atual do Setup (ESTADO-ATUAL.md)

> **Documento de referência primária do rice.**  
> Atualizado em: **2026-09-17**  
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
- **Terminal:** Kitty (`~/.config/kitty/kitty.conf`) com blur e opacidade ajustável ao vivo.
- **Bloqueio de Tela:** `hyprlock` (`~/.config/hypr/hyprlock.conf`).
- **Ociosidade:** `hypridle` (`~/.config/hypr/hypridle.conf`).
- **Documento Dedicado de Revisão & Auditoria:** [`MELHORIAS-E-REVISAO.md`](file:///home/val47/projetos/hyprland-setup/MELHORIAS-E-REVISAO.md).

---

## 2. Componentes de Interface (Quickshell)

Todos os elementos de interface gráfica do desktop são gerenciados pelo Quickshell:

| Componente | Arquivo Principal | Descrição |
|---|---|---|
| **Barra Superior** | `TopBar.qml` | Substitui a antiga Waybar. Workspaces animados em formato pill, título da janela ativa, relógio central que abre o Hub ao clicar, e popups com cantos invertidos para Áudio, Wi-Fi, Bluetooth e Bateria. Em tela cheia regular (jogos/vídeos), fica oculta sob a janela (`WlrLayer.Top`). Ao abrir o Launcher (`Super` ou `Super + R`), eleva-se dinamicamente para a camada `WlrLayer.Overlay` ordenada acima do Launcher, permitindo visualização e cliques completos em módulos, relógio e controles mesmo sobre tela cheia. |
| **Painel de Configurações Visuais (Rice Control Center)** | `VisualConfigPanel.qml`, scripts `rice-*` | Central gráfica completa com barra de navegação lateral (230px) e área de conteúdo fluida, aberta pelo ícone de sintonia (`Theme.icons.tune`) na TopBar, pelo atalho universal **`Super + I`** ou pelo menu de apps. Totalmente projetada para usuários iniciantes e avançados configurarem recursos sem tocar no terminal, expandida para **19 categorias completas**: **1. Fastfetch** (galeria visual de logos e GIFs animados em `~/Imagens/FastFetch`, reprodução e animação contínua de GIFs no Kitty via protocolo `kitty-icat`, sliders de dimensões, ativação interativa de módulos e preview no terminal); **2. Kitty Terminal** (opacidade, tamanho de fonte, window padding, cursor, blur e áudio bell); **3. Mako Notificações** (seletor matricial 3x2 de posição na tela, timeout, raio, borda e botão de teste imediato); **4. Tela & Monitores** (detecta display `eDP-1`, alternância 144Hz vs 60Hz, VRR FreeSync e slider de brilho); **5. Áudio & Som** (saídas e entradas PipeWire, controle de volumes e teste de canal estéreo E/D); **6. Teclado & Mouse** (seletor ABNT2 vs US Internacional, sensibilidade -1.0 a +1.0, aceleração Flat vs Adaptativa e NumLock no boot); **7. Energia & Bateria** (perfis Desempenho/Equilíbrio/Economia, saúde da bateria %, contagem de ciclos e potência em Watts); **8. Inicialização (Boot / Autostart)** (gerenciador com toggles ativar/desativar e catálogo de apps com 1-clique para adicionar); **9. Cores & Wallust** (visualização de 16 cores ANSI do wallpaper, cópia HEX para clipboard, regenerar cores e switcher); **10. Efeitos & Janelas** (luz noturna Hyprsunset com slider em Kelvin, escurecimento inativo, rounding, gaps, presets de animação e temas SDDM/Limine); **11. Bluetooth & Periféricos** (gerenciador visual `rice-bluetooth` com toggle do adaptador, lista de pareados com ícones inteligentes de gamepad/fones e 1-clique conectar/remover); **12. Rede & Wi-Fi** (status da conexão, SSID, IP, gateway, latência/ping em tempo real, toggle Wi-Fi e varredura de redes próximas); **13. Aplicativos Padrão** (associações XDG para Navegador, Gerenciador de Arquivos, Editor, Vídeo e Imagem); **14. Jogos & Gráficos NVIDIA** (monitoramento em tempo real da RTX 3050 Laptop GPU, VRAM usada/total, temperatura, Feral GameMode e gerador de opções de inicialização Steam); **15. Armazenamento & Limpeza** (monitor do SSD Btrfs e limpeza segura de cache pacman, thumbnails, lixeira e cache de usuário); **16. Guia de Atalhos** (cheat sheet interativo com filtro e busca instantânea de teclas); **17. Sistema, Snapshots & Reparo** (snapshots Btrfs com 1 clique e botões de auto-reparo de áudio, pacman travado e Rice Doctor); **18. Central de Aplicativos & Atualizações** (`rice-software` com detecção de pacotes desatualizados do Arch/AUR, 1-clique para atualizar o sistema em terminal amigável e catálogo de softwares recomendados com botões Instalar/Abrir/Remover); **19. Perfis de Estilo & Gerenciador de Backup** (`rice-presets` com 5 presets estéticos/desempenho: Cyberpunk Neon, Tokyo Night, Catppuccin Mocha, Modo Competitivo 0ms e Glassmorphism Ultra, além de sistema completo de criação e restauração de pontos de backup `.tar.gz`). |
| **Hub Central** | `Dashboard.qml` e módulos | Aberto pelo relógio da TopBar. Janela flutuante com abas: Dashboard (visão geral, avatar animado `.face.webp` da Rem, player de áudio/cava), Mídia, **Performance** (`Monitoring.qml` e `SysStats.qml` com medidor de RAM Real deduzindo buffers/cache, chips de disco/swap, botão **Limpar Caches & Otimizar** via `rice-ram-cleaner` e botão/modal explicativo **"Não necessário"** detalhando a arquitetura do page cache do kernel Linux), Workspaces, **Aparência** (`Appearance.qml`), Notificações e **Gravação de Tela** (`Recording.qml`). Fecha ao clicar fora. |
| **Estúdio de Gravação** | `Recording.qml`, `rice-record` | Aba de gravação de tela estilo OBS no Hub central. Utiliza a **dGPU NVIDIA RTX 3050 com NVENC por padrão** (`h264_nvenc`) com 0% de impacto na CPU/iGPU, permitindo alternar também para Intel (VAAPI) ou CPU. Permite gravar **Tela Inteira** (`eDP-1`), **Aplicativo / Janela** específica ou **Região livre** da tela via `slurp`. Toggles independentes de **Áudio do Sistema** e **Microfone** via PipeWire. Grava em `/home/val47/Vídeos/Gravações` com mini-galeria de vídeos recentes, botão de reprodução via player padrão do sistema e exclusão imediata pelo botão de lixeira sem travamentos. |
| **OSD Flutuante** | `OSD.qml` | Pílula flutuante animada estilo Caelestia / Dynamic Island logo abaixo da TopBar. Substituiu o `swayosd`. Exibe feedback em tempo real para Volume, Mute do Microfone e Brilho. Totalmente click-through (`mask: Region {}`). |
| **Cheatsheet de Atalhos** | `Cheatsheet.qml` | Modal central translúcido acionado por `Super + F1` exibindo todos os atalhos organizados por categorias, busca instantânea e fechamento suave via Esc ou clique fora. |
| **Gerenciador de Clipboard** | `Clipboard.qml` | Gerenciador nativo de área de transferência integrado no Quickshell acionado por `Super + V`. **Aposentou completamente o Rofi**. Suporta busca em tempo real, visualização de imagens cacheadas, cópia rápida e limpeza do `cliphist`. |
| **Widgets de Desktop Nativos** | `DesktopWidgets.qml` | Motor avançado de widgets na camada `WlrLayer.Bottom` (acima do wallpaper, abaixo das janelas). Permite arrastar livremente, ordenar por grade magnética (*Snap to Grid* de 20px), customizar via **Inspector visual** (4 estilos: `glass`, `solid`, `glow`, `borderless`; 3 escalas: 80%, 100%, 120%; 4 opacidades de fundo; 6 cores de destaque), duplicar e deletar. Inclui **13 widgets nativos**: Relógio Digital, Relógio Analógico Minimalista, Player de Mídia com vinil giratório animado, Medidores de Sistema (CPU, RTX 3050, RAM Real), Top Processos, Velocidade de Rede em tempo real, Calendário Mensal em grade, Monitor de Bateria, Uso de Armazenamento Btrfs, Timer Pomodoro, Bloco de Notas persistente, Previsão do Tempo (`wttr.in`) e Frase do Dia. Configurações salvas e isoladas por workspace em `~/.config/quickshell/desktop-widgets.json`. Modo de edição entra/sai com `Super + W` ou clique direito no desktop. |
| **Notificações & Modo DND** | `NotifService.qml`, `TopBar.qml`, `Notifications.qml` | Sistema unificado de notificações com suporte a Modo Não Perturbe (*Do Not Disturb*). Badge dinâmico na TopBar com contagem de não-lidas, popup expansível e atalho `Super + N`. |
| **Aparência & Customizer** | `Appearance.qml`, `rice-hypr-prefs` | Aba de personalização ao vivo do Hyprland no Hub central (inspirada no Noctalia/Caelestia). Permite ajustar em tempo real: arredondamento das janelas (0 a 24px), espessura das bordas (0 a 4px), gaps internos e externos, opacidade de janelas inativas, escurecimento (dim) e curvas de animação (**Rápido/Snap**, **Suave/Padrão**, **Elástico/Caelestia**). Persiste em `~/.config/hypr/user-prefs.json`. |
| **Launcher de Apps** | `Launcher.qml` | Abre com `Super + R` ou tecla `Super` isolada. Lista vertical alfabética (A → Z) de cima para baixo com scrollbar sutil de 4px, sensibilidade de rolagem rápida, pesquisa instantânea com foco de teclado automático (`Exclusive`), menu de contexto com botão direito (fixar na dock, adicionar aos jogos). Em `shell.qml`, é instanciado na base da camada `Overlay`, liberando cliques e hover diretos para a TopBar, Dock e EnergySidebar sobrepostas. |
| **Dock Inferior** | `Dock.qml`, `DockConfig.qml` | Retrátil com auto-hide (revela ao encostar o mouse na borda inferior). Em tela cheia regular, permanece inativa no `WlrLayer.Top` (sem hover). Ao abrir o Launcher, eleva-se para `WlrLayer.Overlay` sobre o Launcher, permitindo hover e clique em apps mesmo durante jogos ou vídeos em tela cheia. |
| **Barra de Energia** | `EnergySidebar.qml`, `rice-session-action` | Barra retrátil na borda lateral direita. Em tela cheia regular, permanece no `WlrLayer.Top` com hover 100% desativado e máscara de cliques vazia (zero interferência em jogos). Ao abrir o Launcher (`Super`/`Super+R`), eleva-se dinamicamente para `WlrLayer.Overlay` sobre o Launcher com hover e cliques ativos sobre a tela cheia. Contém avatar animado, contagem de atualizações de pacotes, atalhos de luz noturna e status da dGPU NVIDIA, system trays integrados e controles de energia. |
| **Alternador Alt+Tab** | `AltTab.qml` | Switcher central com miniaturas ao vivo (`ScreencopyView`) ordenadas pelo histórico de foco do Hyprland. Permite navegar com Tab/setas e fechar janelas com `Q`. |
| **Moldura de Tela** | `Frame.qml` | Borda estética de 10px nas laterais e base com cantos internos arredondados (raio 20). |

---

## 3. Gestão de Gráficos e Otimizações de Latência/Frametime

- **Compositor e Desktop:** Forçados a rodar na iGPU Intel via Mesa (`__NV_PRIME_RENDER_OFFLOAD=0`, `__GLX_VENDOR_LIBRARY_NAME=mesa`).
- **Direct Scanout Desativado (`render:direct_scanout = 0`):** Desativado para evitar oscilações de sincronização e flickering visual com as camadas do Quickshell/layer-shell.
- **Zero Blur no Layer de Widgets (`namespace = "quickshell-desktop-widgets"`):** Regra `blur = false` no `hyprland.lua`, impedindo que o Hyprland execute passadas de blur de 1920x1080 em tela cheia na Intel UHD sob os widgets do desktop. Economiza 15-25% de taxa de preenchimento a 144Hz.
- **Otimizações de Render & XWayland:** `misc:disable_splash_rendering = true` (elimina alocação de splash) e `xwayland:force_zero_scaling = true` (elimina passadas bilineares de reescalonamento em apps legados).
- **VRR Desativado no Desktop (`misc:vrr = 0`):** Desativa o refresh rate adaptativo no desktop. Elimina 100% o bug de flickering/piscamento de tela e aplicativos do notebook (painel AU Optronics 144Hz) que ocorria quando o cursor do mouse ficava parado/ocioso.
- **Tearing Imediato Opcional (`general:allow_tearing = true`):** Destrava o triple-buffering forçado do Wayland para jogos com foco em latência de entrada.
- **Sombras Desativadas (`decoration:shadow:enabled = false`):** Alivia a taxa de preenchimento (fillrate) da iGPU Intel a 144Hz.
- **Jogos e Apps 3D:** Executados via wrapper `prime-run` oficial da NVIDIA (`/usr/bin/prime-run`), direcionando a renderização para a RTX 3050 Laptop GPU.
- **Limpeza de Memória e Background:** Aba de Performance do Hub conta com medidor de RAM Real (AnonPages puro sem inflar com cache) e botão "Limpar Caches & Otimizar" que executa o `rice-ram-cleaner` (expurga drop_caches de forma segura e finaliza processos zumbis/órfãos do KDE).
- **Correção Automática do Mod2 / NumLock no XWayland:** Utilitário `~/.local/bin/rice-fix-xwayland-numlock` disparado no autostart do `hyprland.lua` desvincula o `Num_Lock` do modificador `Mod2` no XWayland, eliminando bugs onde o Discord, Steam ou jogos capturam `NumLock` fantasma em atalhos ou push-to-talk.
- **Otimizador de Cenas do Wallpaper Engine (`rice-wallpaper-optimize`):** Utilitário CLI nativo em Python para inspecionar e otimizar pacotes `scene.pkg` (formato PKGV001). Detecta e redimensiona texturas gigantescas (4K/6K como 5760x3240) diretamente para 1080p nativo com filtro Lanczos, equilibra passes de shaders (limitando iterações abusivas de Bloom HDR) e reempacota o arquivo mantendo backup `.pkg.original`, garantindo que papéis de parede pesados da Oficina Steam rodem a 144 FPS na iGPU sem travamentos.
- **Portabilidade Universal e Desacoplamento:** O Quickshell e o Hyprland foram 100% desacoplados de caminhos de usuário (`$HOME` / `Quickshell.env("HOME")`), a leitura de GPU (`SysStats.gpuName`) detecta dinamicamente modelos NVIDIA, AMD ou Intel, a leitura térmica suporta tanto Intel quanto AMD Ryzen (`Tctl`), e o card de bateria se adapta dinamicamente para computadores desktop.
- **Novo Utilitário de Perfil (`rice-set-avatar`):** Permite trocar foto ou GIF de perfil com 1 clique diretamente pelo Dashboard ou atalho gráfico (`zenity`/`kdialog`).
- **Seletor de Arquivos Integrado (KDE / Dolphin FileChooser Portal):** Configurado via `~/.config/xdg-desktop-portal/portals.conf` e `hyprland-portals.conf` definindo `org.freedesktop.impl.portal.FileChooser=kde`. Quando qualquer navegador (Zen, Chrome), aplicativo (Discord) ou jogo solicita abrir/salvar arquivos, invoca nativamente a interface do Dolphin/KDE com tema escuro consistente (Breeze Dark), atalhos laterais de pastas e miniaturas, substituindo o seletor genérico em branco do GTK.
- **Tela de Login SDDM (SilentSDDM + Wallust + Waywallen):**
  - **Correção de Display Manager (SDDM vs Plasmalogin):** Identificado que o serviço `plasmalogin.service` (do KDE 6) estava ativado como gerenciador principal, impedindo o SDDM de subir no boot. O script `rice-sddm-install` agora desativa automaticamente `plasmalogin.service`, ativa `sddm.service` e configura `/etc/sddm.conf.d/theme.conf.user` com tema `SilentSDDM`.
  - **Wallpaper Dinâmico Pausado:** Script `rice-sddm-sync-wallpaper` captura automaticamente um frame limpo em 1080p (`grim`) na troca de wallpaper no `waywallen-switcher` (ocultando TopBar e mudando para workspace vazia temporariamente) e grava em `/usr/share/sddm/themes/SilentSDDM/backgrounds/current.png`.
  - **Paleta Wallust em Tempo Real:** Template `~/.config/wallust/templates/sddm-theme.conf` integrado ao `wallust.toml` aplica as cores dinâmicas no tema do SDDM a cada troca de papel de parede.
  - **Seletor de Sessão / WM Modernizado:** Redesenhado com botão largo (220px), indicador `▾`, ícones dedicados (Hyprland, Plasma KDE, Sway, Gamescope), marcação visual de sessão ativa com checkmark e atalho de teclado `F2`.
  - **Avatar do Usuário:** Carregamento automático da foto de perfil (`~/.face` da Rem) em máscara circular com borda de destaque na cor acentuada do tema.
  - **Data e Hora em Português:** Data formatada em português brasileiro com inicial maiúscula (ex: *"Quarta-feira, 16 de setembro"*).
  - **Calibração de Mouse 1:1:** Drop-in `/etc/X11/xorg.conf.d/50-mouse.conf` com `Option "AccelProfile" "flat"` e `Option "AccelSpeed" "0"`, eliminando a aceleração estranha e deixando o ponteiro do SDDM idêntico ao do Hyprland.
- **Bootloader Limine Personalizado com Wallpaper Suavizado:**
  - Script utilitário `rice-limine-theme` (`~/.local/bin/rice-limine-theme`) para aplicar no `/boot/limine.conf`: resolução nativa 1920x1080, processamento de imagem via `ffmpeg` com filtro Gaussian Blur sutil (`gblur=sigma=12,eq=brightness=-0.12`) para `/boot/limine-wallpaper.png` garantindo contraste nítido e legibilidade perfeita do texto das entradas de kernel/snapshots Btrfs, transparência escura no terminal (`term_background = 90170D0C`), paleta Wallust completa, branding estilizado (`CachyOS // Hyprland`) e timeout de 5 segundos.
- **Utilitário Unificado de Boot & Login (`rice-apply-boot-login`):**
  - Wrapper único que executa o `rice-sddm-install` e o `rice-limine-theme` em sequência com tratamento automático de elevação de privilégios (`sudo`). Também integrado diretamente na interface gráfica na aba "Efeitos & Hyprland" do `VisualConfigPanel.qml` e como entrada `.desktop` no menu de apps.
- **Utilitário de Diagnóstico e Reparo Rápido (`rice-doctor`):**
  - Ferramenta com interface amigável via terminal (`kitty --title "Rice Doctor" rice-doctor`) acessível pelo menu de aplicativos. Diagnostica e oferece reparo em 1 clique para: áudio PipeWire travado, trava do banco do pacman (`db.lck`), limpeza de caches antigos, ativação do display manager SDDM e status do zRAM e placa NVIDIA RTX 3050.
- **Integração de Atalhos Gráficos (.desktop):**
  - Adicionados arquivos `.desktop` em `~/.local/share/applications/` e `dots/applications/` para: **Configurações Visuais do Rice**, **Reparador do Sistema (Rice Doctor)** e **Configurar Login e Boot (SDDM & Limine)**, permitindo busca e execução direta no Launcher (`Super`).


---

## 4. Repositórios e Estratégia de Backup em Nuvem

| Camada | Destino | Descrição |
|---|---|---|
| **Repositório Público Universal** | [`Valcones47/hyprland-setup`](https://github.com/Valcones47/hyprland-setup) | Código-fonte completo do rice, dotfiles limpos e instalador automatizado (`install.sh`) com detecção de GPU/CPU e configuração de zRAM. Pronto para compartilhar com amigos (como o Raul) ou instalar em qualquer PC. |
| **Repositório Privado Pessoal** | [`Valcones47/cachyos-dotfiles`](https://github.com/Valcones47/cachyos-dotfiles) | Totalmente migrado do antigo setup de KDE Plasma para o **Hyprland + Quickshell**. Contém scripts de restauração em 1 comando (`restore-personal.sh`), atalhos de layout de widgets, avatar pessoal da Rem e preferências do usuário. |
| **Google Drive (Assets Pesados)** | `gdrive:Linuxconfig/` via `rclone` | Armazenamento dos arquivos pesados (>100 MB): pasta `Wallpapers-Waywallen/` (680 MB em cenas do Wallpaper Engine), pasta `Videos/` (gravações de demonstração) e pasta `Backups/` (tarball completo de 1.9 GB das sessões do Zen Browser, Discord e Steam). |

---

## 4. Atalhos Globais Ativos (`hyprland.lua`)

| Atalho | Ação |
|---|---|
| `Super` (solto) | Abre/Fecha o Launcher do Quickshell |
| `Super + R` | Abre/Fecha o Launcher do Quickshell |
| `Super + Q` | Abre o terminal Kitty |
| `Super + E` | Abre o gerenciador de arquivos Dolphin |
| `Super + I` | Abre a Central de Configurações Visuais do Rice (`VisualConfigPanel.qml`) |
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
| `XF86AudioMicMute` | Mute de microfone no PipeWire com feedback visual no OSD flutuante |
| `Num_Lock` | Desativar/ativar áudio (*Deafen*) nativo do Discord em segundo plano via `send_shortcut Ctrl+Shift+D` |
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
