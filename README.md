# vps-xray-tg-auto

Автоматическая настройка VPS: **VLESS Reality + AmneziaWG 2.0** с управлением через **Telegram-бота** и автонастройкой роутера **Keenetic**.

Одна команда — рабочий VPN с ботом, обход блокировок на всех устройствах и на роутере.

## Что делает

### Сервер (VPS)
- Устанавливает **Xray** (VLESS + Reality) — маскируется под обычный HTTPS
- Устанавливает **AmneziaWG 2.0** — WireGuard с обфускацией, не блокируется DPI
- Выбор режима: только VLESS, только AWG, или оба
- Настраивает **BBR**, оптимизирует TCP буферы (64MB)
- Разворачивает **Telegram-бота** для управления пользователями и ключами
- Настраивает **UFW**, **fail2ban**, SSH hardening
- Автоматически выбирает лучший **DoH DNS** и **SNI**

### Роутер (Keenetic)
- Автоматически определяет модель, архитектуру, RAM
- Устанавливает **Entware** на USB (форматирует при необходимости)
- Устанавливает **AWG-Go** (userspace AmneziaWG) — последняя версия из GitLab
- Настраивает **OpkgTun0** интерфейс с AWG-туннелем
- Тестирует DNS-серверы и настраивает лучший **DoT/DoH**
- Настраивает **DNS-маршруты** для разблокировки сайтов (YouTube, Instagram, Telegram и др.)
- Очищает конфликтующие сервисы и мусор

## Установка

### 1. Подготовка

