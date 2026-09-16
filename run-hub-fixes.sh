#!/usr/bin/env bash
set -uo pipefail

PROMPT_FILE="/home/val47/projetos/hyprland-setup/prompt-hub-fixes-sidebar-nosudo.md"
LOG_FILE="/home/val47/projetos/hyprland-setup/hub-fixes-run-$(date +%F-%H%M).log"
CLAUDE_BIN="/home/val47/.local/bin/claude"

cd "$HOME" || exit 1

{
  echo "=== Iniciando execução agendada em $(date) ==="
  cat "$PROMPT_FILE" | "$CLAUDE_BIN" -p \
    --permission-mode acceptEdits \
    --permission-prompts none \
    --output-format text
  echo "=== Finalizado em $(date) (exit code $?) ==="
} > "$LOG_FILE" 2>&1
