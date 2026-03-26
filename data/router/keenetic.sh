#!/usr/bin/env bash
# Автонастройка роутера Keenetic для AmneziaWG
# Вызывается из setup.sh после установки AWG на сервере

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DNS_LISTS_DIR="$SCRIPT_DIR/dns-lists"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[router]${NC} $1"; }
warn() { echo -e "${YELLOW}[router]${NC} $1"; }
err()  { echo -e "${RED}[router]${NC} $1" >&2; }

# --- Параметры (передаются из setup.sh) ---
ROUTER_IP="${ROUTER_IP:-192.168.1.1}"
ROUTER_PORT="${ROUTER_PORT:-222}"
ROUTER_PASS="${ROUTER_PASS:-keenetic}"
AWG_CLIENT_CONF="${AWG_CLIENT_CONF:-}"  # Путь к клиентскому конфигу
AWG_CLIENT_IP="${AWG_CLIENT_IP:-10.8.1.2}"

SSH_CMD="sshpass -p '$ROUTER_PASS' ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -p $ROUTER_PORT root@$ROUTER_IP"

ssh_exec() {
    eval "$SSH_CMD '$1'" 2>&1
}

ndmc_exec() {
    ssh_exec "ndmc -c \"$1\"" 2>&1
}

# --- Проверка подключения ---
check_connection() {
    log "Проверка подключения к роутеру $ROUTER_IP:$ROUTER_PORT..."
    if ! ssh_exec "echo ok" | grep -q "ok"; then
        err "Не удалось подключиться к роутеру"
        err "Проверьте: IP ($ROUTER_IP), порт ($ROUTER_PORT), пароль, SSH включён"
        return 1
    fi
    log "Подключение OK"
}

# --- Проверка и установка Entware ---
check_entware() {
    log "Проверка Entware..."
    if ssh_exec "test -f /opt/bin/opkg && echo yes" | grep -q "yes"; then
        log "Entware установлен"
        return 0
    fi

    warn "Entware не установлен"
    # Проверить USB
    if ! ssh_exec "mount | grep /tmp/mnt" | grep -q "/tmp/mnt"; then
        err "USB-накопитель не найден. Подключите USB и установите Entware:"
        err "  https://help.keenetic.com/hc/ru/articles/360021214160"
        return 1
    fi

    log "USB найден, устанавливаю Entware..."
    ndmc_exec "opkg disk $(ssh_exec 'ls /tmp/mnt/' | head -1):"
    sleep 5
    ndmc_exec "opkg initrc /opt/etc/init.d/rc.unslung"
    sleep 3

    if ssh_exec "test -f /opt/bin/opkg && echo yes" | grep -q "yes"; then
        log "Entware установлен"
    else
        err "Не удалось установить Entware автоматически"
        return 1
    fi
}

# --- Определение архитектуры ---
detect_arch() {
    local arch
    arch=$(ssh_exec "uname -m" | tr -d '[:space:]')
    case "$arch" in
        mipsel|mips) echo "${arch}el" ;; # normalize
        aarch64) echo "aarch64" ;;
        *) echo "$arch" ;;
    esac
}

# --- Установка AWG-Go ---
install_awg_go() {
    log "Проверка AWG-Go..."
    if ssh_exec "opkg list-installed 2>/dev/null | grep amneziawg-go" | grep -q "amneziawg-go"; then
        log "AWG-Go уже установлен"
        return 0
    fi

    local arch
    arch=$(detect_arch)
    log "Архитектура: $arch"

    local pkg_suffix
    case "$arch" in
        mipsel|mips*) pkg_suffix="mipsel-3.4" ;;
        aarch64) pkg_suffix="aarch64-3.10" ;;
        *) err "Неподдерживаемая архитектура: $arch"; return 1 ;;
    esac

    local gitlab_base="https://gitlab.com/ShidlaSGC/keenetic-entware-awg-go/-/raw/main/blob/01__Entware_AWG-Go_Install"

    log "Скачиваю пакеты для $pkg_suffix..."
    ssh_exec "mkdir -p /opt/root/awg2-go && cd /opt/root/awg2-go && \
        curl -sLOf '${gitlab_base}/amneziawg-tools_1.0.20250903-2_${pkg_suffix}.ipk' && \
        curl -sLOf '${gitlab_base}/amneziawg-go_v0.2.16-1_${pkg_suffix}.ipk'"

    log "Устанавливаю AWG-Go..."
    ssh_exec "opkg update 2>/dev/null; \
        opkg install /opt/root/awg2-go/amneziawg-tools*.ipk 2>&1; \
        opkg install /opt/root/awg2-go/amneziawg-go*.ipk 2>&1"

    if ssh_exec "which awg" | grep -q "awg"; then
        log "AWG-Go установлен"
    else
        err "Не удалось установить AWG-Go"
        return 1
    fi
}

