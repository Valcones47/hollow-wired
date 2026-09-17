-------------------------------------------------------------------------
-- hyprland.lua
-- Migrado de hyprland.conf (hyprlang) em 2026-09-15.
-- hyprlang some no Hyprland 0.57 (você está na 0.56.2) — esse arquivo
-- passa a ser lido no lugar do .conf automaticamente. O .conf antigo
-- foi mantido no diretório só como referência/backup, não é mais usado.
--
-- Sessão isolada do Plasma. Não referencia nem altera nada do KDE.
-- Valores de input/aparência traduzidos do Plasma/Konsole em 2026-09-14.
-------------------------------------------------------------------------

local home = os.getenv("HOME")

-----------------------------------------------------------------------
---- CORES (geradas pelo wallust) --------------------------------------
-- O template do wallust (~/.config/wallust/templates/hyprland-colors.conf)
-- ainda gera ~/.config/hypr/colors.conf no formato antigo ($nome = valor),
-- porque outras ferramentas (kitty, waybar, etc.) também consomem esse
-- arquivo. A config Lua não tem "source" para hyprlang, então lemos e
-- parseamos essas linhas manualmente aqui. Editar o wallpaper via
-- waywallen continua regenerando colors.conf normalmente.
-----------------------------------------------------------------------

local function loadWallustColors(path)
    local colors = {}
    local f = io.open(path, "r")
    if not f then return colors end
    for line in f:lines() do
        local name, value = line:match("^%$([%w_]+)%s*=%s*(.-)%s*$")
        if name then
            colors[name] = value
        end
    end
    f:close()
    return colors
end

-- "rgba(...) rgba(...) 45deg" -> { colors = {"rgba(...)", "rgba(...)"}, angle = 45 }
local function parseGradient(value)
    local stops, angle = {}, 0
    for token in value:gmatch("%S+") do
        local deg = token:match("^(%d+)deg$")
        if deg then
            angle = tonumber(deg)
        else
            table.insert(stops, token)
        end
    end
    return { colors = stops, angle = angle }
end

local wallust = loadWallustColors(home .. "/.config/hypr/colors.conf")

-----------------
---- MONITORES --
-----------------
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

--------------------------
---- PROGRAMAS BASE ------
--------------------------
local terminal = "kitty"
local fileManager = "dolphin"
-- Launcher em Quickshell (Launcher.qml). O rofi antigo continua instalado
-- (rofi-app-launcher.py) e segue sendo usado pelo Super+V (clipboard).
local menu = "qs ipc call launcher toggle"
local mainMod = "SUPER"

-----------------------------------------------------------------------
---- VARIÁVEIS DE AMBIENTE (escopo de sessão) --------------------------
-- Nunca colocadas em fish/bash/zsh rc.
-----------------------------------------------------------------------

-- Sessão Wayland
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- GPU híbrida Intel + NVIDIA (RTX 3050 Mobile). A tela interna é ligada à
-- Intel (eDP-1 em card2/i915) — a NVIDIA (card1) não tem saída de vídeo
-- nenhuma, só renderiza (reverse PRIME). Forçar o Hyprland inteiro pra
-- NVIDIA aqui (LIBVA_DRIVER_NAME/__GLX_VENDOR_LIBRARY_NAME/GBM_BACKEND)
-- fazia o compositor tentar renderizar via NVIDIA e copiar de volta pra
-- Intel o tempo todo — bate com os travamentos vistos após a atualização
-- do driver 610->615. Removido em 2026-09-15; o padrão agora roda na
-- Intel. Pra rodar algo específico na NVIDIA (jogos, etc.), usa `prime-run
-- comando` (já instalado, pacote nvidia-prime) em vez de env aqui.
--
-- /etc/environment (global, fora deste arquivo) força __NV_PRIME_RENDER_OFFLOAD=1
-- e __GLX_VENDOR_LIBRARY_NAME=nvidia pra TODOS os apps — o Quickshell e o resto
-- renderizavam na NVIDIA e cada frame era copiado pra Intel (interface lagada,
-- erro "does not work across GPUs" no log do Quickshell). Desfeito aqui só pra
-- sessão Hyprland (não mexe no Plasma). Jogos continuam na NVIDIA pelo
-- prime-run / steam.desktop / Heroic.
hl.env("__NV_PRIME_RENDER_OFFLOAD", "0")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "mesa")

