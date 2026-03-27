#!/usr/bin/env bash
set -euo pipefail

# VPS Setup — чистый xray + Telegram бот
# Установка: bash <(curl -sL https://raw.githubusercontent.com/OWNER/REPO/main/setup.sh)

INSTALL_DIR="/opt/vps-setup"
XRAY_DIR="/opt/xray"
REPO_URL="https://github.com/ZveR1nMe/vps-xray-tg-auto"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# --- Режим установки ---

echo ""
log "Выберите режим установки:"
echo "  1) Только VLESS Reality"
echo "  2) Только AmneziaWG 2.0"
echo "  3) VLESS + AmneziaWG (оба)"
echo ""
read -rp "Режим [1/2/3]: " INSTALL_MODE_INPUT
case "${INSTALL_MODE_INPUT:-3}" in
    1) INSTALL_MODE="vless" ;;
    2) INSTALL_MODE="awg" ;;
    3) INSTALL_MODE="both" ;;
    *) warn "Неверный выбор, ставлю оба"; INSTALL_MODE="both" ;;
esac
log "Режим: $INSTALL_MODE"

# --- Минимальные зависимости для проверки ---

log "Установка базовых пакетов..."
export DEBIAN_FRONTEND=noninteractive
apt update -qq
apt install -y -qq jq bc > /dev/null

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
apt upgrade -y
apt install -y curl wget python3 python3-pip python3-venv ufw fail2ban unzip

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
if [[ "$INSTALL_MODE" == "vless" || "$INSTALL_MODE" == "both" ]]; then
    ufw allow 443/tcp comment 'VLESS Reality'
fi
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
# BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.ip_forward = 1

# TCP буферы — 64MB для стабильной скорости
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# Не сбрасывать скорость после простоя
net.ipv4.tcp_slow_start_after_idle = 0

# MTU probing — избегает фрагментации
net.ipv4.tcp_mtu_probing = 1

# Отзывчивость соединений
net.ipv4.tcp_notsent_lowat = 131072

# Очереди
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 8192
net.ipv4.tcp_max_syn_backlog = 8192

# Переиспользование соединений
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# Больше портов
net.ipv4.ip_local_port_range = 1024 65535

# Защита от SYN flood
net.ipv4.tcp_syncookies = 1
SYSCTL
sysctl --system > /dev/null

# --- Установка xray (только для vless/both) ---

if [[ "$INSTALL_MODE" == "vless" || "$INSTALL_MODE" == "both" ]]; then

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

# --- DoH DNS Selection ---

log "Выбор лучшего DoH DNS..."

declare -A DOH_REMOTE=(
    ["https://cloudflare-dns.com/dns-query"]="1.1.1.1"
    ["https://dns.google/dns-query"]="8.8.8.8"
    ["https://dns.quad9.net:443/dns-query"]="9.9.9.9"
)
declare -A DOH_DOMESTIC=(
    ["https://common.dot.dns.yandex.net/dns-query"]="77.88.8.8"
    ["https://dns.google/dns-query"]="8.8.8.8"
)

test_doh() {
    local url="$1"
    local total=0; local success=0
    for i in 1 2 3; do
        t=$(curl --connect-timeout 3 -s -o /dev/null -w "%{time_total}" "${url}?name=google.com&type=A" -H "accept: application/dns-json" 2>/dev/null || echo "999")
        total=$(echo "$total + $t" | bc)
        [[ "$t" != "999" ]] && ((success++)) || true
    done
    if [[ $success -gt 0 ]]; then
        echo "scale=4; $total / 3" | bc
    else
        echo "999"
    fi
}

BEST_REMOTE_DOH="https://dns.google/dns-query"
BEST_REMOTE_DOH_IP="8.8.8.8"
BEST_REMOTE_TIME=999
for url in "${!DOH_REMOTE[@]}"; do
    avg=$(test_doh "$url")
    log "  Remote $url: ${avg}s"
    if (( $(echo "$avg < $BEST_REMOTE_TIME" | bc -l) )); then
        BEST_REMOTE_TIME="$avg"
        BEST_REMOTE_DOH="$url"
        BEST_REMOTE_DOH_IP="${DOH_REMOTE[$url]}"
    fi
done
log "Лучший remote DoH: $BEST_REMOTE_DOH ($BEST_REMOTE_DOH_IP)"

BEST_DOMESTIC_DOH="https://common.dot.dns.yandex.net/dns-query"
BEST_DOMESTIC_DOH_IP="77.88.8.8"
BEST_DOMESTIC_TIME=999
for url in "${!DOH_DOMESTIC[@]}"; do
    avg=$(test_doh "$url")
    log "  Domestic $url: ${avg}s"
    if (( $(echo "$avg < $BEST_DOMESTIC_TIME" | bc -l) )); then
        BEST_DOMESTIC_TIME="$avg"
        BEST_DOMESTIC_DOH="$url"
        BEST_DOMESTIC_DOH_IP="${DOH_DOMESTIC[$url]}"
    fi
