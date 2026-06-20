#!/usr/bin/env bash
# =============================================================================
# Скрипт: установка Chromium (headless) + chrome-devtools-mcp (standalone)
#
# Использование:
#   chmod +x install-chromium-devtools.sh
#   ./install-chromium-devtools.sh
#
# Что делает:
#   1. Проверяет наличие Node.js/npm/npx
#   2. Скачивает Chromium через puppeteer (Chrome for Testing)
#   3. Доустанавливает недостающие системные библиотеки
#   4. Проверяет headless-запуск Chromium
#   5. Устанавливает chrome-devtools-mcp глобально
#
# Результат:
#   Chromium + chrome-devtools-mcp готовы к использованию любым MCP-клиентом
#   или вручную через npx chrome-devtools-mcp
#
# Требования:
#   - Ubuntu 22.04 / 24.04
#   - Node.js >= 18, npm, npx
# =============================================================================

set -euo pipefail

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

echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}  Установка Chromium + chrome-devtools-mcp        ${NC}"
echo -e "${CYAN}  (standalone, без Claude Code)                   ${NC}"
echo -e "${CYAN}=================================================${NC}"
echo ""

# =========================================================================
# Шаг 1: Проверка Node.js / npm / npx
# =========================================================================

echo -e "${CYAN}--- Шаг 1: Проверка Node.js ---${NC}"

MISSING=""
for cmd in node npm npx; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING="$MISSING $cmd"
  fi
done

if [[ -n "$MISSING" ]]; then
  err "Не найдены:$MISSING"
  echo ""
  echo "Установи Node.js 20:"
  echo "  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -"
  echo "  sudo apt-get install -y nodejs"
  exit 1
fi

NODE_MAJOR=$(node -v | cut -d. -f1 | tr -d 'v')
if [[ $NODE_MAJOR -lt 18 ]]; then
  err "Node.js $(node -v) слишком старый, нужен >= 18"
  exit 1
fi

ok "Node.js $(node -v), npm $(npm -v)"

# =========================================================================
# Шаг 2: Скачивание Chromium через puppeteer
# =========================================================================

echo ""
echo -e "${CYAN}--- Шаг 2: Скачивание Chromium ---${NC}"

CHROME="$(find "$HOME/.cache/puppeteer/chrome" -name chrome -type f -path '*chrome-linux64*' 2>/dev/null | sort -V | tail -1 || true)"

if [[ -n "$CHROME" ]] && [[ -x "$CHROME" ]]; then
  ok "Chromium уже скачан: $CHROME"
else
  info "Скачиваю Chromium (Chrome for Testing) через puppeteer..."
  npx -y puppeteer browsers install chrome

  CHROME="$(find "$HOME/.cache/puppeteer/chrome" -name chrome -type f -path '*chrome-linux64*' | sort -V | tail -1)"
  if [[ -z "$CHROME" ]]; then
    err "Не удалось найти бинарь Chromium после установки"
    exit 1
  fi
  ok "Chromium скачан: $CHROME"
fi

# =========================================================================
# Шаг 3: Системные библиотеки
# =========================================================================

echo ""
echo -e "${CYAN}--- Шаг 3: Проверка системных библиотек ---${NC}"

MISSING_LIBS=$(ldd "$CHROME" 2>/dev/null | grep "not found" || true)

if [[ -z "$MISSING_LIBS" ]]; then
  ok "Все библиотеки на месте"
