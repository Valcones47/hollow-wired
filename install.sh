#!/usr/bin/env bash
# ==============================================================================
# CachyOS & Arch Linux - Hyprland & Quickshell Rice Universal Installer
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.config/rice-backup-$(date +%Y%m%d_%H%M%S)"

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          HYPRLAND + QUICKSHELL UNIVERSAL RICE                ║"
echo "║             Instalador Automatizado & Otimizado              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 1. Checagem de Sistema Operacional
if [ ! -f /etc/arch-release ]; then
    echo -e "${RED}[!] Este instalador é destinado ao CachyOS ou distribuições baseadas em Arch Linux.${NC}"
    exit 1
fi

IS_CACHYOS=false
if grep -qi "cachyos" /etc/os-release 2>/dev/null; then
    IS_CACHYOS=true
    echo -e "${GREEN}[✓] CachyOS detectado! Utilizando repositórios de alta performance (x86-64-v3/v4).${NC}"
else
    echo -e "${BLUE}[*] Arch Linux detectado.${NC}"
fi

# 2. Detecção de Hardware
echo -e "\n${BOLD}[1/5] Detectando Hardware do Sistema...${NC}"
CPU_MODEL=$(lscpu | grep "Model name:" | sed 's/Model name:[ \t]*//' || echo "CPU Genérica")
echo -e "  • Processador: ${CYAN}$CPU_MODEL${NC}"

HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL=false

if lspci | grep -Ei "vga|3d" | grep -qi "nvidia"; then
    HAS_NVIDIA=true
    echo -e "  • Placa de Vídeo: ${GREEN}NVIDIA detectada${NC}"
fi
if lspci | grep -Ei "vga|3d" | grep -qi "amd|radeon|advanced micro"; then
    HAS_AMD=true
    echo -e "  • Placa de Vídeo: ${RED}AMD Radeon detectada${NC}"
fi
if lspci | grep -Ei "vga|3d" | grep -qi "intel"; then
    HAS_INTEL=true
    echo -e "  • Gráficos Integrados: ${BLUE}Intel detectada${NC}"
fi

CHASSIS="Desktop"
if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
    CHASSIS="Notebook"
fi
echo -e "  • Tipo de Dispositivo: ${YELLOW}$CHASSIS${NC}"

# Gerenciador de AUR (paru ou yay)
AUR_HELPER=""
if command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
elif command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
else
    echo -e "${YELLOW}[!] Nenhum AUR helper encontrado (paru/yay). Instalando paru...${NC}"
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
    (cd /tmp/paru-bin && makepkg -si --noconfirm)
    AUR_HELPER="paru"
fi
echo -e "  • AUR Helper: ${GREEN}$AUR_HELPER${NC}"

# 3. Instalação de Pacotes Core
echo -e "\n${BOLD}[2/5] Instalando Pacotes Essenciais e Interface...${NC}"

PACKAGES=(
    hyprland
    aquamarine
    quickshell
    kitty
    wallust
    fastfetch
    cava
    playerctl
    pipewire
    pipewire-pulse
    pipewire-alsa
    wireplumber
    wf-recorder
    grim
    slurp
    swappy
    cliphist
    wl-clipboard
    zenity
    ffmpeg
    libwebp
    jq
    socat
    bc
    lm_sensors
    rsync
    ttf-jetbrains-mono-nerd
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    zram-generator
)

# Pacotes adicionais de GPU
if [ "$HAS_NVIDIA" = true ]; then
    PACKAGES+=(nvidia-utils lib32-nvidia-utils)
fi

echo -e "${BLUE}[*] Instalando dependências via pacman e AUR...${NC}"
$AUR_HELPER -S --needed --noconfirm "${PACKAGES[@]}"

# 4. Pacote Opcional de Jogos
echo -e "\n${BOLD}[3/5] Suporte a Jogos & Gaming Meta...${NC}"
read -rp "Deseja instalar o pacote completo de jogos (Steam, Wine, Proton, GameMode)? [S/n]: " INSTALL_GAMES
INSTALL_GAMES=${INSTALL_GAMES:-S}