done
log "Лучший domestic DoH: $BEST_DOMESTIC_DOH ($BEST_DOMESTIC_DOH_IP)"

# --- SNI Selection (через лучший DoH) ---

log "Выбор лучшего SNI..."
SNI_CANDIDATES=("www.google.com" "www.microsoft.com" "www.yahoo.com" "www.apple.com")
BEST_SNI="www.google.com"
BEST_TIME=999

for sni in "${SNI_CANDIDATES[@]}"; do
    total=0; success=0
    for i in 1 2 3; do
        t=$(curl --connect-timeout 3 --doh-url "$BEST_REMOTE_DOH" -s -o /dev/null -w "%{time_connect}" "https://$sni" 2>/dev/null || echo "999")
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
PRIVATE_KEY=$(echo "$KEYS_OUTPUT" | grep -i "private" | awk '{print $NF}')
PUBLIC_KEY=$(echo "$KEYS_OUTPUT" | grep -i "public" | awk '{print $NF}')
SHORT_ID=$(openssl rand -hex 4)

log "Public Key: $PUBLIC_KEY"

# --- SOCKS5 прокси для Telegram ---

SOCKS_PORT=$(shuf -i 10000-60000 -n 1)
SOCKS_USER=$(openssl rand -hex 8)
SOCKS_PASS=$(openssl rand -hex 16)
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

fi  # end VLESS

# --- AmneziaWG 2.0 ---

if [[ "$INSTALL_MODE" == "awg" || "$INSTALL_MODE" == "both" ]]; then

log "Установка AmneziaWG 2.0..."

# PPA
add-apt-repository -y ppa:amnezia/ppa
apt update -qq
apt install -y amneziawg amneziawg-dkms amneziawg-tools

# Определение сетевого интерфейса
NET_IFACE=$(ip route show default | awk '{print $5}' | head -1)
if [[ -z "$NET_IFACE" ]]; then
    err "Не удалось определить сетевой интерфейс"
    exit 1
fi
log "Сетевой интерфейс: $NET_IFACE"

# Генерация ключей
AWG_SERVER_PRIVKEY=$(awg genkey)
AWG_SERVER_PUBKEY=$(echo "$AWG_SERVER_PRIVKEY" | awg pubkey)

# Рандомный UDP порт
AWG_PORT=$(shuf -i 10000-60000 -n 1)
log "AWG порт: $AWG_PORT"

# Параметры обфускации
AWG_JC=4
AWG_JMIN=40
AWG_JMAX=70
AWG_S1=52
AWG_S2=52
AWG_H1=1
AWG_H2=2
AWG_H3=3
AWG_H4=4

