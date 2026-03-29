#!/usr/bin/env bash
# Автонастройка роутера Keenetic: VLESS (XKeen) + AmneziaWG
# Запускается локально на компьютере (macOS/Linux/WSL)
#
# Поддерживаемые протоколы:
#   - VLESS через XKeen (xray + tproxy)
#   - AmneziaWG нативный (ASC, KeeneticOS 4.2+)
#   - AmneziaWG через AWG-Manager (Entware, веб-панель)
#
# Использование:
#   bash keenetic.sh                          — интерактивная настройка
#   bash <(curl -sL URL/keenetic.sh)          — скачать и запустить

set -uo pipefail

# Определяем директорию скрипта (для dns-lists)
if [[ ! -f "${BASH_SOURCE[0]}" ]]; then
    # Запущен через curl/pipe — скачаем dns-lists во временную папку
    SCRIPT_DIR="/tmp/keenetic-setup"
    mkdir -p "$SCRIPT_DIR"
    DOWNLOADED_SCRIPT=true
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    DOWNLOADED_SCRIPT=false
fi
DNS_LISTS_DIR="$SCRIPT_DIR/dns-lists"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[router]${NC} $1"; }
warn() { echo -e "${YELLOW}[router]${NC} $1"; }
err()  { echo -e "${RED}[router]${NC} $1" >&2; }

# --- Параметры ---
ROUTER_IP="${ROUTER_IP:-}"
ROUTER_ADMIN_USER="${ROUTER_ADMIN_USER:-admin}"
ROUTER_ADMIN_PASS="${ROUTER_ADMIN_PASS:-}"
ROUTER_ENTWARE_PASS="${ROUTER_ENTWARE_PASS:-}"
# AWG конфиг (для нативного ASC — путь к .conf файлу)
AWG_CONF_FILE="${AWG_CONF_FILE:-}"

# Состояние подключения (определяется в check_connection)
HAS_ENTWARE_SSH=false
HAS_ADMIN_CLI=false

# SSH для Entware (порт 222, root)
ENTWARE_SSH_ARGS=()
ssh_exec() {
    SSHPASS="$ROUTER_ENTWARE_PASS" sshpass -e ssh "${ENTWARE_SSH_ARGS[@]}" "$1" 2>&1
}

# ndmc через Entware SSH (если доступен) или через telnet (если нет)
ndmc_exec() {
    local cmd="$1"
    cmd="${cmd//\\/\\\\}"
    cmd="${cmd//\"/\\\"}"
    cmd="${cmd//\$/\\\$}"
    cmd="${cmd//\`/\\\`}"
    if [[ "$HAS_ENTWARE_SSH" == true ]]; then
        SSHPASS="$ROUTER_ENTWARE_PASS" sshpass -e ssh "${ENTWARE_SSH_ARGS[@]}" "ndmc -c \"$cmd\"" 2>&1
    else
        _ndmc_via_telnet "$1"
    fi
}

# NDMS CLI через telnet (для роутеров без Entware)
_ndmc_via_telnet() {
    local cmd="$1"
    {
        sleep 1
        echo "$ROUTER_ADMIN_USER"
        sleep 1
        echo "$ROUTER_ADMIN_PASS"
        sleep 1
        echo "$cmd"
        sleep 2
        echo "exit"
    } | nc -w10 "$ROUTER_IP" 23 2>/dev/null | grep -v "^Login:\|^Password:\|^$" | sed 's/\[K//g; s/\r//g'
}

# --- Запрос данных подключения ---
ask_credentials() {
    echo ""
    log "Подключение к роутеру Keenetic"
    echo ""

    if [[ -z "$ROUTER_IP" ]]; then
        read -rp "  IP роутера [192.168.1.1]: " ROUTER_IP
        ROUTER_IP="${ROUTER_IP:-192.168.1.1}"
    fi

    # Проверить какие порты доступны
    log "Сканирую порты роутера..."
    local port_222_open=false
    local port_23_open=false

    if nc -z -w3 "$ROUTER_IP" 222 2>/dev/null; then
        port_222_open=true
        log "  Порт 222 (Entware SSH): открыт"
    else
        log "  Порт 222 (Entware SSH): закрыт"
    fi

    if nc -z -w3 "$ROUTER_IP" 23 2>/dev/null; then
        port_23_open=true
        log "  Порт 23 (Telnet CLI): открыт"
    else
        log "  Порт 23 (Telnet CLI): закрыт"
    fi

    if [[ "$port_222_open" == false && "$port_23_open" == false ]]; then
        err "Роутер $ROUTER_IP недоступен (ни SSH:222, ни Telnet:23)"
        err "Проверьте:"
        err "  - IP роутера ($ROUTER_IP)"
        err "  - Включён ли компонент SSH в настройках роутера"
        err "  - Включён ли Telnet (Управление → Настройки системы)"
        return 1
    fi

    # Запросить данные для Entware SSH (если порт открыт)
    if [[ "$port_222_open" == true ]]; then
        if [[ -z "$ROUTER_ENTWARE_PASS" ]]; then
            read -rsp "  Пароль Entware SSH (порт 222): " ROUTER_ENTWARE_PASS
            echo ""
            if [[ -z "$ROUTER_ENTWARE_PASS" ]]; then
                err "Пароль Entware SSH обязателен"
                return 1
            fi
        fi
    fi

    # Запросить данные для Admin CLI (всегда нужен для ndmc, если Entware нет)
    if [[ "$port_222_open" == false || -z "$ROUTER_ADMIN_PASS" ]]; then
        echo ""
        echo "  Данные администратора роутера (от веб-интерфейса):"
        read -rp "  Логин [admin]: " ROUTER_ADMIN_USER
        ROUTER_ADMIN_USER="${ROUTER_ADMIN_USER:-admin}"
        read -rsp "  Пароль: " ROUTER_ADMIN_PASS
        echo ""

        if [[ -z "$ROUTER_ADMIN_PASS" ]]; then
            err "Пароль администратора обязателен"
            return 1
        fi
    fi
}

# --- Проверка подключения ---
check_connection() {
    ask_credentials || return 1

    # Попробовать Entware SSH (порт 222)
    if nc -z -w3 "$ROUTER_IP" 222 2>/dev/null; then
        ENTWARE_SSH_ARGS=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p 222 "root@$ROUTER_IP")

        if ssh_exec "echo ok" 2>/dev/null | grep -q "ok"; then
            HAS_ENTWARE_SSH=true
            log "Entware SSH (порт 222): подключено"
        else
            warn "Порт 222 открыт, но авторизация не прошла"
        fi
    fi

    # Попробовать Admin CLI через telnet
    if nc -z -w3 "$ROUTER_IP" 23 2>/dev/null && [[ -n "$ROUTER_ADMIN_PASS" ]]; then
        local test_cli
        test_cli=$(_ndmc_via_telnet "show version")
        if echo "$test_cli" | grep -q "title:"; then
            HAS_ADMIN_CLI=true
            log "Admin CLI (Telnet 23): подключено"
        else
            warn "Telnet доступен, но авторизация не прошла. Проверьте логин/пароль администратора."
        fi
    fi

    # Нужен хотя бы один способ подключения
    if [[ "$HAS_ENTWARE_SSH" == false && "$HAS_ADMIN_CLI" == false ]]; then
        err "Не удалось авторизоваться ни через SSH:222, ни через Telnet:23"
        err "Проверьте пароли и попробуйте снова"
        return 1
    fi

    # Если нет Entware SSH, нужно будет установить Entware
    if [[ "$HAS_ENTWARE_SSH" == false ]]; then
        warn "Entware не установлен — будет установлен автоматически"
        warn "Для установки используется Admin CLI (Telnet)"
    fi

    log "Подключение OK"
}

