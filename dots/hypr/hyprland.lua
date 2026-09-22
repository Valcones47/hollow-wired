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

-- Valores de emergência: numa instalação nova o wallust ainda não rodou (ou o
-- usuário não tem wallpaper nenhum), e o colors.conf pode não existir. Sem isso
-- o parseGradient recebia nil e a configuração INTEIRA do Hyprland quebrava —
-- o usuário caía numa sessão sem bordas, sem binds e sem autostart.
local wallustDefaults = {
    wallust_background      = "#12100F",
    wallust_foreground      = "#C2A6A5",
    wallust_accent1         = "#5D1D1D",
    wallust_accent2         = "#64231F",
    wallust_active_border   = "rgba(5D1D1Dee) rgba(64231Fee) 45deg",
    wallust_inactive_border = "rgba(12100F88)",
    wallust_shadow_color    = "rgba(12100Fee)",
}
for key, value in pairs(wallustDefaults) do
    if not wallust[key] or wallust[key] == "" then
        wallust[key] = value
    end
end

-----------------
---- MONITORES --
-----------------
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "1",
})

--------------------------
---- PROGRAMAS BASE ------
--------------------------
-- Layout de teclado: lê o do próprio sistema (/etc/vconsole.conf, escrito pelo
-- localectl/instalador da distro). Antes era "br" fixo, o que dava acentos e
-- símbolos errados pra quem instalasse o rice com teclado de outro país.
-- Lê uma preferência booleana salva pelo painel em user-prefs.json.
--
-- Sem isso, o blur voltava sozinho a ligado a cada `hyprctl reload`: o valor
-- estava fixo em `true` aqui, e a preferência do usuário só era aplicada uma
-- vez, no autostart (`rice-hypr-prefs apply`). Quem desligava o blur via
-- sidebar o via reaparecer em qualquer recarga da configuração.
local function prefBool(key, default)
    local f = io.open(home .. "/.config/hypr/user-prefs.json", "r")
    if not f then return default end
    local txt = f:read("*a")
    f:close()
    local v = txt:match('"' .. key .. '"%s*:%s*(%a+)')
    if v == "true" then return true end
    if v == "false" then return false end
    return default
end

local function systemKbLayout()
    local f = io.open("/etc/vconsole.conf", "r")
    if f then
        for line in f:lines() do
            local layout = line:match("^XKBLAYOUT=\"?([%w_,%-]+)\"?")
            if layout and layout ~= "" then
                f:close()
                return layout
            end
        end
        f:close()
    end
    return "br"
end
local kbLayout = systemKbLayout()

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

-- Detecção dinâmica de GPU (NVIDIA dedicada, Intel, AMD Radeon e Laptops Híbridos)
local hasNvidia = false
local hasIgpu = false

local pciDevices = io.popen("ls -d /sys/bus/pci/devices/* 2>/dev/null")
if pciDevices then
    for dev in pciDevices:lines() do
        local cf = io.open(dev .. "/class", "r")
        if cf then
            local class = cf:read("*line") or ""
            cf:close()
            if class:sub(1, 4) == "0x03" then
                local vf = io.open(dev .. "/vendor", "r")
                if vf then
                    local vendor = vf:read("*line") or ""
                    vf:close()
                    if vendor == "0x10de" then
                        hasNvidia = true
                    elseif vendor == "0x8086" or vendor == "0x1002" then
                        hasIgpu = true
                    end
                end
            end
        end
    end
    pciDevices:close()
end

