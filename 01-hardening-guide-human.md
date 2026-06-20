# Базовый хардинг Ubuntu VPS

> Контекст: в июне 2026 был полностью скомпрометирован сервер через SSH-брутфорс (`PermitRootLogin yes` + пароль). Ниже — набор команд, закрывающий этот вектор.

> **Важно:** перед отключением парольного входа SSH-ключ уже должен быть на сервере в `/root/.ssh/authorized_keys`.

---

## 1. SSH — отключить вход по паролю

```bash
# root может зайти ТОЛЬКО по ключу, пароль не принимается
sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# Отключает парольный вход для ВСЕХ пользователей
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Проверить конфиг и перезапустить SSH
# (на некоторых Ubuntu сервис называется ssh, на других — sshd)
sshd -t && systemctl restart ssh 2>/dev/null || systemctl restart sshd
```

---

## 2. fail2ban — автобан после неудачных попыток входа

```bash
apt install fail2ban -y

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 1h        # По умолчанию банить на 1 час
findtime = 10m       # Считать попытки в окне 10 минут
maxretry = 5         # Банить после 5 неудачных попыток
banaction = iptables-multiport

[sshd]
enabled  = true      # Включить защиту SSH
port     = ssh
logpath  = /var/log/auth.log
maxretry = 3         # Для SSH строже: банить после 3 попыток
bantime  = 24h       # Для SSH строже: банить на 24 часа
EOF

systemctl enable --now fail2ban
```

---

## 3. Фаервол — закрыть лишние порты

```bash
apt install iptables-persistent -y

# -A INPUT = правило на входящий трафик
# -p tcp   = протокол TCP
# --dport  = порт назначения
# -j DROP  = молча отбрасывать пакет (отправитель не узнает что порт есть)
iptables -A INPUT -p tcp --dport 3389 -j DROP   # xrdp (удалённый рабочий стол)
iptables -A INPUT -p tcp --dport 2096 -j DROP    # x-ui (панель управления прокси)

# Сохранить правила (переживут ребут)
netfilter-persistent save
```

---

## 4. Проверка после настройки

```bash
# SSH — должно показать: PermitRootLogin prohibit-password и PasswordAuthentication no
grep -E '(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config | grep -v '^#'

# fail2ban — должен быть active, покажет забаненные IP
fail2ban-client status sshd

# iptables — должны быть видны DROP-правила
iptables -L INPUT -n --line-numbers
```

---

## Приложение: добавление SSH-ключа с Windows

```powershell
# 1. Сгенерировать ключ (если нет)
ssh-keygen -t ed25519

# 2. Скопировать публичный ключ на сервер
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@<IP> "cat >> /root/.ssh/authorized_keys"

# 3. Исправить права на приватный ключ (Windows требует это)
icacls "$env:USERPROFILE\.ssh\id_ed25519" /inheritance:r /grant:r "$($env:USERNAME):(R)"

# 4. Проверить вход по ключу (не должен спрашивать пароль)
ssh -i "$env:USERPROFILE\.ssh\id_ed25519" root@<IP>
```
