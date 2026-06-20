#!/usr/bin/env bash
# =============================================================================
# Скрипт: базовый security hardening Ubuntu VPS (standalone, без Claude Code)
#
# Использование:
#   chmod +x 04-harden-standalone.sh
#   ./04-harden-standalone.sh
#
# Что делает:
#   1. Аудит текущего состояния безопасности
#   2. Установка и настройка fail2ban
#   3. Отключение парольного входа SSH (если есть ключ)
#   4. Установка iptables-persistent
#   5. Итоговый отчёт
#
# Требования:
#   - Ubuntu 22.04 / 24.04
#   - Root-доступ
#   - SSH-ключ уже должен быть в /root/.ssh/authorized_keys
# =============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

LOGFILE="/var/log/vps-hardening-$(date +%Y%m%d-%H%M%S).log"

log() {
  echo "$1" | tee -a "$LOGFILE"
}

header() {
  echo "" | tee -a "$LOGFILE"
  echo -e "${CYAN}=== $1 ===${NC}" | tee -a "$LOGFILE"
}

ok()   { echo -e "  ${GREEN}[OK]${NC} $1" | tee -a "$LOGFILE"; }
warn() { echo -e "  ${YELLOW}[!]${NC}  $1" | tee -a "$LOGFILE"; }
fail() { echo -e "  ${RED}[X]${NC}  $1" | tee -a "$LOGFILE"; }

# --- Проверка root ---
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Этот скрипт нужно запускать от root${NC}"
  exit 1
fi

echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}  VPS Security Hardening (standalone)  ${NC}"
echo -e "${GREEN}=======================================${NC}"
echo ""
log "Лог: $LOGFILE"
log "Дата: $(date)"
log "Хост: $(hostname)"

# =========================================================================
# ФАЗА 1: АУДИТ
# =========================================================================

header "ФАЗА 1: АУДИТ ТЕКУЩЕГО СОСТОЯНИЯ"

# --- 1.1 SSH ---
header "1.1 SSH-конфигурация"