# Конфиг сервера
mkdir -p /etc/amneziawg
cat > /etc/amneziawg/awg0.conf << AWGCONF
[Interface]
PrivateKey = ${AWG_SERVER_PRIVKEY}
Address = 10.8.1.1/24
ListenPort = ${AWG_PORT}
PostUp = iptables -A FORWARD -i awg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${NET_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i awg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${NET_IFACE} -j MASQUERADE
Jc = ${AWG_JC}
Jmin = ${AWG_JMIN}
Jmax = ${AWG_JMAX}
S1 = ${AWG_S1}
S2 = ${AWG_S2}
H1 = ${AWG_H1}
H2 = ${AWG_H2}
H3 = ${AWG_H3}
H4 = ${AWG_H4}
AWGCONF
chmod 600 /etc/amneziawg/awg0.conf

# UFW
ufw allow ${AWG_PORT}/udp comment 'AmneziaWG'

# Systemd
cat > /etc/systemd/system/awg-quick@.service << 'SVC'
[Unit]
Description=AmneziaWG Tunnel %i
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/awg-quick up /etc/amneziawg/%i.conf
ExecStop=/usr/bin/awg-quick down /etc/amneziawg/%i.conf

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable awg-quick@awg0
systemctl start awg-quick@awg0
sleep 2

if ! awg show awg0 > /dev/null 2>&1; then
    err "AmneziaWG не запустился"
    journalctl -u awg-quick@awg0 --no-pager -n 10
    exit 1
fi
log "AmneziaWG запущен на порту $AWG_PORT (UDP)"

# --- Настройка роутера ---

echo ""
read -rp "Настроить роутер Keenetic автоматически? (y/n): " SETUP_ROUTER
if [[ "$(echo "$SETUP_ROUTER" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
    # Проверка sshpass
    if ! command -v sshpass &>/dev/null; then
        apt install -y sshpass
    fi

    # Скрипт keenetic.sh сам запросит все данные для подключения
    # (IP, пароль admin CLI, пароль Entware SSH)
    # и определит доступные способы подключения

    # Генерация клиентского конфига для роутера
    ROUTER_AWG_IP="10.8.1.2"
    ROUTER_PRIVKEY=$(awg genkey)
    ROUTER_PUBKEY=$(echo "$ROUTER_PRIVKEY" | awg pubkey)
    ROUTER_PSK=$(awg genpsk)

    # Добавить peer в серверный конфиг
    cat >> /etc/amneziawg/awg0.conf << PEER

[Peer]
# router
PublicKey = $ROUTER_PUBKEY
PresharedKey = $ROUTER_PSK
AllowedIPs = $ROUTER_AWG_IP/32
PEER

    systemctl restart awg-quick@awg0

    # Создать клиентский конфиг (OpkgTun — без Address/DNS)
    AWG_ROUTER_CONF="/tmp/awg-router.conf"
    cat > "$AWG_ROUTER_CONF" << RCONF
[Interface]
PrivateKey = $ROUTER_PRIVKEY
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

[Peer]
PublicKey = $AWG_SERVER_PUBKEY
PresharedKey = $ROUTER_PSK
Endpoint = $SERVER_IP:$AWG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
RCONF

    # Запуск скрипта настройки роутера
    ROUTER_SCRIPT="$SCRIPT_DIR/data/router/keenetic.sh"
    if [[ ! -f "$ROUTER_SCRIPT" ]]; then
        # Если запущен с сервера — скачать
        ROUTER_SCRIPT="/tmp/keenetic.sh"
        wget -qO "$ROUTER_SCRIPT" "${REPO_URL}/raw/main/data/router/keenetic.sh"
        chmod +x "$ROUTER_SCRIPT"
        # Скачать dns-lists
        mkdir -p /tmp/dns-lists
        for svc in youtube instagram facebook telegram whatsapp twitter discord reddit spotify; do
            wget -qO "/tmp/dns-lists/${svc}.lst" "${REPO_URL}/raw/main/data/router/dns-lists/${svc}.lst"
        done
    fi

    export AWG_CLIENT_IP="$ROUTER_AWG_IP" AWG_CLIENT_CONF="$AWG_ROUTER_CONF"
    bash "$ROUTER_SCRIPT" || warn "Настройка роутера не завершена, но сервер работает"

    rm -f "$AWG_ROUTER_CONF"
fi

fi  # end AWG

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
INSTALL_MODE=$INSTALL_MODE
ENVFILE

if [[ "$INSTALL_MODE" == "vless" || "$INSTALL_MODE" == "both" ]]; then
cat >> "$INSTALL_DIR/.env" << ENVFILE
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
BEST_SNI=$BEST_SNI
REMOTE_DOH=$BEST_REMOTE_DOH
REMOTE_DOH_IP=$BEST_REMOTE_DOH_IP
DOMESTIC_DOH=$BEST_DOMESTIC_DOH
DOMESTIC_DOH_IP=$BEST_DOMESTIC_DOH_IP
SOCKS_PORT=$SOCKS_PORT
SOCKS_USER=$SOCKS_USER
SOCKS_PASS=$SOCKS_PASS
ENVFILE
fi

if [[ "$INSTALL_MODE" == "awg" || "$INSTALL_MODE" == "both" ]]; then
cat >> "$INSTALL_DIR/.env" << ENVFILE
AWG_PORT=$AWG_PORT
AWG_SERVER_PUBKEY=$AWG_SERVER_PUBKEY
AWG_JC=$AWG_JC
AWG_JMIN=$AWG_JMIN
AWG_JMAX=$AWG_JMAX
AWG_S1=$AWG_S1
AWG_S2=$AWG_S2
AWG_H1=$AWG_H1
AWG_H2=$AWG_H2
AWG_H3=$AWG_H3
AWG_H4=$AWG_H4
AWG_CONFIG=/etc/amneziawg/awg0.conf
ENVFILE
fi

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
log "  Режим: $INSTALL_MODE"
if [[ "$INSTALL_MODE" == "vless" || "$INSTALL_MODE" == "both" ]]; then
    log "  Xray: VLESS + Reality на порту 443"
    log "  SNI: $BEST_SNI"
    log "  Public Key: $PUBLIC_KEY"
fi
if [[ "$INSTALL_MODE" == "awg" || "$INSTALL_MODE" == "both" ]]; then
    log "  AmneziaWG: порт $AWG_PORT (UDP)"
    log "  AWG Public Key: $AWG_SERVER_PUBKEY"
fi
log ""
log "  Бот: напишите /start в Telegram"
log "=========================================="

TG_MSG="✅ <b>VPS настроен!</b>

🖥 IP: <code>$SERVER_IP</code>
🔑 SSH: <code>ssh root@$SERVER_IP</code>
📋 Режим: $INSTALL_MODE"

if [[ "$INSTALL_MODE" == "vless" || "$INSTALL_MODE" == "both" ]]; then
    TG_MSG+="
🌐 SNI: $BEST_SNI
🔐 VLESS Key: <code>$PUBLIC_KEY</code>"
fi
if [[ "$INSTALL_MODE" == "awg" || "$INSTALL_MODE" == "both" ]]; then
    TG_MSG+="
🛡 AWG: порт $AWG_PORT
🔐 AWG Key: <code>$AWG_SERVER_PUBKEY</code>"
fi
TG_MSG+="

Напишите /start боту для управления."

curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d parse_mode="HTML" \
    -d text="$TG_MSG" > /dev/null
