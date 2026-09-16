# Setup Hyprland — Sessão Isolada do Plasma

Documentação do ambiente Hyprland no CachyOS. Sessão totalmente isolada da sessão Plasma existente — nenhum arquivo de configuração do KDE foi alterado.

> **Configuração Core:** O compositor utiliza exclusivamente o arquivo [`~/.config/hypr/hyprland.lua`](file:///home/val47/.config/hypr/hyprland.lua) (`configProvider: lua`). O antigo `hyprland.conf` está **deprecado e desativado**.  
> Para consultar o panorama rápido e atual de componentes do rice, veja [`ESTADO-ATUAL.md`](file:///home/val47/projetos/hyprland-setup/ESTADO-ATUAL.md).

---

## 1. Estado do Sistema e Hardware

- **Distro:** CachyOS (base Arch Linux, Kernel Linux 7.2.4-cachyos, FS raiz: **Btrfs**).
- **GPU Híbrida:** Intel TigerLake-H (i915/UHD Graphics) + NVIDIA GeForce RTX 3050 Mobile (driver `nvidia` 615.71.09).
  - A tela interna do laptop (eDP-1) é ligada fisicamente à Intel.
  - O Hyprland e o Quickshell rodam via **Mesa / iGPU Intel** (`__NV_PRIME_RENDER_OFFLOAD=0`, `__GLX_VENDOR_LIBRARY_NAME=mesa`) para eliminar lag de cópia entre GPUs via SHM.
  - Jogos rodam dedicados na NVIDIA via script wrapper `~/.local/bin/game-run` com `MESA_VK_DEVICE_SELECT=10de:25a2` e DLSS ativo (`PROTON_ENABLE_NVAPI=1`).
- **Navegador Padrão:** Zen Browser (`zen-browser`, otimizado com aceleração por hardware via `user.js`).
- **Locale & Teclado:** `pt_BR.UTF-8`, teclado `br` (ABNT2).
- **Cursor:** `Bibata-Modern-Ice` (tamanho 24).

---

## 2. Backup e Rollback (Btrfs / Snapper / Limine)

O sistema utiliza Btrfs com snapshots automáticos e manuais via **Snapper** (config `root`):

> ⚠️ **Atenção sobre Rollback:** O comando `sudo snapper -c root rollback N` **não funciona diretamente** neste sistema porque o `/etc/fstab` monta `subvol=/@` fixo e o boot é gerenciado pelo Limine com `limine-snapper-sync`.  
> **Procedimento correto de restauração:**
> 1. Reiniciar a máquina. No menu do Limine, entrar em **Snapshots** e selecionar o snapshot desejado.
> 2. Inicializar a sessão dentro do snapshot e executar:
>    ```bash
>    sudo limine-snapper-restore
>    ```
>    *(ou utilizar o botão "Tornar este snapshot permanente" na aba Snapshots do Hub Quickshell).*
> 3. Reiniciar novamente.

---

## 3. Shell e Interface Gráfica (Quickshell)

Toda a interface gráfica é desenvolvida de forma nativa e integrada em **Quickshell (QML)**, substituindo a antiga Waybar e menus legados:

- **TopBar (`TopBar.qml`):** Barra superior de 34px de altura. Contém visualizador animado de workspaces (pill deslizante), título da janela ativa, relógio central (clique abre o Hub) e menus popup com cantos invertidos para controle de Áudio, Bateria, Wi-Fi e Bluetooth.
- **Hub Central:** Menu flutuante de tamanho fixo com abas integradas:
  - *Dashboard:* Visão geral, avatar animado da Rem (`~/.face.webp`), visualizador de áudio Cava.
  - *Media:* Controle de mídia ativo via MPRIS (`playerctl`).
  - *Monitoring:* Medidores circulares de CPU, RAM, GPU e Disco.
  - *Workspaces:* Visão geral das janelas abertas por workspace.
  - *SysInfo:* Informações completas de hardware e sistema.
  - *Snapshots:* Consulta e restauração de snapshots do Snapper/Limine.
  - *Notificações:* Histórico de alertas do sistema.
- **Dock Inferior (`Dock.qml` e `DockConfig.qml`):** Barra retrátil com auto-hide (revela apenas ao posicionar o cursor na borda inferior da tela). Exibe aplicativos fixados e abertos, indicadores de workspace onde cada app está alocado (`1·3` ou `✦`), reordenação por arrasto e gaveta de Jogos com modo de edição.
- **Launcher de Aplicativos (`Launcher.qml`):** Abre com `Super + R` ou pressionando a tecla `Super` sozinha. Ordenado alfabeticamente (A → Z) do topo para baixo, busca instantânea por digitação, navegação completa por teclado (setas/Tab/Enter/Esc) e menu de contexto no botão direito (fixar na dock, adicionar aos jogos, editar entrada via `kmenuedit`).
- **EnergySidebar (`EnergySidebar.qml`):** Barra lateral retrátil oculta na borda direita. Contém avatar animado, botão de atualizações pendentes com atalhos de manutenção (abrir cachy-update, limpar cache com `paccache`), ícones de bandeja do sistema (System Tray), botão de **Toggle de Blur** e opções de energia (Logout, Reboot com detecção de kernel pendente, Desligar) com dupla confirmação.
- **Alt+Tab (`AltTab.qml`):** Alternador de janelas com miniaturas ao vivo em tempo real (`ScreencopyView`) organizadas pelo histórico de foco do Hyprland.

---

## 4. Wallpaper Dinâmico e Cores

- O gerenciamento de wallpaper é feito pelo **Waywallen** (Wallpaper Engine via Flatpak + helper nativo `~/.local/bin/waywallen-layer-shell`).
- O wallpaper atual roda cenas animadas com aceleração gráfica na GPU.
- **Carrossel de Wallpapers:** Pressionar `Super + S` abre o `waywallen-switcher` para alternar entre os wallpapers instalados.
- **Esquema de Cores Dinâmico:** O utilitário **Wallust** analisa o wallpaper selecionado e gera a paleta de cores em `~/.config/hypr/colors.conf`. Esse arquivo é lido diretamente pelo `hyprland.lua` e sincronizado com os componentes do Quickshell e Kitty.

---

## 5. Arquivos Criados e Alterados

### Configurações do Hyprland e Sessão
```
~/.config/hypr/hyprland.lua          (Principal: configuração ativa completa em Lua)
~/.config/hypr/hyprland.conf         (Legado: mantido apenas como aviso de deprecação)
~/.config/hypr/hypridle.conf         (Regras de ociosidade do hypridle)
~/.config/hypr/hyprlock.conf         (Tela de bloqueio do hyprlock)
~/.config/hypr/colors.conf           (Paleta de cores gerada pelo wallust a partir do wallpaper)
~/.config/hypr/scripts/              (Scripts de apoio: blur toggle, etc.)
```

### Componentes de Interface (Quickshell)
```
~/.config/quickshell/shell.qml             (Ponto de entrada do Quickshell)
~/.config/quickshell/TopBar.qml            (Barra superior)
~/.config/quickshell/Dock.qml              (Dock inferior com auto-hide)
~/.config/quickshell/DockConfig.qml        (Singleton de configuração de dock/jogos)
~/.config/quickshell/dock.json             (Persistência dos apps fixados e jogos)
~/.config/quickshell/Launcher.qml          (Launcher nativo de aplicativos)
~/.config/quickshell/EnergySidebar.qml     (Barra lateral de energia, updates e trays)
~/.config/quickshell/AltTab.qml            (Alternador de janelas com miniaturas ao vivo)
~/.config/quickshell/Frame.qml             (Moldura e cantos arredondados de tela)
~/.config/quickshell/Dashboard.qml         (Aba principal do Hub)
~/.config/quickshell/Media.qml             (Aba de mídia do Hub)
~/.config/quickshell/Monitoring.qml        (Aba de monitoramento de recursos)
~/.config/quickshell/SysStats.qml          (Sensores do sistema)
~/.config/quickshell/SystemInfo.qml        (Aba de especificações do sistema)
~/.config/quickshell/Snapshots.qml         (Aba de gerenciamento de snapshots)
~/.config/quickshell/Notifications.qml     (Aba de histórico de notificações)
~/.config/quickshell/GameMode.qml          (Monitor de estado para modo jogo)
~/.config/quickshell/Theme.qml             (Definições globais de cores e ícones)
```

### Utilitários e Scripts (`~/.local/bin/`)
```
~/.local/bin/game-run                 (Wrapper para executar jogos na dGPU NVIDIA com DLSS)
~/.local/bin/rice-blur-toggle         (Alterna o efeito de blur entre ligado e desligado)
~/.local/bin/rice-gamemode            (Perfil de alto desempenho para jogos)
~/.local/bin/rice-record              (Gravação de tela/região com wf-recorder)
~/.local/bin/rice-dropterm            (Terminal suspenso drop-down no workspace especial)
~/.local/bin/rice-reboot-needed       (Detecta se há atualização de kernel/driver exigindo reboot)
~/.local/bin/rice-clean-cache         (Limpeza segura do cache de pacotes com paccache/yay)
~/.local/bin/rice-restart             (Reinício do Quickshell em caso de emergência)
~/.local/bin/waywallen-switcher       (Carrossel interativo de seleção de wallpapers)
~/.local/bin/waywallen-layer-shell    (Bridge nativa de layer-shell para o Waywallen Flatpak)
```

### Aplicativos e Ferramentas Auxiliares
- **Kitty (`~/.config/kitty/kitty.conf`):** Terminal com fonte Noto Sans Mono, fundo `#0b0b0b` e transparência com blur.
- **Rofi:** Mantido instalado e configurado **exclusivamente** para o histórico de área de transferência (`cliphist` no `Super + V`). Todo o resto das funções de launcher foi absorvido pelo Quickshell.
- **Wofi:** Não é mais utilizado.
- **Waybar:** Não é mais utilizada no autostart.

---

## 6. Como Usar e Testar

Dentro da sessão Hyprland:

| Atalho / Gesto | O que faz |
|---|---|
| `Super` ou `Super + R` | Abre o **Launcher de Aplicativos** próprio do Quickshell |
| `Super + Q` | Abre o terminal **Kitty** |
| `Super + E` | Abre o gerenciador de arquivos **Dolphin** |
| `Super + V` | Abre o histórico de **Clipboard** via Rofi + Cliphist |
| `Super + B` | Liga/desliga o efeito de **Blur** do compositor |
| `Super + '` | Abre/fecha o terminal suspenso (**Dropterm**) |
| `Super + S` | Abre o carrossel seletor de wallpapers do **Waywallen** |
| `Super + L` | Bloqueia a sessão com o **Hyprlock** |
| `Super + M` | Encerra a sessão Hyprland |
| `Alt + Tab` | Abre o alternador de janelas com miniaturas ao vivo |
| `Super + Shift + S` | Captura interativa de tela com ferramentas de anotação (Swappy) |
| `Super + Shift + R` | Inicia/para a gravação de tela em vídeo |
| **Cursor na borda inferior** | Faz surgir a **Dock** de aplicativos e jogos |
| **Cursor na borda direita** | Faz surgir a **EnergySidebar** de energia, updates e bandejas |
| **Clique no relógio da barra** | Abre o **Hub Central** (dashboard, métricas, snapshots e notificações) |
