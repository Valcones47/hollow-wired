#!/bin/bash
# blur-fullscreen-toggle.sh
# Desativa blur automaticamente quando a janela ativa está em tela cheia.
# Compatível com Hyprland em modo Lua (usa eval em vez de keyword).

# Detecta o socket do Hyprland
if [[ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]]; then
    HYPRLAND_INSTANCE_SIGNATURE=$(ls "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/" 2>/dev/null | head -1)
    export HYPRLAND_INSTANCE_SIGNATURE
fi
SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

[[ ! -S "$SOCKET" ]] && { echo "Socket não encontrado: $SOCKET" >&2; exit 1; }

BLUR_ON=""
STATE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/rice-blur-disabled"

set_blur() {
    [[ "$BLUR_ON" == "$1" ]] && return
    BLUR_ON="$1"
    hyprctl eval "hl.config({ decoration = { blur = { enabled = $1 } } })" &>/dev/null
}

check_fullscreen() {
    if [[ -f "$STATE" ]]; then
        set_blur false
        return
    fi
    local fs
    fs=$(hyprctl activewindow -j 2>/dev/null | jq -r '.fullscreen // 0' 2>/dev/null)
    if [[ "$fs" == "1" ]]; then
        set_blur false
    else
        set_blur true
    fi
}

check_fullscreen

socat -U - "UNIX-CONNECT:${SOCKET}" | while IFS= read -r ev; do
    case "$ev" in
        fullscreen*|workspace\>*|activewindow*)
            check_fullscreen
            ;;
    esac
done