# --- Определение модели и характеристик роутера ---
detect_router() {
    log "Определение модели роутера..."

    local info
    if [[ "$HAS_ENTWARE_SSH" == true ]]; then
        # Через Entware SSH — один вызов, полная информация
        info=$(ssh_exec "echo ARCH=\$(uname -m); echo SOC=\$(grep 'system type' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2); echo RAM=\$(grep MemTotal /proc/meminfo | awk '{print \$2}'); echo INTFREE=\$(df /tmp 2>/dev/null | tail -1 | awk '{print \$4}'); ndmc -c 'show version' 2>/dev/null | grep -E 'device:|hw_id:|title:|arch:'")

        ROUTER_ARCH=$(echo "$info" | grep "^ARCH=" | cut -d= -f2 | tr -d '[:space:]')
        ROUTER_SOC=$(echo "$info" | grep "^SOC=" | cut -d= -f2 | tr -d '[:space:]')
        ROUTER_RAM_KB=$(echo "$info" | grep "^RAM=" | cut -d= -f2 | tr -d '[:space:]')
        INTERNAL_FREE_KB=$(echo "$info" | grep "^INTFREE=" | cut -d= -f2 | tr -d '[:space:]')
    else
        # Через Admin CLI (telnet) — только ndmc доступен
        info=$(ndmc_exec "show version")
        ROUTER_ARCH=$(echo "$info" | grep "arch:" | awk '{print $2}' | tr -d '[:space:]')
        ROUTER_RAM_KB=0
        INTERNAL_FREE_KB=0
    fi

    ROUTER_MODEL=$(echo "$info" | grep "device:" | awk '{print $2}' | tr -d '[:space:]')
    ROUTER_HW_ID=$(echo "$info" | grep "hw_id:" | awk '{print $2}' | tr -d '[:space:]')
    ROUTER_FW=$(echo "$info" | grep "title:" | awk '{print $2}' | tr -d '[:space:]')

    # Безопасные значения по умолчанию
    ROUTER_RAM_KB="${ROUTER_RAM_KB:-0}"
    INTERNAL_FREE_KB="${INTERNAL_FREE_KB:-0}"
    local ROUTER_RAM_MB=$((ROUTER_RAM_KB / 1024))

    log "  Модель: $ROUTER_MODEL ($ROUTER_HW_ID)"
    log "  Прошивка: KeeneticOS $ROUTER_FW"
    log "  SoC: $ROUTER_SOC"
    log "  Архитектура: $ROUTER_ARCH"
    log "  RAM: ${ROUTER_RAM_MB} MB"

    # Определение суффикса пакетов
    # uname -m на Keenetic возвращает "mips" даже для mipsel (little-endian)
    # Entware всегда mipsel на MT7621/MT7628
    case "$ROUTER_ARCH" in
        mips|mipsel) AWG_PKG_SUFFIX="mipsel-3.4" ;;
        aarch64)     AWG_PKG_SUFFIX="aarch64-3.10" ;;
        *)
            err "Неподдерживаемая архитектура: $ROUTER_ARCH"
            return 1
            ;;
    esac
    # Определяем реальный endianness из Entware (только если Entware SSH доступен)
    if [[ "$HAS_ENTWARE_SSH" == true ]]; then
        local entware_arch
        entware_arch=$(ssh_exec "grep 'arch mipsel' /opt/etc/opkg.conf 2>/dev/null || grep 'arch aarch64' /opt/etc/opkg.conf 2>/dev/null" | head -1 | awk '{print $2}' || true)
        if [[ -n "$entware_arch" ]]; then
            AWG_PKG_SUFFIX="$entware_arch"
            log "  Entware архитектура: $entware_arch"
        fi
    fi
    log "  Пакеты: $AWG_PKG_SUFFIX"

    local INTERNAL_FREE_MB=$((INTERNAL_FREE_KB / 1024))
    log "  Внутренняя память (tmpfs): ${INTERNAL_FREE_MB} MB свободно"
}

# --- Проверка и подготовка хранилища ---
setup_storage() {
    log "Проверка хранилища для Entware..."

    # Если Entware SSH работает — Entware точно есть
    if [[ "$HAS_ENTWARE_SSH" == true ]]; then
        local opt_disk
        opt_disk=$(ssh_exec "df /opt 2>/dev/null | tail -1 | awk '{print \$1}'" || echo "unknown")
        local opt_free
        opt_free=$(ssh_exec "df -h /opt 2>/dev/null | tail -1 | awk '{print \$4}'" || echo "unknown")
        log "Entware уже установлен на $opt_disk (свободно: $opt_free)"
        return 0
    fi

    warn "Entware не установлен"

    # Проверить USB-накопитель
    local usb_device
    usb_device=$(ssh_exec "ls /dev/sd[a-z] 2>/dev/null | head -1" | tr -d '[:space:]')

    local usb_mounted
    usb_mounted=$(ssh_exec "mount | grep /tmp/mnt" | head -1)

    if [[ -n "$usb_device" || -n "$usb_mounted" ]]; then
        log "USB-накопитель обнаружен"

        if [[ -n "$usb_mounted" ]]; then
            local usb_fs
            usb_fs=$(echo "$usb_mounted" | awk '{print $5}')
            local usb_mount_point
            usb_mount_point=$(echo "$usb_mounted" | awk '{print $3}')
            local usb_size
            usb_size=$(ssh_exec "df -h $usb_mount_point 2>/dev/null | tail -1 | awk '{print \$2}'")
            log "  Смонтирован: $usb_mount_point ($usb_fs, $usb_size)"

            echo ""
            echo "  USB уже содержит данные. Варианты:"
            echo "   1) Использовать как есть (установить Entware на текущий раздел)"
            echo "   2) Отформатировать USB в ext4 (ВСЕ ДАННЫЕ БУДУТ УДАЛЕНЫ)"
            echo ""
            read -rp "  Выбор [1/2]: " STORAGE_CHOICE
        else
            # USB есть, но не смонтирован — нужно форматировать
            log "  USB обнаружен ($usb_device), но не смонтирован"
            STORAGE_CHOICE="2"
            echo ""
            read -rp "  Отформатировать USB в ext4? (y/n): " FORMAT_CONFIRM
            if [[ "$(echo "$FORMAT_CONFIRM" | tr '[:upper:]' '[:lower:]')" != "y" ]]; then
                STORAGE_CHOICE="3"
            fi
        fi
    else
        log "  USB-накопитель не найден"
        STORAGE_CHOICE="3"
    fi

    case "${STORAGE_CHOICE:-1}" in
        1)
            # Использовать существующий USB
            _install_entware_usb
            ;;
        2)
            # Форматировать USB
            _format_and_install_usb "$usb_device"
            ;;
        3)
            # Попробовать внутреннюю память
            _install_entware_internal
            ;;
    esac
}

_format_and_install_usb() {
    local device="${1:-}"
    if [[ -z "$device" ]]; then
        device=$(ssh_exec "ls /dev/sd[a-z] 2>/dev/null | head -1" | tr -d '[:space:]')
    fi

    if [[ -z "$device" ]]; then
        err "USB-устройство не найдено"
        return 1
    fi

    # Показать информацию об устройстве для подтверждения
    local dev_size
    dev_size=$(ssh_exec "cat /sys/block/$(basename $device)/size 2>/dev/null" | tr -d '[:space:]')
    local dev_size_mb=""
    if [[ -n "$dev_size" && "$dev_size" =~ ^[0-9]+$ ]]; then
        dev_size_mb=$(( dev_size * 512 / 1024 / 1024 ))
        log "  Устройство: $device (${dev_size_mb}MB)"
    else
        log "  Устройство: $device"
    fi

    # Проверить что это не системное устройство
    local dev_basename
    dev_basename=$(basename "$device")
    if [[ "$dev_basename" == "mtdblock"* || "$dev_basename" == "ubi"* ]]; then
        err "ОШИБКА: $device — системное устройство! Форматирование запрещено."
        return 1
    fi

    echo ""
    warn "  ВСЕ ДАННЫЕ НА $device БУДУТ УДАЛЕНЫ!"
    read -rp "  Введите YES для подтверждения: " FORMAT_CONFIRM
    if [[ "$FORMAT_CONFIRM" != "YES" ]]; then
        log "Форматирование отменено"
        return 1
    fi

    # Форматирование требует shell-доступ (Entware SSH)
    if [[ "$HAS_ENTWARE_SSH" == false ]]; then
        err "Форматирование USB невозможно без Entware SSH"
        err "Отформатируйте USB-флешку в ext4 на компьютере вручную и запустите скрипт заново"
        return 1
    fi

    log "Форматирование $device в ext4..."

    # Отмонтировать если смонтировано
    ssh_exec "umount ${device}* 2>/dev/null" || true
    sleep 1

    # Создать один раздел и форматировать
    ssh_exec "echo -e 'o\nn\np\n1\n\n\nw' | fdisk $device 2>/dev/null" || true
    sleep 1
    ssh_exec "mkfs.ext4 -F ${device}1 2>&1 || mkfs.ext4 -F ${device} 2>&1"
    sleep 1

    log "USB отформатирован"

    # Перезагрузить USB через ndmc
    ndmc_exec "system usb detach"
    sleep 2
    ndmc_exec "system usb attach"
    sleep 5

    _install_entware_usb
}