if hasNvidia and hasIgpu then
    -- Laptop híbrido (Optimus / PRIME): compositor roda liso na iGPU (Intel ou AMD),
    -- eliminando overhead de cópia inter-GPU. Jogos usam dGPU via prime-run.
    hl.env("__NV_PRIME_RENDER_OFFLOAD", "0")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "mesa")
    -- Aqui já houve um `hl.env("DRI_PRIME", "0")`, posto junto do conserto do
    -- Discord que não abria. Ele era inválido: o Mesa aceita DRI_PRIME a partir
    -- de 1 (ou "vendor:device") e reclama de "Invalid value (0)" em todo
    -- programa gráfico, porque a iGPU já é o padrão quando a variável não
    -- existe. Testado sem ela: o Discord abre igual — quem resolvia era a
    -- outra metade do conserto, a flag de ozone duplicada no settings.json.
elseif hasNvidia and not hasIgpu then
    -- PC Desktop com NVIDIA exclusiva (sem iGPU): aceleração direta por hardware
    -- NOTA: GBM_BACKEND=nvidia-drm NUNCA deve ser definido no Hyprland moderno pois causa flickering severo
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("NVD_BACKEND", "direct")
    hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
end
-- Sistemas puramente AMD ou Intel usam drivers Mesa nativos sem flags extras.

-- Cursor: Lê dinamicamente o tema do usuário (kcminputrc) ou mantém fallback limpo
local cursor_theme = "default"
local kcminput = io.open(home .. "/.config/kcminputrc", "r")
if kcminput then
    for line in kcminput:lines() do
        local match = line:match("^cursorTheme=(.+)")
        if match and match ~= "" then
            cursor_theme = match:gsub("%s+$", "")
            break
        end
    end
    kcminput:close()
end

