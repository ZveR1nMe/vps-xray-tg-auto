#!/usr/bin/env bash
set -euo pipefail

# Локальный скрипт деплоя — запускается на твоём компьютере.
# Спрашивает данные, копирует файлы на сервер, запускает setup.sh по SSH.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Проверка что bot/ и setup.sh рядом ---

if [[ ! -d "$SCRIPT_DIR/bot" || ! -f "$SCRIPT_DIR/setup.sh" ]]; then
    err "Не найдены bot/ и setup.sh. Запускайте из директории проекта."
    exit 1
fi

# --- Конфиг ---

CONFIG_FILE="$SCRIPT_DIR/.deploy.env"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    log "Загружен конфиг из .deploy.env"
    echo ""
    echo "======================================"
    echo "  Сервер:    ${SSH_USER:-root}@${SERVER_IP}:${CURRENT_SSH_PORT:-22}"
    echo "  SSH-порт:  ${NEW_SSH_PORT:-${CURRENT_SSH_PORT:-22}}"
    echo "  Бот:       ${BOT_TOKEN:0:10}..."
    echo "  Chat ID:   ${CHAT_ID}"
    echo "======================================"
    echo ""
    read -rp "Использовать эти данные? [Y/n] " use_saved
    if [[ ! "$use_saved" =~ ^[Nn]$ ]]; then
        SSH_USER="${SSH_USER:-root}"
        CURRENT_SSH_PORT="${CURRENT_SSH_PORT:-22}"
        NEW_SSH_PORT="${NEW_SSH_PORT:-$CURRENT_SSH_PORT}"
    else
        rm -f "$CONFIG_FILE"
        log "Вводим заново..."
    fi
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo ""
    echo "======================================"
    echo "  VPS Setup — Деплой"
    echo "======================================"
    echo ""

    read -rp "IP сервера: " SERVER_IP
    if [[ -z "$SERVER_IP" ]]; then
        err "IP обязателен"
        exit 1
    fi

    read -rp "SSH-порт сервера (22): " CURRENT_SSH_PORT
    CURRENT_SSH_PORT="${CURRENT_SSH_PORT:-22}"

    read -rp "SSH-пользователь (root): " SSH_USER
    SSH_USER="${SSH_USER:-root}"

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

    read -rp "Новый SSH-порт на сервере (Enter = оставить $CURRENT_SSH_PORT): " NEW_SSH_PORT
    NEW_SSH_PORT="${NEW_SSH_PORT:-$CURRENT_SSH_PORT}"

    # Сохраняем конфиг
    cat > "$CONFIG_FILE" << CONF
SERVER_IP="$SERVER_IP"
CURRENT_SSH_PORT="$CURRENT_SSH_PORT"
SSH_USER="$SSH_USER"
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
NEW_SSH_PORT="$NEW_SSH_PORT"
CONF
    chmod 600 "$CONFIG_FILE"
    log "Конфиг сохранён в .deploy.env"
fi

# --- Подтверждение ---

echo ""
echo "======================================"
echo "  Сервер:    ${SSH_USER}@${SERVER_IP}:${CURRENT_SSH_PORT}"
echo "  SSH-порт:  ${CURRENT_SSH_PORT} → ${NEW_SSH_PORT}"
echo "  Бот:       ${BOT_TOKEN:0:10}..."
echo "  Chat ID:   ${CHAT_ID}"
echo "======================================"
echo ""

read -rp "Всё верно? Начинаем установку? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Отменено"
    exit 0
fi

# --- SSH-опции ---

SSH_OPTS="-o StrictHostKeyChecking=accept-new -p $CURRENT_SSH_PORT"
SSH_CMD="ssh $SSH_OPTS ${SSH_USER}@${SERVER_IP}"
SCP_CMD="scp -o StrictHostKeyChecking=accept-new -P $CURRENT_SSH_PORT"

# --- Проверка подключения ---

log "Проверяю подключение к серверу..."
if ! $SSH_CMD "echo ok" > /dev/null 2>&1; then
    err "Не удалось подключиться к ${SSH_USER}@${SERVER_IP}:${CURRENT_SSH_PORT}"
    err "Убедитесь что SSH-ключ добавлен или используйте ssh-copy-id"
    exit 1
fi
log "Подключение OK"

# --- Копирование файлов ---

REMOTE_TMP="/tmp/vps-setup-$$"

log "Копирую файлы на сервер..."
$SSH_CMD "mkdir -p $REMOTE_TMP"
$SCP_CMD -r "$SCRIPT_DIR/bot" "${SSH_USER}@${SERVER_IP}:${REMOTE_TMP}/"
$SCP_CMD "$SCRIPT_DIR/setup.sh" "${SSH_USER}@${SERVER_IP}:${REMOTE_TMP}/"

# --- Запуск setup.sh на сервере ---

log "Запускаю установку на сервере..."
echo ""

$SSH_CMD "cd $REMOTE_TMP && BOT_TOKEN='$BOT_TOKEN' CHAT_ID='$CHAT_ID' SSH_PORT='$NEW_SSH_PORT' bash setup.sh"

# --- Очистка ---

$SSH_CMD "rm -rf $REMOTE_TMP" 2>/dev/null || true

echo ""
log "======================================"
log "  Готово!"
log "======================================"
log ""
log "  SSH-туннель к панели:"
log "  ssh -L 2053:127.0.0.1:2053 -p $NEW_SSH_PORT ${SSH_USER}@${SERVER_IP}"
log ""
log "  Откройте http://localhost:2053 в браузере"
log "  Напишите /start боту в Telegram"
log ""
