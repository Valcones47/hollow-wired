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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.config/rice-backup-$(date +%Y%m%d_%H%M%S)"

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
        if [ -t 1 ]; then
            # Terminal interativo: anima o gif no tamanho ideal
            chafa --duration "$duration" --speed 1.2 --size "$size" --symbols vhalf+quad --color-space rgb "$gif_file" 2>/dev/null || \
            chafa --size "$size" "$gif_file" 2>/dev/null || true
        else
            # Saída não-interativa / log: renderiza frame estático
            chafa --animate=off --size "$size" "$gif_file" 2>/dev/null || true
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
[ ! -f "$LAIN_GIF_1" ] && [ -f "$HOME/Imagens/FastFetch/lain4.gif" ] && LAIN_GIF_1="$HOME/Imagens/FastFetch/lain4.gif"
[ ! -f "$LAIN_GIF_2" ] && [ -f "$HOME/Imagens/FastFetch/lain5.gif" ] && LAIN_GIF_2="$HOME/Imagens/FastFetch/lain5.gif"

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

# Detecção informativa de GPU (NÃO instala drivers no sistema; deixa para o CachyOS / usuário)
GPU_INFO=$(lspci 2>/dev/null | grep -Ei "vga|3d" | sed 's/.*: //g' | tr '\n' ' | ' | sed 's/ | $//' || echo "Gráficos Genéricos")
info_msg "Placa(s) de Vídeo: ${WHITE}$GPU_INFO${NC}"
info_msg "Drivers de GPU: ${GREEN}Gerenciamento delegado ao CachyOS/Hardware Detection (chwd)${NC}"

CHASSIS="Desktop"
if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
    CHASSIS="Notebook"
fi
info_msg "Chassi detectado: ${WHITE}$CHASSIS${NC}"

# Detecção e instalação do AUR Helper (paru ou yay)
AUR_HELPER=""
if command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
elif command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
else
    warn_msg "Nenhum AUR helper encontrado (paru/yay). Instalando paru-bin..."
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
    (cd /tmp/paru-bin && makepkg -si --noconfirm)
    AUR_HELPER="paru"
fi
ok_msg "AUR Helper ativo: ${GREEN}$AUR_HELPER${NC}"

# ------------------------------------------------------------------------------
# ETAPA 2: INSTALAÇÃO DE DEPENDÊNCIAS DO RICE
# ------------------------------------------------------------------------------
step_banner "02/04" "Dependências Essenciais do Rice" "Instalando Hyprland, Quickshell, Wallust, áudio PipeWire e utilitários"

# Lista focada 100% no ricing e interface (SEM drivers proprietários de GPU e SEM pacotes de jogos)
RICE_PACKAGES=(
    # Compositor & Shell
    hyprland
    aquamarine
    quickshell
    kitty
    wallust
    fastfetch
    cava
    mako
    wlsunset
    
    # Áudio & Mídia
    playerctl
    pipewire
    pipewire-pulse
    pipewire-alsa
    wireplumber
    
    # Captura, Gravação & Área de Transferência
    wf-recorder
    grim
    slurp
    swappy
    cliphist
    wl-clipboard
    
    # Bloqueio, Ociosidade & Feedback
    hypridle
    hyprlock
    hyprshot
    brightnessctl
    
    # Sistema, Portais & Ferramentas
    zenity
    ffmpeg
    libwebp
    jq
    socat
    bc
    lm_sensors
    rsync
    dolphin
    xdg-desktop-portal
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-kde
    zram-generator
    flatpak
    
    # Fontes
    ttf-jetbrains-mono-nerd
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    
    # Bibliotecas de Interface & Atalhos
    gtk4-layer-shell
    python-gobject
    python-evdev   # Necessário para gravação direta de atalhos de hardware do Discord
    chafa          # Renderizador de imagens/GIFs em alta fidelidade no terminal
)

info_msg "Sincronizando chaveiros de segurança e banco do pacman..."
sudo pacman -Sy --needed --noconfirm archlinux-keyring 2>/dev/null || true
if [ "$IS_CACHYOS" = true ]; then
    sudo pacman -Sy --needed --noconfirm cachyos-keyring 2>/dev/null || true
fi

info_msg "Verificando dependências já presentes no sistema..."
MISSING_PKGS=()
for pkg in "${RICE_PACKAGES[@]}"; do
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
        sudo pacman -S --needed --noconfirm "${REPO_MISSING[@]}"
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
for dir in hypr quickshell kitty wallust xdg-desktop-portal fastfetch; do
    if [ -d "$HOME/.config/$dir" ]; then
        info_msg "Criando backup preventivo de ~/.config/$dir em $BACKUP_DIR/"
        cp -a "$HOME/.config/$dir" "$BACKUP_DIR/" 2>/dev/null || true
    fi
done
ok_msg "Backup salvo em: ${WHITE}$BACKUP_DIR${NC}"

