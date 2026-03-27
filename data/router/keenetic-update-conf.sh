#!/usr/bin/env bash
# Быстрая замена AWG-конфига на роутере Keenetic
#
# Использование:
#   bash keenetic-update-conf.sh /path/to/new-awg-router.conf
#   bash <(curl -sL URL/keenetic-update-conf.sh) /path/to/conf
#
# Конфиг создаётся в Telegram-боте: Пользователи → AWG Роутер

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[router]${NC} $1"; }
warn() { echo -e "${YELLOW}[router]${NC} $1"; }
err()  { echo -e "${RED}[router]${NC} $1" >&2; }

CONF_FILE="${1:-}"
ROUTER_IP="${ROUTER_IP:-192.168.1.1}"
ROUTER_PASS="${ROUTER_PASS:-keenetic}"

# Запросить конфиг если не указан
if [[ -z "$CONF_FILE" || ! -f "$CONF_FILE" ]]; then
    echo ""
    log "Замена AWG-конфига на роутере Keenetic"
    echo ""
    read -rp "  Путь к новому .conf файлу: " CONF_FILE
    if [[ -z "$CONF_FILE" || ! -f "$CONF_FILE" ]]; then
        err "Файл не найден: $CONF_FILE"
        exit 1
    fi
fi

read -rp "  IP роутера [192.168.1.1]: " input_ip
ROUTER_IP="${input_ip:-$ROUTER_IP}"

read -rsp "  Пароль Entware SSH [keenetic]: " input_pass
echo ""
ROUTER_PASS="${input_pass:-$ROUTER_PASS}"

SSH_ARGS=(-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -p 222 "root@$ROUTER_IP")

# Проверка подключения
log "Подключаюсь к $ROUTER_IP..."
if ! sshpass -p "$ROUTER_PASS" ssh "${SSH_ARGS[@]}" "echo ok" 2>/dev/null | grep -q "ok"; then
    err "Не удалось подключиться"
    exit 1
fi

# Бэкап старого конфига
log "Бэкап текущего конфига..."
sshpass -p "$ROUTER_PASS" ssh "${SSH_ARGS[@]}" "cp /opt/etc/amnezia/amneziawg/awg0-opkgtun0.conf /opt/etc/amnezia/amneziawg/awg0-opkgtun0.conf.bak 2>/dev/null" || true

# Загрузка нового
log "Загружаю новый конфиг..."
sshpass -p "$ROUTER_PASS" scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -P 222 "$CONF_FILE" "root@$ROUTER_IP:/opt/etc/amnezia/amneziawg/awg0-opkgtun0.conf"
sshpass -p "$ROUTER_PASS" ssh "${SSH_ARGS[@]}" "chmod 600 /opt/etc/amnezia/amneziawg/awg0-opkgtun0.conf"

# Перезапуск AWG
log "Перезапускаю AWG..."
sshpass -p "$ROUTER_PASS" ssh "${SSH_ARGS[@]}" "/opt/etc/init.d/S52awg-opkgtun0 restart 2>&1" || true
sleep 3

# Проверка
STATUS=$(sshpass -p "$ROUTER_PASS" ssh "${SSH_ARGS[@]}" "awg show 2>&1")
if echo "$STATUS" | grep -q "latest handshake"; then
    log "Готово! AWG подключён к новому серверу"
    echo "$STATUS" | grep -E "endpoint|handshake|transfer"
else
    warn "AWG перезапущен, но handshake ещё не прошёл"
    warn "Подождите 30 секунд и проверьте"
    echo ""
    warn "Если не заработает — откат:"
    warn "  ssh -p 222 root@$ROUTER_IP"
    warn "  cp /opt/etc/amnezia/amneziawg/awg0-opkgtun0.conf.bak /opt/etc/amnezia/amneziawg/awg0-opkgtun0.conf"
    warn "  /opt/etc/init.d/S52awg-opkgtun0 restart"
fi