hl.env("XCURSOR_THEME", cursor_theme)
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", cursor_theme)
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
    -- apps abertos via D-Bus/systemd também não herdam o offload global em laptops híbridos
    if hasNvidia and hasIgpu then
        hl.exec_cmd("systemctl --user unset-environment __NV_PRIME_RENDER_OFFLOAD __GLX_VENDOR_LIBRARY_NAME")
    end

    -- Atualiza variáveis Wayland para o DBus/systemd e inicia portais limpos (elimina delay crônico de 25s em apps)
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP=Hyprland XDG_SESSION_TYPE=wayland QT_QPA_PLATFORMTHEME")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE QT_QPA_PLATFORMTHEME")
    hl.exec_cmd(home .. "/.local/bin/rice-portals")
    hl.exec_cmd(home .. "/.local/bin/rice-fix-xwayland-socket")

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

    -- No Wayland quem copiou é "dono" do conteúdo: ao fechar o programa de
    -- origem, o que estava copiado some e o Ctrl+V não cola mais nada. O
    -- wl-clip-persist segura o conteúdo na sessão mesmo depois do app fechar.
    hl.exec_cmd("wl-clip-persist --clipboard regular")

    -- Luz noturna: controlada pela sidebar/painel do Quickshell via rice-nightlight
    -- (hyprsunset). O autostart do wlsunset foi removido: ele vinha com as
    -- coordenadas da cidade do autor fixas no código (luz noturna no horário
    -- errado pra qualquer outra pessoa) e ainda brigava pelo gamma com o
    -- hyprsunset que a interface liga e desliga.

    -- Aplica preferências de aparência salvas pelo Hub do Quickshell
    hl.exec_cmd(home .. "/.local/bin/rice-hypr-prefs apply")

    -- Equalizador (rice-eq): sobe o filtro do PipeWire se ficou ligado.
    hl.exec_cmd(home .. "/.local/bin/rice-eq restore")

    -- Remove modificador Mod2 do Num_Lock no XWayland (evita que Discord/jogos detectem NumLock indevidamente)
    hl.exec_cmd(home .. "/.local/bin/rice-fix-xwayland-numlock")

    -- Autostarts genéricos (só o que existe na máquina: o arch-update é opcional)
    hl.exec_cmd("sh -c 'command -v arch-update >/dev/null 2>&1 && arch-update --tray'")
    if io.open("/usr/local/bin/limitar_cpu.sh", "r") then
        hl.exec_cmd("/usr/local/bin/limitar_cpu.sh")
    end

    -- waywallen: o daemon roda em Flatpak e não enxerga o protocolo
    -- layer-shell de dentro do sandbox, então precisa do binário nativo
    -- waywallen-layer-shell (instalado em ~/.local/bin, baixado de
    -- github.com/waywallen/waywallen-display) rodando fora do Flatpak e
    -- falando com o daemon via socket unix.
    -- Sem o Wallpaper Engine instalado (ele é pago, na Steam), o Waywallen não
    -- sobe e a área de trabalho ficava simplesmente preta — e sem wallpaper o
    -- wallust também não gera paleta nenhuma. Agora, quando o Waywallen não
    -- está presente, o rice aplica um wallpaper estático com o hyprpaper.
    hl.exec_cmd([[sh -c 'if flatpak info org.waywallen.waywallen >/dev/null 2>&1; then
    flatpak run org.waywallen.waywallen --no-ui >/dev/null 2>&1 &
    for i in $(seq 1 30); do
        [ -S "$XDG_RUNTIME_DIR/waywallen/display.sock" ] && exec "$HOME/.local/bin/waywallen-layer-shell" --socket "$XDG_RUNTIME_DIR/waywallen/display.sock"
        sleep 0.5
    done
else
    "$HOME/.local/bin/rice-wallpaper-set" --ensure >/dev/null 2>&1
fi']])
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
            -- Respeita o que ficou salvo no painel; desativado automaticamente
            -- em tela cheia pelo blur-fullscreen-toggle.sh (ver AUTOSTART).
            enabled           = prefBool("blur", true),
            size              = 3,      -- mínimo visual viável pra Intel UHD
            passes            = 1,      -- 1 pass = custo mínimo de blur
            vibrancy          = 0.20,
            xray              = false,
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
hl.layer_rule({ match = { namespace = "quickshell-launcher" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "quickshell-visualconfig" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "quickshell-clipboard" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "quickshell-cheatsheet" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "quickshell-overview" }, blur = true, ignore_alpha = 0.3 })
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

-- Curvas escolhidas no painel Rice (presets ou personalizadas), geradas pelo
-- rice-anim. Vêm depois das de cima e têm prioridade; sem o arquivo (instalação
-- nova) valem as de cima. Carregar aqui é o que faz a escolha sobreviver a um
-- `hyprctl reload` — antes ela era aplicada só com `hyprctl eval` e se perdia.
do
    local animFile = home .. "/.config/hypr/animations.lua"
    local f = io.open(animFile, "r")
    if f then
        f:close()
        local ok, err = pcall(dofile, animFile)
        if not ok then print("Erro ao carregar animations.lua: " .. tostring(err)) end
    end
end

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
        vrr                     = 0, -- VRR desativado (elimina flickering/piscamento na tela quando ocioso)
        -- Se o hyprlock morrer segurando o bloqueio (travou, foi morto, a GPU
        -- engasgou), o Hyprland mantém a sessão travada e mostra um aviso. Com
        -- esta opção desligada, que é o padrão, ele também RECUSA um hyprlock
        -- novo — e a única saída vira um TTY ou reiniciar o computador. Com ela
        -- ligada, basta abrir o hyprlock de novo (Super + L, abaixo) e digitar
        -- a senha. Não destrava nada sozinha: só permite bloquear outra vez.
        allow_session_lock_restore = true,
    },

    render = {
        direct_scanout = 0, -- Desativado para evitar instabilidades e flickering com layer-shell/quickshell
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
        kb_layout = kbLayout,

        numlock_by_default = true,
        follow_mouse       = 1,
        accel_profile      = "flat",
        sensitivity        = 0,

        touchpad = {
            disable_while_typing = false,
        },
    },

    cursor = {
        -- Em desktops com NVIDIA exclusiva (ex: GTX 950/1060), software cursors evita sumiço ou lag de ponteiro
        no_hardware_cursors = (hasNvidia and not hasIgpu),
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
-- Alt+F4 fecha como no Windows e, nas primeiras vezes, avisa do Super+C (rice-tips).
hl.bind("ALT + F4", function()
    hl.dispatch(hl.dsp.window.close())
    hl.exec_cmd("rice-tips show close_super_c")
end)
hl.bind(mainMod .. " + M", hl.dsp.exit())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + F1", hl.dsp.exec_cmd("quickshell ipc call cheatsheet toggle"))
-- Gerenciador de tarefas: Super+Esc e o Ctrl+Shift+Esc de quem vem do Windows.
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("rice-task-manager"))
hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd("rice-task-manager"))
-- Super+I = Painel de Configurações Visuais do Rice (VisualConfigPanel.qml)
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("quickshell ipc call visualconfig toggle"))
-- Super+V = histórico do clipboard nativo no Quickshell (Clipboard.qml)
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("quickshell ipc call clipboard toggle"))
-- Super+Ctrl+V = abre direto na aba de Favoritos da área de transferência
hl.bind(mainMod .. " + CTRL + V", hl.dsp.exec_cmd("quickshell ipc call clipboard favoritesTab"))
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
-- Tela de bloqueio do shell (LockScreen.qml); o rice-lock cai no hyprlock se
-- o Quickshell não estiver de pé. `locked = true` faz o atalho funcionar com a
-- sessão bloqueada: é a saída sem TTY quando a tela de bloqueio morre e sobra
-- só o aviso do Hyprland (allow_session_lock_restore, acima, permite retomar).
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("rice-lock"), { locked = true })

