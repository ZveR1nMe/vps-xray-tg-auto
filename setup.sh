#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/vps-setup"
LOG_DIR="/var/log/vps-setup"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1" >&2; }

# --- Проверки ---

if [[ $EUID -ne 0 ]]; then
    err "Запустите от root: sudo bash setup.sh"
    exit 1
fi

# --- Telegram credentials ---

echo ""
log "Настройка Telegram-бота"
echo "  1. Создайте бота: напишите @BotFather в Telegram → /newbot"
echo "  2. Узнайте свой Chat ID: напишите @userinfobot или @getmyid_bot"
echo ""

read -rp "Bot Token: " BOT_TOKEN
read -rp "Chat ID: " CHAT_ID

if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
    err "Bot Token и Chat ID обязательны"
    exit 1
fi

if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
    err "Поддерживается только Ubuntu"
    exit 1
fi

SERVER_IP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)
if [[ -z "$SERVER_IP" ]]; then
    err "Не удалось определить IP сервера"
    exit 1
fi

log "IP сервера: $SERVER_IP"

# --- Деинсталляция ---

if [[ "${1:-}" == "--uninstall" ]]; then
    log "Деинсталляция..."
    systemctl stop vps-bot.service 2>/dev/null || true
    systemctl disable vps-bot.service 2>/dev/null || true
    rm -f /etc/systemd/system/vps-bot.service
    systemctl daemon-reload

    crontab -l 2>/dev/null | grep -v "vps-setup" | crontab - || true

    read -rp "Удалить $INSTALL_DIR? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        log "Удалён $INSTALL_DIR"
    fi

    rm -rf "$LOG_DIR"

    warn "Оставлены (удалите вручную при необходимости):"
    warn "  - 3X-UI (x-ui uninstall)"
    warn "  - UFW правила (ufw status)"
    warn "  - SSH-конфиг (/etc/ssh/sshd_config)"
    warn "  - sysctl настройки (/etc/sysctl.d/99-vps-setup.conf)"
    warn "  - fail2ban (/etc/fail2ban/jail.local)"
    log "Деинсталляция завершена"
    exit 0
fi

# --- Обновление системы ---

log "Обновление системы..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y curl wget jq python3 python3-pip python3-venv ufw fail2ban unzip

apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# --- SSH-порт ---

read -rp "SSH-порт (текущий: 22, Enter для 22): " SSH_PORT
SSH_PORT="${SSH_PORT:-22}"

if [[ "$SSH_PORT" != "22" ]]; then
    log "Смена SSH-порта на $SSH_PORT..."
    sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
fi

sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

if [[ -s ~/.ssh/authorized_keys ]]; then
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    log "Парольная аутентификация отключена (ключи найдены)"
else
    warn "authorized_keys пуст — парольная аутентификация оставлена"
fi

systemctl restart sshd

# --- Файрвол ---

log "Настройка UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp comment 'SSH'
ufw allow 443/tcp comment 'VLESS Reality'
echo "y" | ufw enable

# --- Fail2ban ---

log "Настройка fail2ban..."
cat > /etc/fail2ban/jail.local << 'JAIL'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
JAIL

sed -i "s/^port = ssh/port = $SSH_PORT/" /etc/fail2ban/jail.local
systemctl restart fail2ban

# --- Сетевая оптимизация ---

log "Оптимизация сети (BBR)..."
cat > /etc/sysctl.d/99-vps-setup.conf << 'SYSCTL'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192
net.ipv4.ip_forward = 1
SYSCTL
sysctl --system > /dev/null

# --- Проверка Telegram ---

log "Проверка Telegram-бота..."
RESPONSE=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="🟢 VPS Setup запущен на $SERVER_IP")

if ! echo "$RESPONSE" | jq -e '.ok' > /dev/null 2>&1; then
    err "Не удалось отправить сообщение в Telegram. Проверьте BOT_TOKEN и CHAT_ID"
    err "Ответ: $RESPONSE"
    exit 1
fi
log "Telegram OK"

# --- 3X-UI ---

log "Установка 3X-UI..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<< "y"

XUI_USER="admin_$(openssl rand -hex 4)"
XUI_PASS="$(openssl rand -base64 16)"
XUI_PATH="/panel-$(openssl rand -hex 8)"

x-ui setting -username "$XUI_USER" -password "$XUI_PASS"
x-ui setting -webBasePath "$XUI_PATH"
x-ui setting -listen 127.0.0.1
x-ui setting -port 2053

systemctl restart x-ui
sleep 3

log "3X-UI установлен: user=$XUI_USER path=$XUI_PATH"

# --- SNI Selection ---

log "Выбор лучшего SNI..."
SNI_CANDIDATES=("www.microsoft.com" "www.google.com" "www.yahoo.com" "www.apple.com" "www.amazon.com")
BEST_SNI="www.microsoft.com"
BEST_TIME=999

