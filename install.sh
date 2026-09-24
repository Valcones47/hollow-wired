#!/usr/bin/env bash
# ==============================================================================
#  _   _  ___  _     _     _____        __ __        _____ ____  _____ ____  
# | | | |/ _ \| |   | |   / _ \ \      / / \ \      / /_ _|  _ \| ____|  _ \ 
# | |_| | | | | |   | |  | | | \ \ /\ / /   \ \ /\ / / | || |_) |  _| | | | |
# |  _  | |_| | |___| |__| |_| |\ V  V /     \ V  V /  | ||  _ <| |___| |_| |
# |_| |_|\___/|_____|_____\___/  \_/\_/       \_/\_/  |___|_| \_\_____|____/ 
# ==============================================================================
# HOLLOW-WIRED // Hyprland + Quickshell Universal Rice Installer
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# PALETA DE CORES CYBERPUNK / HOLLOW-WIRED
# ------------------------------------------------------------------------------
CYAN='\033[38;2;34;211;238m'     # #22d3ee - Destaque principal
PINK='\033[38;2;244;114;182m'    # #f472b6 - Acento magenta
GREEN='\033[38;2;52;211;153m'    # #34d399 - Sucesso
RED='\033[38;2;248;113;113m'     # #f87171 - Alerta / Erro
AMBER='\033[38;2;251;191;36m'    # #fbbf24 - Atenção
YELLOW="$AMBER"
PURPLE='\033[38;2;192;132;252m'  # #c084fc - Wired / Lain
GRAY='\033[38;2;100;116;139m'    # #64748b - Texto secundário
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
BACKUP_DIR="$HOME/.config/rice-backup-$(date +%Y%m%d_%H%M%S)"

# Suporte à execução via curl / pipe (ex: curl -sS https://... | bash)
# Se o script estiver sendo executado via stdin ou fora da pasta clonada, clona automaticamente.
#
# O repositório vai para ~/.local/share/hollow-wired (o lugar padrão de dados de
# programa no Linux), e não para uma pasta de projetos na home: quem instala
# pelo curl não é desenvolvedor e não precisa ver nem mexer nesses arquivos. As
# configurações continuam em ~/.config. O `rice-update` puxa as novidades daqui.
if [ -z "$SCRIPT_DIR" ] || [ ! -d "$SCRIPT_DIR/dots" ]; then
    TARGET_REPO="${XDG_DATA_HOME:-$HOME/.local/share}/hollow-wired"
    OLD_REPO="$HOME/projetos/hollow-wired"
    echo -e "\033[38;2;34;211;238m[*] Execução remota detectada. Clonando repositório hollow-wired...\033[0m"
    if ! command -v git >/dev/null 2>&1; then
        echo -e "\033[38;2;248;113;113m[!] Git não encontrado. Instalando git...\033[0m"
        sudo pacman -S --needed --noconfirm git
    fi
    mkdir -p "$(dirname "$TARGET_REPO")"
    # Instalações antigas clonavam em ~/projetos/hollow-wired. Se aquele clone
    # estiver limpo (sem mudanças locais nem commits próprios), é movido para o
    # lugar novo; se tiver algo do usuário, fica onde está e um clone novo é
    # feito, para não perder nada.
    if [ ! -d "$TARGET_REPO/.git" ] && [ -d "$OLD_REPO/.git" ] \
        && [ -z "$(git -C "$OLD_REPO" status --porcelain 2>/dev/null)" ] \
        && [ "$(git -C "$OLD_REPO" rev-list --count origin/main..HEAD 2>/dev/null || echo 1)" = "0" ]; then
        echo -e "\033[38;2;52;211;153m[*] Movendo o repositório de $OLD_REPO para $TARGET_REPO...\033[0m"
        mv "$OLD_REPO" "$TARGET_REPO"
        rmdir "$HOME/projetos" 2>/dev/null || true
    fi
    if [ -d "$TARGET_REPO/.git" ]; then
        echo -e "\033[38;2;52;211;153m[*] Repositório existente em $TARGET_REPO. Atualizando...\033[0m"
        git -C "$TARGET_REPO" pull --ff-only origin main || true
    else
        git clone https://github.com/Valcones47/hollow-wired.git "$TARGET_REPO"
    fi
    # Reexecuta com terminal interativo (/dev/tty) para suportar animações e prompts
    exec bash "$TARGET_REPO/install.sh" "$@" </dev/tty
fi

# ------------------------------------------------------------------------------
# FUNÇÕES DE INTERFACE DO TERMINAL
# ------------------------------------------------------------------------------
box_msg() {
    local color="$1"
    local title="$2"
    local line="──────────────────────────────────────────────────────────────"
    echo -e "${color}╭─${line}─╮${NC}"
    echo -e "${color}│${NC}  ${BOLD}${title}${NC}"
    echo -e "${color}╰─${line}─╯${NC}"
}

step_banner() {
    local step="$1"
    local title="$2"
    local desc="$3"
    echo -e "\n${CYAN}┌── ${BOLD}[$step] ${WHITE}${title}${NC}"
    echo -e "${CYAN}│   ${GRAY}$desc${NC}"
    echo -e "${CYAN}└───┄┄${NC}"
}

info_msg()    { echo -e "  ${CYAN}◈${NC} ${BOLD}[INFO]${NC} $1"; }
ok_msg()      { echo -e "  ${GREEN}✓${NC} ${BOLD}[OK]${NC}   $1"; }
warn_msg()    { echo -e "  ${AMBER}▲${NC} ${BOLD}[WARN]${NC} $1"; }
gear_msg()    { echo -e "  ${PURPLE}⬢${NC} ${BOLD}[GEAR]${NC} $1"; }
lain_msg()    { echo -e "  ${PINK}♥${NC} ${BOLD}[LAIN]${NC} $1"; }