else
  info "Не хватает библиотек:"
  echo "$MISSING_LIBS"
  echo ""
  info "Устанавливаю недостающие пакеты..."

  # На Ubuntu 24.04 некоторые пакеты переименованы с суффиксом t64
  # Пробуем t64-версию, при неудаче — версию без t64
  PACKAGES=(
    "libasound2t64|libasound2"
    "libgbm1"
    "libnss3"
    "libnspr4"
    "libatk1.0-0t64|libatk1.0-0"
    "libatk-bridge2.0-0t64|libatk-bridge2.0-0"
    "libcups2t64|libcups2"
    "libdrm2"
    "libxkbcommon0"
    "libxcomposite1"
    "libxdamage1"
    "libxfixes3"
    "libxrandr2"
    "libpango-1.0-0"
    "libcairo2"
    "libatspi2.0-0t64|libatspi2.0-0"
    "fonts-liberation"
  )

  $APT_CMD update -qq 2>/dev/null

  for pkg_entry in "${PACKAGES[@]}"; do
    IFS='|' read -ra VARIANTS <<< "$pkg_entry"
    INSTALLED=false
    for variant in "${VARIANTS[@]}"; do
      if dpkg -l "$variant" &>/dev/null; then
        INSTALLED=true
        break
      fi
      if DEBIAN_FRONTEND=noninteractive $APT_CMD install -y -qq "$variant" 2>/dev/null; then
        INSTALLED=true
        break
      fi
    done
    if [[ "$INSTALLED" == false ]]; then
      err "Не удалось установить: $pkg_entry"
    fi
  done

  # Повторная проверка
  MISSING_LIBS=$(ldd "$CHROME" 2>/dev/null | grep "not found" || true)
  if [[ -n "$MISSING_LIBS" ]]; then
    err "Всё ещё не хватает библиотек:"
    echo "$MISSING_LIBS"
    exit 1
  fi
  ok "Все библиотеки установлены"
fi

# =========================================================================
# Шаг 4: Проверка запуска Chromium
# =========================================================================

echo ""
echo -e "${CYAN}--- Шаг 4: Проверка запуска Chromium ---${NC}"

SANDBOX_FLAG=""
if [[ $EUID -eq 0 ]]; then
  SANDBOX_FLAG="--no-sandbox"
fi

CHROME_VERSION=$("$CHROME" --headless=new $SANDBOX_FLAG --disable-gpu --version 2>/dev/null || true)

if [[ -z "$CHROME_VERSION" ]]; then
  err "Chromium не запускается"
  info "Попытка диагностики:"
  "$CHROME" --headless=new $SANDBOX_FLAG --disable-gpu --dump-dom about:blank 2>&1 || true
  exit 1
fi

ok "$CHROME_VERSION"

# Проверяем рендеринг
DUMP=$("$CHROME" --headless=new $SANDBOX_FLAG --disable-gpu --dump-dom about:blank 2>/dev/null || true)
if echo "$DUMP" | grep -q "<html"; then
  ok "Headless-рендеринг работает"
else
  err "Headless-рендеринг не работает"
  exit 1
fi

# =========================================================================
# Шаг 5: Установка chrome-devtools-mcp
# =========================================================================

echo ""
echo -e "${CYAN}--- Шаг 5: Установка chrome-devtools-mcp ---${NC}"

if npm list -g chrome-devtools-mcp &>/dev/null; then
  ok "chrome-devtools-mcp уже установлен глобально"
else
  info "Устанавливаю chrome-devtools-mcp глобально..."
  npm install -g chrome-devtools-mcp
  ok "chrome-devtools-mcp установлен"
fi

# =========================================================================
# Итог
# =========================================================================

echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}  Установка завершена                             ${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo "  Chromium:           $CHROME"
echo "  Версия:             $CHROME_VERSION"
echo "  chrome-devtools-mcp: $(which chrome-devtools-mcp 2>/dev/null || echo 'npx chrome-devtools-mcp')"
echo ""
echo "Запуск MCP-сервера вручную:"
echo "  npx chrome-devtools-mcp --headless=true --isolated=true --executablePath=\"$CHROME\""
echo ""
echo "Для регистрации в Claude Code (если понадобится):"
echo "  claude mcp add chrome-devtools --scope user -- npx -y chrome-devtools-mcp@latest \\"
echo "    --headless=true --isolated=true --executablePath=\"$CHROME\""