- **VPS:** Ubuntu 22.04 / 24.04
- **Telegram-бот:** создай через [@BotFather](https://t.me/BotFather) → `/newbot` → скопируй токен
- **Chat ID:** напиши [@userinfobot](https://t.me/userinfobot)
- **Роутер (опционально):** Keenetic с USB-накопителем

### 2. Запуск

```bash
bash <(curl -sL https://raw.githubusercontent.com/ZveR1nMe/vps-xray-tg-auto/main/setup.sh)
```

Скрипт спросит:
1. **Bot Token** и **Chat ID**
2. **Режим установки:** VLESS / AWG / оба
3. **Настроить роутер?** — если да, автоматически подключится и настроит

### 3. Готово

Бот пришлёт сообщение в Telegram. Напиши `/start`.

## Telegram-бот

### Главное меню

| Кнопка | Что делает |
|--------|-----------|
| **Пользователи** | Единый список. Каждый пользователь может иметь несколько ключей |
| **Статус** | CPU, RAM, диск, uptime, статус xray и AWG |
| **Сеть** | Пинг до Google DNS, Cloudflare |
| **Советы** | Инструкция по подключению |

### Управление пользователями

```
Пользователи → 👤 Вася → Карточка пользователя

Ключи:
  ✅ VLESS Reality
  ✅ AmneziaWG
  ✅ AWG Роутер

[+ Добавить ключ]  [🗑 Удалить]
```

**Типы ключей:**

| Тип | Для чего | Что отправляет бот |
|-----|----------|-------------------|
| **VLESS Reality** | Мобильные/ПК через Happ | QR + vless:// ссылка + Happ роутинг |
| **AmneziaWG** | Мобильные через AmneziaVPN | .conf файл + QR |
| **AWG Роутер** | Keenetic через OpkgTun | .conf файл (без Address/DNS) |

## Настройка роутера Keenetic

Скрипт автоматически:

1. **Сканирует порты** — SSH:222 (Entware) или Telnet:23 (Admin CLI)
2. **Определяет модель** — Viva, Ultra, Giant и др., SoC, RAM, архитектура
3. **Чистит конфликты** — удаляет dnscrypt-proxy, MagiTrickle, старые AWG, дубликаты opkg
4. **Готовит USB** — форматирует в ext4 при необходимости
5. **Ставит Entware** — если не установлен
6. **Ставит AWG-Go** — определяет последнюю версию из GitLab, выбирает пакет под архитектуру
7. **Настраивает OpkgTun0** — интерфейс с AWG-туннелем
8. **Тестирует DNS** — пингует 7 провайдеров (Cloudflare, Google, Yandex, AdGuard, Quad9, NextDNS), рекомендует лучший
9. **DNS-маршруты** — выбор сервисов для разблокировки:
   - YouTube, Instagram, Facebook, Telegram, WhatsApp, Twitter/X, Discord, Reddit, Spotify

### Поддерживаемые роутеры

Keenetic с USB-портом и KeenOS 5.0+. Протестировано на Keenetic Viva (KN-1913, MT7621, mipsel).

### Ручной запуск (без VPS)

```bash
export ROUTER_IP="192.168.1.1"
export AWG_CLIENT_CONF="/path/to/awg-client.conf"
export AWG_CLIENT_IP="10.8.1.2"
bash data/router/keenetic.sh
```

## Добавление друга

1. В боте: **Пользователи** → **Добавить** → ввести имя
2. Нажать на пользователя → **Добавить ключ** → выбрать тип
3. Бот отправит конфиг — переслать другу

### VLESS (для Happ)
1. Скачать **Happ** → ссылки в сообщении
2. Скопировать `vless://` ссылку → в Happ: **Добавить** → вставить
3. Открыть `happ://routing/` ссылку → импортирует split-tunnel
4. Подключиться ▶

### AmneziaWG (для мобильных)
1. Скачать **AmneziaVPN** → [amnezia.org](https://amnezia.org)
2. Импортировать .conf файл или отсканировать QR
3. Подключиться ▶

## Рекомендуемые клиенты

| Протокол | Клиент | Платформы |
|----------|--------|-----------|
| VLESS | [Happ](https://github.com/Happ-proxy/happ-desktop) | iOS, Android, macOS, Windows |
| AmneziaWG | [AmneziaVPN](https://amnezia.org) | iOS, Android, macOS, Windows, Linux |

<details>
<summary>Альтернативные клиенты VLESS</summary>

| Платформа | Клиент |
|-----------|--------|
| Android | [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid/releases) |
| iOS | [Streisand](https://apps.apple.com/app/streisand/id6450534064) |
| Windows / Linux | [Nekoray](https://github.com/MatsuriDayo/nekoray/releases) |

</details>

## Архитектура

```
                    ┌─────────────────────────────┐
                    │         VPS (Ubuntu)         │
                    │                              │
Happ ──VLESS:443──▶ │  Xray (VLESS Reality)       │
                    │                              │
AmneziaVPN ──UDP──▶ │  AmneziaWG (awg0)           │──▶ Интернет
                    │                              │
Telegram ──SOCKS──▶ │  Xray (SOCKS5 proxy)        │
                    │                              │
                    │  Telegram Bot (aiogram)      │
                    └─────────────────────────────┘

                    ┌─────────────────────────────┐
                    │    Keenetic Router           │
                    │                              │
Все устройства ───▶ │  AWG-Go (OpkgTun0) ────────▶│──▶ VPS AWG
  в домашней сети   │                              │
                    │  DNS-маршруты:               │
                    │  YouTube, Instagram и др.    │──▶ через AWG
                    │  Остальное                   │──▶ напрямую
                    └─────────────────────────────┘
```

## Структура проекта

```
setup.sh                        — установка VPS (VLESS + AWG + бот)
bot/
  bot.py                        — точка входа, инициализация
  config.py                     — конфигурация из .env
  deps.py                       — глобальные зависимости
  handlers/
    start.py                    — главное меню
    users.py                    — управление пользователями и ключами
    status.py                   — мониторинг сервера
    network.py                  — сетевая диагностика
    tips.py                     — инструкции
  services/
    xray_manager.py             — управление VLESS клиентами
    awg_manager.py              — управление AWG peers
    user_store.py               — единое хранилище users.json
    monitor.py                  — фоновый мониторинг
data/
  router/
    keenetic.sh                 — автонастройка роутера Keenetic
    dns-lists/                  — списки доменов для разблокировки
      youtube.lst, instagram.lst, telegram.lst, ...
```

## Оптимизация сети

Скрипт автоматически применяет:

- **BBR** — congestion control для максимальной пропускной способности
- **TCP буферы 64MB** — запас для всплесков трафика
- **tcp_slow_start_after_idle = 0** — скорость не падает после паузы
- **MTU probing** — избегает фрагментации пакетов
- **tcp_notsent_lowat = 128KB** — улучшает отзывчивость
- **tcp_fastopen = 3** — ускоряет установку соединений

## Технологии

- [Xray-core](https://github.com/xtls/xray-core) — VLESS + Reality
- [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module) — WireGuard с обфускацией
- [AWG-Go](https://gitlab.com/ShidlaSGC/keenetic-entware-awg-go) — userspace AWG для роутеров
- [Happ](https://github.com/Happ-proxy/happ-desktop) — клиент с поддержкой роутинга
- [AmneziaVPN](https://amnezia.org) — клиент для AWG
- [russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — geo-файлы для РФ
- Python 3 + [aiogram 3](https://github.com/aiogram/aiogram) — Telegram-бот