for sni in "${SNI_CANDIDATES[@]}"; do
    total=0
    success=0
    for i in 1 2 3; do
        t=$(curl --connect-timeout 3 -s -o /dev/null -w "%{time_connect}" "https://$sni" 2>/dev/null || echo "999")
        total=$(echo "$total + $t" | bc)
        if [[ "$t" != "999" ]]; then
            ((success++)) || true
        fi
    done
    if [[ $success -gt 0 ]]; then
        avg=$(echo "scale=4; $total / 3" | bc)
        log "  $sni: ${avg}s"
        if (( $(echo "$avg < $BEST_TIME" | bc -l) )); then
            BEST_TIME="$avg"
            BEST_SNI="$sni"
        fi
    fi
done

log "Лучший SNI: $BEST_SNI"

# --- Reality Keys ---

KEYS_OUTPUT=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS_OUTPUT" | grep "Private" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS_OUTPUT" | grep "Public" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

log "Reality keys сгенерированы"

# --- Конфиг inbound через API ---

sleep 5

COOKIE_FILE=$(mktemp)
curl -s -c "$COOKIE_FILE" "http://127.0.0.1:2053${XUI_PATH}/login" \
    -d "username=$XUI_USER&password=$XUI_PASS" > /dev/null

INBOUND_JSON=$(cat << ENDJSON
{
  "up": 0, "down": 0, "total": 0, "remark": "vless-reality",
  "enable": true, "expiryTime": 0,
  "listen": "", "port": 443, "protocol": "vless",
  "settings": "{\"clients\":[],\"decryption\":\"none\",\"fallbacks\":[]}",
  "streamSettings": "{\"network\":\"tcp\",\"security\":\"reality\",\"realitySettings\":{\"show\":false,\"dest\":\"${BEST_SNI}:443\",\"xver\":0,\"serverNames\":[\"${BEST_SNI}\"],\"privateKey\":\"${PRIVATE_KEY}\",\"shortIds\":[\"${SHORT_ID}\"]},\"tcpSettings\":{\"header\":{\"type\":\"none\"}}}",
  "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\"]}"
}
ENDJSON
)

INBOUND_RESP=$(curl -s -b "$COOKIE_FILE" \
    "http://127.0.0.1:2053${XUI_PATH}/xui/API/inbounds/add" \
    -H "Content-Type: application/json" \
    -d "$INBOUND_JSON")

rm -f "$COOKIE_FILE"

if ! echo "$INBOUND_RESP" | jq -e '.success' > /dev/null 2>&1; then
    err "Не удалось создать inbound в 3X-UI"
    err "Ответ: $INBOUND_RESP"
    exit 1
fi

log "VLESS Reality inbound создан на порту 443"

# --- Python Bot ---

log "Развёртывание Telegram-бота..."
mkdir -p "$INSTALL_DIR"/{data/backups,logs}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/bot" ]]; then
    cp -r "$SCRIPT_DIR/bot" "$INSTALL_DIR/"
else
    err "Директория bot/ не найдена рядом со скриптом"
    exit 1
fi

python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/bot/requirements.txt"

cat > "$INSTALL_DIR/.env" << ENVFILE
BOT_TOKEN=$BOT_TOKEN
CHAT_ID=$CHAT_ID
XUI_USER=$XUI_USER
XUI_PASS=$XUI_PASS
XUI_PATH=$XUI_PATH
SERVER_IP=$SERVER_IP
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
BEST_SNI=$BEST_SNI
ENVFILE
chmod 600 "$INSTALL_DIR/.env"

# --- Systemd ---

cat > /etc/systemd/system/vps-bot.service << SERVICE
[Unit]
Description=VPS Telegram Bot
After=network.target x-ui.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python -m bot.bot
EnvironmentFile=$INSTALL_DIR/.env
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable vps-bot.service
systemctl start vps-bot.service

# --- Logrotate ---

cat > /etc/logrotate.d/vps-setup << 'LOGROTATE'
/opt/vps-setup/logs/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
LOGROTATE

# --- Итоговое сообщение ---

log "=========================================="
log "  Установка завершена!"
log "=========================================="
log ""
log "  IP: $SERVER_IP"
log "  SSH порт: $SSH_PORT"
log "  3X-UI: http://127.0.0.1:2053$XUI_PATH"
log "  Логин: $XUI_USER"
log "  Пароль: $XUI_PASS"
log ""
log "  SSH-туннель к панели:"
log "  ssh -L 2053:127.0.0.1:2053 -p $SSH_PORT root@$SERVER_IP"
log ""
log "  Reality SNI: $BEST_SNI"
log "  Public Key: $PUBLIC_KEY"
log ""
log "  Бот: @vps_dm_bot"
log "=========================================="

curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d parse_mode="HTML" \
    -d text="✅ <b>VPS настроен!</b>

🖥 IP: <code>$SERVER_IP</code>
🔑 SSH: <code>ssh -p $SSH_PORT root@$SERVER_IP</code>
🌐 Панель: <code>ssh -L 2053:127.0.0.1:2053 -p $SSH_PORT root@$SERVER_IP</code>

SNI: $BEST_SNI
Public Key: <code>$PUBLIC_KEY</code>" > /dev/null