# Exibição de GIFs animados da Lain com fallback gracioso
show_lain_gif() {
    local gif_file="$1"
    local duration="${2:-2.5}"
    local title="${3:-LAIN.SYS // WIRED PROTOCOL}"
    local subtitle="${4:-Conectando à rede...}"
    local size="${5:-36x18}"

    # Se chafa não estiver instalado, tenta instalar rapidamente
    if ! command -v chafa >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm chafa >/dev/null 2>&1 || true
    fi

    echo -e "\n${PURPLE}╭──────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${PURPLE}│${NC}  ${PINK}♥${NC} ${BOLD}${WHITE}$title${NC}"
    echo -e "${PURPLE}│${NC}  ${GRAY}$subtitle${NC}"
    echo -e "${PURPLE}╰──────────────────────────────────────────────────────────────╯${NC}"

    if [ -f "$gif_file" ] && command -v chafa >/dev/null 2>&1; then
        # Terminal interativo ou /dev/tty disponível: anima o GIF com máxima performance
        if [ -w /dev/tty ] || [ -t 1 ]; then
            chafa --probe=off --duration "$duration" --speed 1.2 --size "$size" --symbols vhalf+quad --color-space rgb "$gif_file" 2>/dev/null || \
            chafa --probe=off --size "$size" "$gif_file" 2>/dev/null || true
        else
            # Saída não-interativa / log: renderiza frame estático
            chafa --probe=off --animate=off --size "$size" "$gif_file" 2>/dev/null || true
        fi
    else
        # Fallback ASCII estético caso gif ou chafa não estejam disponíveis
        echo -e "${PURPLE}"
        cat << "EOF"
         .-.
       .-| |-.     [ CLOSE THE WORLD ]
       | | | |     [   OPEN THE NEXT ]
       | | | |     [   LAIN IS HERE  ]
       '-'-'-'
EOF
        echo -e "${NC}"
        sleep 1
    fi
    echo ""
}

# ------------------------------------------------------------------------------
# APRESENTAÇÃO & FASE 1: LAIN GIF 1 (lain4.gif)
# ------------------------------------------------------------------------------
clear 2>/dev/null || true

LAIN_GIF_1="$SCRIPT_DIR/dots/fastfetch/logos/lain4.gif"
LAIN_GIF_2="$SCRIPT_DIR/dots/fastfetch/logos/lain5.gif"

# Se não estiverem em dots/fastfetch/logos, busca no sistema
_pics_dir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Imagens")"
[ ! -f "$LAIN_GIF_1" ] && [ -f "$_pics_dir/FastFetch/lain4.gif" ] && LAIN_GIF_1="$_pics_dir/FastFetch/lain4.gif"
[ ! -f "$LAIN_GIF_2" ] && [ -f "$_pics_dir/FastFetch/lain5.gif" ] && LAIN_GIF_2="$_pics_dir/FastFetch/lain5.gif"

echo -e "${CYAN}${BOLD}"
cat << "BANNER"
  ╦ ╦╔═╗╦  ╦  ╔═╗╦ ╦   ╦ ╦╦╦═╗╔═╗╔╦╗
  ╠═╣║ ║║  ║  ║ ║║║║───║║║║╠╦╝║╣  ║║
  ╩ ╩╚═╝╩═╝╩═╝╚═╝╚╩╝   ╚╩╝╩╩╚═╚═╝═╩╝
BANNER
echo -e "${NC}"
echo -e "${GRAY}  Cyberpunk Desktop Environment • Hyprland (Lua) + Quickshell${NC}"
echo -e "${GRAY}  Versão 2.0 • Totalmente Automatizado & Customizável${NC}\n"

# Exibe o primeiro GIF da Lain (inicialização)
show_lain_gif "$LAIN_GIF_1" 2.5 "LAIN.SYS // PROTOCOLO WIRED INICIALIZADO" "Acessando a rede... Preparando o ambiente do rice."

# ------------------------------------------------------------------------------
# ETAPA 1: DETECÇÃO DE SISTEMA & HARDWARE
# ------------------------------------------------------------------------------
step_banner "01/04" "Sistema & Detecção de Ambiente" "Verificando distribuição Linux, arquitetura e periféricos"

if [ ! -f /etc/arch-release ]; then
    echo -e "${RED}[!] Este instalador é destinado ao CachyOS ou Arch Linux.${NC}"
    exit 1
fi

IS_CACHYOS=false
if grep -qi "cachyos" /etc/os-release 2>/dev/null; then
    IS_CACHYOS=true
    ok_msg "Distribuição: ${GREEN}CachyOS detectado!${NC} (Repositórios otimizados x86-64-v3/v4)"
else
    info_msg "Distribuição: ${CYAN}Arch Linux detectado${NC}"
fi

CPU_MODEL=$(lscpu | grep "Model name:" | sed 's/Model name:[ \t]*//' || echo "Processador Compatível")
info_msg "Processador: ${WHITE}$CPU_MODEL${NC}"

# Detecção informativa de GPU & Verificação de Séries Legadas da NVIDIA (900 / 1000)
# Sem o pciutils (instalação mínima) o lspci não existe e a detecção saía vazia.
command -v lspci >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm pciutils >/dev/null 2>&1 || true
GPU_INFO=$(lspci 2>/dev/null | grep -Ei "vga|3d" | sed 's/.*: //g' | paste -sd '|' - | sed 's/|/ | /g')
GPU_INFO="${GPU_INFO:-Gráficos Genéricos}"
info_msg "Placa(s) de Vídeo: ${WHITE}$GPU_INFO${NC}"