-- Super + esquerda/direita troca de área de trabalho. Antes as quatro setas
-- moviam só o foco entre janelas — algo que quem vem do Windows não procura,
-- enquanto trocar de workspace é a ação do dia a dia (e já existia escondida
-- na roda do mouse). Mover o foco continua disponível em Super + Alt + setas.
hl.bind(mainMod .. " + left",  hl.dsp.focus({ workspace = "-1" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ workspace = "+1" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Levar a janela atual junto para a área de trabalho do lado.
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ workspace = "-1" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ workspace = "+1" }))

-- Foco entre janelas, que era o papel antigo do Super + setas.
hl.bind(mainMod .. " + ALT + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + ALT + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + ALT + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + ALT + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10 -- 10 mapeia pra tecla 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + A",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.window.move({ workspace = "special:magic" }))

-- Atalhos pessoais trazidos do kglobalshortcutsrc do KDE (Plasma + Krohnkite).
-- Só são registrados quando o programa existe: numa máquina sem eles, o atalho
-- ficava ocupado e não fazia nada (e o usuário achava que estava quebrado).
-- os.execute não é confiável dentro do interpretador Lua do Hyprland (devolve
-- nil e os binds sumiam sem aviso); io.popen funciona e já é usado aqui em cima
-- pra detecção de GPU.
local function hasCommand(cmd)
    local pipe = io.popen("command -v " .. cmd .. " 2>/dev/null")
    if not pipe then return false end
    local out = pipe:read("*l")
    pipe:close()
    return out ~= nil and out ~= ""
end

-- Super+S: seletor de wallpaper. Com o Wallpaper Engine instalado abre o
-- carrossel do Waywallen; sem ele, abre o seletor de imagem estática.
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd([[sh -c 'if flatpak info org.waywallen.waywallen >/dev/null 2>&1; then exec "$HOME/.local/bin/waywallen-switcher"; else exec "$HOME/.local/bin/rice-wallpaper-set"; fi']]))
if hasCommand("claude-desktop") then
    hl.bind("CTRL + slash", hl.dsp.exec_cmd("claude-desktop"))
end
if hasCommand("zapzap") then
    hl.bind("CTRL + bracketright", hl.dsp.exec_cmd("zapzap"))