_install_entware_usb() {
    log "Установка Entware на USB..."

    # Через Admin CLI (ndmc) — установить компонент OPKG
    log "  Проверяю компонент OPKG в прошивке..."
    ndmc_exec "components install opkg"
    sleep 3

    # Найти USB-накопитель через ndmc
    local usb_info
    usb_info=$(ndmc_exec "show usb")

    # Подключить Entware к USB
    local usb_id
    if [[ "$HAS_ENTWARE_SSH" == true ]]; then
        usb_id=$(ssh_exec "ls /tmp/mnt/ 2>/dev/null | head -1" | tr -d '[:space:]')
    else
        # Без SSH — берём из ndmc show media
        usb_id=$(ndmc_exec "show media" | grep "uuid:" | head -1 | awk '{print $2}' | tr -d '[:space:]')
    fi

    if [[ -z "$usb_id" ]]; then
        err "USB не смонтирован. Попробуйте перезагрузить роутер с USB и запустить скрипт заново."
        return 1
    fi

    log "  USB ID: $usb_id"
    ndmc_exec "opkg disk ${usb_id}:"
    sleep 5
    ndmc_exec "opkg initrc /opt/etc/init.d/rc.unslung"
    sleep 5

    # После установки Entware — должен появиться SSH на порту 222
    log "  Ожидаю запуск Entware SSH (порт 222)..."
    local retry=0
    while [[ $retry -lt 10 ]]; do
        if nc -z -w3 "$ROUTER_IP" 222 2>/dev/null; then
            ENTWARE_SSH_ARGS=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p 222 "root@$ROUTER_IP")
            if ssh_exec "echo ok" 2>/dev/null | grep -q "ok"; then
                HAS_ENTWARE_SSH=true
                log "Entware установлен на USB, SSH:222 доступен"
                return 0
            fi
        fi
        retry=$((retry + 1))
        sleep 3
    done

    # SSH не появился — проверить через ndmc
    local opkg_status
    opkg_status=$(ndmc_exec "show opkg" || true)
    if echo "$opkg_status" | grep -q "installed"; then
        warn "Entware установлен, но SSH:222 не запустился"
        warn "Пароль Entware SSH по умолчанию: keenetic"
        warn "Попробуйте перезагрузить роутер и запустить скрипт заново"
        return 1
    fi

    err "Не удалось установить Entware"
    return 1
}

_install_entware_internal() {
    # Keenetic поддерживает Entware только на USB.
    # Внутренний NAND (/storage) используется системой и не подходит для opkg.
    # Некоторые модели (Ultra KN-1811, Peak) имеют eMMC с достаточным местом,
    # но KeeneticOS всё равно требует USB для Entware.
    err "Keenetic требует USB-накопитель для установки Entware"
    err "Внутренняя память (NAND/UBI) не подходит — используется системой"
    err ""
    err "Подключите USB-флешку (минимум 1GB) и запустите скрипт заново"
    return 1
}

# --- Проверка поддержки нативного AWG (ASC) ---
check_native_awg_support() {
    if [[ "$HAS_ADMIN_CLI" != true ]]; then
        err "Нужен Admin CLI для нативного AWG"
        return 1
    fi

    # Проверяем версию KeeneticOS (нужна 4.2+)
    local os_ver
    os_ver=$(ndmc_exec "show version" | grep "release:" | awk '{print $2}' | head -1)

    if [[ -z "$os_ver" ]]; then
        warn "Не удалось определить версию KeeneticOS"
        return 0
    fi

    local major minor
    major=$(echo "$os_ver" | cut -d. -f1)
    minor=$(echo "$os_ver" | cut -d. -f2)

    if [[ "$major" -lt 4 ]] || { [[ "$major" -eq 4 ]] && [[ "$minor" -lt 2 ]]; }; then
        err "Нативный AWG требует KeeneticOS 4.2+ (установлена: $os_ver)"
        err "Используйте AWG-Manager (Entware) вместо нативного"
        return 1
    fi

    # Проверяем компонент WireGuard
    local wg_component
    wg_component=$(ndmc_exec "show components" | grep -i wireguard || true)
    if [[ -z "$wg_component" ]]; then
        warn "Компонент WireGuard не установлен в KeeneticOS"
        echo "  Установите: Настройки → Обновление → Компоненты → WireGuard VPN"
        return 1
    fi

    log "KeeneticOS $os_ver — поддержка ASC подтверждена"
}

# --- Парсинг AWG .conf файла ---
parse_awg_conf() {
    local conf_file="$1"

    if [[ ! -f "$conf_file" ]]; then
        err "Файл не найден: $conf_file"
        return 1
    fi

    # Извлечь параметры из [Interface]
    AWG_PRIVATE_KEY=$(awk -F' *= *' '/^PrivateKey/{print $2}' "$conf_file")
    AWG_ADDRESS=$(awk -F' *= *' '/^Address/{print $2}' "$conf_file")
    AWG_DNS=$(awk -F' *= *' '/^DNS/{print $2}' "$conf_file")

    # ASC параметры
    AWG_JC=$(awk -F' *= *' '/^Jc/{print $2}' "$conf_file")
    AWG_JMIN=$(awk -F' *= *' '/^Jmin/{print $2}' "$conf_file")
    AWG_JMAX=$(awk -F' *= *' '/^Jmax/{print $2}' "$conf_file")
    AWG_S1=$(awk -F' *= *' '/^S1/{print $2}' "$conf_file")
    AWG_S2=$(awk -F' *= *' '/^S2/{print $2}' "$conf_file")
    AWG_H1=$(awk -F' *= *' '/^H1/{print $2}' "$conf_file")
    AWG_H2=$(awk -F' *= *' '/^H2/{print $2}' "$conf_file")
    AWG_H3=$(awk -F' *= *' '/^H3/{print $2}' "$conf_file")
    AWG_H4=$(awk -F' *= *' '/^H4/{print $2}' "$conf_file")

    # Извлечь параметры из [Peer]
    AWG_PEER_KEY=$(awk -F' *= *' '/^PublicKey/{print $2}' "$conf_file")
    AWG_PEER_PSK=$(awk -F' *= *' '/^PresharedKey/{print $2}' "$conf_file")
    AWG_ENDPOINT=$(awk -F' *= *' '/^Endpoint/{print $2}' "$conf_file")
    AWG_ALLOWED_IPS=$(awk -F' *= *' '/^AllowedIPs/{print $2}' "$conf_file")
    AWG_KEEPALIVE=$(awk -F' *= *' '/^PersistentKeepalive/{print $2}' "$conf_file")

    AWG_ENDPOINT_HOST="${AWG_ENDPOINT%%:*}"
    AWG_ENDPOINT_PORT="${AWG_ENDPOINT##*:}"

    log "Конфиг распарсен:"
    log "  Адрес: $AWG_ADDRESS"
    log "  Сервер: $AWG_ENDPOINT"
    if [[ -n "$AWG_JC" ]]; then
        log "  ASC: Jc=$AWG_JC Jmin=$AWG_JMIN Jmax=$AWG_JMAX"
    fi
}

