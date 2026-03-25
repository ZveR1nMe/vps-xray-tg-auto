#!/usr/bin/env bash
set -euo pipefail

# VPS Setup — чистый xray + Telegram бот
# Установка: bash <(curl -sL https://raw.githubusercontent.com/OWNER/REPO/main/setup.sh)

INSTALL_DIR="/opt/vps-setup"
XRAY_DIR="/opt/xray"
REPO_URL="https://github.com/OWNER/REPO"  # TODO: заменить на реальный

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1" >&2; }

# --- Проверки ---

if [[ $EUID -ne 0 ]]; then err "Запустите от root"; exit 1; fi

if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
    err "Поддерживается только Ubuntu"
    exit 1
fi

SERVER_IP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)
if [[ -z "$SERVER_IP" ]]; then err "Не удалось определить IP"; exit 1; fi

# --- Telegram credentials ---

if [[ -z "${BOT_TOKEN:-}" || -z "${CHAT_ID:-}" ]]; then
    echo ""
    log "Настройка Telegram-бота"
    echo "  1. Создайте бота: @BotFather → /newbot → скопируйте токен"
    echo "  2. Узнайте Chat ID: напишите @userinfobot"
    echo ""
    read -rp "Bot Token: " BOT_TOKEN
    read -rp "Chat ID: " CHAT_ID
    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        err "Bot Token и Chat ID обязательны"
        exit 1
    fi
fi

# --- Проверка Telegram ---

log "Проверка Telegram..."
RESPONSE=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" -d text="🟢 Установка VPS начата ($SERVER_IP)")
if ! echo "$RESPONSE" | jq -e '.ok' > /dev/null 2>&1; then
    err "Telegram: неверный токен или chat_id"
    exit 1
fi
log "Telegram OK"

# --- Обновление системы ---

log "Обновление системы..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y curl wget jq bc python3 python3-pip python3-venv ufw fail2ban unzip

# Автообновления безопасности
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# --- SSH hardening ---

SSH_PORT="${SSH_PORT:-22}"

sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

if [[ -s ~/.ssh/authorized_keys ]]; then
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    log "Парольная аутентификация отключена"
else
    warn "authorized_keys пуст — пароль оставлен"
fi

systemctl restart ssh || systemctl restart sshd

# --- UFW ---

log "Настройка UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp comment 'SSH'
ufw allow 443/tcp comment 'VLESS Reality'
echo "y" | ufw enable

# --- Fail2ban ---

log "Настройка fail2ban..."
cat > /etc/fail2ban/jail.local << JAIL
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
JAIL
systemctl restart fail2ban

# --- BBR ---

log "Оптимизация сети..."
cat > /etc/sysctl.d/99-vps.conf << 'SYSCTL'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.ip_forward = 1
SYSCTL
sysctl --system > /dev/null

# --- Установка xray ---

log "Установка xray..."
mkdir -p "$XRAY_DIR"

# Скачиваем последнюю версию
XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name')
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"
log "xray $XRAY_VERSION"

wget -qO /tmp/xray.zip "$XRAY_URL"
unzip -o /tmp/xray.zip -d "$XRAY_DIR" > /dev/null
chmod +x "$XRAY_DIR/xray"
rm -f /tmp/xray.zip

# Скачиваем geo-файлы для России
log "Скачиваю geo-файлы..."
wget -qO "$XRAY_DIR/geoip.dat" "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat"
wget -qO "$XRAY_DIR/geosite.dat" "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat"

# --- SNI Selection ---

log "Выбор лучшего SNI..."
SNI_CANDIDATES=("www.google.com" "www.microsoft.com" "www.yahoo.com" "www.apple.com")
BEST_SNI="www.google.com"
BEST_TIME=999

for sni in "${SNI_CANDIDATES[@]}"; do
    total=0; success=0
    for i in 1 2 3; do
        t=$(curl --connect-timeout 3 -s -o /dev/null -w "%{time_connect}" "https://$sni" 2>/dev/null || echo "999")
        total=$(echo "$total + $t" | bc)
        [[ "$t" != "999" ]] && ((success++)) || true
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