# 2. Criação das pastas de destino
mkdir -p "$HOME/.config" \
         "$HOME/.local/bin" \
         "$HOME/.local/share/applications" \
         "$HOME/Vídeos/Gravações" \
         "$HOME/Imagens/Capturas de tela" \
         "$HOME/Imagens/FastFetch"

# 3. Cópia dos dotfiles para o usuário
gear_msg "Copiando configurações do Quickshell, Hyprland Lua e Kitty..."
cp -a "$SCRIPT_DIR/dots/hypr" "$HOME/.config/"
cp -a "$SCRIPT_DIR/dots/quickshell" "$HOME/.config/"
cp -a "$SCRIPT_DIR/dots/kitty" "$HOME/.config/"
[ -d "$SCRIPT_DIR/dots/wallust" ] && cp -a "$SCRIPT_DIR/dots/wallust" "$HOME/.config/"
[ -d "$SCRIPT_DIR/dots/xdg-desktop-portal" ] && cp -a "$SCRIPT_DIR/dots/xdg-desktop-portal" "$HOME/.config/"
[ -d "$SCRIPT_DIR/dots/fastfetch" ] && cp -a "$SCRIPT_DIR/dots/fastfetch" "$HOME/.config/"

# 4. Cópia dos atalhos .desktop e binários
gear_msg "Instalando utilitários do rice em ~/.local/bin/..."
[ -d "$SCRIPT_DIR/dots/applications" ] && cp -a "$SCRIPT_DIR/dots/applications/"* "$HOME/.local/share/applications/" 2>/dev/null || true
cp -a --remove-destination "$SCRIPT_DIR/dots/bin/"* "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/"*

# 5. Cópia dos Logos e GIFs da Lain para ~/Imagens/FastFetch
gear_msg "Copiando GIFs da Lain e logos para ~/Imagens/FastFetch/..."
if [ -d "$SCRIPT_DIR/dots/fastfetch/logos" ]; then
    cp -a "$SCRIPT_DIR/dots/fastfetch/logos/"* "$HOME/Imagens/FastFetch/" 2>/dev/null || true
fi

# 6. Atualização dinâmica do caminho no Fastfetch config para o usuário atual
if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
    sed -i "s|/home/[^/]*/Imagens/FastFetch|$HOME/Imagens/FastFetch|g" "$HOME/.config/fastfetch/config.jsonc"
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

# 9. Avatar Inicial se não existir
if [ ! -f "$HOME/.face.webp" ] && [ ! -f "$HOME/.face" ]; then
    touch "$HOME/.face"
fi

systemctl --user restart xdg-desktop-portal 2>/dev/null || true
ok_msg "Dotfiles, scripts e assets aplicados com perfeição!"

# ------------------------------------------------------------------------------
# ETAPA 4: SERVIÇOS, ZRAM & OPÇÕES DO SISTEMA
# ------------------------------------------------------------------------------
step_banner "04/04" "Serviços, zRAM & Opções Adicionais" "Configurações de memória ultrarrápida e recursos opcionais"

# Configuração de zRAM com algoritmo ZSTD (3:1 de compactação na RAM)
if [ ! -f /etc/systemd/zram-generator.conf ]; then
    gear_msg "Configurando zRAM ZSTD para multitarefa sem travamentos..."
    sudo bash -c 'cat << "ZRAM_EOF" > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
ZRAM_EOF'
    sudo systemctl daemon-reload
    sudo systemctl start /dev/zram0 2>/dev/null || true
    ok_msg "zRAM ZSTD configurado e ativado com sucesso!"
else
    ok_msg "zRAM já configurado no sistema."
fi

# Opcional: Wallpaper Engine (Waywallen via Flatpak)
echo -e "\n${CYAN}◈ [OPCIONAL] Deseja instalar o suporte a Wallpaper Engine (Waywallen via Flatpak)?${NC}"
read -rp "  Instalar Waywallen? [S/n]: " INSTALL_WAYWALLEN || true
INSTALL_WAYWALLEN=${INSTALL_WAYWALLEN:-S}
if [[ "$INSTALL_WAYWALLEN" =~ ^[Ss]$ ]]; then
    gear_msg "Configurando Flathub e instalando Waywallen..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    flatpak install -y flathub org.waywallen.waywallen 2>/dev/null || true
    ok_msg "Waywallen instalado! Atalho Super + S configurado."
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
echo -e "  • ${CYAN}Utilitários:${NC}    ~/.local/bin (Doctor, Wallust, Gravação NVENC, Presets)"
echo -e "  • ${CYAN}Discord Binds:${NC}  Gravação de tecla ativa (Mute/Deafen via Super + I)"
echo -e "  • ${CYAN}Lain Fastfetch:${NC} ~/Imagens/FastFetch (Gifs e logos da Lain prontos)"
echo -e "  • ${YELLOW}Backup:${NC}         $BACKUP_DIR\n"

echo -e "${PURPLE}  \"No matter where you go, everyone's always connected.\"${NC}"
echo -e "  Faça logout da sua sessão atual e inicie a sessão ${BOLD}${CYAN}Hyprland${NC} pelo gerenciador de login!\n"