# --- Настройка нативного AmneziaWG (ASC) ---
setup_native_awg() {
    log "Настройка нативного AmneziaWG (ASC)..."

    check_native_awg_support || return 1

    # Запросить .conf файл
    if [[ -z "$AWG_CONF_FILE" || ! -f "$AWG_CONF_FILE" ]]; then
        echo ""
        log "Укажите путь к конфигу AmneziaWG (.conf)"
        log "Создайте в Telegram-боте: Пользователи → Добавить ключ → AWG Роутер"
        echo ""
        read -rp "  Путь к .conf файлу: " AWG_CONF_FILE

        if [[ -z "$AWG_CONF_FILE" || ! -f "$AWG_CONF_FILE" ]]; then
            err "Файл не найден: $AWG_CONF_FILE"
            return 1
        fi
    fi

    parse_awg_conf "$AWG_CONF_FILE" || return 1

    # Определить имя интерфейса (Wireguard1 если Wireguard0 занят)
    local wg_iface="Wireguard0"
    if ndmc_exec "show interface Wireguard0" 2>/dev/null | grep -q "interface-name:"; then
        wg_iface="Wireguard1"
        log "Wireguard0 занят, использую $wg_iface"
    fi

    log "Создаю интерфейс $wg_iface..."

    # Создать WireGuard интерфейс
    ndmc_exec "interface $wg_iface"
    ndmc_exec "interface $wg_iface description AmneziaWG"
    ndmc_exec "interface $wg_iface wireguard private-key $AWG_PRIVATE_KEY"

    # Установить ASC параметры
    if [[ -n "$AWG_JC" ]]; then
        log "  Устанавливаю ASC параметры..."
        ndmc_exec "interface $wg_iface wireguard asc $AWG_JC $AWG_JMIN $AWG_JMAX $AWG_S1 $AWG_S2 $AWG_H1 $AWG_H2 $AWG_H3 $AWG_H4"
    fi

    # Установить IP адрес
    local ip_addr="${AWG_ADDRESS%%/*}"
    local ip_mask="${AWG_ADDRESS##*/}"
    case "$ip_mask" in
        32) ip_mask="255.255.255.255" ;;
        24) ip_mask="255.255.255.0" ;;
        16) ip_mask="255.255.0.0" ;;
        *)  ip_mask="255.255.255.0" ;;
    esac
    ndmc_exec "interface $wg_iface ip address $ip_addr $ip_mask"
    ndmc_exec "interface $wg_iface ip mtu 1340"
    ndmc_exec "interface $wg_iface ip tcp adjust-mss pmtu"

    # Добавить пир
    log "  Добавляю пир ($AWG_ENDPOINT_HOST)..."
    ndmc_exec "interface $wg_iface wireguard peer $AWG_PEER_KEY"
    ndmc_exec "interface $wg_iface wireguard peer $AWG_PEER_KEY endpoint $AWG_ENDPOINT_HOST $AWG_ENDPOINT_PORT"
    ndmc_exec "interface $wg_iface wireguard peer $AWG_PEER_KEY keepalive ${AWG_KEEPALIVE:-25}"

    # PresharedKey
    if [[ -n "$AWG_PEER_PSK" ]]; then
        ndmc_exec "interface $wg_iface wireguard peer $AWG_PEER_KEY preshared-key $AWG_PEER_PSK"
    fi

    # AllowedIPs
    IFS=',' read -ra allowed_ips <<< "$AWG_ALLOWED_IPS"
    for aip in "${allowed_ips[@]}"; do
        aip=$(echo "$aip" | tr -d ' ')
        ndmc_exec "interface $wg_iface wireguard peer $AWG_PEER_KEY allow $aip"
    done

    # Включить интерфейс
    ndmc_exec "interface $wg_iface up"
    ndmc_exec "system configuration save"

    log "$wg_iface настроен и запущен"

    # Сохранить имя интерфейса для DNS-маршрутов
    AWG_INTERFACE="$wg_iface"
}

# --- Установка XKeen (xray + tproxy) ---
setup_xkeen() {
    log "Проверка XKeen..."

    if ! ssh_exec "test -f /opt/sbin/xkeen && echo yes" | grep -q "yes"; then
        err "XKeen не установлен (/opt/sbin/xkeen не найден)"
        err "Установите XKeen вручную: https://github.com/Jenya54/XKeen"
        return 1
    fi

    local xkeen_ver
    xkeen_ver=$(ssh_exec "xkeen -v 2>/dev/null" || echo "unknown")
    log "XKeen найден ($xkeen_ver)"

    # Зависимости
    log "Проверка зависимостей XKeen..."
    ssh_exec "opkg update 2>/dev/null"
    for pkg in jq curl coreutils-uname coreutils-nohup; do
        if ! ssh_exec "opkg list-installed | grep -q '^${pkg} '"; then
            log "  Устанавливаю $pkg..."
            ssh_exec "opkg install $pkg 2>&1"
        fi
    done

    # xray-core
    if ssh_exec "test -f /opt/sbin/xray && echo yes" | grep -q "yes"; then
        local xray_ver
        xray_ver=$(ssh_exec "/opt/sbin/xray version 2>/dev/null | head -1" || echo "unknown")
        log "xray-core уже установлен ($xray_ver)"
    else
        log "Устанавливаю xray-core из Entware..."
        ssh_exec "opkg install xray-core 2>&1"
        if ! ssh_exec "test -f /opt/sbin/xray && echo yes" | grep -q "yes"; then
            err "Не удалось установить xray-core"
            return 1
        fi
        log "xray-core установлен"
    fi

    # Директории
    log "Создаю директории XKeen..."
    ssh_exec "mkdir -p /opt/etc/xray/configs /opt/etc/xray/dat /opt/var/log/xray /opt/etc/xkeen"

    # Шаблоны конфигов (если директория пуста)
    local configs_count
    configs_count=$(ssh_exec "ls /opt/etc/xray/configs/*.json 2>/dev/null | wc -l" || echo "0")
    configs_count=$(echo "$configs_count" | tr -d '[:space:]')

    if [[ "$configs_count" == "0" ]]; then
        log "Копирую шаблоны конфигов XKeen..."
        local tpl_dir="/opt/sbin/.xkeen/02_install/08_install_configs/02_configs_dir"
        for tpl in 01_log.json 03_inbounds.json 06_policy.json; do
            if ssh_exec "test -f ${tpl_dir}/${tpl} && echo yes" | grep -q "yes"; then
                ssh_exec "cp ${tpl_dir}/${tpl} /opt/etc/xray/configs/${tpl}"
                log "  Скопирован $tpl"
            else
                warn "  Шаблон ${tpl} не найден в ${tpl_dir}"
            fi
        done
    else
        log "Конфиги XKeen уже существуют ($configs_count файлов)"
    fi

    # GeoSite/GeoIP базы (Re:filter)
    if ! ssh_exec "test -f /opt/etc/xray/dat/geosite.dat && echo yes" | grep -q "yes"; then
        log "Скачиваю GeoSite базу (Re:filter)..."
        ssh_exec "curl -sL -o /opt/etc/xray/dat/geosite.dat https://github.com/nickspaargaren/no-google/releases/latest/download/geosite.dat 2>&1 || \
            curl -sL -o /opt/etc/xray/dat/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat 2>&1"
    fi
    if ! ssh_exec "test -f /opt/etc/xray/dat/geoip.dat && echo yes" | grep -q "yes"; then
        log "Скачиваю GeoIP базу..."
        ssh_exec "curl -sL -o /opt/etc/xray/dat/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat 2>&1"
    fi

    # Init-скрипт S99xkeen
    if ! ssh_exec "test -f /opt/etc/init.d/S99xkeen && echo yes" | grep -q "yes"; then
        local init_tpl="/opt/sbin/.xkeen/02_install/07_install_register/04_register_init.sh"
        if ssh_exec "test -f ${init_tpl} && echo yes" | grep -q "yes"; then
            log "Копирую init-скрипт S99xkeen из шаблона..."
            ssh_exec "cp ${init_tpl} /opt/etc/init.d/S99xkeen && chmod +x /opt/etc/init.d/S99xkeen"
        else
            warn "Шаблон init-скрипта не найден, S99xkeen не создан"
        fi
    else
        log "S99xkeen уже существует"
    fi

    # Пользователь xkeen (uid/gid 11111)
    if ! ssh_exec "id xkeen 2>/dev/null && echo yes" | grep -q "yes"; then
        log "Создаю пользователя xkeen..."
        ssh_exec "grep -q '^xkeen:' /opt/etc/group || echo 'xkeen:x:11111:' >> /opt/etc/group"
        ssh_exec "grep -q '^xkeen:' /opt/etc/passwd || echo 'xkeen:x:11111:11111:XKeen:/opt/etc/xkeen:/bin/false' >> /opt/etc/passwd"
    else
        log "Пользователь xkeen уже существует"
    fi

    log "XKeen готов к настройке"
}

