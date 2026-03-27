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

# --- Определение модели и характеристик роутера ---
detect_router() {
    log "Определение модели роутера..."

    ROUTER_MODEL=$(ndmc_exec "show version" | grep "device:" | awk '{print $2}' | tr -d '[:space:]')
    ROUTER_HW_ID=$(ndmc_exec "show version" | grep "hw_id:" | awk '{print $2}' | tr -d '[:space:]')
    ROUTER_FW=$(ndmc_exec "show version" | grep "title:" | awk '{print $2}' | tr -d '[:space:]')
    ROUTER_ARCH=$(ssh_exec "uname -m" | tr -d '[:space:]')
    ROUTER_SOC=$(ssh_exec "cat /proc/cpuinfo 2>/dev/null | grep 'system type' | head -1 | cut -d: -f2" | tr -d '[:space:]')
    ROUTER_RAM_KB=$(ssh_exec "grep MemTotal /proc/meminfo | awk '{print \$2}'" | tr -d '[:space:]')
    ROUTER_RAM_MB=$((ROUTER_RAM_KB / 1024))

    log "  Модель: $ROUTER_MODEL ($ROUTER_HW_ID)"
    log "  Прошивка: KeeneticOS $ROUTER_FW"
    log "  SoC: $ROUTER_SOC"
    log "  Архитектура: $ROUTER_ARCH"
    log "  RAM: ${ROUTER_RAM_MB} MB"

    # Определение суффикса пакетов
    case "$ROUTER_ARCH" in
        mips|mipsel) AWG_PKG_SUFFIX="mipsel-3.4" ;;
        aarch64)     AWG_PKG_SUFFIX="aarch64-3.10" ;;
        *)
            err "Неподдерживаемая архитектура: $ROUTER_ARCH"
            return 1
            ;;
    esac
    log "  Пакеты: $AWG_PKG_SUFFIX"

    # Проверка внутренней памяти
    INTERNAL_FREE_KB=$(ssh_exec "df /tmp 2>/dev/null | tail -1 | awk '{print \$4}'" | tr -d '[:space:]')
    INTERNAL_FREE_MB=$((INTERNAL_FREE_KB / 1024))
    log "  Внутренняя память (tmpfs): ${INTERNAL_FREE_MB} MB свободно"
}

# --- Проверка и подготовка хранилища ---
setup_storage() {
    log "Проверка хранилища для Entware..."

    # Проверить, есть ли уже Entware
    if ssh_exec "test -f /opt/bin/opkg && echo yes" | grep -q "yes"; then
        local opt_disk
        opt_disk=$(ssh_exec "df /opt 2>/dev/null | tail -1 | awk '{print \$1}'")
        local opt_free
        opt_free=$(ssh_exec "df -h /opt 2>/dev/null | tail -1 | awk '{print \$4}'")
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
            if [[ "${FORMAT_CONFIRM,,}" != "y" ]]; then
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

    # Найти точку монтирования USB
    local usb_id
    usb_id=$(ssh_exec "ls /tmp/mnt/ 2>/dev/null | head -1" | tr -d '[:space:]')

    if [[ -z "$usb_id" ]]; then
        err "USB не смонтирован. Попробуйте перезагрузить роутер с USB и запустить скрипт заново."
        return 1
    fi

    log "  USB ID: $usb_id"
    ndmc_exec "opkg disk ${usb_id}:"
    sleep 5
    ndmc_exec "opkg initrc /opt/etc/init.d/rc.unslung"
    sleep 3

    if ssh_exec "test -f /opt/bin/opkg && echo yes" | grep -q "yes"; then
        log "Entware установлен на USB"
    else
        err "Не удалось установить Entware на USB"
        return 1
    fi
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

# --- Установка AWG-Go ---
install_awg_go() {
    log "Проверка AWG-Go..."
    if ssh_exec "opkg list-installed 2>/dev/null | grep amneziawg-go" | grep -q "amneziawg-go"; then
        local installed_ver
        installed_ver=$(ssh_exec "opkg list-installed 2>/dev/null | grep amneziawg-go" | awk '{print $3}')
        log "AWG-Go уже установлен (версия: $installed_ver)"

        # Проверить наличие обновлений
        _check_awg_updates "$installed_ver"
        return 0
    fi

    # AWG_PKG_SUFFIX определяется в detect_router()
    if [[ -z "${AWG_PKG_SUFFIX:-}" ]]; then
        err "Архитектура не определена (detect_router не был вызван)"
        return 1
    fi

    _download_latest_awg
    _install_awg_packages
}

_get_awg_arch_folder() {
    # Определяет папку в GitLab по архитектуре
    case "$ROUTER_ARCH" in
        mips)    echo "mips_awg-go" ;;
        mipsel)  echo "mipsel_awg-go" ;;
        aarch64) echo "aarch64_awg-go" ;;
        *)       echo "mipsel_awg-go" ;;  # fallback
    esac
}