# --- Настройка OpkgTun0 ---
setup_opkgtun() {
    log "Настройка OpkgTun0..."

    # Проверка существования
    if ndmc_exec "show interface OpkgTun0" | grep -q "interface-name: OpkgTun0"; then
        log "OpkgTun0 уже существует"
    else
        log "Создаю интерфейс OpkgTun0..."
        ndmc_exec "interface OpkgTun0"
        ndmc_exec "interface OpkgTun0 description AWG-Go"
        ndmc_exec "interface OpkgTun0 ip global auto"
    fi

    ndmc_exec "interface OpkgTun0 ip address $AWG_CLIENT_IP 255.255.255.255"
    ndmc_exec "interface OpkgTun0 ip mtu 1376"
    ndmc_exec "interface OpkgTun0 ip tcp adjust-mss pmtu"
    ndmc_exec "interface OpkgTun0 up"
    ndmc_exec "system configuration save"

    log "OpkgTun0 настроен (IP: $AWG_CLIENT_IP)"
}

# --- Конфиг и автозапуск ---
setup_awg_config() {
    log "Загрузка конфига AWG..."

    if [[ -z "$AWG_CLIENT_CONF" || ! -f "$AWG_CLIENT_CONF" ]]; then
        err "Клиентский конфиг не найден: $AWG_CLIENT_CONF"
        return 1
    fi

    # Создать директорию и загрузить конфиг
    ssh_exec "mkdir -p /opt/etc/amnezia/amneziawg"

    # Передать конфиг через stdin
    cat "$AWG_CLIENT_CONF" | eval "$SSH_CMD 'cat > /opt/etc/amnezia/amneziawg/awg0-opkgtun0.conf'"
    ssh_exec "chmod 600 /opt/etc/amnezia/amneziawg/awg0-opkgtun0.conf"

    # Скачать init.d скрипт
    log "Скачиваю скрипт запуска..."
    ssh_exec "cd /opt/etc/init.d/ && \
        curl -sLOf 'https://gitlab.com/ShidlaSGC/keenetic-entware-awg-go/-/raw/main/blob/02__KeenOS_5.0_(OpkgTun)/S52awg-opkgtun0' && \
        chmod +x S52awg-opkgtun0"

    # Запуск
    log "Запускаю AWG..."
    ssh_exec "/opt/etc/init.d/S52awg-opkgtun0 restart 2>&1" || true
    sleep 3

    # Проверка
    local status
    status=$(ssh_exec "awg show 2>&1")
    if echo "$status" | grep -q "latest handshake"; then
        log "AWG подключён, handshake OK"
    else
        warn "AWG запущен, но handshake ещё не прошёл (может нужно подождать)"
    fi
}

# --- DNS маршруты ---
setup_dns_routes() {
    echo ""
    log "Настройка DNS-маршрутов для разблокировки"
    echo ""
    echo "  Какие сервисы разблокировать через AWG?"
    echo "   1) YouTube"
    echo "   2) Instagram"
    echo "   3) Facebook"
    echo "   4) Telegram"
    echo "   5) WhatsApp"
    echo "   6) Twitter/X"
    echo "   7) Discord"
    echo "   8) Reddit"
    echo "   9) Spotify"
    echo "  10) Все"
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
        [6]="twitter"
        [7]="discord"
        [8]="reddit"
        [9]="spotify"
    )

    local services=()
    if [[ "$SELECTED" == "10" ]]; then
        services=(youtube instagram facebook telegram whatsapp twitter discord reddit spotify)
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
        ndmc_exec "dns-proxy route object-group $group_name OpkgTun0 auto reject"
    done

    ndmc_exec "system configuration save"
    log "DNS-маршруты настроены для: ${services[*]}"
}

# --- Главная функция ---
main() {
    log "=========================================="
    log "  Настройка роутера Keenetic"
    log "=========================================="

    check_connection || return 1
    check_entware || return 1
    install_awg_go || return 1
    setup_opkgtun || return 1
    setup_awg_config || return 1
    setup_dns_routes

    log "=========================================="
    log "  Роутер настроен!"
    log "=========================================="
}

main "$@"