# --- Конфиг VLESS через XKeen (tproxy) ---
setup_xkeen_vless_config() {
    log "Настройка VLESS через XKeen..."

    echo ""
    echo "  Введите данные VLESS-подключения."
    echo "  Можно вставить vless:// ссылку или ввести параметры вручную."
    echo ""
    read -rp "  vless:// ссылка (или Enter для ручного ввода): " VLESS_LINK

    local VLESS_SERVER="" VLESS_PORT="" VLESS_UUID="" VLESS_PUBKEY="" VLESS_SHORT_ID="" VLESS_SNI=""

    if [[ -n "$VLESS_LINK" && "$VLESS_LINK" == vless://* ]]; then
        # Парсинг vless://UUID@SERVER:PORT?params#name
        VLESS_UUID=$(echo "$VLESS_LINK" | sed 's|vless://||' | cut -d'@' -f1)
        local server_part
        server_part=$(echo "$VLESS_LINK" | sed 's|vless://[^@]*@||' | cut -d'#' -f1)
        VLESS_SERVER=$(echo "$server_part" | cut -d':' -f1)
        VLESS_PORT=$(echo "$server_part" | cut -d':' -f2 | cut -d'?' -f1)

        local params
        params=$(echo "$server_part" | grep -o '?.*' | sed 's/^?//')
        VLESS_PUBKEY=$(echo "$params" | tr '&' '\n' | grep '^pbk=' | cut -d'=' -f2)
        VLESS_SHORT_ID=$(echo "$params" | tr '&' '\n' | grep '^sid=' | cut -d'=' -f2)
        VLESS_SNI=$(echo "$params" | tr '&' '\n' | grep '^sni=' | cut -d'=' -f2)

        # Fallback для SNI
        if [[ -z "$VLESS_SNI" ]]; then
            VLESS_SNI=$(echo "$params" | tr '&' '\n' | grep '^host=' | cut -d'=' -f2)
        fi

        log "  Распознано из ссылки:"
        log "    Сервер: $VLESS_SERVER:$VLESS_PORT"
        log "    UUID: ${VLESS_UUID:0:8}..."
        log "    SNI: $VLESS_SNI"
    else
        read -rp "  IP сервера: " VLESS_SERVER
        read -rp "  Порт [443]: " VLESS_PORT
        VLESS_PORT="${VLESS_PORT:-443}"
        read -rp "  UUID: " VLESS_UUID
        read -rp "  Public Key (Reality): " VLESS_PUBKEY
        read -rp "  Short ID: " VLESS_SHORT_ID
        read -rp "  SNI (например: www.google.com): " VLESS_SNI
    fi

    # Валидация
    if [[ -z "$VLESS_SERVER" || -z "$VLESS_UUID" ]]; then
        err "Не указаны обязательные параметры (сервер, UUID)"
        return 1
    fi
    VLESS_PORT="${VLESS_PORT:-443}"
    VLESS_SNI="${VLESS_SNI:-www.google.com}"

    # Выбор сервисов для маршрутизации через xray
    echo ""
    log "Какие сервисы направить через VLESS?"
    echo "   1) YouTube + Google"
    echo "   2) Instagram"
    echo "   3) Facebook"
    echo "   4) Telegram"
    echo "   5) WhatsApp"
    echo "   6) Viber"
    echo "   7) AI (Claude, ChatGPT)"
    echo "   8) Все вышеперечисленные"
    echo "   9) Весь трафик (всё через прокси)"
    echo ""
    echo "  Можно выбрать несколько через запятую (например: 1,2,4)"
    read -rp "  Выбор [8]: " XKEEN_SERVICES
    XKEEN_SERVICES="${XKEEN_SERVICES:-8}"

    # Собираем массив geosite/domain правил
    local route_domains=()
    local all_traffic=false

    if [[ "$XKEEN_SERVICES" == *"9"* ]]; then
        all_traffic=true
    elif [[ "$XKEEN_SERVICES" == *"8"* ]]; then
        route_domains+=("geosite:youtube" "geosite:google" "geosite:instagram" "geosite:facebook" "geosite:meta" "geosite:telegram")
        route_domains+=("domain:whatsapp.com" "domain:whatsapp.net" "domain:wa.me")
        route_domains+=("domain:viber.com" "domain:viber.media" "domain:viber-cdn.com")
        route_domains+=("domain:anthropic.com" "domain:claude.ai" "domain:openai.com" "domain:chatgpt.com")
    else
        IFS=',' read -ra selections <<< "$XKEEN_SERVICES"
        for sel in "${selections[@]}"; do
            sel=$(echo "$sel" | tr -d '[:space:]')
            case "$sel" in
                1) route_domains+=("geosite:youtube" "geosite:google") ;;
                2) route_domains+=("geosite:instagram") ;;
                3) route_domains+=("geosite:facebook" "geosite:meta") ;;
                4) route_domains+=("geosite:telegram") ;;
                5) route_domains+=("domain:whatsapp.com" "domain:whatsapp.net" "domain:wa.me") ;;
                6) route_domains+=("domain:viber.com" "domain:viber.media" "domain:viber-cdn.com") ;;
                7) route_domains+=("domain:anthropic.com" "domain:claude.ai" "domain:openai.com" "domain:chatgpt.com") ;;
            esac
        done
    fi

    # Генерируем 04_outbounds.json
    log "Создаю конфиг outbounds (04_outbounds.json)..."

    SSHPASS="$ROUTER_ENTWARE_PASS" sshpass -e ssh "${ENTWARE_SSH_ARGS[@]}" "cat > /opt/etc/xray/configs/04_outbounds.json" << OUTEOF
{
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "$VLESS_SERVER",
          "port": $VLESS_PORT,
          "users": [{
            "id": "$VLESS_UUID",
            "encryption": "none",
            "flow": "xtls-rprx-vision"
          }]
        }]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "fingerprint": "chrome",
          "serverName": "$VLESS_SNI",
          "publicKey": "$VLESS_PUBKEY",
          "shortId": "$VLESS_SHORT_ID"
        }
      }
    },
    {"tag": "direct", "protocol": "freedom", "settings": {}},
    {"tag": "block", "protocol": "blackhole", "settings": {}}
  ]
}
OUTEOF

    ssh_exec "chmod 600 /opt/etc/xray/configs/04_outbounds.json"

    # Генерируем 05_routing.json
    log "Создаю конфиг маршрутизации (05_routing.json)..."

    if [[ "$all_traffic" == true ]]; then
        # Весь трафик через прокси, кроме приватных сетей и IP сервера
        SSHPASS="$ROUTER_ENTWARE_PASS" sshpass -e ssh "${ENTWARE_SSH_ARGS[@]}" "cat > /opt/etc/xray/configs/05_routing.json" << ROUTEEOF
{
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["$VLESS_SERVER"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "proxy"
      }
    ]
  }
}
ROUTEEOF
    else
        # Формируем JSON-массив доменов для маршрутизации
        local domains_json=""
        for i in "${!route_domains[@]}"; do
            if [[ $i -gt 0 ]]; then
                domains_json+=","
            fi
            domains_json+="\"${route_domains[$i]}\""
        done

        SSHPASS="$ROUTER_ENTWARE_PASS" sshpass -e ssh "${ENTWARE_SSH_ARGS[@]}" "cat > /opt/etc/xray/configs/05_routing.json" << ROUTEEOF
{
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["$VLESS_SERVER"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": [$domains_json],
        "outboundTag": "proxy"
      }
    ]
  }
}
ROUTEEOF
    fi

    ssh_exec "chmod 600 /opt/etc/xray/configs/05_routing.json"

    # Запуск XKeen
    log "Запускаю XKeen..."
    ssh_exec "xkeen -start 2>&1" || true
    sleep 3

    # Проверка статуса
    log "Проверяю статус XKeen..."
    local xkeen_status
    xkeen_status=$(ssh_exec "xkeen -status 2>&1" || true)
    echo "$xkeen_status"

    if echo "$xkeen_status" | grep -qi "running\|работает\|запущен\|active"; then
        log "XKeen запущен и работает"
    else
        warn "XKeen запущен, но статус неясен — проверьте вручную: xkeen -status"
    fi
}