if [[ "$INSTALL_GAMES" =~ ^[Ss]$ ]]; then
    if [ "$IS_CACHYOS" = true ]; then
        echo -e "${GREEN}[*] Instalando cachyos-gaming-meta (otimizado com proton/wine cachyos)...${NC}"
        $AUR_HELPER -S --needed --noconfirm cachyos-gaming-meta
    else
        echo -e "${BLUE}[*] Instalando Steam, GameMode, MangoHud e Wine...${NC}"
        $AUR_HELPER -S --needed --noconfirm steam gamemode mangohud wine-staging winetricks
    fi
fi

# 5. Otimização de Memória (zRAM com ZSTD)
echo -e "\n${BOLD}[4/5] Otimizando Gerenciamento de Memória (zRAM ZSTD)...${NC}"
if [ ! -f /etc/systemd/zram-generator.conf ]; then
    echo -e "${BLUE}[*] Configurando zRAM com algoritmo ZSTD (3:1 de compactação de RAM)...${NC}"
    sudo bash -c 'cat << "ZRAM_EOF" > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
ZRAM_EOF'
    sudo systemctl daemon-reload
    sudo systemctl start /dev/zram0 2>/dev/null || true
    echo -e "${GREEN}[✓] zRAM ativado! Swap em RAM de alta velocidade pronto.${NC}"
else
    echo -e "${GREEN}[✓] zRAM já configurado no sistema.${NC}"
fi

# 6. Aplicação dos Dotfiles
echo -e "\n${BOLD}[5/5] Instalando Configurações do Rice...${NC}"

# Backup de segurança
mkdir -p "$BACKUP_DIR"
for dir in hypr quickshell kitty wallust; do
    if [ -d "$HOME/.config/$dir" ]; then
        echo -e "  • Criando backup de ~/.config/$dir -> $BACKUP_DIR/"
        cp -a "$HOME/.config/$dir" "$BACKUP_DIR/" 2>/dev/null || true
    fi
done

# Copiar novas configs
mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/Vídeos/Gravações" "$HOME/Imagens/Capturas de tela"
cp -a "$SCRIPT_DIR/dots/hypr" "$HOME/.config/"
cp -a "$SCRIPT_DIR/dots/quickshell" "$HOME/.config/"
cp -a "$SCRIPT_DIR/dots/kitty" "$HOME/.config/"
[ -d "$SCRIPT_DIR/dots/wallust" ] && cp -a "$SCRIPT_DIR/dots/wallust" "$HOME/.config/"
cp -a "$SCRIPT_DIR/dots/bin/"* "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/"*

# Garantir ~/.local/bin no PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    [ -f "$HOME/.zshrc" ] && echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
fi

# 7. Avatar Inicial se não existir
if [ ! -f "$HOME/.face.webp" ] && [ ! -f "$HOME/.face" ]; then
    echo -e "${BLUE}[*] Criando avatar padrão inicial...${NC}"
    # Se houver um ícone ou imagem nos dots, copia, senão cria placeholder
    touch "$HOME/.face"
fi

echo -e "\n${GREEN}${BOLD}══════════════════════════════════════════════════════════════"
echo "  ✓ INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
echo "══════════════════════════════════════════════════════════════${NC}"
echo -e "  • Hyprland configurado em: ${CYAN}~/.config/hypr/hyprland.lua${NC}"
echo -e "  • Quickshell configurado em: ${CYAN}~/.config/quickshell/${NC}"
echo -e "  • Utilitários e scripts em: ${CYAN}~/.local/bin/${NC}"
echo -e "  • Backup das configs antigas salvo em: ${YELLOW}$BACKUP_DIR${NC}\n"
echo -e "Para testar, faça logout e inicie a sessão ${BOLD}Hyprland${NC} pelo seu gerenciador de login!"