PERMIT_ROOT=$(grep -E '^PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[[ -z "$PERMIT_ROOT" ]] && PERMIT_ROOT="не задан"
PASS_AUTH=$(grep -E '^PasswordAuthentication' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[[ -z "$PASS_AUTH" ]] && PASS_AUTH="не задан (по умолчанию yes)"

if [[ "$PERMIT_ROOT" == "yes" ]] || [[ "$PERMIT_ROOT" == "не задан" ]]; then
  fail "PermitRootLogin = $PERMIT_ROOT (root по паролю разрешён)"
else
  ok "PermitRootLogin = $PERMIT_ROOT"
fi

if [[ "$PASS_AUTH" == *"yes"* ]] || [[ "$PASS_AUTH" == *"не задан"* ]]; then
  fail "PasswordAuthentication = $PASS_AUTH (парольный вход разрешён)"
else
  ok "PasswordAuthentication = $PASS_AUTH"
fi

HAS_KEY=false
if [[ -f /root/.ssh/authorized_keys ]] && [[ -s /root/.ssh/authorized_keys ]]; then
  KEY_COUNT=$(grep -c '' /root/.ssh/authorized_keys 2>/dev/null || echo 0)
  ok "authorized_keys: $KEY_COUNT ключ(ей)"
  HAS_KEY=true
else
  fail "authorized_keys пуст или отсутствует"
fi

# --- 1.2 Брутфорс ---
header "1.2 Брутфорс-атаки"

if [[ -f /var/log/btmp ]]; then
  BTMP_SIZE=$(ls -lh /var/log/btmp | awk '{print $5}')
  BTMP_COUNT=$(lastb 2>/dev/null | wc -l)
  if [[ $BTMP_COUNT -gt 1000 ]]; then
    fail "btmp: $BTMP_SIZE, $BTMP_COUNT попыток брутфорса"
  else
    ok "btmp: $BTMP_SIZE, $BTMP_COUNT попыток"
  fi
else
  ok "btmp отсутствует"
fi

# --- 1.3 fail2ban ---
header "1.3 fail2ban"

if dpkg -l fail2ban &>/dev/null; then
  if systemctl is-active fail2ban &>/dev/null; then
    ok "fail2ban установлен и активен"
    BANNED=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
    ok "Забанено IP: ${BANNED:-0}"
  else
    warn "fail2ban установлен, но не запущен"
  fi
else
  fail "fail2ban НЕ установлен"
fi

# --- 1.4 Фаервол ---
header "1.4 Фаервол"

UFW_STATUS=$(ufw status 2>/dev/null | head -1 || echo "не установлен")
if echo "$UFW_STATUS" | grep -q "inactive"; then
  warn "UFW: $UFW_STATUS"
elif echo "$UFW_STATUS" | grep -q "active"; then
  ok "UFW: $UFW_STATUS"
else
  warn "UFW: $UFW_STATUS"
fi

INPUT_POLICY=$(iptables -L INPUT -n 2>/dev/null | head -1 | grep -oP '\(policy \K[A-Z]+' || echo "UNKNOWN")
INPUT_RULES=$(iptables -L INPUT -n 2>/dev/null | tail -n +3 | wc -l)
if [[ "$INPUT_POLICY" == "ACCEPT" ]] && [[ $INPUT_RULES -eq 0 ]]; then
  fail "iptables INPUT: policy ACCEPT, правил нет — всё пропускает"
else
  ok "iptables INPUT: policy $INPUT_POLICY, правил: $INPUT_RULES"
fi

if dpkg -l iptables-persistent &>/dev/null; then
  ok "iptables-persistent установлен"
else
  warn "iptables-persistent НЕ установлен (правила не переживут ребут)"
fi

# --- 1.5 Открытые порты ---
header "1.5 Порты, открытые в интернет"

OPEN_PORTS=$(ss -tlnp 2>/dev/null | grep -E '0\.0\.0\.0|:::|\*:' | awk '{print $4}' | sed 's/.*://' | sort -un || true)
for port in $OPEN_PORTS; do
  PROC=$(ss -tlnp 2>/dev/null | grep ":${port} " | head -1 | grep -oP 'users:\(\("\K[^"]+' || echo "?")
  warn "Порт $port открыт ($PROC)"
done

# --- 1.6 Подозрительные сервисы ---
header "1.6 Подозрительные сервисы"

SUSPICIOUS=0
for svc in nezha xray tunnel argo; do
  if systemctl list-unit-files 2>/dev/null | grep -qi "$svc"; then
    fail "Найден подозрительный сервис: $svc"
    SUSPICIOUS=$((SUSPICIOUS + 1))
  fi
done

CRON_LINES=$(crontab -l 2>/dev/null | grep -cv '^#\|^$' || echo 0)
CRON_SUSPECT=$(crontab -l 2>/dev/null | grep -icE '(miner|watchdog|nezha|rpow|\.sh)' || echo 0)
if [[ $CRON_SUSPECT -gt 0 ]]; then
  fail "Подозрительные cron-записи: $CRON_SUSPECT"
else
  ok "Cron: $CRON_LINES записей, подозрительных нет"
fi

SUDO_MEMBERS=$(grep '^sudo:' /etc/group 2>/dev/null | cut -d: -f4 || echo "")
if [[ -z "$SUDO_MEMBERS" ]]; then
  ok "Группа sudo пуста (только root)"
else
  warn "В группе sudo: $SUDO_MEMBERS"
fi

if [[ $SUSPICIOUS -eq 0 ]]; then
  ok "Подозрительных сервисов не найдено"
fi

# =========================================================================
# ФАЗА 2: ИСПРАВЛЕНИЯ
# =========================================================================

header "ФАЗА 2: ИСПРАВЛЕНИЯ"

# --- 2.1 fail2ban ---
if ! dpkg -l fail2ban &>/dev/null; then
  log "Устанавливаю fail2ban..."
  apt-get install -y fail2ban >>"$LOGFILE" 2>&1

  cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled  = true
port     = ssh
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 24h
EOF

  systemctl enable --now fail2ban >>"$LOGFILE" 2>&1
  ok "fail2ban установлен и запущен"
else
  ok "fail2ban уже установлен, пропускаю"
fi

# --- 2.2 SSH hardening ---
if [[ "$HAS_KEY" == true ]]; then
  CHANGED=false

  if [[ "$PERMIT_ROOT" == "yes" ]]; then
    sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    ok "PermitRootLogin → prohibit-password"
    CHANGED=true
  fi

  CURRENT_PASS_AUTH=$(grep -E '^#?PasswordAuthentication' /etc/ssh/sshd_config 2>/dev/null | head -1 || echo "")
  if echo "$CURRENT_PASS_AUTH" | grep -q '^#'; then
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    ok "PasswordAuthentication → no"
    CHANGED=true
  elif echo "$CURRENT_PASS_AUTH" | grep -q 'yes'; then
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    ok "PasswordAuthentication → no"
    CHANGED=true
  fi

  if [[ "$CHANGED" == true ]]; then
    if sshd -t 2>>"$LOGFILE"; then
      systemctl restart sshd
      ok "SSH перезапущен с новыми настройками"
    else
      fail "Ошибка в конфиге sshd! Откатываю..."
      cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config 2>/dev/null || true
    fi
  else
    ok "SSH уже настроен правильно"
  fi
else
  fail "ПРОПУСКАЮ SSH hardening: нет ключей в authorized_keys!"
  fail "Добавь ключ и запусти скрипт повторно."
fi

# --- 2.3 iptables-persistent ---
if ! dpkg -l iptables-persistent &>/dev/null; then
  log "Устанавливаю iptables-persistent..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >>"$LOGFILE" 2>&1
  ok "iptables-persistent установлен"
fi

netfilter-persistent save >>"$LOGFILE" 2>&1
ok "Правила iptables сохранены"

# =========================================================================
# ФАЗА 3: ИТОГОВЫЙ ОТЧЁТ
# =========================================================================

header "ФАЗА 3: ИТОГОВЫЙ ОТЧЁТ"

echo "" | tee -a "$LOGFILE"

FINAL_PERMIT=$(grep -E '^PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[[ -z "$FINAL_PERMIT" ]] && FINAL_PERMIT="?"
FINAL_PASS=$(grep -E '^PasswordAuthentication' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[[ -z "$FINAL_PASS" ]] && FINAL_PASS="?"
FINAL_F2B=$(systemctl is-active fail2ban 2>/dev/null || echo "inactive")
FINAL_IPTABLES=$(iptables -L INPUT -n 2>/dev/null | tail -n +3 | wc -l)

printf "  %-30s %-20s %-10s\n" "Параметр" "Значение" "Статус" | tee -a "$LOGFILE"
printf "  %-30s %-20s %-10s\n" "------------------------------" "--------------------" "----------" | tee -a "$LOGFILE"
printf "  %-30s %-20s %-10s\n" "PermitRootLogin" "$FINAL_PERMIT" "$( [[ "$FINAL_PERMIT" != "yes" ]] && echo 'OK' || echo 'РИСК')" | tee -a "$LOGFILE"
printf "  %-30s %-20s %-10s\n" "PasswordAuthentication" "$FINAL_PASS" "$( [[ "$FINAL_PASS" == "no" ]] && echo 'OK' || echo 'РИСК')" | tee -a "$LOGFILE"
printf "  %-30s %-20s %-10s\n" "fail2ban" "$FINAL_F2B" "$( [[ "$FINAL_F2B" == "active" ]] && echo 'OK' || echo 'РИСК')" | tee -a "$LOGFILE"
printf "  %-30s %-20s %-10s\n" "iptables правил" "$FINAL_IPTABLES" "$( [[ $FINAL_IPTABLES -gt 0 ]] && echo 'OK' || echo 'ВНИМАНИЕ')" | tee -a "$LOGFILE"
printf "  %-30s %-20s %-10s\n" "iptables-persistent" "$(dpkg -l iptables-persistent &>/dev/null && echo 'да' || echo 'нет')" "OK" | tee -a "$LOGFILE"

echo "" | tee -a "$LOGFILE"
echo -e "${GREEN}Хардинг завершён. Лог: $LOGFILE${NC}" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo -e "${YELLOW}ВАЖНО: открой НОВУЮ SSH-сессию и проверь что вход по ключу работает.${NC}" | tee -a "$LOGFILE"
echo -e "${YELLOW}Не закрывай текущую сессию до проверки!${NC}" | tee -a "$LOGFILE"