# --- Очистка ДО установки (убрать конфликты) ---
cleanup_before() {
    if [[ "$HAS_ENTWARE_SSH" == false ]]; then
        log "Пропуск очистки (нет SSH доступа к Entware)"
        return 0
    fi
    log "Проверка конфликтующих сервисов..."
    local cleaned=0

    # 0. Старый xray/tun2socks (миграция на XKeen)
    if ssh_exec "test -f /opt/etc/init.d/S51xray-tun && echo yes" | grep -q "yes"; then
        warn "Найден старый S51xray-tun — останавливаю и удаляю"
        ssh_exec "/opt/etc/init.d/S51xray-tun stop 2>/dev/null" || true
        ssh_exec "rm -f /opt/etc/init.d/S51xray-tun"
        cleaned=$((cleaned + 1))
    fi

    # 0a. Удаляем tun2socks (заменён на tproxy в XKeen)
    if ssh_exec "test -f /opt/sbin/tun2socks && echo yes" | grep -q "yes"; then
        warn "Найден tun2socks — удаляю (XKeen использует tproxy)"
        ssh_exec "rm -f /opt/sbin/tun2socks"
        cleaned=$((cleaned + 1))
    fi

    # 0b. Бэкап старого config.json (заменён на модульные конфиги XKeen)
    if ssh_exec "test -f /opt/etc/xray/config.json && echo yes" | grep -q "yes"; then
        warn "Найден старый config.json — делаю бэкап"
        ssh_exec "mv /opt/etc/xray/config.json /opt/etc/xray/config.json.old 2>/dev/null"
        cleaned=$((cleaned + 1))
    fi

    # 0c. Удаляем интерфейс OpkgTun1 (XKeen не использует tun-интерфейс)
    if [[ "$HAS_ADMIN_CLI" == true ]]; then
        if ndmc_exec "show interface OpkgTun1" 2>/dev/null | grep -q "interface-name: OpkgTun1"; then
            warn "Найден OpkgTun1 — удаляю (XKeen использует tproxy)"
            ndmc_exec "no interface OpkgTun1"
            ndmc_exec "system configuration save"
            cleaned=$((cleaned + 1))
        fi
    fi

    # 1. Старый AWG скрипт (S89amnezia-wg-quick) — заменён на S52awg-opkgtun0
    if ssh_exec "test -f /opt/etc/init.d/S89amnezia-wg-quick && echo yes" | grep -q "yes"; then
        warn "Найден старый AWG скрипт S89amnezia-wg-quick — удаляю"
        ssh_exec "/opt/etc/init.d/S89amnezia-wg-quick stop 2>/dev/null" || true
        ssh_exec "rm -f /opt/etc/init.d/S89amnezia-wg-quick"
        cleaned=$((cleaned + 1))
    fi

    # 2. Shadowsocks — обычно не нужен при AWG
    if ssh_exec "test -f /opt/etc/init.d/S22shadowsocks && echo yes" | grep -q "yes"; then
        local ss_running
        ss_running=$(ssh_exec "ps w | grep -v grep | grep shadowsocks" || true)
        if [[ -n "$ss_running" ]]; then
            warn "Найден Shadowsocks (запущен)"
        else
            warn "Найден Shadowsocks (не запущен)"
        fi
        echo ""
        read -rp "  Удалить Shadowsocks? (y/n): " DEL_SS
        if [[ "$(echo "$DEL_SS" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
            ssh_exec "/opt/etc/init.d/S22shadowsocks stop 2>/dev/null" || true
            ssh_exec "rm -f /opt/etc/init.d/S22shadowsocks"
            ssh_exec "opkg remove shadowsocks-libev 2>/dev/null" || true
            log "Shadowsocks удалён"
            cleaned=$((cleaned + 1))
        fi
    fi

    # 3. dnscrypt-proxy — конфликтует с системным DNS (stubby/https_dns_proxy)
    if ssh_exec "test -f /opt/sbin/dnscrypt-proxy && echo yes" | grep -q "yes"; then
        # Проверить, есть ли системный DNS (stubby или https_dns_proxy)
        local system_dns
        system_dns=$(ssh_exec "ps w | grep -v grep | grep -c 'stubby\|https_dns_proxy'" || echo "0")

        if [[ "$system_dns" -gt 0 ]]; then
            warn "Найден dnscrypt-proxy (13MB RAM), но Keenetic уже имеет встроенный DNS-over-TLS/HTTPS"
            warn "  Запущено системных DNS процессов: $system_dns"
            echo ""
            read -rp "  Удалить dnscrypt-proxy (рекомендуется)? (y/n): " DEL_DNS
            if [[ "$(echo "$DEL_DNS" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
                ssh_exec "/opt/etc/init.d/S09dnscrypt-proxy2 stop 2>/dev/null" || true
                ssh_exec "rm -f /opt/etc/init.d/S09dnscrypt-proxy2"
                ssh_exec "opkg remove dnscrypt-proxy2 2>/dev/null" || true
                ssh_exec "rm -f /opt/sbin/dnscrypt-proxy"
                ssh_exec "rm -rf /opt/etc/dnscrypt-proxy.toml /opt/etc/dnscrypt-proxy"
                log "dnscrypt-proxy удалён (экономия ~13MB диска + ~500MB RAM)"
                cleaned=$((cleaned + 1))
            fi
        else
            log "dnscrypt-proxy — единственный DNS, оставляю"
        fi
    fi

    # 4. Entware dnsmasq — конфликтует с системным
    if ssh_exec "test -f /opt/etc/init.d/S56dnsmasq && echo yes" | grep -q "yes"; then
        local system_dnsmasq
        system_dnsmasq=$(ssh_exec "ps w | grep -v grep | grep -v '/opt' | grep -c dnsmasq" || echo "0")

        if [[ "$system_dnsmasq" -gt 0 ]]; then
            warn "Найден Entware dnsmasq, но системный dnsmasq уже запущен"
            echo ""
            read -rp "  Удалить Entware dnsmasq? (y/n): " DEL_DNSMASQ
            if [[ "$(echo "$DEL_DNSMASQ" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
                ssh_exec "/opt/etc/init.d/S56dnsmasq stop 2>/dev/null" || true
                ssh_exec "rm -f /opt/etc/init.d/S56dnsmasq"
                ssh_exec "opkg remove dnsmasq-full 2>/dev/null; opkg remove dnsmasq 2>/dev/null" || true
                log "Entware dnsmasq удалён"
                cleaned=$((cleaned + 1))
            fi
        fi
    fi

    # 5. MagiTrickle — заменён DNS-маршрутами Keenetic
    if ssh_exec "test -f /opt/bin/magitrickled && echo yes" | grep -q "yes"; then
        warn "Найден MagiTrickle — заменён DNS-маршрутами KeenOS 5.0"
        echo ""
        read -rp "  Удалить MagiTrickle? (y/n): " DEL_MT
        if [[ "$(echo "$DEL_MT" | tr '[:upper:]' '[:lower:]')" != "y" ]]; then
            log "MagiTrickle оставлен"
        else
        ssh_exec "/opt/etc/init.d/S99magitrickle stop 2>/dev/null" || true
        ssh_exec "rm -f /opt/etc/init.d/S99magitrickle /opt/bin/magitrickled"
        ssh_exec "rm -rf /opt/etc/magitrickle /opt/usr/share/magitrickle /opt/var/lib/magitrickle"
        ssh_exec "rm -f /opt/etc/ndm/netfilter.d/100-magitrickle"
        ssh_exec "rm -f /opt/lib/opkg/lists/magitrickle_*"
        log "MagiTrickle удалён"
        cleaned=$((cleaned + 1))
        fi
    fi

    # 6. opkg.conf дубликаты
    local dup_count
    dup_count=$(ssh_exec "grep -c 'src/gz entware' /opt/etc/opkg.conf 2>/dev/null" || echo "0")
    if [[ "$dup_count" -gt 1 ]]; then
        warn "Дубликаты в opkg.conf ($dup_count записей entware) — исправляю"
        # Определить правильный URL для архитектуры на основе AWG_PKG_SUFFIX
        local entware_url
        local arch_name="${AWG_PKG_SUFFIX:-mipsel-3.4}"
        case "$arch_name" in
            aarch64-3.10) entware_url="http://bin.entware.net/aarch64-k3.10" ;;
            mips-3.4)     entware_url="http://bin.entware.net/mipssf-k3.4" ;;
            *)             entware_url="http://bin.entware.net/mipselsf-k3.4" ;;
        esac
        ssh_exec "cat > /opt/etc/opkg.conf << OPKG
src/gz entware ${entware_url}
src/gz keendev ${entware_url}/keenetic
dest root /
lists_dir ext /opt/var/opkg-lists
arch all 100
arch ${arch_name} 150
arch ${arch_name}_kn 200
OPKG"
        log "opkg.conf исправлен (архитектура: $arch_name)"
        cleaned=$((cleaned + 1))
    fi

    # 7. Старые DNS-маршруты NDMS (от предыдущих ручных настроек)
    local old_routes
    old_routes=$(ndmc_exec "show running-config" | grep "ip route .* OpkgTun0" || true)
    if [[ -n "$old_routes" ]]; then
        warn "Найдены старые ip route через OpkgTun0 — удаляю"
        while IFS= read -r route_line; do
            [[ -z "$route_line" ]] && continue
            ndmc_exec "no $route_line" 2>/dev/null || true
        done <<< "$old_routes"
        ndmc_exec "system configuration save"
        log "Старые маршруты удалены"
        cleaned=$((cleaned + 1))
    fi

    if [[ $cleaned -gt 0 ]]; then
        log "Очистка завершена: удалено $cleaned конфликтов"
    else
        log "Конфликтов не найдено"
    fi
}

# --- Очистка ПОСЛЕ установки (убрать мусор) ---
cleanup_after() {
    log "Очистка временных файлов..."
    local freed=0

    # 1. Установочные .ipk файлы
    if ssh_exec "test -d /opt/root/awg2-go && echo yes" | grep -q "yes"; then
        local ipk_size
        ipk_size=$(ssh_exec "du -sk /opt/root/awg2-go/ 2>/dev/null | awk '{print \$1}'" || echo "0")
        ssh_exec "rm -rf /opt/root/awg2-go"
        log "  Удалены .ipk пакеты (${ipk_size}KB)"
        freed=$((freed + ipk_size))
    fi

    # 2. opkg кэш
    if ssh_exec "test -d /opt/var/opkg-lists && echo yes" | grep -q "yes"; then
        local cache_size
        cache_size=$(ssh_exec "du -sk /opt/var/opkg-lists/ 2>/dev/null | awk '{print \$1}'" || echo "0")
        ssh_exec "rm -rf /opt/var/opkg-lists/*"
        log "  Очищен кэш opkg (${cache_size}KB)"
        freed=$((freed + cache_size))
    fi

    # 3. Логи
    ssh_exec "rm -f /opt/var/log/*.log 2>/dev/null" || true

    # 4. Bash/shell history
    ssh_exec "rm -f /opt/root/.ash_history /opt/root/.bash_history 2>/dev/null" || true

    # 5. wget/curl temp files
    ssh_exec "rm -f /opt/root/.wget-hsts 2>/dev/null" || true

    # 6. Осиротевшие библиотеки (после удаления пакетов)
    ssh_exec "opkg --autoremove remove 2>/dev/null" || true

    local freed_mb=$((freed / 1024))
    if [[ $freed_mb -gt 0 ]]; then
        log "Освобождено: ~${freed_mb}MB"
    fi

    # Показать итог
    local opt_used opt_free
    opt_used=$(ssh_exec "df -h /opt 2>/dev/null | tail -1 | awk '{print \$3}'")
    opt_free=$(ssh_exec "df -h /opt 2>/dev/null | tail -1 | awk '{print \$4}'")
    log "Хранилище: занято $opt_used, свободно $opt_free"

    local ram_used ram_free
    ram_free=$(ssh_exec "free | grep Mem | awk '{print int(\$4/1024)}'")
    log "RAM свободно: ${ram_free}MB"
}

# --- Выбор лучшего DNS ---
setup_dns() {
    log "Тестирование DNS-серверов..."

    # DNS-over-TLS серверы для тестирования
    declare -A DOT_SERVERS=(
        ["AdGuard"]="94.140.14.14|dns.adguard-dns.com"
        ["Cloudflare"]="1.1.1.1|cloudflare-dns.com"
        ["Google"]="8.8.8.8|dns.google"
        ["Quad9"]="9.9.9.9|dns.quad9.net"
        ["NextDNS"]="45.90.28.0|dns.nextdns.io"
        ["Yandex"]="77.88.8.8|common.dot.dns.yandex.net"
        ["Yandex Safe"]="77.88.8.88|safe.dot.dns.yandex.net"
    )

    # DNS-over-HTTPS серверы
    declare -A DOH_SERVERS=(
        ["AdGuard"]="https://dns.adguard-dns.com/dns-query"
        ["Cloudflare"]="https://cloudflare-dns.com/dns-query"
        ["Google"]="https://dns.google/dns-query"
        ["Quad9"]="https://dns.quad9.net:443/dns-query"
        ["Yandex"]="https://common.dot.dns.yandex.net/dns-query"
        ["Yandex Safe"]="https://safe.dot.dns.yandex.net/dns-query"
    )

    # Тестируем пинг до каждого DNS (с роутера)
    log "  Тестирую задержку до DNS-серверов с роутера..."

    local best_name="" best_time=9999 best_ip="" best_sni=""
    local results=""

    for name in "${!DOT_SERVERS[@]}"; do
        local entry="${DOT_SERVERS[$name]}"
        local ip="${entry%%|*}"
        local sni="${entry##*|}"

        # Пинг с роутера (3 пакета, таймаут 2с)
        local avg_time
        avg_time=$(ssh_exec "ping -c 3 -W 2 $ip 2>/dev/null | grep 'avg' | cut -d'/' -f5" | tr -d '[:space:]')

        if [[ -z "$avg_time" ]]; then
            # BusyBox ping может иметь другой формат
            avg_time=$(ssh_exec "ping -c 3 -W 2 $ip 2>/dev/null | tail -1 | awk -F'/' '{print \$4}'" | tr -d '[:space:]')
        fi

        if [[ -n "$avg_time" && "$avg_time" != "" ]]; then
            local time_int=${avg_time%%.*}
            results+="    $name ($ip): ${avg_time}ms\n"

            if [[ $time_int -lt $best_time ]]; then
                best_time=$time_int
                best_name=$name
                best_ip=$ip
                best_sni=$sni
            fi
        else
            results+="    $name ($ip): timeout\n"
        fi
    done

    echo -e "$results"

    if [[ -z "$best_name" ]]; then
        warn "Не удалось протестировать DNS. Использую AdGuard по умолчанию"
        best_name="AdGuard"
        best_ip="94.140.14.14"
        best_sni="dns.adguard-dns.com"
    fi

    log "  Лучший DNS: $best_name ($best_ip, ${best_time}ms)"

    # Предложить настройку
    echo ""
    echo "  Рекомендуемый DNS: $best_name (DoT: $best_sni)"
    echo ""
    echo "  Варианты:"
    echo "   1) $best_name (рекомендуется, ${best_time}ms)"

    # Показать топ-3
    local opt=2
    for name in "${!DOT_SERVERS[@]}"; do
        [[ "$name" == "$best_name" ]] && continue
        local entry="${DOT_SERVERS[$name]}"
        local ip="${entry%%|*}"
        echo "   $opt) $name ($ip)"
        opt=$((opt + 1))
        [[ $opt -gt 4 ]] && break
    done
    echo "   0) Не менять DNS"
    echo ""
    read -rp "  Выбор [1]: " DNS_CHOICE
    DNS_CHOICE="${DNS_CHOICE:-1}"

    if [[ "$DNS_CHOICE" == "0" ]]; then
        log "DNS не изменён"
        return 0
    fi

    # Определить выбранный сервер
    local chosen_name="$best_name"
    local chosen_ip="$best_ip"
    local chosen_sni="$best_sni"

    if [[ "$DNS_CHOICE" != "1" ]]; then
        # Пользователь выбрал другой — найти по порядку
        local idx=2
        for name in "${!DOT_SERVERS[@]}"; do
            [[ "$name" == "$best_name" ]] && continue
            if [[ "$idx" == "$DNS_CHOICE" ]]; then
                chosen_name="$name"
                local entry="${DOT_SERVERS[$name]}"
                chosen_ip="${entry%%|*}"
                chosen_sni="${entry##*|}"
                break
            fi
            idx=$((idx + 1))
        done
    fi

    log "Настраиваю DNS: $chosen_name (DoT: $chosen_sni)"

    # БЕЗОПАСНАЯ смена DNS:
    # 1. Сначала добавляем plain DNS fallback (чтобы интернет не пропал)
    # 2. Добавляем новый DoT/DoH
    # 3. Удаляем старый DoT/DoH
    # 4. Удаляем plain fallback
    # Если скрипт упадёт на любом шаге — интернет сохранится

    log "  Добавляю временный DNS fallback (Google DoT)..."
    ndmc_exec "dns-proxy tls upstream 8.8.8.8 sni dns.google" 2>/dev/null || true

    # Добавить новый DoT (основной + резервный)
    case "$chosen_name" in
        "AdGuard")
            ndmc_exec "dns-proxy tls upstream 94.140.14.14 sni dns.adguard-dns.com"
            ndmc_exec "dns-proxy tls upstream 94.140.15.15 sni dns.adguard-dns.com"
            ;;
        "Cloudflare")
            ndmc_exec "dns-proxy tls upstream 1.1.1.1 sni cloudflare-dns.com"
            ndmc_exec "dns-proxy tls upstream 1.0.0.1 sni cloudflare-dns.com"
            ;;
        "Google")
            ndmc_exec "dns-proxy tls upstream 8.8.8.8 sni dns.google"
            ndmc_exec "dns-proxy tls upstream 8.8.4.4 sni dns.google"
            ;;
        "Quad9")
            ndmc_exec "dns-proxy tls upstream 9.9.9.9 sni dns.quad9.net"
            ndmc_exec "dns-proxy tls upstream 149.112.112.112 sni dns.quad9.net"
            ;;
        "NextDNS")
            ndmc_exec "dns-proxy tls upstream 45.90.28.0 sni dns.nextdns.io"
            ndmc_exec "dns-proxy tls upstream 45.90.30.0 sni dns.nextdns.io"
            ;;
        "Yandex")
            ndmc_exec "dns-proxy tls upstream 77.88.8.8 sni common.dot.dns.yandex.net"
            ndmc_exec "dns-proxy tls upstream 77.88.8.1 sni common.dot.dns.yandex.net"
            ;;
        "Yandex Safe")
            ndmc_exec "dns-proxy tls upstream 77.88.8.88 sni safe.dot.dns.yandex.net"
            ndmc_exec "dns-proxy tls upstream 77.88.8.2 sni safe.dot.dns.yandex.net"
            ;;
    esac

    # Добавить DoH
    local doh_url="${DOH_SERVERS[$chosen_name]:-}"
    if [[ -n "$doh_url" ]]; then
        ndmc_exec "dns-proxy https upstream $doh_url dnsm"
    fi

    # Теперь безопасно удалить старые DNS (новые уже работают)
    log "  Удаляю старые DNS upstream..."

    # Удалить старые DoT (кроме выбранного)
    local old_tls_ips
    old_tls_ips=$(ndmc_exec "show running-config" | grep "tls upstream" | grep -v "$chosen_sni" | awk '{print $3}' || true)
    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        ip=$(echo "$ip" | tr -d '[:space:]')
        ndmc_exec "dns-proxy no tls upstream $ip" 2>/dev/null || true
    done <<< "$old_tls_ips"

    # Удалить старые DoH (кроме выбранного)
    local old_https_urls
    old_https_urls=$(ndmc_exec "show running-config" | grep "https upstream" | grep -v "${doh_url:-NONE}" | awk '{print $3}' || true)
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        url=$(echo "$url" | tr -d '[:space:]')
        ndmc_exec "dns-proxy no https upstream $url" 2>/dev/null || true
    done <<< "$old_https_urls"

    # Удалить временный Google DoT fallback (если он не был выбран основным)
    if [[ "$chosen_name" != "Google" ]]; then
        ndmc_exec "dns-proxy no tls upstream 8.8.8.8" 2>/dev/null || true
    fi

    # Игнорировать DNS провайдера (важно для обхода блокировок)
    ndmc_exec "dns-proxy no rebind-protect"
    ndmc_exec "system configuration save"

    log "DNS настроен: $chosen_name (DoT + DoH)"
    log "  DoT: $chosen_sni ($chosen_ip)"
    [[ -n "$doh_url" ]] && log "  DoH: $doh_url"
}