IS_LEGACY_NVIDIA=false
LEGACY_NVIDIA_NAME=""
if echo "$GPU_INFO" | grep -Eiq "(GeForce|GTX|GT)[^]]*\b9[0-9]{2}"; then
    IS_LEGACY_NVIDIA=true
    LEGACY_NVIDIA_NAME="Série 900 (Maxwell - ex: GTX 950/960/970/980)"
elif echo "$GPU_INFO" | grep -Eiq "(GeForce|GTX|GT)[^]]*\b10[0-9]{2}"; then
    IS_LEGACY_NVIDIA=true
    LEGACY_NVIDIA_NAME="Série 1000 (Pascal - ex: GTX 1050/1060/1070/1080)"
fi

if [ "$IS_LEGACY_NVIDIA" = true ]; then
    warn_msg "NVIDIA ${WHITE}$LEGACY_NVIDIA_NAME${AMBER} detectada!"
    info_msg "Drivers de GPU: ${CYAN}Opção de instalação do driver legado proprietário (580xx) será oferecida na Etapa 4.${NC}"
else
    info_msg "Drivers de GPU: ${GREEN}Gerenciamento delegado ao CachyOS/Hardware Detection (chwd)${NC}"
fi

CHASSIS="Desktop"
if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
    CHASSIS="Notebook"
fi
info_msg "Chassi detectado: ${WHITE}$CHASSIS${NC}"

# Detecção e instalação do AUR Helper — yay é o principal; paru só é usado
# quando já está instalado e o yay não.
AUR_HELPER=""
if command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
elif command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
else
    warn_msg "Nenhum AUR helper encontrado (yay/paru). Instalando yay..."
    sudo pacman -S --needed --noconfirm base-devel git
    if pacman -Si yay >/dev/null 2>&1; then
        # CachyOS (e outros) trazem o yay no repositório: sem compilar nada.
        sudo pacman -S --needed --noconfirm yay
    else
        # Sobra de uma tentativa anterior faria o clone falhar e, com set -e, abortaria tudo.
        rm -rf /tmp/yay-bin
        git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
        (cd /tmp/yay-bin && makepkg -si --noconfirm)
    fi
    AUR_HELPER="yay"
fi
ok_msg "AUR Helper ativo: ${GREEN}$AUR_HELPER${NC}"

# ------------------------------------------------------------------------------
# ETAPA 2: INSTALAÇÃO DE DEPENDÊNCIAS DO RICE
# ------------------------------------------------------------------------------
step_banner "02/04" "Dependências Essenciais do Rice" "Instalando Hyprland, Quickshell, Wallust, áudio PipeWire e utilitários"

# Lista focada 100% no ricing e interface (SEM drivers proprietários de GPU e SEM pacotes de jogos)
# Lista em packages.txt (a mesma que o rice-update usa para instalar o que
# entrar de novo em quem já tem o rice).
# Módulos opcionais: pacotes marcados com "@modulo" no packages.txt. Os
# recusados ficam em ~/.config/hollow-wired/skip-modules (o rice-update
# também respeita, para não instalá-los numa atualização).
SKIP_FILE="$HOME/.config/hollow-wired/skip-modules"
mkdir -p "$(dirname "$SKIP_FILE")"
touch "$SKIP_FILE"
if [ -t 0 ]; then
    echo -e "  ${BOLD}Módulos opcionais${NC} ${GRAY}(Enter = sim)${NC}"
    ask_module() {
        local mod="$1" desc="$2" ans
        read -rp "  $desc [S/n]: " ans || ans=s
        if [[ "${ans:-s}" =~ ^[Nn]$ ]]; then
            grep -qx "$mod" "$SKIP_FILE" || echo "$mod" >> "$SKIP_FILE"
        else
            sed -i "/^${mod}\$/d" "$SKIP_FILE"
        fi
    }
    ask_module gravacao "Gravação de tela (gpu-screen-recorder, wf-recorder)"
    ask_module apps "Programas para quem vem do Windows (compactados, PDF, imagens, pendrives NTFS)"
fi

RICE_PACKAGES=()
while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%%#*}"
    line="${line//[[:space:]]/}"
    [ -n "$line" ] || continue
    if [[ "$raw" =~ @([a-z]+) ]] && grep -qx "${BASH_REMATCH[1]}" "$SKIP_FILE" 2>/dev/null; then
        continue
    fi
    RICE_PACKAGES+=("$line")
done < "$SCRIPT_DIR/packages.txt"

info_msg "Sincronizando chaveiros de segurança e banco do pacman..."
sudo pacman -Sy --needed --noconfirm archlinux-keyring 2>/dev/null || true
if [ "$IS_CACHYOS" = true ]; then
    sudo pacman -Sy --needed --noconfirm cachyos-keyring 2>/dev/null || true
fi

# Drivers Vulkan e de decodificação de vídeo da placa que desenha a tela.
# (NVIDIA fica com o chwd/driver do sistema; a série legada tem etapa própria.)
if echo "$GPU_INFO" | grep -qi "intel"; then
    RICE_PACKAGES+=(vulkan-intel intel-media-driver)
fi
if echo "$GPU_INFO" | grep -Eqi "amd|ati|radeon"; then
    RICE_PACKAGES+=(vulkan-radeon)
fi
# Notebook híbrido com NVIDIA: prime-run manda jogos para a placa dedicada.
if echo "$GPU_INFO" | grep -qi "nvidia" && [ "$(echo "$GPU_INFO" | grep -o '|' | wc -l)" -ge 1 ]; then
    RICE_PACKAGES+=(nvidia-prime)
fi

