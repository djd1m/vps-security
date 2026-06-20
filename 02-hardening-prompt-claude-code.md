# Задание для Claude Code: базовый security hardening Ubuntu VPS

Ты — агент безопасности. Выполни аудит и хардинг этого Ubuntu VPS сервера.
Действуй последовательно: сначала аудит, потом исправления.

---

## Фаза 1: Аудит текущего состояния

Проверь и выведи отчёт по каждому пункту:

### 1.1 SSH-конфигурация
- Прочитай `/etc/ssh/sshd_config` и все файлы в `/etc/ssh/sshd_config.d/`
- Проверь значения: `PermitRootLogin`, `PasswordAuthentication`, `PubkeyAuthentication`
- Покажи содержимое `/root/.ssh/authorized_keys`
- **КРИТИЧНО:** если `authorized_keys` пуст или отсутствует — НЕ отключай парольный вход, предупреди пользователя

### 1.2 Брутфорс-атаки
- Проверь размер `/var/log/btmp` и количество неудачных попыток входа (`lastb | wc -l`)
- Покажи последние успешные входы: `grep 'Accepted' /var/log/auth.log | tail -20`
- Покажи текущие SSH-сессии: `who`

### 1.3 Фаервол
- Проверь статус UFW: `ufw status`
- Проверь iptables: `iptables -L INPUT -n`
- Проверь установлен ли `iptables-persistent`

### 1.4 Защита от брутфорса
- Проверь установлен ли fail2ban: `dpkg -l fail2ban`
- Если установлен — покажи статус: `fail2ban-client status sshd`

### 1.5 Открытые порты
- Покажи все слушающие порты: `ss -tlnp`
- Отдельно выдели порты на `0.0.0.0` и `*` — они доступны из интернета
- Покажи установленные соединения наружу: `ss -tnp | grep ESTAB | grep -v 127.0.0.1`

### 1.6 Подозрительные сервисы
- Проверь наличие: nezha, xray, argo, tunnel.service, майнеров
- `systemctl list-unit-files --state=enabled --type=service` — покажи нестандартные
- `crontab -l` — проверь на подозрительные записи
- Проверь группу sudo: `grep '^sudo:' /etc/group`

### 1.7 Выведи сводную таблицу
Формат: параметр | текущее значение | статус (OK / РИСК / КРИТИЧНО)

---

## Фаза 2: Исправления

Применяй только если аудит выявил проблемы. Перед каждым действием сообщи что делаешь.

### 2.1 SSH (только если есть ключ в authorized_keys!)
```bash
sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sshd -t && systemctl restart sshd
```

### 2.2 fail2ban (если не установлен)
```bash
apt install fail2ban -y
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
systemctl enable --now fail2ban
```

### 2.3 iptables-persistent (если не установлен)
```bash
DEBIAN_FRONTEND=noninteractive apt install iptables-persistent -y
```

### 2.4 Сохранить правила фаервола
```bash
netfilter-persistent save
```

---

## Фаза 3: Верификация

После исправлений выполни повторный аудит (Фаза 1) и покажи сводную таблицу ДО и ПОСЛЕ.

Убедись:
- `PermitRootLogin` = `prohibit-password`
- `PasswordAuthentication` = `no`
- fail2ban активен и защищает sshd
- Нет подозрительных сервисов, cron-записей, пользователей в sudo

---

## Ограничения

- НЕ отключай парольный вход если нет ключа в authorized_keys
- НЕ включай UFW без подтверждения пользователя (можно заблокировать всё)
- НЕ удаляй сервисы без подтверждения — только сообщи о подозрительных
- НЕ закрывай текущую SSH-сессию