log "Генерация ключей..."
KEYS_OUTPUT=$("$XRAY_DIR/xray" x25519)
PRIVATE_KEY=$(echo "$KEYS_OUTPUT" | grep "PrivateKey" | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS_OUTPUT" | grep "Password" | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 4)

log "Public Key: $PUBLIC_KEY"

# --- SOCKS5 прокси для Telegram ---

SOCKS_PORT=$(shuf -i 10000-60000 -n 1)
SOCKS_USER=$(openssl rand -hex 5)
SOCKS_PASS=$(openssl rand -hex 5)
log "SOCKS5 прокси: порт $SOCKS_PORT"
ufw allow "$SOCKS_PORT"/tcp comment 'SOCKS5 Telegram'

# --- xray config ---

log "Создание конфига xray..."
mkdir -p "$INSTALL_DIR"/{data,logs}

cat > "$INSTALL_DIR/xray-config.json" << XRAYCONF
{
  "log": {
    "loglevel": "warning",
    "access": "/opt/vps-setup/logs/xray-access.log",
    "error": "/opt/vps-setup/logs/xray-error.log"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${BEST_SNI}:443",
          "xver": 0,
          "serverNames": ["${BEST_SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "socks-proxy",
      "port": ${SOCKS_PORT},
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {"user": "${SOCKS_USER}", "pass": "${SOCKS_PASS}"}
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
XRAYCONF

# --- systemd для xray ---

cat > /etc/systemd/system/xray.service << 'SVC'
[Unit]
Description=Xray VLESS Reality
After=network.target

[Service]
Type=simple
ExecStart=/opt/xray/xray run -c /opt/vps-setup/xray-config.json
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable xray
systemctl start xray
sleep 2

if ! pgrep -f "xray" > /dev/null; then
    err "xray не запустился"
    journalctl -u xray --no-pager -n 10
    exit 1
fi
log "xray запущен на порту 443"

# --- Python Bot ---

log "Установка бота..."

# Скачиваем бот из репозитория (или копируем если запущен локально)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/bot" ]]; then
    cp -r "$SCRIPT_DIR/bot" "$INSTALL_DIR/"
else
    # Скачиваем из GitHub
    wget -qO /tmp/repo.tar.gz "${REPO_URL}/archive/refs/heads/main.tar.gz"
    tar -xzf /tmp/repo.tar.gz -C /tmp
    cp -r /tmp/*/bot "$INSTALL_DIR/"
    rm -rf /tmp/repo.tar.gz /tmp/*-main
fi

python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip -q
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/bot/requirements.txt" -q

# --- .env ---

cat > "$INSTALL_DIR/.env" << ENVFILE
BOT_TOKEN=$BOT_TOKEN
CHAT_ID=$CHAT_ID
SERVER_IP=$SERVER_IP
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
BEST_SNI=$BEST_SNI
SOCKS_PORT=$SOCKS_PORT
SOCKS_USER=$SOCKS_USER
SOCKS_PASS=$SOCKS_PASS
ENVFILE
chmod 600 "$INSTALL_DIR/.env"

# --- systemd для бота ---

cat > /etc/systemd/system/vps-bot.service << SVC
[Unit]
Description=VPS Telegram Bot
After=network.target xray.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python -m bot.bot
EnvironmentFile=$INSTALL_DIR/.env
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable vps-bot
systemctl start vps-bot

# --- Logrotate ---

cat > /etc/logrotate.d/vps-setup << 'LR'
/opt/vps-setup/logs/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
LR

# --- Готово ---

log "=========================================="
log "  Установка завершена!"
log "=========================================="
log ""
log "  IP: $SERVER_IP"
log "  Xray: VLESS + Reality на порту 443"
log "  SNI: $BEST_SNI"
log "  Public Key: $PUBLIC_KEY"
log ""
log "  Бот: напишите /start в Telegram"
log "=========================================="

curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d parse_mode="HTML" \
    -d text="✅ <b>VPS настроен!</b>

🖥 IP: <code>$SERVER_IP</code>
🔑 SSH: <code>ssh root@$SERVER_IP</code>
🌐 SNI: $BEST_SNI
🔐 Public Key: <code>$PUBLIC_KEY</code>

Напишите /start боту для управления." > /dev/null
