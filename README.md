# vps-xray-tg-auto

Автоматическая настройка VPS: **Xray VLESS + Reality** с управлением через **Telegram-бота**.

Одна команда — и у тебя рабочий VPN с ботом для добавления друзей.

## Что делает

- Устанавливает **Xray** (VLESS + Reality) — лучший протокол для обхода блокировок
- Настраивает **BBR**, оптимизирует TCP буферы (64MB) для стабильной скорости
- Разворачивает **Telegram-бота** для управления пользователями
- Генерирует **профиль роутинга для Happ** — split-tunnel, российские сайты напрямую
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
| **Пользователи** | Список, добавить, удалить. QR-код + vless-ссылка + роутинг + ссылки на скачивание |
| **Статус** | CPU, RAM, диск, uptime, статус xray |
| **Сеть** | Пинг до Google DNS, Cloudflare |
| **Советы** | Инструкция по подключению через Happ |

## Добавление друга

1. В боте: **Пользователи** → **Добавить** → ввести имя
2. Бот отправит:
   - QR-код + `vless://` ссылка для подключения
   - `happ://routing/add/` ссылка для split-tunnel роутинга
   - Ссылки на скачивание Happ (iOS, Android, macOS, Windows)
   - Прокси для Telegram
3. Перешли сообщения другу — всё в тексте, кнопки не нужны

### Как подключиться (для друга)

1. Скачать **Happ** → ссылки в сообщении от бота
2. Скопировать `vless://` ссылку → в Happ: **Добавить** → вставить из буфера
3. Скопировать `happ://routing/` ссылку → открыть в браузере → Happ импортирует роутинг
4. Подключиться ▶

> Российские сайты (Яндекс, ВК, Госуслуги и др.) идут напрямую.
> Заблокированные — через VPN. Реклама блокируется.

## Рекомендуемый клиент — Happ

| Платформа | Ссылка |
|-----------|--------|
| iOS | [App Store RU](https://apps.apple.com/ru/app/happ-proxy-utility-plus/id6746188973) |
| Android | [APK](https://github.com/Happ-proxy/happ-android/releases/latest/download/Happ.apk) |
| macOS | [DMG](https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.macOS.universal.dmg) |
| Windows | [EXE](https://github.com/Happ-proxy/happ-desktop/releases/latest/download/setup-Happ.x64.exe) |

<details>
<summary>Другие клиенты</summary>

| Платформа | Клиент |
|-----------|--------|
| Android | [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid/releases) |
| iOS | [Streisand](https://apps.apple.com/app/streisand/id6450534064) |
| Windows / Linux | [Nekoray](https://github.com/MatsuriDayo/nekoray/releases) |

> Другие клиенты не поддерживают импорт роутинга через `happ://` ссылку — маршрутизацию нужно настраивать вручную.

</details>

## Настройки Happ

После импорта ссылок рекомендуемые настройки:

| Параметр | Значение |
|----------|----------|
| Правила маршрутизации | VPS Split-Tunnel RU |
| Системный прокси | Вкл |
| TUN | Вкл (для полного перехвата трафика) |
| Мультиплексор | Вкл (стабилизирует скорость) |
| TCP / XUDP соединения | 8 / 8 |
| Фрагментация | Выкл |

## Архитектура

```
Клиент (Happ)
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
- **Split-tunnel роутинг** — генерируется как `happ://routing/add/` deep link
- **Без панелей** (3X-UI и т.д.) — минимум кода, максимум надёжности

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
- [Happ](https://github.com/Happ-proxy/happ-desktop) — рекомендуемый клиент с поддержкой роутинга
- [russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — geo-файлы для РФ
- Python 3 + [aiogram 3](https://github.com/aiogram/aiogram) — Telegram-бот
- BBR + оптимизированные TCP буферы — стабильная скорость
