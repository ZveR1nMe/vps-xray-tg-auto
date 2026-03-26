# AmneziaWG 2.0 + Автонастройка роутера Keenetic

**Дата:** 2026-03-27
**Статус:** Утверждён (v2 — после ревью)

---

## 1. Цель

Расширить скрипт `setup.sh` и Telegram-бот для поддержки AmneziaWG 2.0 параллельно с VLESS Reality, включая автоматическую настройку роутера Keenetic через SSH.

## 2. Серверная часть (setup.sh)

### 2.1 Режим установки

При запуске пользователь выбирает:
```
1) Только VLESS Reality
2) Только AmneziaWG 2.0
3) VLESS + AmneziaWG (оба)
```

Выбор сохраняется в `.env` как `INSTALL_MODE=vless|awg|both`. Бот использует эту переменную, чтобы скрывать недоступные типы ключей (например, при режиме "только VLESS" кнопки AWG не показываются).

### 2.2 Установка AmneziaWG на сервер

Последовательность:
1. Добавление PPA: `ppa:amnezia/ppa`
2. Установка пакетов: `amneziawg amneziawg-dkms amneziawg-tools`
3. Генерация серверных ключей: `awg genkey`, `awg pubkey`
4. Генерация параметров обфускации (фиксированные безопасные значения):
   - `Jc` = 4 (junk packet count, диапазон 1-128)
   - `Jmin` = 40 (min junk size, диапазон 0-1280)
   - `Jmax` = 70 (max junk size, диапазон Jmin-1280)
   - `S1` = 52 (init padding, диапазон 0-1280)
   - `S2` = 52 (response padding, диапазон 0-1280)
   - `H1` = 1, `H2` = 2, `H3` = 3, `H4` = 4 (header constants, диапазон 1-2147483647)
5. Автоматическое определение сетевого интерфейса: `ip route show default | awk '{print $5}'` (не хардкод eth0)
6. Генерация случайного UDP-порта: диапазон 10000-60000
7. Создание конфига `/etc/amneziawg/awg0.conf` (см. шаблон в разделе 2.3)
8. IP forwarding: проверяет наличие в `/etc/sysctl.d/99-vps.conf`, добавляет только если отсутствует
9. Открытие UDP-порта в UFW
10. Создание systemd-сервиса `awg-quick@awg0` для автозапуска
11. Запуск и проверка: `awg show`

### 2.3 Шаблон серверного конфига awg0.conf

```ini
[Interface]
PrivateKey = <SERVER_PRIVATE_KEY>
Address = 10.8.1.1/24
ListenPort = <AWG_PORT>
PostUp = iptables -A FORWARD -i awg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o <NET_IFACE> -j MASQUERADE
PostDown = iptables -D FORWARD -i awg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o <NET_IFACE> -j MASQUERADE
Jc = 4
Jmin = 40
Jmax = 70
S1 = 52
S2 = 52
H1 = 1
H2 = 2
H3 = 3
H4 = 4

# Peers добавляются ботом через awg_manager.py
```

### 2.4 Настройка роутера (после установки AWG)

После успешной установки скрипт спрашивает:
```
Настроить роутер Keenetic автоматически? (y/n)
```

Если да, запрашивает:
- IP роутера (по умолчанию 192.168.1.1)
- SSH порт Entware (по умолчанию 222)
- Пароль SSH (по умолчанию keenetic)

Проверяет SSH-подключение (timeout 10s). Если не удалось — выводит ошибку с рекомендациями (проверить IP, порт, пароль, включён ли SSH на роутере) и завершает секцию роутера без аварийной остановки всего скрипта. Сервер остаётся настроенным.

Подключается по SSH и выполняет последовательность из раздела 4.

## 3. Telegram-бот

### 3.1 Source of Truth

**`users.json`** — единый источник истины для метаданных пользователей (имена, какие ключи есть, даты создания).

**Рабочие конфиги** (`xray-config.json`, `awg0.conf`) — source of truth для параметров подключения. Менеджеры (`xray_manager.py`, `awg_manager.py`) управляют своими конфигами напрямую.

