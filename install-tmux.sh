#!/usr/bin/env bash
# =============================================================================
# Скрипт: установка и настройка tmux для VPS
#
# Использование:
#   chmod +x install-tmux.sh
#   ./install-tmux.sh
#
# Что делает:
#   1. Устанавливает tmux (если нет)
#   2. Создаёт ~/.tmux.conf с удобной конфигурацией
#   3. Опционально добавляет автостарт tmux при SSH-входе
#   4. Создаёт и подключается к сессии "main"
#
# Требования:
#   - Ubuntu 22.04 / 24.04
# =============================================================================

set -uo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
info() { echo -e "  ${YELLOW}[..]${NC} $1"; }
err()  { echo -e "  ${RED}[X]${NC}  $1"; }

APT_CMD="apt-get"
if [[ $EUID -ne 0 ]]; then
  APT_CMD="sudo apt-get"
fi

TMUX_CONF="$HOME/.tmux.conf"
BASHRC="$HOME/.bashrc"

echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}  Установка и настройка tmux                      ${NC}"
echo -e "${CYAN}=================================================${NC}"
echo ""

# =========================================================================
# Шаг 1: Установка tmux
# =========================================================================

echo -e "${CYAN}--- Шаг 1: Установка tmux ---${NC}"

if command -v tmux &>/dev/null; then
  ok "tmux уже установлен: $(tmux -V)"
else
  info "Устанавливаю tmux..."
  $APT_CMD update -qq 2>/dev/null
  $APT_CMD install -y -qq tmux
  ok "tmux установлен: $(tmux -V)"
fi

# =========================================================================
# Шаг 2: Конфигурация ~/.tmux.conf
# =========================================================================

echo ""
echo -e "${CYAN}--- Шаг 2: Конфигурация ---${NC}"

if [[ -f "$TMUX_CONF" ]]; then
  BACKUP="${TMUX_CONF}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$TMUX_CONF" "$BACKUP"
  ok "Бэкап старого конфига: $BACKUP"
fi

cat > "$TMUX_CONF" << 'TMUXCONF'
# --- Основное ---
set -g mouse on
set -sg escape-time 10
set -g history-limit 100000

# --- Префикс: Ctrl+A вместо Ctrl+B ---
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# --- Навигация в стиле vi ---
setw -g mode-keys vi

# --- Разделение панелей: | и - (в текущей директории) ---
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
unbind '"'
unbind %

# --- Переключение панелей: Alt+стрелки ---
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D

# --- Ресайз панелей: prefix + H/J/K/L ---
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# --- Нумерация окон/панелей с 1 ---
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on

# --- Статус-бар ---
set -g status-interval 5
set -g status-left-length 40
set -g status-right-length 80
set -g status-left "#[bold]#S#[default] "
set -g status-right "%Y-%m-%d %H:%M | #H"

# --- Перечитать конфиг: prefix + r ---
bind r source-file ~/.tmux.conf \; display-message "tmux config reloaded"
TMUXCONF

ok "Конфиг записан: $TMUX_CONF"

# =========================================================================
# Шаг 3: Автостарт tmux при SSH-входе (опционально)
# =========================================================================

echo ""
echo -e "${CYAN}--- Шаг 3: Автостарт tmux при SSH-входе ---${NC}"

AUTOSTART_MARKER="# tmux-autostart"

if grep -q "$AUTOSTART_MARKER" "$BASHRC" 2>/dev/null; then
  ok "Автостарт уже настроен в $BASHRC"
else
  echo ""
  echo -e "${YELLOW}Добавить автоподключение к tmux при SSH-входе?${NC}"
  echo "  При каждом SSH-входе будет автоматически подключаться к сессии 'main'"
  echo "  (или создавать её, если не существует)."
  echo ""
  read -r -p "  Добавить? [y/N]: " REPLY

  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    cat >> "$BASHRC" << 'BASHRC_BLOCK'

# tmux-autostart
if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then
  tmux attach -t main 2>/dev/null || tmux new -s main
fi
BASHRC_BLOCK
    ok "Автостарт добавлен в $BASHRC"
  else
    ok "Автостарт пропущен"
  fi
fi

# =========================================================================
# Шаг 4: Создание сессии
# =========================================================================

echo ""
echo -e "${CYAN}--- Шаг 4: Сессия tmux ---${NC}"

if tmux has-session -t main 2>/dev/null; then
  ok "Сессия 'main' уже существует"
else
  tmux new-session -d -s main
  ok "Сессия 'main' создана"
fi

tmux source-file "$TMUX_CONF" 2>/dev/null || true
ok "Конфиг применён к сессии"

# =========================================================================
# Итог
# =========================================================================

echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}  tmux установлен и настроен                      ${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo "  Версия:     $(tmux -V)"
echo "  Конфиг:     $TMUX_CONF"
echo "  Сессия:     main"
echo ""
echo "Подключиться к сессии:"
echo "  tmux attach -t main"
echo ""
echo "Шпаргалка:"
echo "  Ctrl+A |       — разделить вертикально"
echo "  Ctrl+A -       — разделить горизонтально"
echo "  Alt+стрелки    — переключение между панелями"
echo "  Ctrl+A d       — отключиться (сессия продолжит работать)"
echo "  Ctrl+A r       — перечитать конфиг"
echo "  tmux ls        — список сессий"