end
-- Ctrl + Alt + Delete = Menu de Energia / Desligar / Suspender
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("quickshell ipc call sidebar toggle"))
hl.bind("CTRL + ALT + delete", hl.dsp.exec_cmd("quickshell ipc call sidebar toggle"))

-- "e+1"/"e-1" são aceitos sem erro mas não movem nada neste provider Lua:
-- o Super + roda do mouse estava quebrado em silêncio. O relativo que funciona
-- é "+1"/"-1" (confirmado por teste).
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- OSD nativo Quickshell (Caelestia / Dynamic Island pill em OSD.qml)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("quickshell ipc call osd volumeUp"),   { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("quickshell ipc call osd volumeDown"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("quickshell ipc call osd volumeMute"), { locked = true, repeating = true })

-- Toggle de mute do microfone via tecla multimídia (mostra OSD do microfone no PipeWire)
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("quickshell ipc call osd micMute"), { locked = true, repeating = true })

-- Num_Lock: Desativa/ativa o áudio (Deafen) do Discord nativamente em segundo plano com debounce e liberação segura de teclas
-- ==============================================================================
-- ATALHOS GLOBAIS DO DISCORD / VESKTOP (MUTE & DEAFEN)
-- ==============================================================================
-- Relato: "a primeira vez que uso depois de um tempo conta duas vezes; depois
-- fica normal por um tempo e volta a fazer isso". O debounce de 200ms era curto
-- demais para pegar um repique que chega mais tarde, e o timer que rearmava o
-- estado não tinha proteção contra timers sobrepostos: um timer velho podia
-- liberar a trava antes da hora e deixar o segundo evento passar.
--
-- Agora são 500ms e cada disparo carrega uma "geração"; só o timer da geração
-- mais recente pode reabrir a trava. O log em /tmp/rice-discord-binds.log diz se
-- um toggle duplicado veio de dois disparos do atalho (duas linhas ENVIADO) ou
-- da entrega ao Discord (uma linha ENVIADO só) — sem isso é chute.
local DISCORD_DEBOUNCE_MS = 500

local function discord_log(tag)
    local f = io.open("/tmp/rice-discord-binds.log", "a")
    if f then
        f:write(os.date("%H:%M:%S"), " ", tag, "\n")
        f:close()
    end
end

local discord_deafen_ready = true
local discord_deafen_gen = 0
local function toggle_discord_deafen()
    if not discord_deafen_ready then
        discord_log("deafen IGNORADO (repique dentro de " .. DISCORD_DEBOUNCE_MS .. "ms)")
        return
    end
    discord_deafen_ready = false
    discord_deafen_gen = discord_deafen_gen + 1
    local gen = discord_deafen_gen

    hl.timer(function()
        if gen == discord_deafen_gen then
            discord_deafen_ready = true
        end
    end, { timeout = DISCORD_DEBOUNCE_MS, type = "oneshot" })

    discord_log("deafen ENVIADO")

    -- Envia Ctrl + Shift + d (minúsculo) para o Discord / Vesktop
    hl.dispatch(hl.dsp.send_shortcut({ mods = "CTRL SHIFT", key = "d", window = "class:^(discord|vesktop)$" }))
    -- Força liberação imediata do 'd' e modificadores para nunca travar a tecla repetindo no chat
    hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "d", state = "up", window = "class:^(discord|vesktop)$" }))
    hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "Control_L", state = "up", window = "class:^(discord|vesktop)$" }))
    hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "Shift_L", state = "up", window = "class:^(discord|vesktop)$" }))
end