**`user_store.py`** — координатор. При добавлении ключа:
1. Вызывает соответствующий менеджер (xray_manager или awg_manager) для создания записи в рабочем конфиге
2. Сохраняет метаданные в `users.json`

При удалении — обратный порядок. При рассинхронизации — `users.json` перегенерируется из рабочих конфигов.

### 3.2 Единый список пользователей

Главное меню:
```
[Пользователи]  [Статус]
[Сеть]          [Помощь]
```

Список пользователей:
```
👤 Вася
👤 Петя
👤 Роутер
[+ Добавить]
```

### 3.3 Карточка пользователя

При нажатии на пользователя:
```
👤 Вася

Ключи:
✅ VLESS Reality
✅ AmneziaWG
✅ AWG Роутер

[+ Добавить ключ]  [🗑 Удалить пользователя]
```

Callback patterns:
- `user:{name}` — открыть карточку
- `user_key:{name}:{type}` — показать конфиг ключа
- `add_key:{name}:{type}` — добавить ключ
- `del_key:{name}:{type}` — удалить ключ
- `del_user:{name}` — удалить пользователя со всеми ключами

### 3.4 Добавление ключа

Меню выбора типа (показываются только доступные — не созданные + разрешённые INSTALL_MODE):
```
Какой ключ добавить для Вася?

[VLESS Reality]
[AmneziaWG (мобильный)]
[AmneziaWG (роутер)]
```

После выбора:
- **VLESS Reality** — генерит UUID через xray_manager, отправляет vless:// ссылку + QR + Happ routing link
- **AmneziaWG (мобильный)** — генерит ключи через awg_manager, отправляет .conf файл + QR-код (если конфиг помещается в QR, иначе только файл)
- **AmneziaWG (роутер)** — генерит ключи через awg_manager, отправляет OpkgTun-версию конфига файлом (только генерация конфига, без SSH-подключения к роутеру)

### 3.5 Шаблон клиентского AWG-конфига (мобильный)

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = <CLIENT_IP>/32
DNS = 1.1.1.1, 8.8.8.8
Jc = 4
Jmin = 40
Jmax = 70
S1 = 52
S2 = 52
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
PresharedKey = <PSK>
Endpoint = <SERVER_IP>:<AWG_PORT>
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### 3.6 Шаблон клиентского AWG-конфига (роутер / OpkgTun)

Отличие от мобильного: **нет Address и DNS** (задаются через ndmc на роутере).

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Jc = 4
Jmin = 40
Jmax = 70
S1 = 52
S2 = 52
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
PresharedKey = <PSK>
Endpoint = <SERVER_IP>:<AWG_PORT>
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### 3.7 Просмотр существующего ключа

При нажатии на существующий ключ — повторно отправляет конфиг/ссылку/QR.

### 3.8 Удаление

- **Удалить отдельный ключ** — удаляет ключ из users.json + peer/client из рабочего конфига
- **Удалить пользователя** — удаляет все ключи (из обоих конфигов) и запись из users.json

### 3.9 Хранение данных

Файл `/opt/vps-setup/users.json`:
```json
{
  "Вася": {
    "vless": {
      "uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "created": "2026-03-27T10:00:00"
    },
    "awg": {
      "private_key": "...",
      "public_key": "...",
      "psk": "...",
      "ip": "10.8.1.2",
      "created": "2026-03-27T10:05:00"
    },
    "awg_router": {
      "private_key": "...",
      "public_key": "...",
      "psk": "...",
      "ip": "10.8.1.3",
      "created": "2026-03-27T10:10:00"
    }
  }
}
```

IP-адреса AWG-клиентов назначаются автоинкрементом из подсети 10.8.1.0/24 (начиная с 10.8.1.2, максимум 253 клиента). При удалении клиента IP не переиспользуется (следующий свободный).

Конкурентный доступ: файл пишется атомарно (запись во временный файл + rename). Бот однопоточный по обработке callback — гонок не будет.

### 3.10 Миграция существующих пользователей

При первом запуске обновлённого бота, если `users.json` не существует:
1. Читает clients из xray config через xray_manager
2. Создаёт users.json с записями `{email: {vless: {uuid, created}}}`
3. Существующие пользователи не теряются

