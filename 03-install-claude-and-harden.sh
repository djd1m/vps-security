#!/usr/bin/env bash
# =============================================================================
# Скрипт: установка Claude Code + запуск security hardening через него
#
# Использование:
#   chmod +x 03-install-claude-and-harden.sh
#   ./03-install-claude-and-harden.sh
#
# Что делает:
#   1. Устанавливает Node.js 20 (если нет)
#   2. Устанавливает Claude Code CLI (npm)
#   3. Копирует промпт-инструкцию для Claude Code
#   4. Запускает Claude Code с этой инструкцией
#
# Требования:
#   - Ubuntu 22.04 / 24.04
#   - Root-доступ
#   - SSH-ключ уже должен быть в /root/.ssh/authorized_keys
#   - API-ключ Anthropic (будет запрошен)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== VPS Security Hardening через Claude Code ===${NC}"
echo ""

# --- Проверка root ---
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Этот скрипт нужно запускать от root${NC}"
  exit 1
fi

# --- Проверка SSH-ключа ---
if [[ ! -f /root/.ssh/authorized_keys ]] || [[ ! -s /root/.ssh/authorized_keys ]]; then
  echo -e "${RED}СТОП: в /root/.ssh/authorized_keys нет SSH-ключей.${NC}"
  echo "Сначала добавь свой публичный ключ, иначе потеряешь доступ к серверу."
  echo ""
  echo "На Windows (PowerShell):"
  echo '  type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@<IP> "cat >> /root/.ssh/authorized_keys"'
  exit 1
fi

echo -e "${GREEN}[OK]${NC} SSH-ключ найден в authorized_keys"

# --- Установка Node.js ---
if command -v node &>/dev/null && [[ $(node -v | cut -d. -f1 | tr -d 'v') -ge 18 ]]; then
  echo -e "${GREEN}[OK]${NC} Node.js $(node -v) уже установлен"
else
  echo -e "${YELLOW}[..] Устанавливаю Node.js 20...${NC}"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
  echo -e "${GREEN}[OK]${NC} Node.js $(node -v) установлен"
fi

# --- Установка Claude Code ---
if command -v claude &>/dev/null; then
  echo -e "${GREEN}[OK]${NC} Claude Code уже установлен"
else
  echo -e "${YELLOW}[..] Устанавливаю Claude Code...${NC}"
  npm install -g @anthropic-ai/claude-code
  echo -e "${GREEN}[OK]${NC} Claude Code установлен"
fi

# --- API-ключ ---
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo ""
  echo -e "${YELLOW}Введи Anthropic API ключ (начинается с sk-ant-):${NC}"
  read -r -s ANTHROPIC_API_KEY
  export ANTHROPIC_API_KEY
  echo ""
fi

# --- Создание промпт-файла ---
PROMPT_FILE="/tmp/claude-hardening-prompt.md"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "$SCRIPT_DIR/02-hardening-prompt-claude-code.md" ]]; then
  cp "$SCRIPT_DIR/02-hardening-prompt-claude-code.md" "$PROMPT_FILE"
  echo -e "${GREEN}[OK]${NC} Промпт-инструкция скопирована"
else
  echo -e "${RED}Файл 02-hardening-prompt-claude-code.md не найден рядом со скриптом${NC}"
  exit 1
fi

# --- Запуск Claude Code ---
echo ""
echo -e "${GREEN}=== Запускаю Claude Code для хардинга ===${NC}"
echo "Claude Code выполнит аудит и применит исправления."
echo "Ты сможешь взаимодействовать с ним в интерактивном режиме."
echo ""

claude --print "$(cat "$PROMPT_FILE")"

echo ""
echo -e "${GREEN}=== Готово ===${NC}"
echo "Рекомендуется открыть новую SSH-сессию и проверить что вход по ключу работает."