local discord_mute_ready = true
local discord_mute_gen = 0
local function toggle_discord_mute()
    if not discord_mute_ready then
        discord_log("mute IGNORADO (repique dentro de " .. DISCORD_DEBOUNCE_MS .. "ms)")
        return
    end
    discord_mute_ready = false
    discord_mute_gen = discord_mute_gen + 1
    local gen = discord_mute_gen

    hl.timer(function()
        if gen == discord_mute_gen then
            discord_mute_ready = true
        end
    end, { timeout = DISCORD_DEBOUNCE_MS, type = "oneshot" })

    discord_log("mute ENVIADO")

    -- Envia Ctrl + Shift + m (minúsculo) para o Discord / Vesktop
    hl.dispatch(hl.dsp.send_shortcut({ mods = "CTRL SHIFT", key = "m", window = "class:^(discord|vesktop)$" }))
    hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "m", state = "up", window = "class:^(discord|vesktop)$" }))
    hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "Control_L", state = "up", window = "class:^(discord|vesktop)$" }))
    hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "Shift_L", state = "up", window = "class:^(discord|vesktop)$" }))
end

-- Teclas de mute/ensurdecer escolhidas no painel (rice-discord-binds), em
-- ~/.config/hypr/discord-binds.conf ("mute=..." e "deafen=..."). Antes o
-- script reescrevia estas linhas do hyprland.lua, e toda atualização do rice
-- devolvia as teclas ao padrão.
local discordKeys = { mute = "CTRL + SHIFT + M", deafen = "Num_Lock" }
do
    local f = io.open(home .. "/.config/hypr/discord-binds.conf", "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^%s*(%w+)%s*=%s*(.-)%s*$")
            if (k == "mute" or k == "deafen") and v ~= "" then discordKeys[k] = v end
        end
        f:close()
    end
end
hl.bind(discordKeys.mute, toggle_discord_mute, { locked = true })
hl.bind(discordKeys.deafen, toggle_discord_deafen, { locked = true })
-- Para o `rice-discord-binds toggle-mute|toggle-deafen` (via hyprctl eval).
rice_discord_mute = toggle_discord_mute
rice_discord_deafen = toggle_discord_deafen

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
-- Sistema unificado de captura via rice-screenshot (hyprshot + swappy seguro)
-- Print e Super+Shift+S: Captura de região (salva em ~/Imagens/Capturas de tela, copia pro clipboard e notifica)
-- Super+Alt+S: Captura de região com editor de anotações (Swappy)
hl.bind("Print",                         hl.dsp.exec_cmd("rice-screenshot region"))
hl.bind(mainMod .. " + SHIFT + S",       hl.dsp.exec_cmd("rice-screenshot region"))
hl.bind(mainMod .. " + ALT + S",         hl.dsp.exec_cmd("rice-screenshot edit"))
hl.bind("SHIFT + Print",                 hl.dsp.exec_cmd("rice-screenshot output"))
hl.bind("CTRL + Print",                  hl.dsp.exec_cmd("rice-screenshot window"))

-----------------------
---- QoL (backlog) ----
-----------------------
-- Gravar a tela inteira (Super+Shift+R); de novo para parar. Sem seleção de
-- região: o atalho começa a gravar na hora. Gravar só uma região ou uma janela
-- continua possível pela aba Gravação do hub. Script em ~/.local/bin/rice-record.
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("rice-record full"))
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
-- Visão geral das áreas de trabalho em carrossel (Visão de Tarefas do Windows).
hl.bind(mainMod .. " + Tab", hl.dsp.global("quickshell:overview"))

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
rice_suppress_max_rule = hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

----------------------------------------------------------------
---- MODO DE JANELAS: "hyprland" (lado a lado) ou "windows" ----
----------------------------------------------------------------
-- No modo Windows toda janela nova abre flutuando e centralizada, do tamanho
-- que o app pede, e pode ser redimensionada pela borda. O botão maximizar
-- dos próprios apps volta a funcionar (no modo lado a lado ele é ignorado
-- pela regra "suppress-maximize-events"). Os atalhos não mudam.
--
-- A escolha fica em ~/.config/hypr/window-mode (preferência do usuário) e é
-- trocada ao vivo pelo `rice-window-mode`, que chama rice_set_window_mode()
-- via `hyprctl eval`: as regras têm nome e são ligadas/desligadas sem reload.
local windowModeFile = home .. "/.config/hypr/window-mode"
rice_window_mode = "hyprland"
do
    local f = io.open(windowModeFile, "r")
    if f then
        local m = (f:read("*l") or ""):gsub("%s+", "")
        f:close()
        if m == "windows" then rice_window_mode = "windows" end
    end