### 3.11 Обновление deps.py

Добавить в `deps.py`:
- `awg_mgr: AwgManager` — менеджер AWG (создаётся только если INSTALL_MODE содержит awg)
- `user_store: UserStore` — хранилище пользователей

### 3.12 Новый сервис awg_manager.py

Аналог `xray_manager.py`:
- Чтение/запись `/etc/amneziawg/awg0.conf` (парсинг INI-подобного формата WireGuard)
- `add_peer(name, peer_type)` — генерит ключи (`awg genkey/pubkey/genpsk`), добавляет [Peer] секцию, перезапускает AWG, возвращает клиентский конфиг
- `delete_peer(public_key)` — удаляет [Peer] по PublicKey, перезапускает AWG
- `get_config(name, peer_type)` — формирует клиентский конфиг из сохранённых данных
- `list_peers()` — парсит вывод `awg show` для трафика и handshake

### 3.13 Новый сервис user_store.py

- `load()` / `save()` — чтение/запись users.json (атомарная запись)
- `add_user(name)` — создаёт пустую запись
- `add_key(name, key_type, data)` — добавляет ключ пользователю
- `delete_key(name, key_type)` — удаляет ключ
- `delete_user(name)` — удаляет пользователя
- `get_user(name)` — возвращает данные пользователя
- `list_users()` — список всех пользователей
- `next_awg_ip()` — следующий свободный IP из 10.8.1.0/24
- `migrate_from_xray(xray_mgr)` — миграция при первом запуске

## 4. Скрипт настройки роутера Keenetic

### 4.1 Подключение

Скрипт подключается к роутеру через SSH (`sshpass -p <pass> ssh -p <port> root@<ip>`).

Обработка ошибок:
- Timeout 10 секунд на подключение
- При ошибке — выводит сообщение и предлагает повторить или пропустить
- Каждый шаг проверяет успешность предыдущего

### 4.2 Идемпотентность

Перед каждым шагом проверяется, не выполнен ли он уже:
- Entware: `test -f /opt/bin/opkg`
- AWG-Go: `opkg list-installed | grep amneziawg-go`
- OpkgTun0: `ndmc -c "show interface OpkgTun0"` — проверка exists
- Конфиг: `test -f /opt/etc/amnezia/amneziawg/awg0-opkgtun0.conf`

Повторный запуск скрипта не ломает существующую настройку.

### 4.3 Проверка и установка Entware

1. Проверка: `test -f /opt/bin/opkg`
2. Если нет — проверяет USB-накопитель через `mount | grep /tmp/mnt`
3. Если USB есть — устанавливает Entware через ndmc
4. Если USB нет — выводит инструкцию как подключить USB и установить Entware, завершает секцию роутера

### 4.4 Определение архитектуры

Команда `uname -m`:
- `mipsel` → пакеты mipsel-3.4
- `aarch64` → пакеты aarch64-3.10
- `mips` → пакеты mips-3.4

### 4.5 Установка AWG-Go

1. Скачивание `.ipk` пакетов из GitLab:
   - `https://gitlab.com/ShidlaSGC/keenetic-entware-awg-go/-/raw/main/blob/01__Entware_AWG-Go_Install/amneziawg-tools_<version>_<arch>.ipk`
   - `https://gitlab.com/ShidlaSGC/keenetic-entware-awg-go/-/raw/main/blob/01__Entware_AWG-Go_Install/amneziawg-go_<version>_<arch>.ipk`
2. `opkg install amneziawg-tools*.ipk`
3. `opkg install amneziawg-go*.ipk`

### 4.6 Настройка OpkgTun0

Через ndmc (только если интерфейс ещё не создан):
```
interface OpkgTun0
interface OpkgTun0 description AWG-Go
interface OpkgTun0 ip global auto
interface OpkgTun0 ip address <CLIENT_IP> 255.255.255.255
interface OpkgTun0 ip mtu 1376
interface OpkgTun0 ip tcp adjust-mss pmtu
interface OpkgTun0 up
system configuration save
```

### 4.7 Конфиг и автозапуск

