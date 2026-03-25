# vps-xray-tg-auto

Автоматическая настройка VPS: **Xray VLESS + Reality** с управлением через **Telegram-бота**.

Одна команда — и у тебя рабочий VPN с ботом для добавления друзей.

## Что делает

- Устанавливает **Xray** (VLESS + Reality) — лучший протокол для обхода блокировок
- Настраивает **BBR**, оптимизирует TCP буферы для максимальной скорости
- Разворачивает **Telegram-бота** для управления пользователями
- Настраивает **UFW**, **fail2ban**, SSH hardening
- Создаёт **SOCKS5 прокси** для Telegram
- Скачивает **geo-файлы** для РФ

## Установка

### 1. Подготовка

- Ubuntu VPS (22.04 / 24.04)
- Telegram-бот: создай через [@BotFather](https://t.me/BotFather) → `/newbot` → скопируй токен
- Свой Chat ID: напиши [@userinfobot](https://t.me/userinfobot)

### 2. Запуск

Подключись к серверу по SSH и выполни:

```bash
bash <(curl -sL https://raw.githubusercontent.com/ZveR1nMe/vps-xray-tg-auto/main/setup.sh)
```

Скрипт спросит:
- **Bot Token** — токен от BotFather
- **Chat ID** — твой ID из userinfobot

Всё остальное автоматически: обновление системы, установка xray, генерация ключей, деплой бота.

### 3. Готово

После установки бот пришлёт сообщение в Telegram. Напиши ему `/start`.

## Telegram-бот

| Кнопка | Что делает |
|--------|-----------|
| **Пользователи** | Список, добавить, удалить. QR-код + ссылка + прокси для Telegram |
| **Статус** | CPU, RAM, диск, uptime, статус xray |
| **Сеть** | Пинг до Google DNS, Cloudflare |
| **Советы** | Список клиентов для подключения |

## Добавление друга

1. В боте: **Пользователи** → **Добавить** → ввести имя
2. Бот отправит QR-код + vless:// ссылку + прокси для Telegram
3. Перешли сообщение другу
4. Друг сканирует QR или копирует ссылку в клиент

## Клиенты для подключения

| Платформа | Клиент |
|-----------|--------|
| Android | [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid/releases), [v2rayNG](https://github.com/2dust/v2rayNG/releases) |
| iOS | [Streisand](https://apps.apple.com/app/streisand/id6450534064), [V2Box](https://apps.apple.com/app/v2box-v2ray-client/id6446814690) |
| Windows | [v2rayN](https://github.com/2dust/v2rayN/releases), [Nekoray](https://github.com/MatsuriDayo/nekoray/releases) |
| macOS | [V2Box](https://apps.apple.com/app/v2box-v2ray-client/id6446814690) |

## Архитектура

```
Клиент (v2rayNG и др.)
    ↓ VLESS + Reality (порт 443)
Xray на VPS
    ↓
Интернет

Telegram
    ↓ SOCKS5 прокси (случайный порт)
Xray на VPS
    ↓
Интернет
```

- **Xray** — обрабатывает VPN и SOCKS5 прокси
- **Telegram-бот** — управляет xray конфигом напрямую (JSON файл)
- **Без панелей** (3X-UI и т.д.) — минимум кода, максимум надёжности

## Технологии

- [Xray-core](https://github.com/xtls/xray-core) — VLESS + Reality
- [russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — geo-файлы для РФ
- Python 3 + [aiogram 3](https://github.com/aiogram/aiogram) — Telegram-бот
- BBR + оптимизированные TCP буферы — максимальная скорость