info_msg "Verificando dependências já presentes no sistema..."
MISSING_PKGS=()
for pkg in "${RICE_PACKAGES[@]}"; do
    if [ "$pkg" = "wallust-git" ] && (pacman -T wallust >/dev/null 2>&1 || pacman -T wallust-git >/dev/null 2>&1 || command -v wallust >/dev/null 2>&1); then
        continue
    fi
    if ! pacman -T "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
    ok_msg "Todas as dependências do rice já estão instaladas e satisfeitas!"
else
    info_msg "Identificados ${#MISSING_PKGS[@]} pacote(s) pendente(s) para instalação."
    
    # Separa pacotes de repositórios oficiais e pacotes exclusivos do AUR
    REPO_MISSING=()
    AUR_MISSING=()
    for pkg in "${MISSING_PKGS[@]}"; do
        if pacman -Si "$pkg" >/dev/null 2>&1; then
            REPO_MISSING+=("$pkg")
        else
            AUR_MISSING+=("$pkg")
        fi
    done

    if [ ${#REPO_MISSING[@]} -gt 0 ]; then
        gear_msg "Instalando pacotes dos repositórios oficiais (${#REPO_MISSING[@]}): ${REPO_MISSING[*]}..."
        # Um conflito (ex.: tuned-ppd x power-profiles-daemon) derrubava a
        # transação inteira e nada era instalado. Plano B: um por vez.
        if ! sudo pacman -S --needed --noconfirm "${REPO_MISSING[@]}"; then
            warn_pkgs=()
            for pkg in "${REPO_MISSING[@]}"; do
                sudo pacman -S --needed --noconfirm "$pkg" >/dev/null 2>&1 || warn_pkgs+=("$pkg")
            done
            [ ${#warn_pkgs[@]} -gt 0 ] && echo -e "  ${GRAY}Não instalados (conflito ou indisponíveis): ${warn_pkgs[*]}${NC}"
        fi
    fi

    if [ ${#AUR_MISSING[@]} -gt 0 ]; then
        gear_msg "Instalando pacotes do AUR (${#AUR_MISSING[@]}) via $AUR_HELPER: ${AUR_MISSING[*]}..."
        if [ "$AUR_HELPER" = "paru" ]; then
            paru -S --needed --noconfirm --skipreview "${AUR_MISSING[@]}"
        else
            $AUR_HELPER -S --needed --noconfirm "${AUR_MISSING[@]}"
        fi
    fi
    ok_msg "Dependências do rice instaladas com sucesso!"
fi

# ------------------------------------------------------------------------------
# ETAPA 3: A TROCA! LAIN GIF 2 (lain5.gif) & DEPLOY DOS DOTFILES
# ------------------------------------------------------------------------------
# Aqui ocorre a troca de GIF da Lain para a fase de sincronização e ricing!
show_lain_gif "$LAIN_GIF_2" 3.0 "LAIN.SYS // FASE 2: TRANSMITINDO O RICE PARA A WIRED" "Sincronizando Quickshell, Hyprland Lua, Wallust e utilitários..."

step_banner "03/04" "Sincronização de Dotfiles & Configurações" "Aplicando temas, barras, menus e scripts em ~/.config e ~/.local/bin"

# 1. Backup de segurança de configurações existentes
mkdir -p "$BACKUP_DIR"
for dir in hypr quickshell kitty wallust xdg-desktop-portal fastfetch swappy gtk-3.0 gtk-4.0; do
    if [ -d "$HOME/.config/$dir" ]; then
        info_msg "Criando backup preventivo de ~/.config/$dir em $BACKUP_DIR/"
        cp -a "$HOME/.config/$dir" "$BACKUP_DIR/" 2>/dev/null || true
    fi
done
ok_msg "Backup salvo em: ${WHITE}$BACKUP_DIR${NC}"

# 2. Criação das pastas de destino
# Gera/atualiza ~/.config/user-dirs.dirs pro idioma/locale atual do usuário
# (essencial pra quem instala em inglês ou outro idioma diferente do pt-BR do
# autor: sem isso, "Vídeos"/"Imagens" ficariam hardcoded em português mesmo em
# sistemas onde a pasta real do usuário é "Videos"/"Pictures").
command -v xdg-user-dirs-update >/dev/null 2>&1 && xdg-user-dirs-update 2>/dev/null || true
PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Imagens")"
VIDEOS_DIR="$(xdg-user-dir VIDEOS 2>/dev/null || echo "$HOME/Vídeos")"

mkdir -p "$HOME/.config" \
         "$HOME/.local/bin" \
         "$HOME/.local/share/applications" \
         "$VIDEOS_DIR/Gravações" \
         "$PICTURES_DIR/Capturas de tela" \
         "$PICTURES_DIR/FastFetch"

# 3. Cópia dos dotfiles para o usuário (preservando preferências pessoais se já existirem)
gear_msg "Copiando configurações do Quickshell, Hyprland Lua, Kitty e Temas..."

saved_dock="" saved_widgets="" saved_shell="" saved_locale="" saved_kitty="" saved_user_binds="" saved_user_prefs="" saved_colors=""
[ -f "$HOME/.config/hypr/colors.conf" ] && saved_colors=$(cat "$HOME/.config/hypr/colors.conf")
[ -f "$HOME/.config/quickshell/dock.json" ] && saved_dock=$(cat "$HOME/.config/quickshell/dock.json")
[ -f "$HOME/.config/quickshell/desktop-widgets.json" ] && saved_widgets=$(cat "$HOME/.config/quickshell/desktop-widgets.json")
[ -f "$HOME/.config/quickshell/shell-customization.json" ] && saved_shell=$(cat "$HOME/.config/quickshell/shell-customization.json")
[ -f "$HOME/.config/quickshell/locale.json" ] && saved_locale=$(cat "$HOME/.config/quickshell/locale.json")
[ -f "$HOME/.config/kitty/kitty.conf" ] && saved_kitty=$(cat "$HOME/.config/kitty/kitty.conf")
[ -f "$HOME/.config/hypr/user-binds.lua" ] && saved_user_binds=$(cat "$HOME/.config/hypr/user-binds.lua")
[ -f "$HOME/.config/hypr/user-prefs.json" ] && saved_user_prefs=$(cat "$HOME/.config/hypr/user-prefs.json")

cp -a "$SCRIPT_DIR/dots/hypr" "$HOME/.config/"
cp -a "$SCRIPT_DIR/dots/quickshell" "$HOME/.config/"
cp -a "$SCRIPT_DIR/dots/kitty" "$HOME/.config/"
[ -d "$SCRIPT_DIR/dots/wallust" ] && cp -a "$SCRIPT_DIR/dots/wallust" "$HOME/.config/"
[ -d "$SCRIPT_DIR/dots/xdg-desktop-portal" ] && cp -a "$SCRIPT_DIR/dots/xdg-desktop-portal" "$HOME/.config/"
[ -d "$SCRIPT_DIR/dots/fastfetch" ] && cp -a "$SCRIPT_DIR/dots/fastfetch" "$HOME/.config/"
[ -d "$SCRIPT_DIR/dots/swappy" ] && cp -a "$SCRIPT_DIR/dots/swappy" "$HOME/.config/"
# Sem este arquivo o mako caía no visual padrão (caixa branca, sem bordas
# arredondadas e sem as cores do wallust), destoando de todo o resto do rice.
[ -d "$SCRIPT_DIR/dots/mako" ] && cp -a "$SCRIPT_DIR/dots/mako" "$HOME/.config/"
[ -d "$SCRIPT_DIR/dots/gtk-3.0" ] && cp -a "$SCRIPT_DIR/dots/gtk-3.0" "$HOME/.config/"
[ -d "$SCRIPT_DIR/dots/gtk-4.0" ] && cp -a "$SCRIPT_DIR/dots/gtk-4.0" "$HOME/.config/"

# A paleta do wallust (colors.conf) pertence ao wallpaper do usuário: a cópia do
# repositório só serve de ponto de partida quando ainda não existe nenhuma.
if [ -n "$saved_colors" ]; then
    echo "$saved_colors" > "$HOME/.config/hypr/colors.conf"
fi

# Restaura preferências pessoais pré-existentes
[ -n "$saved_dock" ] && echo "$saved_dock" > "$HOME/.config/quickshell/dock.json"
[ -n "$saved_widgets" ] && echo "$saved_widgets" > "$HOME/.config/quickshell/desktop-widgets.json"
[ -n "$saved_shell" ] && echo "$saved_shell" > "$HOME/.config/quickshell/shell-customization.json"
[ -n "$saved_locale" ] && echo "$saved_locale" > "$HOME/.config/quickshell/locale.json"
# Instalação nova: idioma da interface pelo idioma do sistema. Antes vinha
# sempre o do repositório (inglês), mesmo num sistema em português.
if [ -z "$saved_locale" ]; then
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
        pt*) echo '{"locale": "pt-BR"}' > "$HOME/.config/quickshell/locale.json" ;;
        *)   echo '{"locale": "en"}' > "$HOME/.config/quickshell/locale.json" ;;
    esac
fi
[ -n "$saved_kitty" ] && echo "$saved_kitty" > "$HOME/.config/kitty/kitty.conf"
[ -n "$saved_user_binds" ] && echo "$saved_user_binds" > "$HOME/.config/hypr/user-binds.lua"
[ -n "$saved_user_prefs" ] && echo "$saved_user_prefs" > "$HOME/.config/hypr/user-prefs.json"

# 4. Cópia dos atalhos .desktop e binários
gear_msg "Instalando utilitários do rice em ~/.local/bin/..."
[ -d "$SCRIPT_DIR/dots/applications" ] && cp -a "$SCRIPT_DIR/dots/applications/"* "$HOME/.local/share/applications/" 2>/dev/null || true
cp -a --remove-destination "$SCRIPT_DIR/dots/bin/"* "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/"*

# 5. Cópia dos Logos e GIFs da Lain para ~/Imagens/FastFetch
gear_msg "Copiando GIFs da Lain e logos para $PICTURES_DIR/FastFetch/..."
if [ -d "$SCRIPT_DIR/dots/fastfetch/logos" ]; then
    cp -a "$SCRIPT_DIR/dots/fastfetch/logos/"* "$PICTURES_DIR/FastFetch/" 2>/dev/null || true
fi

# 6. Atualização dinâmica do caminho no Fastfetch e Swappy config para o usuário atual
if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
    # Cobre tanto o caminho do autor (~/Imagens/FastFetch) quanto qualquer outro
    # já gravado, apontando pra pasta de imagens real deste usuário.
    sed -i -E "s|/home/[^/\"]*/(Imagens|Pictures|Bilder|Images)/FastFetch|$PICTURES_DIR/FastFetch|g" "$HOME/.config/fastfetch/config.jsonc"
fi
if [ -f "$HOME/.config/swappy/config" ]; then
    sed -i "s|save_dir=.*|save_dir=$PICTURES_DIR/Capturas de tela|g" "$HOME/.config/swappy/config"
fi

# 7. Registra repositório para o atualizador automático (rice-update)
echo "$SCRIPT_DIR" > "$HOME/.config/hollow-wired-repo"
echo "$SCRIPT_DIR" > "$HOME/.config/hyprland-setup-repo"

# 8. Garantir ~/.local/bin no PATH do usuário
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    [ -f "$HOME/.zshrc" ] && echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    info_msg "Adicionado ~/.local/bin ao PATH em ~/.bashrc / ~/.zshrc"
fi

# 9. Configuração de Temas de Ícones e Aparência GTK
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme "cachyos-nord" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true
fi
sudo ln -sf /usr/share/icons/*.png /usr/share/pixmaps/ 2>/dev/null || true

# 9. Avatar Inicial se não existir
if [ ! -f "$HOME/.face.webp" ] && [ ! -f "$HOME/.face" ]; then
    touch "$HOME/.face"
fi

"$HOME/.local/bin/rice-portals" 2>/dev/null || true
ok_msg "Dotfiles, scripts e assets aplicados com perfeição!"

# ------------------------------------------------------------------------------
# ETAPA 4: SERVIÇOS, ZRAM & OPÇÕES DO SISTEMA
# ------------------------------------------------------------------------------
step_banner "04/04" "Serviços, zRAM & Opções Adicionais" "Configurações de memória ultrarrápida e recursos opcionais"

# Configuração inteligente de zRAM (ZSTD), escalada pela RAM física instalada.
# Nunca configura mais zRAM do que a RAM total da máquina: como o zram guarda
# dados comprimidos dentro da própria RAM, um valor fixo alto (ex: 16GB) numa
# máquina com pouca RAM (notebooks de 4-8GB de amigos, por exemplo) compete
# pela mesma memória que deveria estar aliviando e pode causar pressão/OOM.
# Teto de 16GB em máquinas com RAM suficiente (comportamento anterior preservado).
TOTAL_RAM_MB=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024))
if [ "$TOTAL_RAM_MB" -lt 16384 ]; then
    TARGET_ZRAM_MB=$TOTAL_RAM_MB
else
    TARGET_ZRAM_MB=16384
fi
TARGET_ZRAM_BYTES=$((TARGET_ZRAM_MB * 1024 * 1024))

CURRENT_ZRAM_BYTES=$(zramctl -b -n -o DISKSIZE /dev/zram0 2>/dev/null | head -n1 || echo 0)
[ -z "$CURRENT_ZRAM_BYTES" ] && CURRENT_ZRAM_BYTES=0

if [ "$CURRENT_ZRAM_BYTES" -ge "$TARGET_ZRAM_BYTES" ] 2>/dev/null; then
    ok_msg "zRAM já configurado com ${TARGET_ZRAM_MB}MB ou mais ($((CURRENT_ZRAM_BYTES / 1024 / 1024))MB). Nenhuma alteração necessária."
else
    if [ "$CURRENT_ZRAM_BYTES" -gt 0 ] 2>/dev/null; then
        warn_msg "zRAM atual detectado abaixo do ideal ($((CURRENT_ZRAM_BYTES / 1024 / 1024))MB). Redefinindo para ${TARGET_ZRAM_MB}MB ZSTD..."
    else
        gear_msg "zRAM não detectado ou inativo. Configurando ${TARGET_ZRAM_MB}MB de zRAM com compressão ZSTD (RAM detectada: ${TOTAL_RAM_MB}MB)..."
    fi

    sudo bash -c "cat << ZRAM_EOF > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ${TARGET_ZRAM_MB}
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
ZRAM_EOF"

    sudo systemctl daemon-reload
    sudo swapoff /dev/zram0 2>/dev/null || true
    sudo systemctl restart /dev/zram0 2>/dev/null || sudo systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
    ok_msg "zRAM configurado para ${TARGET_ZRAM_MB}MB (ZSTD) com sucesso!"
fi

# Flathub sempre: a loja de apps (Shelly) e o Waywallen instalam por ele, e
# antes ele só era configurado se a pessoa aceitasse o Waywallen.
# Instalação do sistema (a mesma que o `flatpak install flathub ...` usa por padrão).
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

# Navegador: numa instalação mínima não há nenhum, e o rice abre links,
# o clima e a loja pelo navegador padrão.
# O Zen é checado pela instalação real: o rice põe um atalho `zen-browser`
# em ~/.local/bin (para rodar na placa dedicada) que existe mesmo sem o Zen.
zen_installed() {
    local c
    for c in /opt/zen-browser-bin/zen-bin /opt/zen-browser/zen-bin /usr/lib/zen-browser/zen-bin /usr/bin/zen-browser /usr/bin/zen; do
        [ -x "$c" ] && return 0
    done
    flatpak info app.zen_browser.zen >/dev/null 2>&1
}
HAS_BROWSER=false
zen_installed && HAS_BROWSER=true
for b in firefox chromium google-chrome-stable brave vivaldi-stable librewolf microsoft-edge-stable; do
    command -v "$b" >/dev/null 2>&1 && HAS_BROWSER=true && break
done
if [ "$HAS_BROWSER" = false ]; then
    echo -e "\n${CYAN}◈ [RECOMENDADO] Nenhum navegador encontrado.${NC}"
    echo -e "  ${WHITE}1${NC}) Firefox   ${WHITE}2${NC}) Zen Browser   ${WHITE}3${NC}) Chromium   ${WHITE}4${NC}) Brave   ${WHITE}0${NC}) Nenhum"
    read -rp "  Qual instalar? [1]: " BROWSER_CHOICE || true
    case "${BROWSER_CHOICE:-1}" in
        1) sudo pacman -S --needed --noconfirm firefox firefox-i18n-pt-br || true ;;
        2) [ -n "${AUR_HELPER:-}" ] && $AUR_HELPER -S --needed --noconfirm zen-browser-bin || true ;;
        3) sudo pacman -S --needed --noconfirm chromium || true ;;
        4) [ -n "${AUR_HELPER:-}" ] && $AUR_HELPER -S --needed --noconfirm brave-bin || true ;;
    esac
fi

# A dock vem com o Zen fixado. Sem ele, fixa o navegador padrão que existir
# (senão a dock ficava sem navegador nenhum).
if ! zen_installed && [ -f "$HOME/.config/quickshell/dock.json" ] && command -v jq >/dev/null 2>&1; then
    BROWSER_ID=$(xdg-settings get default-web-browser 2>/dev/null | sed 's/\.desktop$//')
    if [ -z "$BROWSER_ID" ]; then
        for b in firefox chromium brave-browser google-chrome vivaldi-stable; do
            [ -f "/usr/share/applications/$b.desktop" ] && BROWSER_ID=$b && break
        done
    fi
    if [ -n "$BROWSER_ID" ]; then
        tmp_dock=$(jq --arg b "$BROWSER_ID" '.pins = [.pins[] | if . == "zen" then $b else . end]' "$HOME/.config/quickshell/dock.json" 2>/dev/null)
        [ -n "$tmp_dock" ] && printf '%s\n' "$tmp_dock" > "$HOME/.config/quickshell/dock.json"
    fi
fi

# Opcional: Wallpaper Engine (Waywallen via Flatpak)
echo -e "\n${CYAN}◈ [OPCIONAL] Deseja instalar o suporte a Wallpaper Engine (Waywallen via Flatpak)?${NC}"
read -rp "  Instalar Waywallen? [S/n]: " INSTALL_WAYWALLEN || true
INSTALL_WAYWALLEN=${INSTALL_WAYWALLEN:-S}
if [[ "$INSTALL_WAYWALLEN" =~ ^[Ss]$ ]]; then
    gear_msg "Instalando Waywallen..."
    flatpak install -y flathub org.waywallen.waywallen 2>/dev/null || true
    ok_msg "Waywallen instalado! Atalho Super + S configurado."
fi

# Opcional: loja de programas (Shelly)
# O rice abre a "loja" pelo painel e pela sidebar; sem nenhuma, esses botões só
# conseguem oferecer a instalação na hora. O Shelly instala e atualiza pacotes
# do repositório, AUR, Flatpak e AppImage num lugar só, e no CachyOS vem do
# repositório oficial (recompilado junto com o pacman — o Pamac, do AUR,
# quebra a cada atualização da libalpm).
if command -v shelly-ui >/dev/null 2>&1 || command -v shelly >/dev/null 2>&1; then
    ok_msg "Shelly (loja de programas) já está instalado."
else
    echo -e "\n${CYAN}◈ [RECOMENDADO] O Shelly não está instalado.${NC}"
    echo -e "  ${GRAY}É a loja de programas do rice: instala e atualiza pacotes do repositório, AUR, Flatpak e AppImage.${NC}"
    if pacman -Q pamac-aur >/dev/null 2>&1 || pacman -Q pamac-gtk >/dev/null 2>&1; then
        echo -e "  ${GRAY}O Pamac que você tem continua funcionando; o Shelly passa a ser o preferido.${NC}"
    fi
    read -rp "  Instalar o Shelly agora? [S/n]: " INSTALL_SHELLY || true
    INSTALL_SHELLY=${INSTALL_SHELLY:-s}
    if [[ "$INSTALL_SHELLY" =~ ^[Ss]$ ]]; then
        gear_msg "Instalando Shelly..."
        if pacman -Si shelly >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm shelly || true
        elif [ -n "${AUR_HELPER:-}" ]; then
            $AUR_HELPER -S --needed --noconfirm shelly || true
        fi
        if command -v shelly-ui >/dev/null 2>&1 || command -v shelly >/dev/null 2>&1; then
            ok_msg "Shelly instalado!"
        else
            echo -e "  ${GRAY}Não consegui instalar o Shelly agora — dá para instalar depois pelo painel (Super + I).${NC}"
        fi
    fi
fi

# Opcional: Tela de Login SDDM & Bootloader Limine
echo -e "\n${CYAN}◈ [OPCIONAL] Deseja configurar o SDDM (SilentSDDM) e o Bootloader Limine com tema do rice?${NC}"
read -rp "  Configurar Login e Boot agora? [s/N]: " APPLY_BOOT || true
APPLY_BOOT=${APPLY_BOOT:-n}
if [[ "$APPLY_BOOT" =~ ^[Ss]$ ]]; then
    gear_msg "Executando rice-apply-boot-login..."
    sudo "$HOME/.local/bin/rice-apply-boot-login" || true
    ok_msg "SDDM e Limine configurados com sucesso!"
fi

# Opcional: tela de login do rice (greetd) no lugar do SDDM
echo -e "\n${CYAN}◈ [OPCIONAL] Usar a tela de login do rice no lugar do SDDM?${NC}"
echo -e "  ${GRAY}A mesma cara da tela de bloqueio (relógio, clima, foto, wallpaper) com a${NC}"
echo -e "  ${GRAY}lista de sessões para escolher. Um assistente explica cada passo e só troca${NC}"
echo -e "  ${GRAY}no boot se você confirmar. Também dá para fazer depois pelo painel (Super + I).${NC}"
read -rp "  Configurar a tela de login do rice agora? [s/N]: " APPLY_GREETER || true
APPLY_GREETER=${APPLY_GREETER:-n}
if [[ "$APPLY_GREETER" =~ ^[Ss]$ ]]; then
    gear_msg "Abrindo o assistente da tela de login..."
    "$SCRIPT_DIR/dots/bin/rice-greeter" setup || \
        echo -e "  ${GRAY}O assistente não terminou — dá para rodar de novo com: rice-greeter setup${NC}"
fi

# Opcional: Driver Proprietário Legado NVIDIA para Séries 900 / 1000 (Maxwell / Pascal)
if [ "$IS_LEGACY_NVIDIA" = true ]; then
    echo -e "\n${CYAN}◈ [OPCIONAL] Placa NVIDIA ${WHITE}$LEGACY_NVIDIA_NAME${CYAN} detectada!${NC}"
    if pacman -Q nvidia-580xx-dkms >/dev/null 2>&1 || pacman -Q nvidia-550xx-dkms >/dev/null 2>&1 || pacman -Q nvidia-dkms >/dev/null 2>&1; then
        ok_msg "Driver proprietário NVIDIA já está instalado no sistema."
    else
        echo -e "  ${GRAY}Os drivers abertos (nouveau) travam GPUs dessa série em clock mínimo de repouso (~135 MHz).${NC}"
        echo -e "  ${GRAY}Instalar o driver proprietário legado (nvidia-580xx-dkms) libera 100% de clock, FPS e aceleração por hardware.${NC}"
        read -rp "  Deseja instalar o driver legado nvidia-580xx agora? [s/N]: " INSTALL_LEGACY_NV || true
        INSTALL_LEGACY_NV=${INSTALL_LEGACY_NV:-n}
        if [[ "$INSTALL_LEGACY_NV" =~ ^[Ss]$ ]]; then
            gear_msg "Instalando driver proprietário nvidia-580xx..."
            
            # Tenta via chwd se disponível, senão via pacman direto (repo cachyos), senão via AUR helper
            if command -v chwd >/dev/null 2>&1 && chwd -i nvidia-dkms-580xx 2>/dev/null; then
                ok_msg "Perfil nvidia-dkms-580xx aplicado com sucesso via chwd!"
            elif pacman -Si nvidia-580xx-dkms >/dev/null 2>&1; then
                sudo pacman -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils
            else
                $AUR_HELPER -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils 2>/dev/null || \
                $AUR_HELPER -S --needed --noconfirm nvidia-550xx-dkms nvidia-550xx-utils lib32-nvidia-550xx-utils
            fi
            
            gear_msg "Configurando nvidia-drm.modeset=1 e preservação de VRAM em /etc/modprobe.d/nvidia.conf..."
            sudo bash -c 'cat << "EOF" > /etc/modprobe.d/nvidia.conf
options nvidia-drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF'
            sudo systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service 2>/dev/null || true
            ok_msg "Driver legado nvidia-580xx e serviços de kernel configurados com sucesso!"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# SERVIÇOS DO SISTEMA
# ------------------------------------------------------------------------------
# Instalar não liga: numa instalação mínima o Wi-Fi e o Bluetooth ficavam
# desligados até alguém descobrir o systemctl.
for svc in NetworkManager bluetooth power-profiles-daemon; do
    if systemctl list-unit-files "$svc.service" 2>/dev/null | grep -q "^$svc.service" \
        && ! systemctl is-enabled --quiet "$svc.service" 2>/dev/null; then
        sudo systemctl enable --now "$svc.service" >/dev/null 2>&1 && ok_msg "Serviço $svc ativado."
    fi
done

# ------------------------------------------------------------------------------
# PAPEL DE PAREDE GARANTIDO
# ------------------------------------------------------------------------------
# Sem Wallpaper Engine, a área de trabalho abria totalmente preta e o wallust não
# tinha imagem nenhuma de onde tirar a paleta. Aqui garantimos que sempre exista
# um wallpaper — o do usuário, se houver, ou um gerado com as cores do tema.
if ! flatpak info org.waywallen.waywallen >/dev/null 2>&1; then
    gear_msg "Nenhum Wallpaper Engine detectado — definindo papel de parede estático..."
    "$HOME/.local/bin/rice-wallpaper-set" --ensure >/dev/null 2>&1 || true
    ok_msg "Papel de parede definido (troque quando quiser com Super + S)."
fi

# ------------------------------------------------------------------------------
# FINALIZAÇÃO & STATUS
# ------------------------------------------------------------------------------
echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════════╗"
echo "║          ✓ INSTALAÇÃO CONCLUÍDA COM SUCESSO!                 ║"
echo "║             Bem-vindo à Wired // Hollow-Wired                ║"
echo -e "╚══════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "  ${WHITE}${BOLD}Resumo do Sistema Configurado:${NC}"
echo -e "  • ${CYAN}Compositor:${NC}     Hyprland 0.56+ (Configurado em ~/.config/hypr/hyprland.lua)"
echo -e "  • ${CYAN}Interface:${NC}      Quickshell (TopBar, Hub Central, Dock, OSD, Widgets)"
echo -e "  • ${CYAN}Utilitários:${NC}    ~/.local/bin (Doctor, Wallust, Gravação, Wallpaper, Presets)"
echo -e "  • ${CYAN}Discord Binds:${NC}  Gravação de tecla ativa (Mute/Deafen via Super + I)"
echo -e "  • ${CYAN}Lain Fastfetch:${NC} $PICTURES_DIR/FastFetch (Gifs e logos da Lain prontos)"
echo -e "  • ${YELLOW}Backup:${NC}         $BACKUP_DIR\n"

echo -e "  ${WHITE}${BOLD}Primeiros passos:${NC}"
echo -e "  • Ao entrar na sessão, uma tela de ${CYAN}boas-vindas${NC} mostra os atalhos essenciais."
echo -e "  • ${CYAN}Tecla Windows${NC} abre o menu de aplicativos · ${CYAN}Super + F1${NC} lista todos os atalhos."
echo -e "  • ${CYAN}Super + I${NC} abre o painel de configurações · ${CYAN}Rice Doctor${NC} conserta problemas comuns.\n"

echo -e "${PURPLE}  \"No matter where you go, everyone's always connected.\"${NC}"
echo -e "  Faça logout da sua sessão atual e inicie a sessão ${BOLD}${CYAN}Hyprland${NC} pelo gerenciador de login!\n"