-- Cursor (tema copiado do Plasma: kcminputrc [Mouse] cursorTheme)
hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("HYPRCURSOR_SIZE", "24")

-- Apps padrão de sessão (nunca em shell rc, apenas aqui)
hl.env("TERMINAL", "kitty")
hl.env("EDITOR", "micro")
hl.env("VISUAL", "kate")
hl.env("BROWSER", "zen-browser")

-----------------
---- AUTOSTART --
-----------------
hl.on("hyprland.start", function()
    -- apps abertos via D-Bus/systemd também não herdam o offload global
    hl.exec_cmd("systemctl --user unset-environment __NV_PRIME_RENDER_OFFLOAD __GLX_VENDOR_LIBRARY_NAME")

    -- Desativa blur automaticamente quando a janela ativa está em tela cheia;
    -- reativa ao sair. Evita gastar ~70% da Intel UHD com blur inútil em jogo.
    -- (os.execute com & porque hl.exec_cmd não mantém scripts de longa duração)
    os.execute(home .. "/.config/hypr/scripts/blur-fullscreen-toggle.sh &")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
    hl.exec_cmd("mako")
    hl.exec_cmd("hypridle")
    -- waybar substituída pela barra do Quickshell (TopBar.qml) em 2026-09-15;
    -- config dela continua em ~/.config/waybar pra voltar se precisar.
    -- swayosd substituído pelo OSD nativo Quickshell (OSD.qml)
    -- hl.exec_cmd("swayosd-server")

    -- Hub do relógio (novo, em Quickshell — a versão em eww foi aposentada).
    hl.exec_cmd("quickshell")

    -- Histórico de clipboard (cliphist): guarda texto e imagem copiados.
    -- Picker no Super+V (ver KEYBINDINGS).
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Luz noturna: 6500K de dia, 4000K à noite, horário do sol calculado pra
    -- Mandaguaçu/PR. Liga/desliga pela sidebar do Quickshell.
    hl.exec_cmd("wlsunset -l -23.35 -L -52.10 -t 4000 -T 6500")

    -- Aplica preferências de aparência salvas pelo Hub do Quickshell
    hl.exec_cmd(home .. "/.local/bin/rice-hypr-prefs apply")

    -- Remove modificador Mod2 do Num_Lock no XWayland (evita que Discord/jogos detectem NumLock indevidamente)
    hl.exec_cmd(home .. "/.local/bin/rice-fix-xwayland-numlock")

    -- Autostarts genéricos trazidos do Plasma (~/.config/autostart), não
    -- específicos do KDE
    hl.exec_cmd("arch-update --tray")
    hl.exec_cmd("/usr/local/bin/limitar_cpu.sh")

    -- waywallen: o daemon roda em Flatpak e não enxerga o protocolo
    -- layer-shell de dentro do sandbox, então precisa do binário nativo
    -- waywallen-layer-shell (instalado em ~/.local/bin, baixado de
    -- github.com/waywallen/waywallen-display) rodando fora do Flatpak e
    -- falando com o daemon via socket unix.
    hl.exec_cmd("flatpak run org.waywallen.waywallen --no-ui")
    hl.exec_cmd([[sh -c 'while [ ! -S "$XDG_RUNTIME_DIR/waywallen/display.sock" ]; do sleep 0.5; done; exec ]] .. home .. [[/.local/bin/waywallen-layer-shell --socket "$XDG_RUNTIME_DIR/waywallen/display.sock"']])
end)