1. Генерация клиентского конфига (OpkgTun-версия без Address/DNS) → `/opt/etc/amnezia/amneziawg/awg0-opkgtun0.conf`
2. Скачивание init.d скрипта S52awg-opkgtun0:
   `https://gitlab.com/ShidlaSGC/keenetic-entware-awg-go/-/raw/main/blob/02__KeenOS_5.0_(OpkgTun)/S52awg-opkgtun0`
3. Запуск: `/opt/etc/init.d/S52awg-opkgtun0 start`
4. Проверка: `awg show` — наличие handshake
5. Проверка IP через туннель: `curl --interface awg0 http://myip.wtf/text`

### 4.8 DNS-маршруты (интерактивный выбор)

Скрипт показывает меню:
```
Какие сервисы разблокировать через AWG?
 1) YouTube
 2) Instagram
 3) Facebook
 4) Telegram
 5) WhatsApp
 6) Twitter/X
 7) Discord
 8) Reddit
 9) Spotify
10) Все
 0) Пропустить

Введите номера через пробел (например: 1 2 4):
```

Для каждого выбранного сервиса:
1. Создаёт `object-group fqdn <name>` со списком доменов через ndmc
2. Добавляет правило `dns-proxy route object-group <name> OpkgTun0 auto reject`
3. Сохраняет конфигурацию: `system configuration save`

Списки доменов хранятся в `data/router/dns-lists/*.lst` — один домен на строку, строки с `#` — комментарии.

## 5. Структура файлов

```
setup.sh                              — основной скрипт (расширен)
bot/
  bot.py                              — добавить инициализацию awg_mgr, user_store
  config.py                           — добавить AWG_PORT, INSTALL_MODE, AWG_*
  deps.py                             — добавить awg_mgr, user_store
  handlers/
    users.py                          — рефакторинг: единый список + выбор ключей
  services/
    xray_manager.py                   — минимальные изменения (адаптация интерфейса)
    awg_manager.py                    — менеджер AWG конфигов (новый)
    user_store.py                     — хранилище users.json (новый)
data/
  router/
    keenetic.sh                       — функции настройки Keenetic (новый)
    dns-lists/
      youtube.lst
      instagram.lst
      facebook.lst
      telegram.lst
      whatsapp.lst
      twitter.lst
      discord.lst
      reddit.lst
      spotify.lst
```

Архитектура расширяемая: для нового роутера добавляется файл в `data/router/` (например `openwrt.sh`).

## 6. Фазы реализации

Проект разбит на 4 фазы, каждая приносит рабочий результат:

### Фаза 1: Серверная часть AWG
- Добавить установку AWG в setup.sh (выбор режима, PPA, конфиг, systemd)
- Создать awg_manager.py
- Результат: AWG сервер работает, можно добавлять peers вручную

### Фаза 2: Рефакторинг бота
- Создать user_store.py + users.json
- Рефакторинг users.py (единый список, карточки, типы ключей)
- Обновить deps.py, config.py, bot.py
- Миграция существующих VLESS-пользователей
- Результат: бот управляет и VLESS, и AWG клиентами

### Фаза 3: Скрипт настройки Keenetic
- Создать data/router/keenetic.sh
- Интегрировать в setup.sh (вопрос после установки AWG)
- Entware, AWG-Go, OpkgTun0, конфиг, автозапуск
- Результат: роутер автоматически настраивается одной командой

### Фаза 4: DNS-маршруты
- Создать файлы dns-lists/*.lst
- Интерактивное меню выбора сервисов
- Добавление fqdn object-groups и правил маршрутизации через ndmc
- Результат: заблокированные сайты работают через туннель

## 7. Ограничения и допущения

- Ubuntu 22.04/24.04 на сервере (PPA amnezia)
- Keenetic с KeenOS 5.0+ (OpkgTun)
- USB-накопитель на роутере для Entware
- SSH-доступ к Entware на роутере (порт 222)
- Подсеть AWG: 10.8.1.0/24, максимум 253 клиента
- AWG-Go (userspace) на роутере, amneziawg-dkms (kernel) на сервере
- При режиме "Только VLESS" порт 443/tcp открывается, AWG UDP-порт не нужен
- При режиме "Только AWG" порт 443/tcp не открывается