# --- DNS маршруты ---
setup_dns_routes() {
    echo ""
    log "Настройка DNS-маршрутов для разблокировки"
    echo ""

    local VPN_INTERFACE="OpkgTun0"
    log "Интерфейс для DNS-маршрутов: $VPN_INTERFACE (AWG-Go)"

    echo ""
    echo "  Какие сервисы разблокировать через ${VPN_INTERFACE}?"
    echo "   1) YouTube"
    echo "   2) Instagram"
    echo "   3) Facebook"
    echo "   4) Telegram"
    echo "   5) WhatsApp"
    echo "   6) Viber"
    echo "   7) Anthropic/Claude AI"
    echo "   8) Custom (Hetzner и др.)"
    echo "   9) Все"
    echo "   0) Пропустить"
    echo ""
    read -rp "  Введите номера через пробел (например: 1 2 4): " SELECTED

    if [[ "$SELECTED" == "0" ]]; then
        log "DNS-маршруты пропущены"
        return 0
    fi

    # Map numbers to list files
    declare -A SERVICE_MAP=(
        [1]="youtube"
        [2]="instagram"
        [3]="facebook"
        [4]="telegram"
        [5]="whatsapp"
        [6]="viber"
        [7]="anthropic"
        [8]="custom"
    )

    local services=()
    if [[ "$SELECTED" == "9" ]]; then
        services=(youtube instagram facebook telegram whatsapp viber anthropic custom)
    else
        for num in $SELECTED; do
            if [[ -n "${SERVICE_MAP[$num]:-}" ]]; then
                services+=("${SERVICE_MAP[$num]}")
            fi
        done
    fi

    for service in "${services[@]}"; do
        local list_file="$DNS_LISTS_DIR/${service}.lst"
        if [[ ! -f "$list_file" ]]; then
            warn "Файл списка не найден: $list_file"
            continue
        fi

        local group_name="awg_${service}"
        log "Добавляю DNS-маршрут: $service..."

        # Create object-group fqdn
        ndmc_exec "object-group fqdn $group_name"
        ndmc_exec "object-group fqdn $group_name description $service"

        while IFS= read -r domain; do
            [[ -z "$domain" || "$domain" == \#* ]] && continue
            ndmc_exec "object-group fqdn $group_name include $domain"
        done < "$list_file"

        # Add DNS route
        ndmc_exec "dns-proxy route object-group $group_name $VPN_INTERFACE auto reject"
    done

    ndmc_exec "system configuration save"
    log "DNS-маршруты настроены для: ${services[*]}"
}

# --- Скачивание dns-lists (при запуске через curl) ---
download_dns_lists() {
    if [[ -d "$DNS_LISTS_DIR" ]] && ls "$DNS_LISTS_DIR"/*.lst &>/dev/null; then
        return 0  # Уже есть
    fi

    local repo_url="https://raw.githubusercontent.com/ZveR1nMe/vps-xray-tg-auto/main"
    log "Скачиваю списки доменов..."
    mkdir -p "$DNS_LISTS_DIR"
    for svc in youtube instagram facebook telegram whatsapp viber anthropic custom; do
        curl -sL "${repo_url}/data/router/dns-lists/${svc}.lst" -o "$DNS_LISTS_DIR/${svc}.lst" 2>/dev/null
    done
    log "Списки загружены"
}

# --- Главная функция ---
main() {
    # Принять конфиг как аргумент
    if [[ -n "${1:-}" && -f "${1:-}" ]]; then
        AWG_CLIENT_CONF="$1"
    fi

    log "=============================================="
    log "  Настройка Keenetic: AmneziaWG + VLESS"
    log "=============================================="
    log ""
    log "  Запускайте этот скрипт на компьютере (macOS/Linux/WSL)"
    log "  Конфиг AWG создаётся в Telegram-боте → AWG Роутер"
    log ""

    # Проверить sshpass
    if ! command -v sshpass &>/dev/null; then
        err "sshpass не установлен"
        echo ""
        echo "  Установите:"
        echo "    macOS:  brew install sshpass  (или brew install hudochenkov/sshpass/sshpass)"
        echo "    Ubuntu: sudo apt install sshpass"
        echo "    Arch:   sudo pacman -S sshpass"
        return 1
    fi

    # Скачать dns-lists если нет
    download_dns_lists

    check_connection || return 1
    detect_router || return 1
    cleanup_before
    setup_storage || return 1

    # Выбор протоколов
    echo ""
    log "Какие протоколы настроить?"
    echo "   1) Только AWG-Go"
    echo "   2) Только VLESS (XKeen)"
    echo "   3) Оба (AWG-Go + VLESS)"
    echo ""
    read -rp "  Выбор [3]: " PROTO_CHOICE
    PROTO_CHOICE="${PROTO_CHOICE:-3}"

    # AWG
    if [[ "$PROTO_CHOICE" == "1" || "$PROTO_CHOICE" == "3" ]]; then
        install_awg_go || return 1
        setup_opkgtun || return 1
        setup_awg_config || return 1
    fi

    # VLESS (XKeen)
    if [[ "$PROTO_CHOICE" == "2" || "$PROTO_CHOICE" == "3" ]]; then
        setup_xkeen || return 1
        setup_xkeen_vless_config || return 1
    fi

    setup_dns

    # DNS-маршруты только для AWG-Go (XKeen использует маршрутизацию xray)
    if [[ "$PROTO_CHOICE" == "1" || "$PROTO_CHOICE" == "3" ]]; then
        setup_dns_routes
    fi
    cleanup_after

    # Очистка временных файлов при запуске через curl
    if [[ "$DOWNLOADED_SCRIPT" == true ]]; then
        rm -rf "$SCRIPT_DIR"
    fi

    log "=========================================="
    log "  Роутер настроен!"
    log "=========================================="
}

main "$@"