-----------------------------
---- LOOK AND FEEL ----------
-----------------------------
hl.config({
    general = {
        gaps_in  = 4,
        -- 8 em cima; nos outros lados 8 + 10 da moldura (Frame.qml)
        gaps_out = { top = 8, right = 18, bottom = 18, left = 18 },

        border_size = 2,

        col = {
            active_border   = parseGradient(wallust.wallust_active_border),
            inactive_border = wallust.wallust_inactive_border,
        },

        resize_on_border = false,
        allow_tearing    = true, -- Permite tearing/entrega imediata de frames em jogos sem buffer queue
        layout           = "dwindle",
    },

    decoration = {
        rounding = 6,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = false, -- Desativado: economiza fillrate e latência pesada na Intel UHD a 144Hz
            range        = 4,
            render_power = 3,
            color        = wallust.wallust_shadow_color,
        },

        blur = {
            enabled           = true,   -- desativado automaticamente em tela
            -- cheia pelo script blur-fullscreen-toggle.sh (ver AUTOSTART).
            size              = 3,      -- mínimo visual viável pra Intel UHD
            passes            = 1,      -- 1 pass = custo mínimo de blur
            vibrancy          = 0.20,
            xray              = true,
            ignore_opacity    = true,
            new_optimizations = true,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Blur nas layer-shell surfaces. Apenas as menores/intermitentes têm blur;
-- frame (1920x1046) e alttab (1920x1080) são grandes demais pra Intel UHD.
hl.layer_rule({ match = { namespace = "waybar" }, blur = true })
hl.layer_rule({ match = { namespace = "rofi" }, blur = true })
hl.layer_rule({ match = { namespace = "notifications" }, blur = true })
hl.layer_rule({ match = { namespace = "eww-hub" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell-hub" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "quickshell-sidebar" }, blur = true, ignore_alpha = 0.3 })
-- frame e alttab: sem blur (cobrem a tela quase toda, custo absurdo na iGPU)
-- hl.layer_rule({ match = { namespace = "quickshell-frame" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "quickshell-bar" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "quickshell-sysinfo" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "quickshell-dock" }, blur = true, ignore_alpha = 0.3 })
-- hl.layer_rule({ match = { namespace = "quickshell-alttab" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "quickshell-launcher" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "quickshell-desktop-widgets" }, blur = false })

-- Beziers customizados (não usa só os presets padrão)
hl.curve("wallustOvershoot", { type = "bezier", points = { {0.34, 1.56}, {0.64, 1} } })
hl.curve("wallustSnap",      { type = "bezier", points = { {0.16, 1},    {0.3, 1} } })
hl.curve("wallustSmooth",    { type = "bezier", points = { {0.25, 0.1},  {0.25, 1} } })

-- Abrir/fechar janela: popin (escala) + fade (opacidade) combinados
hl.animation({ leaf = "windows",          enabled = true, speed = 4,  bezier = "wallustOvershoot", style = "popin 85%" })
hl.animation({ leaf = "windowsOut",       enabled = true, speed = 3,  bezier = "wallustSnap",      style = "popin 85%" })
hl.animation({ leaf = "windowsMove",      enabled = true, speed = 4,  bezier = "wallustSmooth" })
hl.animation({ leaf = "fade",             enabled = true, speed = 4,  bezier = "wallustSmooth" })
hl.animation({ leaf = "fadeDim",          enabled = true, speed = 4,  bezier = "wallustSmooth" })

-- Troca de workspace
hl.animation({ leaf = "workspaces",       enabled = true, speed = 5,  bezier = "wallustSmooth", style = "slidefade 15%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 5,  bezier = "wallustSmooth", style = "slidevert" })

-- Borda ativa: gradiente (definido em col.active_border) girando
hl.animation({ leaf = "border",           enabled = true, speed = 10, bezier = "wallustSmooth" })
-- borderangle loop desativado: força o compositor a redesenhar TODO frame
-- mesmo sem nenhuma mudança na tela — gasta GPU de graça na Intel UHD.
-- hl.animation({ leaf = "borderangle", enabled = true, speed = 30, bezier = "wallustSmooth", style = "loop" })

hl.config({
    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
        background_color        = "rgba(000000ff)",
        vrr                     = 1, -- VRR adaptativo para o monitor 144Hz (elimina stutter)
    },

    render = {
        direct_scanout = 1, -- Bypassa composição da iGPU em jogos fullscreen, entregando buffer direto ao KMS
    },

    xwayland = {
        force_zero_scaling = true,
    },
})

-----------------
---- INPUT ------
-----------------
-- Traduzido de ~/.config/kcminputrc em 2026-09-14:
--   [Libinput][...][USB Gaming Mouse] PointerAccelerationProfile=1 (libinput FLAT)
--   sem PointerAcceleration explícito -> velocidade neutra (0)
--   touchpad ELAN0521:01 04F3:31B1: Enabled=false (desabilitado no Plasma)
hl.config({
    input = {
        kb_layout = "br",

        numlock_by_default = true,
        follow_mouse       = 1,
        accel_profile      = "flat",
        sensitivity        = 0,

        touchpad = {
            disable_while_typing = false,
        },
    },

    cursor = {
        no_hardware_cursors = false,
        -- Não teleporta o mouse pro centro da janela ao focar (dock, launcher,
        -- Super+setas). Pedido do usuário.
        no_warps = true,
    },
})

-- Mouse principal: perfil flat = sem curva de aceleração (equivalente ao Plasma)
hl.device({
    name          = "usb-gaming-mouse",
    accel_profile = "flat",
    sensitivity   = 0,
})

-- Touchpad estava desabilitado no Plasma - replicando aqui.
-- Confirme o nome exato com `hyprctl devices` e ajuste se necessário.
hl.device({
    name    = "elan0521:01-04f3:31b1-touchpad",
    enabled = false,
})

-----------------------
---- KEYBINDINGS ------
-----------------------
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind("ALT + F4", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exit())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + F1", hl.dsp.exec_cmd("quickshell ipc call cheatsheet toggle"))
-- Super+I = Painel de Configurações Visuais do Rice (VisualConfigPanel.qml)
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("quickshell ipc call visualconfig toggle"))
-- Super+V = histórico do clipboard nativo no Quickshell (Clipboard.qml)
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("quickshell ipc call clipboard toggle"))
-- Super+W = Editor de Widgets no desktop por workspace (DesktopWidgets.qml)
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("quickshell ipc call desktopwidgets toggleEdit"))
-- Super+N = Notificações / Super+Shift+N = Alternar Não Perturbe (DND)
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("quickshell ipc call notif open"))
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("quickshell ipc call notif toggleDnd"))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + SUPER_L", hl.dsp.exec_cmd(menu), { release = true })
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))

hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10 -- 10 mapeia pra tecla 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + A",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.window.move({ workspace = "special:magic" }))

-- Atalhos pessoais trazidos do kglobalshortcutsrc do KDE (Plasma + Krohnkite)
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd(home .. "/.local/bin/waywallen-switcher"))
hl.bind("CTRL + slash",         hl.dsp.exec_cmd("claude-desktop"))
hl.bind("CTRL + bracketright",  hl.dsp.exec_cmd("zapzap"))
hl.bind("CTRL + bracketleft",   hl.dsp.exec_cmd(home .. "/projetos/FischMacro/noisefish-linux/.venv/bin/python " .. home .. "/projetos/FischMacro/noisefish-linux/tray.py"))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- OSD nativo Quickshell (Caelestia / Dynamic Island pill em OSD.qml)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("quickshell ipc call osd volumeUp"),   { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("quickshell ipc call osd volumeDown"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("quickshell ipc call osd volumeMute"), { locked = true, repeating = true })

-- Toggle de mute do microfone via Num Lock (mostra OSD do microfone)
hl.bind("Num_Lock", hl.dsp.exec_cmd("quickshell ipc call osd micMute"), { locked = true, repeating = true })

-- OSD de brilho via Quickshell
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("quickshell ipc call osd brightnessUp"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("quickshell ipc call osd brightnessDown"), { locked = true, repeating = true })

-- Controle de mídia (playerctl) — keycodes confirmados via wev: anterior=173, pause=172, próximo=171
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"),       { locked = true })

-----------------
---- SCREENSHOT -
-----------------
-- hyprshot (equivalente ao Spectacle do KDE). hyprshot.conf NÃO é lido pelo
-- hyprshot de verdade (não existe suporte a arquivo de config nele) — por
-- isso a pasta de destino vai direto na flag -o.
local screenshotDir = home .. "/Imagens/Capturas de tela"
hl.bind("Print",        hl.dsp.exec_cmd('hyprshot -m region -o "' .. screenshotDir .. '"'))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd('hyprshot -m output -o "' .. screenshotDir .. '"'))
hl.bind("CTRL + Print",  hl.dsp.exec_cmd('hyprshot -m window -o "' .. screenshotDir .. '"'))

