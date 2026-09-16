# Diretrizes para Agentes de IA (AGENTS.md)

Este documento define as regras fundamentais e arquitetura ativa deste projeto. **LEIA ANTES DE QUALQUER AÇÃO.**

---

### 1. Regra Absoluta: Configuração do Hyprland
- **O Hyprland utiliza EXCLUSIVAMENTE o arquivo [`~/.config/hypr/hyprland.lua`](file:///home/val47/.config/hypr/hyprland.lua) (configuração em Lua).**
- O arquivo `hyprland.conf` é **obsoleto/legado** e NÃO é carregado pelo compositor (`configProvider: lua`).
- **NUNCA** analise, sugira alterações ou edite `hyprland.conf`. Toda alteração de binds, regras de janela, autostart e visual deve ser feita no `hyprland.lua`.

---

### 2. Interface Desktop & Shell (Quickshell)
- Todo o shell (barras, menus, notificações, painéis) é desenvolvido em **Quickshell (QML)** dentro de [`~/.config/quickshell/`](file:///home/val47/.config/quickshell/):
  - **`TopBar.qml`**: Barra superior ativa (substituiu a antiga `waybar`).
  - **`Launcher.qml`**: Launcher nativo de aplicativos (`Super + R` ou `Super`). O `wofi` foi completamente descartado.
  - **`Dock.qml` & `DockConfig.qml`**: Dock inferior retrátil com badges de workspace e menu de jogos.
  - **`EnergySidebar.qml`**: Barra lateral retrátil (hover direito) com botões de energia, updates, trays e toggle de blur.
  - **`AltTab.qml`**: Alternador de janelas com miniaturas ao vivo.
  - **Hub central (`Dashboard.qml`, `Media.qml`, `Monitoring.qml`, `SysInfo.qml`, `Snapshots.qml`, etc.)**: Aberto ao clicar no relógio da TopBar.
- **Rofi**: Permanece instalado e configurado **apenas** para o menu do histórico de área de transferência (`Super + V` com `cliphist`).

---

### 3. Wallpaper Dinâmico & Cores
- O wallpaper ativo é gerenciado pelo **Waywallen** (Wallpaper Engine via Flatpak + `waywallen-layer-shell`).
- Atalho `Super + S` abre o `waywallen-switcher`.
- As cores dinâmicas são geradas pelo `wallust` em `~/.config/hypr/colors.conf` e parseadas pelo `hyprland.lua`.

---

### 4. GPU & Otimização
- **Interface e Compositor:** Forçados a rodar na iGPU Intel (`Mesa`) para evitar overhead de cópia entre GPUs.
- **Jogos:** Executados via wrapper `~/.local/bin/game-run` direcionando para a dGPU NVIDIA RTX 3050 com DLSS ativo via DXVK-NVAPI.

---

### 5. Documentação Ativa & Manutenção
- **Primeiro lugar a checar:** [`ESTADO-ATUAL.md`](file:///home/val47/projetos/hyprland-setup/ESTADO-ATUAL.md) — contém o estado exato e atual do rice.
- **Regra obrigatória:** Sempre que realizar qualquer modificação, ajuste ou adição no rice, **atualize imediatamente o [`ESTADO-ATUAL.md`](file:///home/val47/projetos/hyprland-setup/ESTADO-ATUAL.md)**.
- O arquivo `quickshell-hub-progress.md` serve apenas como histórico/auditoria de etapas anteriores.