end

rice_windows_rule = hl.window_rule({
    name    = "windows-mode",
    enabled = rice_window_mode == "windows",
    match   = { class = ".*" },

    float  = true,
    center = true,
})

-- Definida antes das regras do dropterm e do PiP para que elas, vindo
-- depois, continuem valendo sobre o "centralizar".
-- Janelas com regra própria de posição: não mexer ao trocar de modo.
local keepAsIs = { dropterm = true }

-- Barra de título (plugin hyprbars, opcional: pacote
-- hyprland-plugin-hyprbars). Só no modo Windows, e só nas janelas que não
-- desenham a própria barra (navegadores, Electron e apps GNOME já têm; ficaria
-- dupla). Botões: minimizar (vai para a área escondida do Super+A),
-- maximizar e fechar. Duplo clique na barra maximiza.
local hyprbarsLib = "/usr/lib/libhyprbars.so"
-- Recomeça a cada leitura do config: o reload apaga os botões do plugin.
rice_hyprbars_ready = false
local ownTitlebar = "^(zen|firefox|librewolf|floorp|chromium|google-chrome|brave-browser|vivaldi-stable|microsoft-edge|"
    .. "com.anthropic.Claude|discord|vesktop|youtube-music-desktop-app|spotify|code|code-oss|Code|steam|"
    .. "org.gnome..*|dropterm|xdg-desktop-portal-gtk)$"

local function hex(c, alpha)
    c = tostring(c or ""):gsub("#", "")
    if #c ~= 6 then c = "1e1e2e" end
    return alpha and ("rgba(" .. c .. alpha .. ")") or ("rgb(" .. c .. ")")
end