_download_latest_awg() {
    local arch_folder
    arch_folder=$(_get_awg_arch_folder)

    local gitlab_api="https://gitlab.com/api/v4/projects/ShidlaSGC%2Fkeenetic-entware-awg-go/repository/tree"
    local gitlab_raw="https://gitlab.com/ShidlaSGC/keenetic-entware-awg-go/-/raw/main"

    log "Поиск последних версий AWG-Go для $ROUTER_ARCH..."

    # Получить список файлов из GitLab API
    local file_list
    file_list=$(curl -s "${gitlab_api}?path=blob/01__Entware_AWG-Go_Install/${arch_folder}&per_page=50" 2>/dev/null)

    if [[ -z "$file_list" || "$file_list" == "[]" ]]; then
        warn "Не удалось получить список из GitLab API, использую прямые ссылки"
        _download_awg_fallback
        return
    fi

    # Извлечь имена файлов .ipk
    local tools_file
    tools_file=$(echo "$file_list" | grep -o '"name":"amneziawg-tools[^"]*\.ipk"' | head -1 | cut -d'"' -f4)
    local go_file
    go_file=$(echo "$file_list" | grep -o '"name":"amneziawg-go[^"]*\.ipk"' | head -1 | cut -d'"' -f4)

    if [[ -z "$tools_file" || -z "$go_file" ]]; then
        warn "Не удалось определить файлы пакетов, использую fallback"
        _download_awg_fallback
        return
    fi

    log "  amneziawg-tools: $tools_file"
    log "  amneziawg-go: $go_file"

    local download_path="blob/01__Entware_AWG-Go_Install/${arch_folder}"

    ssh_exec "mkdir -p /opt/root/awg2-go && cd /opt/root/awg2-go && \
        rm -f *.ipk && \
        curl -sLOf '${gitlab_raw}/${download_path}/${tools_file}' && \
        curl -sLOf '${gitlab_raw}/${download_path}/${go_file}'"

    log "Пакеты скачаны (последние версии)"
}

_download_awg_fallback() {
    # Fallback — попробовать скачать с захардкоженными именами
    local gitlab_raw="https://gitlab.com/ShidlaSGC/keenetic-entware-awg-go/-/raw/main/blob/01__Entware_AWG-Go_Install"
    local arch_folder
    arch_folder=$(_get_awg_arch_folder)

    warn "Пробую скачать с fallback URL..."
    ssh_exec "mkdir -p /opt/root/awg2-go && cd /opt/root/awg2-go && \
        rm -f *.ipk && \
        curl -sLOf '${gitlab_raw}/${arch_folder}/amneziawg-tools_1.0.20250903-2_${AWG_PKG_SUFFIX}.ipk' && \
        curl -sLOf '${gitlab_raw}/${arch_folder}/amneziawg-go_v0.2.16-1_${AWG_PKG_SUFFIX}.ipk'"
}

_install_awg_packages() {
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

_check_awg_updates() {
    local current_ver="${1:-}"
    local arch_folder
    arch_folder=$(_get_awg_arch_folder)

    local gitlab_api="https://gitlab.com/api/v4/projects/ShidlaSGC%2Fkeenetic-entware-awg-go/repository/tree"
    local file_list
    file_list=$(curl -s "${gitlab_api}?path=blob/01__Entware_AWG-Go_Install/${arch_folder}&per_page=50" 2>/dev/null)

    if [[ -z "$file_list" || "$file_list" == "[]" ]]; then
        return 0
    fi

    local latest_go
    latest_go=$(echo "$file_list" | grep -o '"name":"amneziawg-go[^"]*\.ipk"' | head -1 | cut -d'"' -f4)

    if [[ -n "$latest_go" ]]; then
        # Извлечь версию из имени файла (amneziawg-go_v0.2.16-1_xxx.ipk → v0.2.16-1)
        local latest_ver
        latest_ver=$(echo "$latest_go" | sed 's/amneziawg-go_\([^_]*\)_.*/\1/')

        if [[ "$latest_ver" != "$current_ver" && "$latest_ver" != "v$current_ver" ]]; then
            warn "Доступна новая версия AWG-Go: $latest_ver (установлена: $current_ver)"
            echo ""
            read -rp "  Обновить? (y/n): " UPDATE_AWG
            if [[ "${UPDATE_AWG,,}" == "y" ]]; then
                _download_latest_awg
                _install_awg_packages
            fi
        else
            log "AWG-Go актуальная версия"
        fi
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

# --- Очистка ДО установки (убрать конфликты) ---
cleanup_before() {
    log "Проверка конфликтующих сервисов..."
    local cleaned=0

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
        if [[ "${DEL_SS,,}" == "y" ]]; then
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
            if [[ "${DEL_DNS,,}" == "y" ]]; then
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
            if [[ "${DEL_DNSMASQ,,}" == "y" ]]; then
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
        ssh_exec "/opt/etc/init.d/S99magitrickle stop 2>/dev/null" || true
        ssh_exec "rm -f /opt/etc/init.d/S99magitrickle /opt/bin/magitrickled"
        ssh_exec "rm -rf /opt/etc/magitrickle /opt/usr/share/magitrickle /opt/var/lib/magitrickle"
        ssh_exec "rm -f /opt/etc/ndm/netfilter.d/100-magitrickle"
        ssh_exec "rm -f /opt/lib/opkg/lists/magitrickle_*"
        log "MagiTrickle удалён"
        cleaned=$((cleaned + 1))
    fi

    # 6. opkg.conf дубликаты
    local dup_count
    dup_count=$(ssh_exec "grep -c 'src/gz entware' /opt/etc/opkg.conf 2>/dev/null" || echo "0")
    if [[ "$dup_count" -gt 1 ]]; then
        warn "Дубликаты в opkg.conf ($dup_count записей entware) — исправляю"
        ssh_exec "cat > /opt/etc/opkg.conf << 'OPKG'
src/gz entware http://bin.entware.net/mipselsf-k3.4
src/gz keendev http://bin.entware.net/mipselsf-k3.4/keenetic
dest root /
lists_dir ext /opt/var/opkg-lists
arch all 100
arch mipsel-3.4 150
arch mipsel-3.4_kn 200
OPKG"
        log "opkg.conf исправлен"
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
    detect_router || return 1
    cleanup_before
    setup_storage || return 1
    install_awg_go || return 1
    setup_opkgtun || return 1
    setup_awg_config || return 1
    setup_dns_routes
    cleanup_after

    log "=========================================="
    log "  Роутер настроен!"
    log "=========================================="
}

main "$@"