-----------------------
---- QoL (backlog) ----
-----------------------
-- Print com anotação: seleciona região e abre no swappy (salva em
-- screenshotDir, config em ~/.config/swappy/config).
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd([[sh -c 'grim -g "$(slurp)" - | swappy -f -']]))
-- Gravar tela: região (Super+Shift+R) ou tela inteira (Super+Ctrl+Shift+R).
-- Rodar de novo para parar. Script em ~/.local/bin/rice-record.
hl.bind(mainMod .. " + SHIFT + R",        hl.dsp.exec_cmd("rice-record"))
hl.bind(mainMod .. " + CTRL + SHIFT + R", hl.dsp.exec_cmd("rice-record full"))
-- Conta-gotas: clica num pixel e a cor (hex) vai pro clipboard.
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd([[sh -c 'c=$(hyprpicker -a -f hex) && notify-send -a "Conta-gotas" -t 2500 "Cor copiada" "$c"']]))
-- Matar janela travada: o cursor vira "mira", clique na janela pra matar.
hl.bind(mainMod .. " + SHIFT + X", hl.dsp.exec_cmd("hyprctl kill"))
-- Terminal drop-down (estilo Quake), abre/fecha de qualquer workspace.
-- Tecla à esquerda do 1 (no ABNT2 é aspas; "grave" nunca dispara nesse
-- teclado porque a crase é tecla morta com Shift).
hl.bind(mainMod .. " + apostrophe", hl.dsp.exec_cmd("rice-dropterm"))
-- Emergência: reinicia quickshell/barra sem abrir terminal.
hl.bind(mainMod .. " + CTRL + R", hl.dsp.exec_cmd("rice-restart"))
-- Toggle manual de blur (também acessível pelo botão da sidebar do Quickshell)
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("rice-blur-toggle"))
-- Modo ultra-desempenho (desliga blur E animações para liberar 100% da iGPU para jogos)
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd("rice-perf-mode"))
-- Alt+Tab com miniaturas ao vivo (AltTab.qml). Soltar o Alt troca.
hl.bind("ALT + Tab",         hl.dsp.global("quickshell:alttab-next"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.global("quickshell:alttab-prev"))

-----------------
---- MINIMIZAR --
-----------------
-- Hyprland é tiling, não existe "minimizar" de verdade (não tem taskbar pra
-- restaurar depois). O equivalente é mandar a janela pro workspace especial
-- oculto (o mesmo "magic" do Super+A) e trazer de volta com Super+A.
hl.bind(mainMod .. " + D", hl.dsp.window.move({ workspace = "special:magic" }))

--------------------
---- WINDOW RULES --
--------------------
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

-- Terminal drop-down (rice-dropterm): mora no workspace especial "dropterm",
-- flutuante, centralizado no topo, 70% x 55% da tela.
hl.window_rule({
    name  = "dropterm",
    match = { class = "^dropterm$" },

    workspace = "special:dropterm",
    float     = true,
    size      = "monitor_w*0.7 monitor_h*0.55",
    move      = "monitor_w*0.15 50",
})

-- Picture-in-picture do navegador: flutua, fica por cima de tudo (pin) e
-- vai pro canto inferior direito, sem roubar o foco.
hl.window_rule({
    name  = "pip",
    match = { title = "^(Picture-in-Picture|Picture in picture|Imagem sobre imagem|Picture-in-picture)$" },

    float             = true,
    pin               = true,
    keep_aspect_ratio = true,
    no_initial_focus  = true,
    size              = "480 270",
    move              = "monitor_w-510 monitor_h-300",
})

-- Sem windowrule de opacidade pro kitty de propósito: opacity do Hyprland
-- se aplica na janela INTEIRA (texto incluso), deixando a fonte apagada. O
-- background_opacity do próprio kitty.conf já deixa só o fundo da célula
-- transparente e mantém o texto 100% opaco — o Hyprland ainda detecta a
-- transparência nativa do kitty e borra atrás normalmente.