local function hyprbars_setup()
    if rice_hyprbars_ready then return true end
    if not hl.plugin.hyprbars then
        local f = io.open(hyprbarsLib, "r")
        if not f then return false end
        f:close()
        local ok = pcall(hl.plugin.load, hyprbarsLib)
        if not ok or not hl.plugin.hyprbars then return false end
    end
    local bg = wallust.wallust_background or "#1e1e2e"
    local fg = wallust.wallust_foreground or "#ffffff"
    hl.config({ plugin = { hyprbars = {
        bar_height = 28,
        bar_color = hex(bg, "e6"),
        ["col.text"] = hex(fg),
        bar_text_font = "JetBrainsMono Nerd Font",
        bar_text_size = 10,
        bar_text_align = "left",
        bar_padding = 12,
        bar_button_padding = 8,
        bar_part_of_window = true,
        bar_precedence_over_border = true,
        on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
    } } })
    -- Da direita para a esquerda: fechar, maximizar, minimizar.
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(e06c75)", fg_color = hex(bg), size = 16, icon = "󰖭",
        action = [[hyprctl dispatch 'hl.dsp.window.close()']],
    })
    hl.plugin.hyprbars.add_button({
        bg_color = hex(wallust.wallust_accent2 or fg), fg_color = hex(bg), size = 16, icon = "󰖯",
        action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
    })
    hl.plugin.hyprbars.add_button({
        bg_color = hex(wallust.wallust_accent1 or fg), fg_color = hex(bg), size = 16, icon = "󰖰",
        action = [[hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:magic" })']],
    })
    -- Com o plugin carregado a regra passa a existir.
    rice_nobar_rule = hl.window_rule({
        name  = "hyprbars-own-titlebar",
        match = { class = ownTitlebar },
        ["hyprbars:no_bar"] = true,
    })
    hl.window_rule({
        name  = "hyprbars-pinned",
        match = { pin = true },
        ["hyprbars:no_bar"] = true,
    })
    rice_hyprbars_ready = true
    return true
end

function rice_set_window_mode(mode, convert)
    local on = mode == "windows"
    rice_window_mode = on and "windows" or "hyprland"
    rice_windows_rule:set_enabled(on)
    rice_suppress_max_rule:set_enabled(not on)
    hl.config({ general = { resize_on_border = on } })
    if on then
        if hyprbars_setup() then hl.config({ plugin = { hyprbars = { enabled = true } } }) end
    elseif hl.plugin.hyprbars then
        hl.config({ plugin = { hyprbars = { enabled = false } } })
    end
    if not convert then return end
    -- As janelas já abertas acompanham a troca: soltas num tamanho
    -- confortável e centralizadas, ou de volta para o lado a lado.
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped and not keepAsIs[w.class] and not w.pinned and w.fullscreen == 0 then
            local sel = "address:" .. w.address
            if on and not w.floating then
                hl.dispatch(hl.dsp.window.float({ action = "enable", window = sel }))
                rice_window_comfy(w)
            elseif not on and w.floating then
                hl.dispatch(hl.dsp.window.float({ action = "disable", window = sel }))
            end
        end
    end
end

-- Apps que lembram o último tamanho (o kitty, por exemplo) abriam quase do
-- tamanho da tela, com a barra de título escondida atrás da barra do topo.
-- No modo Windows, janela nova maior que 90% da tela volta a um tamanho
-- confortável, centralizada.
local function comfy(w)
    local m = w.monitor
    if not m then return end
    local sel = "address:" .. w.address
    local mw, mh = m.width / m.scale, m.height / m.scale
    hl.dispatch(hl.dsp.window.resize({
        exact = true, window = sel,
        x = math.floor(math.min(1400, mw * 0.62)),
        y = math.floor(math.min(900, mh * 0.72)),
    }))
    hl.dispatch(hl.dsp.window.center({ window = sel }))
end
rice_window_comfy = comfy

hl.on("window.open", function(w)
    if rice_window_mode ~= "windows" or not w or not w.floating or w.pinned or keepAsIs[w.class] then return end
    local m = w.monitor
    if not m or type(w.size) ~= "table" then return end
    local sw = w.size.x or w.size[1] or 0
    local sh = w.size.y or w.size[2] or 0
    if sw > m.width / m.scale * 0.9 or sh > m.height / m.scale * 0.85 then comfy(w) end
end)

if rice_window_mode == "windows" then
    rice_set_window_mode("windows", false)
elseif hl.plugin.hyprbars then
    -- Plugin continua carregado depois de voltar ao modo Hyprland.
    hl.config({ plugin = { hyprbars = { enabled = false } } })
end

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

-----------------------------------------------------------------------
---- ATALHOS CUSTOMIZADOS DO USUÁRIO (~/.config/hypr/user-binds.lua) --
-----------------------------------------------------------------------
local userBindsFile = home .. "/.config/hypr/user-binds.lua"
local uf = io.open(userBindsFile, "r")
if uf then
    uf:close()
    -- `dofile` roda num escopo novo: as locais daqui (home, mainMod) não chegam
    -- lá dentro. Quem escrevia um atalho usando `home` via o bind sumir sem
    -- explicação, porque o erro era engolido pelo pcall abaixo. Exportar as
    -- duas como globais deixa o arquivo pessoal se parecer com este aqui.
    _G.home = home
    _G.mainMod = mainMod
    local ok, err = pcall(dofile, userBindsFile)
    if not ok then
        print("Erro ao carregar user-binds.lua: " .. tostring(err))
        hl.exec_cmd("notify-send -a 'Hyprland' -i dialog-error 'Erro nos seus atalhos personalizados' "
            .. "'Veja ~/.config/hypr/user-binds.lua'")
    end
end

