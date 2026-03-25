# VPS Setup Script — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bash-установщик + Python Telegram-бот для настройки Ubuntu VPS с 3X-UI, VLESS Reality и удалённым управлением через Telegram.

**Architecture:** `setup.sh` — единая точка входа, выполняет hardening, ставит 3X-UI, разворачивает Python-бота как systemd-сервис. Бот (aiogram 3) общается с 3X-UI API по localhost, управляет пользователями, мониторит систему, шлёт алерты.

**Tech Stack:** Bash 5+, Python 3.10+, aiogram 3, aiohttp, psutil, python-dotenv, systemd, UFW, fail2ban

**Spec:** `docs/superpowers/specs/2026-03-25-vps-setup-script-design.md`

---

## File Structure

```
script_vps/                         # Репозиторий
├── setup.sh                        # Bash-установщик (точка входа)
├── bot/
│   ├── bot.py                      # Точка входа бота: загрузка конфига, регистрация роутеров, запуск
│   ├── config.py                   # Загрузка .env, dataclass с настройками
│   ├── middleware.py                # Мидлварь: фильтрация по chat_id
│   ├── keyboards.py                # Inline-клавиатуры (главное меню, подменю)
│   ├── requirements.txt            # Зависимости: aiogram, psutil, aiohttp, python-dotenv
│   ├── handlers/
│   │   ├── __init__.py             # Регистрация всех роутеров
│   │   ├── start.py                # /start → главное меню
│   │   ├── status.py               # Статус сервера (CPU, RAM, диск, аптайм)
│   │   ├── network.py              # Пинг, потери пакетов, скорость
│   │   ├── users.py                # Список / добавить / удалить пользователя
│   │   ├── traffic.py              # Трафик по пользователям
│   │   ├── diagnostics.py          # Проверка блокировок через check-host.net
│   │   ├── backup.py               # Бэкап конфигов → в Telegram
│   │   ├── tips.py                 # Советы по настройке, ссылки на Hiddify
│   │   └── update.py               # Проверка и обновление 3X-UI
│   └── services/
│       ├── __init__.py
│       ├── xui_api.py              # HTTP-клиент к 3X-UI API (login, CRUD клиентов)
│       ├── link_gen.py             # Генерация vless:// ссылок
│       └── monitor.py              # Фоновый мониторинг (алерты каждые 5 мин)
└── tests/
    ├── conftest.py                 # Общие фикстуры (mock конфиг, mock aiohttp)
    ├── test_config.py              # Тесты config.py
    ├── test_middleware.py           # Тесты фильтрации по chat_id
    ├── test_xui_api.py             # Тесты xui_api.py (мокаем HTTP)
    ├── test_link_gen.py            # Тесты генерации vless:// ссылок
    ├── test_monitor.py             # Тесты логики алертов
    ├── test_handlers_users.py      # Тесты хэндлеров пользователей
    ├── test_handlers_status.py     # Тесты хэндлера статуса
    ├── test_handlers_backup.py     # Тесты хэндлера бэкапов
    └── test_keyboards.py           # Тесты клавиатур
```

**На сервере после установки:**
```
/opt/vps-setup/
├── bot/                            # Копия bot/ из репозитория
├── venv/                           # Python venv
├── .env                            # BOT_TOKEN, CHAT_ID, XUI_USER, XUI_PASS, XUI_PATH, SERVER_IP
├── data/backups/                   # Ротируемые бэкапы (7 шт)
└── logs/                           # Логи бота
```

---

## Task 1: Scaffolding проекта и конфиг

**Files:**
- Create: `bot/config.py`
- Create: `bot/requirements.txt`
- Create: `tests/conftest.py`
- Create: `tests/test_config.py`

- [ ] **Step 1: Создать requirements.txt**

```
bot/requirements.txt:
```
```text
aiogram>=3.4,<4
aiohttp>=3.9,<4
psutil>=5.9,<6
python-dotenv>=1.0,<2
```

```
tests/requirements-dev.txt:
```
```text
pytest>=8.0,<9
pytest-asyncio>=0.23,<1
```

- [ ] **Step 2: Создать `bot/__init__.py` и `bot/handlers/__init__.py` (пустые)**

```python
# bot/__init__.py
```

```python
# bot/handlers/__init__.py
```

- [ ] **Step 3: Установить dev-зависимости**

Run: `pip install -r tests/requirements-dev.txt`

- [ ] **Step 4: Написать failing test для config.py**

```python
# tests/test_config.py
import os
import pytest
from unittest.mock import patch

from bot.config import load_config


def test_load_config_from_env():
    env = {
        "BOT_TOKEN": "123:ABC",
        "CHAT_ID": "999",
        "XUI_USER": "admin",
        "XUI_PASS": "secret",
        "XUI_PATH": "/panel-xyz",
        "SERVER_IP": "1.2.3.4",
        "PUBLIC_KEY": "pubkey123",
        "SHORT_ID": "deadbeef",
        "BEST_SNI": "www.microsoft.com",
    }
    with patch.dict(os.environ, env, clear=False):
        cfg = load_config()
        assert cfg.bot_token == "123:ABC"
        assert cfg.chat_id == 999
        assert cfg.xui_user == "admin"
        assert cfg.xui_pass == "secret"
        assert cfg.xui_path == "/panel-xyz"
        assert cfg.server_ip == "1.2.3.4"
        assert cfg.public_key == "pubkey123"
        assert cfg.xui_base_url == "http://127.0.0.1:2053/panel-xyz"


def test_load_config_missing_token():
    with patch.dict(os.environ, {}, clear=True):
        with pytest.raises(SystemExit):
            load_config()
```

- [ ] **Step 5: Запустить тест — убедиться что падает**

Run: `cd /Users/dmverlan/Documents/script_vps && python -m pytest tests/test_config.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'bot.config'`

- [ ] **Step 6: Написать config.py**

```python
# bot/config.py
from __future__ import annotations

import os
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    bot_token: str
    chat_id: int
    xui_user: str
    xui_pass: str
    xui_path: str
    server_ip: str
    public_key: str
    short_id: str
    sni: str

    @property
    def xui_base_url(self) -> str:
        return f"http://127.0.0.1:2053{self.xui_path}"


def load_config() -> Config:
    """Загрузка конфигурации из переменных окружения."""
    try:
        return Config(
            bot_token=os.environ["BOT_TOKEN"],
            chat_id=int(os.environ["CHAT_ID"]),
            xui_user=os.environ["XUI_USER"],
            xui_pass=os.environ["XUI_PASS"],
            xui_path=os.environ["XUI_PATH"],
            server_ip=os.environ["SERVER_IP"],
            public_key=os.environ["PUBLIC_KEY"],
            short_id=os.environ["SHORT_ID"],
            sni=os.environ["BEST_SNI"],
        )
    except KeyError as e:
        print(f"Missing env var: {e}", file=sys.stderr)
        sys.exit(1)
```

- [ ] **Step 7: Создать conftest.py с общими фикстурами**

```python
# tests/conftest.py
import os
import pytest
from unittest.mock import patch


@pytest.fixture
def sample_env():
    """Стандартный набор env-переменных для тестов."""
    return {
        "BOT_TOKEN": "123:ABC",
        "CHAT_ID": "999",
        "XUI_USER": "admin",
        "XUI_PASS": "secret",
        "XUI_PATH": "/panel-xyz",
        "SERVER_IP": "1.2.3.4",
        "PUBLIC_KEY": "pubkey123",
        "SHORT_ID": "deadbeef",
        "BEST_SNI": "www.microsoft.com",
    }


@pytest.fixture
def config(sample_env):
    """Загруженный Config для тестов."""
    with patch.dict(os.environ, sample_env, clear=False):
        from bot.config import load_config
        return load_config()
```

- [ ] **Step 8: Запустить тесты — убедиться что проходят**

Run: `python -m pytest tests/test_config.py -v`
Expected: 2 passed

- [ ] **Step 9: Коммит**

```bash
git add bot/__init__.py bot/config.py bot/requirements.txt bot/handlers/__init__.py tests/conftest.py tests/test_config.py tests/requirements-dev.txt
git commit -m "feat: project scaffolding — config loader with tests"
```

---

## Task 2: Middleware авторизации по chat_id

**Files:**
- Create: `bot/middleware.py`
- Create: `tests/test_middleware.py`

- [ ] **Step 1: Написать failing test**

```python
# tests/test_middleware.py
import pytest
from unittest.mock import AsyncMock, MagicMock


@pytest.mark.asyncio
async def test_allows_authorized_chat():
    from bot.middleware import AuthMiddleware

    mw = AuthMiddleware(allowed_chat_id=999)
    event = MagicMock()
    event.chat = MagicMock(id=999)
    handler = AsyncMock(return_value="ok")

    result = await mw(handler, event, {})
    handler.assert_called_once()
    assert result == "ok"


@pytest.mark.asyncio
async def test_blocks_unauthorized_chat():
    from bot.middleware import AuthMiddleware

    mw = AuthMiddleware(allowed_chat_id=999)
    event = MagicMock()
    event.chat = MagicMock(id=123)
    handler = AsyncMock()

    result = await mw(handler, event, {})
    handler.assert_not_called()
    assert result is None
```

- [ ] **Step 2: Запустить — убедиться что падает**

Run: `python -m pytest tests/test_middleware.py -v`
Expected: FAIL

- [ ] **Step 3: Реализовать middleware**

```python
# bot/middleware.py
from __future__ import annotations

from typing import Any, Awaitable, Callable

from aiogram import BaseMiddleware
from aiogram.types import TelegramObject


class AuthMiddleware(BaseMiddleware):
    """Пропускает только сообщения от разрешённого chat_id."""

    def __init__(self, allowed_chat_id: int) -> None:
        self.allowed_chat_id = allowed_chat_id

    async def __call__(
        self,
        handler: Callable[[TelegramObject, dict[str, Any]], Awaitable[Any]],
        event: TelegramObject,
        data: dict[str, Any],
    ) -> Any:
        chat = getattr(event, "chat", None)
        if chat is None or chat.id != self.allowed_chat_id:
            return None
        return await handler(event, data)
```

- [ ] **Step 4: Запустить тесты — проходят**

Run: `python -m pytest tests/test_middleware.py -v`
Expected: 2 passed

- [ ] **Step 5: Коммит**

```bash
git add bot/middleware.py tests/test_middleware.py
git commit -m "feat: auth middleware — filter by chat_id"
```

---

## Task 3: Клавиатуры (inline-меню)

**Files:**
- Create: `bot/keyboards.py`
- Create: `tests/test_keyboards.py`

- [ ] **Step 1: Написать failing test**

```python
# tests/test_keyboards.py
from bot.keyboards import main_menu, users_menu


def test_main_menu_has_expected_buttons():
    kb = main_menu()
    texts = [btn.text for row in kb.inline_keyboard for btn in row]
    assert "📊 Статус" in texts
    assert "👥 Пользователи" in texts
    assert "🌐 Сеть" in texts
    assert "🔍 Диагностика" in texts
    assert "💾 Бэкап" in texts
    assert "💡 Советы" in texts


def test_users_menu_has_expected_buttons():
    kb = users_menu()
    texts = [btn.text for row in kb.inline_keyboard for btn in row]
    assert "📋 Список" in texts
    assert "➕ Добавить" in texts
    assert "🔙 Назад" in texts
```

- [ ] **Step 2: Запустить — падает**

Run: `python -m pytest tests/test_keyboards.py -v`
Expected: FAIL

- [ ] **Step 3: Реализовать keyboards.py**

```python
# bot/keyboards.py
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup


def main_menu() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="📊 Статус", callback_data="status"),
            InlineKeyboardButton(text="👥 Пользователи", callback_data="users"),
        ],
        [
            InlineKeyboardButton(text="🌐 Сеть", callback_data="network"),
            InlineKeyboardButton(text="📈 Трафик", callback_data="traffic"),
        ],
        [
            InlineKeyboardButton(text="🔍 Диагностика", callback_data="diagnostics"),
            InlineKeyboardButton(text="💾 Бэкап", callback_data="backup"),
        ],
        [
            InlineKeyboardButton(text="💡 Советы", callback_data="tips"),
            InlineKeyboardButton(text="🔄 Обновление", callback_data="update"),
        ],
    ])


def users_menu() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="📋 Список", callback_data="users_list"),
            InlineKeyboardButton(text="➕ Добавить", callback_data="users_add"),
        ],
        [
            InlineKeyboardButton(text="❌ Удалить", callback_data="users_del"),
            InlineKeyboardButton(text="🔙 Назад", callback_data="main_menu"),
        ],
    ])


def back_button() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔙 Назад", callback_data="main_menu")],
    ])


def confirm_delete(email: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="✅ Да", callback_data=f"del_confirm:{email}"),
            InlineKeyboardButton(text="❌ Нет", callback_data="users"),
        ],
    ])


def update_buttons() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="🔄 Обновить", callback_data="update_confirm"),
            InlineKeyboardButton(text="⏭ Пропустить", callback_data="main_menu"),
        ],
    ])
```

- [ ] **Step 4: Тесты проходят**

Run: `python -m pytest tests/test_keyboards.py -v`
Expected: 2 passed

- [ ] **Step 5: Коммит**

```bash
git add bot/keyboards.py tests/test_keyboards.py
git commit -m "feat: inline keyboards for bot menus"
```

---

## Task 4: Сервис xui_api.py — HTTP-клиент к 3X-UI

**Files:**
- Create: `bot/services/__init__.py`
- Create: `bot/services/xui_api.py`
- Create: `tests/test_xui_api.py`

- [ ] **Step 1: Написать failing tests**

```python
# tests/test_xui_api.py
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from aiohttp import ClientSession


@pytest.fixture
def mock_session():
    session = AsyncMock(spec=ClientSession)
    return session


@pytest.mark.asyncio
async def test_login_sets_cookie(mock_session, config):
    from bot.services.xui_api import XUIClient

    resp = AsyncMock()
    resp.status = 200
    resp.json = AsyncMock(return_value={"success": True})
    mock_session.post = AsyncMock(return_value=resp)

    client = XUIClient(config, session=mock_session)
    await client.login()

    mock_session.post.assert_called_once()
    call_url = mock_session.post.call_args[0][0]
    assert "/login" in call_url


@pytest.mark.asyncio
async def test_list_inbounds(mock_session, config):
    from bot.services.xui_api import XUIClient

    resp = AsyncMock()
    resp.status = 200
    resp.json = AsyncMock(return_value={
        "success": True,
        "obj": [{"id": 1, "remark": "vless-reality", "settings": "{}"}],
    })
    mock_session.post = AsyncMock(return_value=resp)

    client = XUIClient(config, session=mock_session)
    client._logged_in = True
    result = await client.list_inbounds()

    assert len(result) == 1
    assert result[0]["id"] == 1


@pytest.mark.asyncio
async def test_add_client(mock_session, config):
    from bot.services.xui_api import XUIClient

    resp = AsyncMock()
    resp.status = 200
    resp.json = AsyncMock(return_value={"success": True})
    mock_session.post = AsyncMock(return_value=resp)

    client = XUIClient(config, session=mock_session)
    client._logged_in = True
    result = await client.add_client(
        inbound_id=1, uuid="test-uuid", email="friend1"
    )

    assert result is True


@pytest.mark.asyncio
async def test_auto_relogin_on_401(mock_session, config):
    from bot.services.xui_api import XUIClient

    resp_401 = AsyncMock()
    resp_401.status = 401
    resp_ok = AsyncMock()
    resp_ok.status = 200
    resp_ok.json = AsyncMock(return_value={"success": True, "obj": []})

    login_resp = AsyncMock()
    login_resp.status = 200
    login_resp.json = AsyncMock(return_value={"success": True})

    mock_session.post = AsyncMock(side_effect=[resp_401, login_resp, resp_ok])

    client = XUIClient(config, session=mock_session)
    client._logged_in = True
    result = await client.list_inbounds()

    assert result == []
    assert mock_session.post.call_count == 3  # 401 + login + retry
```

- [ ] **Step 2: Запустить — падает**

Run: `python -m pytest tests/test_xui_api.py -v`
Expected: FAIL

- [ ] **Step 3: Реализовать xui_api.py**

```python
# bot/services/xui_api.py
from __future__ import annotations

import json
import logging
from typing import Any

from aiohttp import ClientSession

from bot.config import Config

logger = logging.getLogger(__name__)


class XUIError(Exception):
    pass


class XUIClient:
    """HTTP-клиент для 3X-UI API."""

    def __init__(self, config: Config, session: ClientSession) -> None:
        self._config = config
        self._session = session
        self._base = config.xui_base_url
        self._logged_in = False

    async def login(self) -> None:
        resp = await self._session.post(
            f"{self._base}/login",
            data={"username": self._config.xui_user, "password": self._config.xui_pass},
        )
        body = await resp.json()
        if not body.get("success"):
            raise XUIError("Login failed")
        self._logged_in = True

    async def _request(self, method: str, path: str, **kwargs: Any) -> Any:
        """Выполнить запрос с автоматическим re-login при 401."""
        url = f"{self._base}{path}"
        resp = await self._session.post(url, **kwargs) if method == "POST" else await self._session.get(url, **kwargs)

        if resp.status == 401:
            logger.info("Got 401, re-logging in")
            await self.login()
            resp = await self._session.post(url, **kwargs) if method == "POST" else await self._session.get(url, **kwargs)

        if resp.status != 200:
            raise XUIError(f"HTTP {resp.status} from {path}")

        body = await resp.json()
        if not body.get("success"):
            raise XUIError(f"API error: {body}")
        return body

    async def list_inbounds(self) -> list[dict]:
        body = await self._request("POST", "/xui/API/inbounds/list")
        return body.get("obj", [])

    async def add_client(self, inbound_id: int, uuid: str, email: str) -> bool:
        settings = json.dumps({
            "clients": [{
                "id": uuid,
                "flow": "xtls-rprx-vision",
                "email": email,
                "totalGB": 0,
                "expiryTime": 0,
            }]
        })
        await self._request(
            "POST",
            "/xui/API/inbounds/addClient",
            data={"id": inbound_id, "settings": settings},
        )
        return True

    async def delete_client(self, inbound_id: int, client_uuid: str) -> bool:
        await self._request(
            "POST",
            f"/xui/API/inbounds/{inbound_id}/delClient/{client_uuid}",
        )
        return True

    async def get_client_traffic(self, email: str) -> dict:
        body = await self._request(
            "POST",  # Note: некоторые версии используют GET
            f"/xui/API/inbounds/getClientTraffics/{email}",
        )
        return body.get("obj", {})

    async def server_status(self) -> dict:
        body = await self._request("GET", "/server/status")
        return body.get("obj", {})
```

```python
# bot/services/__init__.py
```

- [ ] **Step 4: Тесты проходят**

Run: `python -m pytest tests/test_xui_api.py -v`
Expected: 4 passed

- [ ] **Step 5: Коммит**

```bash
git add bot/services/__init__.py bot/services/xui_api.py tests/test_xui_api.py
git commit -m "feat: xui_api.py — HTTP client for 3X-UI API with auto-relogin"
```

---

## Task 5: Сервис link_gen.py — генерация vless:// ссылок

**Files:**
- Create: `bot/services/link_gen.py`
- Create: `tests/test_link_gen.py`

- [ ] **Step 1: Написать failing test**

```python
# tests/test_link_gen.py
from urllib.parse import urlparse, parse_qs, unquote


def test_generate_vless_link():
    from bot.services.link_gen import generate_vless_link

    link = generate_vless_link(
        uuid="abc-123",
        server_ip="1.2.3.4",
        public_key="pubkey123",
        short_id="deadbeef",
        sni="www.microsoft.com",
        name="friend1",
    )

    assert link.startswith("vless://abc-123@1.2.3.4:443?")
    assert "security=reality" in link
    assert "fp=chrome" in link
    assert "pbk=pubkey123" in link
    assert "sid=deadbeef" in link
    assert "sni=www.microsoft.com" in link
    assert "flow=xtls-rprx-vision" in link
    assert link.endswith("#friend1")


def test_generate_vless_link_name_with_spaces():
    from bot.services.link_gen import generate_vless_link

    link = generate_vless_link(
        uuid="abc-123",
        server_ip="1.2.3.4",
        public_key="pk",
        short_id="aa",
        sni="www.google.com",
        name="Вася Пупкин",
    )

    # Имя должно быть URL-encoded во фрагменте
    assert "#" in link
    fragment = link.split("#", 1)[1]
    assert unquote(fragment) == "Вася Пупкин"
```

- [ ] **Step 2: Запустить — падает**

Run: `python -m pytest tests/test_link_gen.py -v`
Expected: FAIL

- [ ] **Step 3: Реализовать link_gen.py**

```python
# bot/services/link_gen.py
from urllib.parse import quote


def generate_vless_link(
    uuid: str,
    server_ip: str,
    public_key: str,
    short_id: str,
    sni: str,
    name: str,
) -> str:
    """Генерация vless:// ссылки для VLESS + Reality."""
    params = (
        f"type=tcp"
        f"&security=reality"
        f"&fp=chrome"
        f"&pbk={public_key}"
        f"&sid={short_id}"
        f"&sni={sni}"
        f"&flow=xtls-rprx-vision"
    )
    fragment = quote(name, safe="")
    return f"vless://{uuid}@{server_ip}:443?{params}#{fragment}"
```

- [ ] **Step 4: Тесты проходят**

Run: `python -m pytest tests/test_link_gen.py -v`
Expected: 2 passed

- [ ] **Step 5: Коммит**

```bash
git add bot/services/link_gen.py tests/test_link_gen.py
git commit -m "feat: link_gen.py — vless:// link generator"
```

---

## Task 6: Хэндлер /start + главное меню

**Files:**
- Create: `bot/handlers/__init__.py`
- Create: `bot/handlers/start.py`

- [ ] **Step 1: Реализовать start.py**

```python
# bot/handlers/start.py
from aiogram import Router
from aiogram.filters import CommandStart
from aiogram.types import CallbackQuery, Message

from bot.keyboards import main_menu

router = Router()


@router.message(CommandStart())
async def cmd_start(message: Message) -> None:
    await message.answer("🖥 VPS Control Panel", reply_markup=main_menu())


@router.callback_query(lambda c: c.data == "main_menu")
async def cb_main_menu(callback: CallbackQuery) -> None:
    await callback.message.edit_text("🖥 VPS Control Panel", reply_markup=main_menu())
    await callback.answer()
```

- [ ] **Step 2: Реализовать __init__.py для регистрации роутеров**

```python
# bot/handlers/__init__.py
from aiogram import Router

from bot.handlers.start import router as start_router


def register_all_routers() -> Router:
    """Создаёт корневой роутер и подключает все хэндлеры."""
    root = Router()
    root.include_router(start_router)
    return root
```

Примечание: по мере добавления хэндлеров в следующих тасках, сюда добавляются импорты.

- [ ] **Step 3: Коммит**

```bash
git add bot/handlers/__init__.py bot/handlers/start.py
git commit -m "feat: /start handler and main menu"
```

---

## Task 7: Хэндлер статуса сервера

**Files:**
- Create: `bot/handlers/status.py`
- Create: `tests/test_handlers_status.py`

- [ ] **Step 1: Написать failing test**

```python
# tests/test_handlers_status.py
import pytest
from unittest.mock import AsyncMock, patch, MagicMock


@pytest.mark.asyncio
async def test_status_formats_output():
    from bot.handlers.status import format_status

    data = {
        "cpu_percent": 25.0,
        "mem_used_gb": 1.2,
        "mem_total_gb": 4.0,
        "disk_used_gb": 10.5,
        "disk_total_gb": 40.0,
        "uptime_str": "5d 3h 12m",
        "load_avg": "0.15, 0.10, 0.05",
        "swap_used_gb": 0.0,
        "swap_total_gb": 1.0,
        "kernel": "5.15.0-91-generic",
        "xui_version": "2.5.4",
        "xray_version": "1.8.24",
    }
    text = format_status(data)

    assert "CPU" in text
    assert "25.0%" in text
    assert "RAM" in text
    assert "1.2" in text
    assert "Uptime" in text
    assert "5.15.0" in text
    assert "2.5.4" in text
```

- [ ] **Step 2: Запустить — падает**

Run: `python -m pytest tests/test_handlers_status.py -v`
Expected: FAIL

- [ ] **Step 3: Реализовать status.py**

```python
# bot/handlers/status.py
import asyncio
import psutil
import time
from aiogram import Router
from aiogram.types import CallbackQuery

from bot.keyboards import back_button

router = Router()


async def _get_version(cmd: list[str]) -> str:
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await proc.communicate()
        return stdout.decode().strip() or "?"
    except Exception:
        return "?"


def _get_system_status() -> dict:
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    swap = psutil.swap_memory()
    uptime_sec = time.time() - psutil.boot_time()
    days, rem = divmod(int(uptime_sec), 86400)
    hours, rem = divmod(rem, 3600)
    minutes = rem // 60
    load = psutil.getloadavg()

    return {
        "cpu_percent": psutil.cpu_percent(interval=1),
        "mem_used_gb": round(mem.used / (1024 ** 3), 1),
        "mem_total_gb": round(mem.total / (1024 ** 3), 1),
        "disk_used_gb": round(disk.used / (1024 ** 3), 1),
        "disk_total_gb": round(disk.total / (1024 ** 3), 1),
        "swap_used_gb": round(swap.used / (1024 ** 3), 1),
        "swap_total_gb": round(swap.total / (1024 ** 3), 1),
        "uptime_str": f"{days}d {hours}h {minutes}m",
        "load_avg": f"{load[0]:.2f}, {load[1]:.2f}, {load[2]:.2f}",
        "kernel": "",   # заполняется async
        "xui_version": "",
        "xray_version": "",
    }


def format_status(data: dict) -> str:
    return (
        f"📊 <b>Статус сервера</b>\n\n"
        f"CPU: {data['cpu_percent']}%\n"
        f"RAM: {data['mem_used_gb']}/{data['mem_total_gb']} GB\n"
        f"Disk: {data['disk_used_gb']}/{data['disk_total_gb']} GB\n"
        f"Swap: {data['swap_used_gb']}/{data['swap_total_gb']} GB\n"
        f"Load: {data['load_avg']}\n"
        f"Uptime: {data['uptime_str']}\n\n"
        f"Kernel: {data['kernel']}\n"
        f"3X-UI: {data['xui_version']}\n"
        f"Xray: {data['xray_version']}"
    )


@router.callback_query(lambda c: c.data == "status")
async def cb_status(callback: CallbackQuery) -> None:
    data = _get_system_status()
    # Добавляем версии (async)
    data["kernel"] = await _get_version(["uname", "-r"])
    data["xui_version"] = await _get_version(["x-ui", "version"])
    data["xray_version"] = await _get_version(["xray", "version"])
    await callback.message.edit_text(
        format_status(data), reply_markup=back_button(), parse_mode="HTML"
    )
    await callback.answer()
```

- [ ] **Step 4: Зарегистрировать роутер в handlers/__init__.py**

Добавить в `bot/handlers/__init__.py`:
```python
from bot.handlers.status import router as status_router
# ...
root.include_router(status_router)
```

- [ ] **Step 5: Тесты проходят**

Run: `python -m pytest tests/test_handlers_status.py -v`
Expected: 1 passed

- [ ] **Step 6: Коммит**

```bash
git add bot/handlers/status.py bot/handlers/__init__.py tests/test_handlers_status.py
git commit -m "feat: server status handler with system metrics"
```

---

## Task 8: Хэндлер сети (пинг, потери пакетов)

**Files:**
- Create: `bot/handlers/network.py`

- [ ] **Step 1: Реализовать network.py**

```python
# bot/handlers/network.py
import asyncio
import psutil
from aiogram import Router
from aiogram.types import CallbackQuery

from bot.keyboards import back_button

router = Router()

PING_TARGETS = [
    ("Google DNS", "8.8.8.8"),
    ("Cloudflare", "1.1.1.1"),
    ("Moscow IX", "195.208.208.1"),
]


async def _ping(host: str, count: int = 4) -> dict:
    proc = await asyncio.create_subprocess_exec(
        "ping", "-c", str(count), "-W", "3", host,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    output = stdout.decode()

    avg_ms = None
    loss = "100%"
    for line in output.splitlines():
        if "packet loss" in line:
            for part in line.split(","):
                if "packet loss" in part:
                    loss = part.strip().split()[0]
        if "avg" in line:
            # rtt min/avg/max/mdev = ...
            parts = line.split("=")[-1].strip().split("/")
            if len(parts) >= 2:
                avg_ms = parts[1]

    return {"avg_ms": avg_ms, "loss": loss}


async def _get_bandwidth() -> tuple[float, float]:
    """Текущая скорость in/out за 2 секунды (KB/s)."""
    net1 = psutil.net_io_counters()
    await asyncio.sleep(2)
    net2 = psutil.net_io_counters()
    rx = (net2.bytes_recv - net1.bytes_recv) / 2 / 1024
    tx = (net2.bytes_sent - net1.bytes_sent) / 2 / 1024
    return round(rx, 1), round(tx, 1)


@router.callback_query(lambda c: c.data == "network")
async def cb_network(callback: CallbackQuery) -> None:
    await callback.answer("⏳ Проверяю сеть...")

    results = await asyncio.gather(*[_ping(host) for _, host in PING_TARGETS])
    rx, tx = await _get_bandwidth()

    lines = ["🌐 <b>Сеть</b>\n"]
    for (name, _), res in zip(PING_TARGETS, results):
        ms = f"{res['avg_ms']} ms" if res["avg_ms"] else "timeout"
        lines.append(f"{name}: {ms} (loss: {res['loss']})")

    lines.append(f"\n📥 In: {rx} KB/s | 📤 Out: {tx} KB/s")

    # Потеря пакетов (серия 20)
    big_ping = await _ping("8.8.8.8", count=20)
    lines.append(f"\nПотеря пакетов (20 пакетов → Google): {big_ping['loss']}")

    await callback.message.edit_text(
        "\n".join(lines), reply_markup=back_button(), parse_mode="HTML"
    )
```

- [ ] **Step 2: Зарегистрировать роутер**

Добавить в `bot/handlers/__init__.py`:
```python
from bot.handlers.network import router as network_router
root.include_router(network_router)
```

- [ ] **Step 3: Коммит**

```bash
git add bot/handlers/network.py bot/handlers/__init__.py
git commit -m "feat: network handler — ping, packet loss, bandwidth"
```

---

## Task 9: Хэндлеры пользователей (список, добавить, удалить)

**Files:**
- Create: `bot/handlers/users.py`
- Create: `tests/test_handlers_users.py`

- [ ] **Step 1: Написать failing test**

```python
# tests/test_handlers_users.py
import pytest
import json


@pytest.mark.asyncio
async def test_parse_clients_from_inbound():
    from bot.handlers.users import parse_clients

    inbound = {
        "id": 1,
        "settings": json.dumps({
            "clients": [
                {"id": "uuid-1", "email": "alice", "flow": "xtls-rprx-vision"},
                {"id": "uuid-2", "email": "bob", "flow": "xtls-rprx-vision"},
            ]
        }),
    }
    clients = parse_clients(inbound)
    assert len(clients) == 2
    assert clients[0]["email"] == "alice"
    assert clients[1]["id"] == "uuid-2"


def test_format_users_list():
    from bot.handlers.users import format_users_list

    clients = [
        {"email": "alice", "id": "uuid-1"},
        {"email": "bob", "id": "uuid-2"},
    ]
    text = format_users_list(clients)
    assert "alice" in text
    assert "bob" in text
```

- [ ] **Step 2: Запустить — падает**

Run: `python -m pytest tests/test_handlers_users.py -v`
Expected: FAIL

- [ ] **Step 3: Реализовать users.py**

```python
# bot/handlers/users.py
from __future__ import annotations

import json
import uuid as uuid_mod

from aiogram import F, Router
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import CallbackQuery, Message

from bot.keyboards import back_button, confirm_delete, users_menu

router = Router()


class AddUser(StatesGroup):
    waiting_name = State()


class DeleteUser(StatesGroup):
    waiting_name = State()


def parse_clients(inbound: dict) -> list[dict]:
    settings = json.loads(inbound.get("settings", "{}"))
    return settings.get("clients", [])


def format_users_list(clients: list[dict]) -> str:
    if not clients:
        return "👥 Нет пользователей"
    lines = ["👥 <b>Пользователи</b>\n"]
    for i, c in enumerate(clients, 1):
        lines.append(f"{i}. {c['email']}")
    return "\n".join(lines)


@router.callback_query(F.data == "users")
async def cb_users(callback: CallbackQuery) -> None:
    await callback.message.edit_text("👥 Управление пользователями", reply_markup=users_menu())
    await callback.answer()


@router.callback_query(F.data == "users_list")
async def cb_users_list(callback: CallbackQuery) -> None:
    xui = callback.bot["xui_client"]
    inbounds = await xui.list_inbounds()
    clients = []
    for ib in inbounds:
        clients.extend(parse_clients(ib))

    await callback.message.edit_text(
        format_users_list(clients), reply_markup=users_menu(), parse_mode="HTML"
    )
    await callback.answer()


@router.callback_query(F.data == "users_add")
async def cb_users_add(callback: CallbackQuery, state: FSMContext) -> None:
    await callback.message.edit_text("Введите имя нового пользователя:")
    await state.set_state(AddUser.waiting_name)
    await callback.answer()


@router.message(AddUser.waiting_name)
async def on_user_name(message: Message, state: FSMContext) -> None:
    name = message.text.strip()
    if not name:
        await message.answer("Имя не может быть пустым. Попробуйте ещё раз:")
        return

    xui = message.bot["xui_client"]
    link_gen = message.bot["link_gen_params"]

    client_uuid = str(uuid_mod.uuid4())
    inbounds = await xui.list_inbounds()
    if not inbounds:
        await message.answer("❌ Нет inbound'ов в 3X-UI", reply_markup=users_menu())
        await state.clear()
        return

    inbound_id = inbounds[0]["id"]
    await xui.add_client(inbound_id=inbound_id, uuid=client_uuid, email=name)

    from bot.services.link_gen import generate_vless_link

    link = generate_vless_link(
        uuid=client_uuid,
        server_ip=link_gen["server_ip"],
        public_key=link_gen["public_key"],
        short_id=link_gen["short_id"],
        sni=link_gen["sni"],
        name=name,
    )

    await message.answer(
        f"✅ Пользователь <b>{name}</b> добавлен!\n\n"
        f"<code>{link}</code>\n\n"
        f"Перешлите эту ссылку другу — он вставляет её в Hiddify через «Буфер обмена».",
        parse_mode="HTML",
        reply_markup=users_menu(),
    )
    await state.clear()


@router.callback_query(F.data == "users_del")
async def cb_users_del(callback: CallbackQuery, state: FSMContext) -> None:
    await callback.message.edit_text("Введите имя пользователя для удаления:")
    await state.set_state(DeleteUser.waiting_name)
    await callback.answer()


@router.message(DeleteUser.waiting_name)
async def on_delete_name(message: Message, state: FSMContext) -> None:
    name = message.text.strip()
    await message.answer(
        f"Удалить пользователя <b>{name}</b>?",
        parse_mode="HTML",
        reply_markup=confirm_delete(name),
    )
    await state.clear()


@router.callback_query(F.data.startswith("del_confirm:"))
async def cb_del_confirm(callback: CallbackQuery) -> None:
    email = callback.data.split(":", 1)[1]
    xui = callback.bot["xui_client"]

    inbounds = await xui.list_inbounds()
    deleted = False
    for ib in inbounds:
        for client in parse_clients(ib):
            if client["email"] == email:
                await xui.delete_client(ib["id"], client["id"])
                deleted = True
                break
        if deleted:
            break

    msg = f"✅ Пользователь {email} удалён" if deleted else f"❌ Пользователь {email} не найден"
    await callback.message.edit_text(msg, reply_markup=users_menu())
    await callback.answer()
```

- [ ] **Step 4: Зарегистрировать роутер**

Добавить в `bot/handlers/__init__.py`:
```python
from bot.handlers.users import router as users_router
root.include_router(users_router)
```

- [ ] **Step 5: Тесты проходят**

Run: `python -m pytest tests/test_handlers_users.py -v`
Expected: 2 passed

- [ ] **Step 6: Коммит**

```bash
git add bot/handlers/users.py tests/test_handlers_users.py bot/handlers/__init__.py
git commit -m "feat: user management handlers — list, add, delete"
```

---

## Task 10: Хэндлер трафика

**Files:**
- Create: `bot/handlers/traffic.py`

- [ ] **Step 1: Реализовать traffic.py**

```python
# bot/handlers/traffic.py
import json
from aiogram import Router
from aiogram.types import CallbackQuery

from bot.keyboards import back_button

router = Router()


def _format_bytes(b: int) -> str:
    if b < 1024:
        return f"{b} B"
    elif b < 1024 ** 2:
        return f"{b / 1024:.1f} KB"
    elif b < 1024 ** 3:
        return f"{b / (1024 ** 2):.1f} MB"
    return f"{b / (1024 ** 3):.2f} GB"


@router.callback_query(lambda c: c.data == "traffic")
async def cb_traffic(callback: CallbackQuery) -> None:
    xui = callback.bot["xui_client"]
    inbounds = await xui.list_inbounds()

    lines = ["📈 <b>Трафик по пользователям</b>\n"]
    for ib in inbounds:
        settings = json.loads(ib.get("settings", "{}"))
        clients = settings.get("clients", [])
        client_stats = ib.get("clientStats", [])

        stat_map = {s["email"]: s for s in client_stats} if client_stats else {}

        for c in clients:
            email = c["email"]
            stats = stat_map.get(email, {})
            up = stats.get("up", 0)
            down = stats.get("down", 0)
            lines.append(f"👤 {email}: ↑{_format_bytes(up)} ↓{_format_bytes(down)}")

    if len(lines) == 1:
        lines.append("Нет данных о трафике")

    await callback.message.edit_text(
        "\n".join(lines), reply_markup=back_button(), parse_mode="HTML"
    )
    await callback.answer()
```

- [ ] **Step 2: Зарегистрировать роутер**

- [ ] **Step 3: Коммит**

```bash
git add bot/handlers/traffic.py bot/handlers/__init__.py
git commit -m "feat: traffic handler — per-user traffic stats"
```

---

## Task 11: Хэндлер диагностики блокировок

**Files:**
- Create: `bot/handlers/diagnostics.py`

- [ ] **Step 1: Реализовать diagnostics.py**

```python
# bot/handlers/diagnostics.py
import asyncio
import aiohttp
from aiogram import Router
from aiogram.types import CallbackQuery

from bot.keyboards import back_button

router = Router()

CHECK_HOST_API = "https://check-host.net"


async def _check_from_russia(server_ip: str, session: aiohttp.ClientSession) -> dict | None:
    """Проверка доступности IP из РФ через check-host.net API."""
    try:
        headers = {"Accept": "application/json"}
        resp = await session.get(
            f"{CHECK_HOST_API}/check-tcp?host={server_ip}:443",
            headers=headers,
            timeout=aiohttp.ClientTimeout(total=15),
        )
        if resp.status != 200:
            return None

        data = await resp.json()
        request_id = data.get("request_id")
        if not request_id:
            return None

        await asyncio.sleep(5)

        resp2 = await session.get(
            f"{CHECK_HOST_API}/check-result/{request_id}",
            headers=headers,
            timeout=aiohttp.ClientTimeout(total=15),
        )
        if resp2.status != 200:
            return None

        results = await resp2.json()

        ru_nodes = {k: v for k, v in results.items() if ".ru" in k or "russia" in k.lower()}
        if not ru_nodes:
            return {"status": "no_ru_nodes", "results": results}

        reachable = 0
        total = len(ru_nodes)
        for node, result in ru_nodes.items():
            if result and isinstance(result, list) and result[0] and result[0].get("error") is None:
                reachable += 1

        return {"reachable": reachable, "total": total}

    except Exception:
        return None


async def _check_isitdown(server_ip: str, session: aiohttp.ClientSession) -> dict | None:
    """Fallback: проверка через isitdown.site."""
    try:
        resp = await session.get(
            f"https://isitdown.site/api/v3/{server_ip}",
            timeout=aiohttp.ClientTimeout(total=15),
        )
        if resp.status != 200:
            return None
        data = await resp.json()
        is_down = data.get("isitdown", False)
        if is_down:
            return {"reachable": 0, "total": 1}
        return {"reachable": 1, "total": 1}
    except Exception:
        return None


async def _check_xray_running() -> bool:
    proc = await asyncio.create_subprocess_exec(
        "systemctl", "is-active", "x-ui",
        stdout=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    return stdout.decode().strip() == "active"


@router.callback_query(lambda c: c.data == "diagnostics")
async def cb_diagnostics(callback: CallbackQuery) -> None:
    await callback.answer("⏳ Запускаю диагностику...")

    config = callback.bot["config"]
    lines = ["🔍 <b>Диагностика</b>\n"]

    # Проверка xray
    xray_ok = await _check_xray_running()
    lines.append(f"xray/x-ui: {'✅ работает' if xray_ok else '❌ не запущен!'}")

    # Проверка из РФ (check-host.net → fallback: isitdown.site)
    async with aiohttp.ClientSession() as session:
        result = await _check_from_russia(config.server_ip, session)
        if result is None:
            result = await _check_isitdown(config.server_ip, session)

    if result is None:
        lines.append("\n🌐 Проверка из РФ: ⚠️ Оба API недоступны (check-host.net, isitdown.site)")
    elif result.get("status") == "no_ru_nodes":
        lines.append("\n🌐 Проверка из РФ: ⚠️ нет RU-нод в результатах")
    else:
        r = result["reachable"]
        t = result["total"]
        if r == t:
            lines.append(f"\n🌐 Из РФ: ✅ доступен ({r}/{t} нод)")
        elif r > 0:
            lines.append(f"\n🌐 Из РФ: ⚠️ частично ({r}/{t} нод)")
        else:
            lines.append(
                f"\n🌐 Из РФ: ❌ заблокирован ({r}/{t} нод)\n"
                f"💡 Рекомендация: смените IP у провайдера"
            )

    await callback.message.edit_text(
        "\n".join(lines), reply_markup=back_button(), parse_mode="HTML"
    )
```

- [ ] **Step 2: Зарегистрировать роутер**

- [ ] **Step 3: Коммит**

```bash
git add bot/handlers/diagnostics.py bot/handlers/__init__.py
git commit -m "feat: diagnostics handler — block detection from Russia"
```

---

## Task 12: Хэндлер бэкапов

**Files:**
- Create: `bot/handlers/backup.py`
- Create: `tests/test_handlers_backup.py`

- [ ] **Step 1: Написать failing test**

```python
# tests/test_handlers_backup.py
import os
import pytest
from unittest.mock import patch, MagicMock


def test_rotate_backups_keeps_only_7(tmp_path):
    from bot.handlers.backup import rotate_backups

    # Создаём 8 файлов
    for i in range(8):
        f = tmp_path / f"backup_{i:02d}.tar.gz"
        f.write_text("data")
        # Устанавливаем разное время модификации
        os.utime(f, (1000 + i, 1000 + i))

    rotate_backups(str(tmp_path), max_backups=7)

    remaining = list(tmp_path.glob("*.tar.gz"))
    assert len(remaining) == 7
    # Самый старый (backup_00) должен быть удалён
    assert not (tmp_path / "backup_00.tar.gz").exists()
```

- [ ] **Step 2: Запустить — падает**

Run: `python -m pytest tests/test_handlers_backup.py -v`
Expected: FAIL

- [ ] **Step 3: Реализовать backup.py**

```python
# bot/handlers/backup.py
from __future__ import annotations

import asyncio
import os
import tarfile
import tempfile
from datetime import datetime
from pathlib import Path

from aiogram import Router
from aiogram.types import CallbackQuery, FSInputFile

from bot.keyboards import back_button

router = Router()

BACKUP_DIR = "/opt/vps-setup/data/backups"
XUI_DB_PATH = "/etc/x-ui/x-ui.db"
XRAY_CONFIG_PATH = "/usr/local/x-ui/bin/config.json"
MAX_BACKUP_SIZE = 45 * 1024 * 1024  # 45 MB
MAX_BACKUPS = 7


def rotate_backups(backup_dir: str, max_backups: int = MAX_BACKUPS) -> None:
    """Удаляет старейшие бэкапы, оставляя max_backups."""
    backups = sorted(
        Path(backup_dir).glob("*.tar.gz"),
        key=lambda f: f.stat().st_mtime,
    )
    while len(backups) > max_backups:
        oldest = backups.pop(0)
        oldest.unlink()


def create_backup() -> str:
    """Создаёт tar.gz архив с БД и конфигом xray. Возвращает путь к файлу."""
    os.makedirs(BACKUP_DIR, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = os.path.join(BACKUP_DIR, f"backup_{timestamp}.tar.gz")

    with tarfile.open(backup_path, "w:gz") as tar:
        if os.path.exists(XUI_DB_PATH):
            tar.add(XUI_DB_PATH, arcname="x-ui.db")
        if os.path.exists(XRAY_CONFIG_PATH):
            tar.add(XRAY_CONFIG_PATH, arcname="xray-config.json")

    rotate_backups(BACKUP_DIR)
    return backup_path


@router.callback_query(lambda c: c.data == "backup")
async def cb_backup(callback: CallbackQuery) -> None:
    await callback.answer("⏳ Создаю бэкап...")

    backup_path = await asyncio.to_thread(create_backup)
    file_size = os.path.getsize(backup_path)

    if file_size > MAX_BACKUP_SIZE:
        await callback.message.edit_text(
            f"💾 Бэкап создан: {backup_path}\n"
            f"⚠️ Размер ({file_size // (1024*1024)} MB) превышает лимит Telegram.\n"
            f"Файл сохранён только на сервере.",
            reply_markup=back_button(),
        )
    else:
        doc = FSInputFile(backup_path)
        await callback.message.answer_document(doc, caption=f"💾 Бэкап {datetime.now():%Y-%m-%d %H:%M}")
        await callback.message.edit_text("💾 Бэкап отправлен ↑", reply_markup=back_button())
```

- [ ] **Step 4: Зарегистрировать роутер**

- [ ] **Step 5: Тесты проходят**

Run: `python -m pytest tests/test_handlers_backup.py -v`
Expected: 1 passed

- [ ] **Step 6: Коммит**

```bash
git add bot/handlers/backup.py tests/test_handlers_backup.py bot/handlers/__init__.py
git commit -m "feat: backup handler — create, send, rotate backups"
```

---

## Task 13: Хэндлер советов

**Files:**
- Create: `bot/handlers/tips.py`

- [ ] **Step 1: Реализовать tips.py**

```python
# bot/handlers/tips.py
from aiogram import Router
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup

from bot.keyboards import back_button

router = Router()

TIPS = {
    "tip_hiddify": (
        "📱 <b>Установка Hiddify</b>\n\n"
        "• Android: https://play.google.com/store/apps/details?id=app.hiddify.com\n"
        "• iOS: https://apps.apple.com/app/hiddify-proxy-vpn/id6596777532\n"
        "• Windows: https://github.com/hiddify/hiddify-app/releases/latest\n"
        "• macOS: https://github.com/hiddify/hiddify-app/releases/latest\n"
    ),
    "tip_paste": (
        "📋 <b>Как вставить ссылку</b>\n\n"
        "1. Скопируйте vless:// ссылку из Telegram\n"
        "2. Откройте Hiddify\n"
        "3. Нажмите «+» → «Буфер обмена»\n"
        "4. Профиль добавится автоматически\n"
        "5. Нажмите кнопку подключения ▶"
    ),
    "tip_routing": (
        "🗺 <b>Маршрутизация</b>\n\n"
        "Чтобы российские сайты работали напрямую:\n"
        "Hiddify → Настройки → Регион → Россия (ru)\n\n"
        "Трафик на RU-сайты пойдёт напрямую, остальной — через VPN."
    ),
    "tip_panel": (
        "🖥 <b>Доступ к панели 3X-UI</b>\n\n"
        "Панель доступна только через SSH-туннель:\n"
        "<code>ssh -L 2053:127.0.0.1:2053 -p SSH_PORT root@SERVER_IP</code>\n\n"
        "Затем откройте http://localhost:2053 в браузере."
    ),
    "tip_sni": (
        "🌐 <b>SNI для Reality</b>\n\n"
        "Лучшие SNI — крупные сайты с поддержкой TLS 1.3 и HTTP/2:\n"
        "• www.microsoft.com\n"
        "• www.google.com\n"
        "• www.yahoo.com\n\n"
        "Скрипт автоматически выбирает SNI с минимальной задержкой."
    ),
}


def tips_menu() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📱 Hiddify", callback_data="tip_hiddify")],
        [InlineKeyboardButton(text="📋 Как вставить ссылку", callback_data="tip_paste")],
        [InlineKeyboardButton(text="🗺 Маршрутизация", callback_data="tip_routing")],
        [InlineKeyboardButton(text="🖥 Панель 3X-UI", callback_data="tip_panel")],
        [InlineKeyboardButton(text="🌐 Выбор SNI", callback_data="tip_sni")],
        [InlineKeyboardButton(text="🔙 Назад", callback_data="main_menu")],
    ])


@router.callback_query(lambda c: c.data == "tips")
async def cb_tips(callback: CallbackQuery) -> None:
    await callback.message.edit_text("💡 <b>Советы</b>", reply_markup=tips_menu(), parse_mode="HTML")
    await callback.answer()


@router.callback_query(lambda c: c.data and c.data.startswith("tip_"))
async def cb_tip_detail(callback: CallbackQuery) -> None:
    text = TIPS.get(callback.data, "Совет не найден")
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔙 К советам", callback_data="tips")],
    ])
    await callback.message.edit_text(text, reply_markup=kb, parse_mode="HTML")
    await callback.answer()
```

- [ ] **Step 2: Зарегистрировать роутер**

- [ ] **Step 3: Коммит**

```bash
git add bot/handlers/tips.py bot/handlers/__init__.py
git commit -m "feat: tips handler — Hiddify install, link paste, routing, panel access"
```

---

## Task 14: Хэндлер обновления 3X-UI

**Files:**
- Create: `bot/handlers/update.py`

- [ ] **Step 1: Реализовать update.py**

```python
# bot/handlers/update.py
from __future__ import annotations

import asyncio
import logging
import shutil
from pathlib import Path

import aiohttp
from aiogram import F, Router
from aiogram.types import CallbackQuery

from bot.keyboards import back_button, update_buttons

router = Router()
logger = logging.getLogger(__name__)

GITHUB_API = "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest"
XUI_DB_PATH = Path("/etc/x-ui/x-ui.db")
XUI_BIN_PATH = Path("/usr/local/x-ui")
ROLLBACK_DIR = Path("/opt/vps-setup/data/rollback")


async def get_latest_version() -> str | None:
    try:
        async with aiohttp.ClientSession() as session:
            resp = await session.get(GITHUB_API, timeout=aiohttp.ClientTimeout(total=10))
            if resp.status != 200:
                return None
            data = await resp.json()
            return data.get("tag_name")
    except Exception:
        return None


async def get_current_version() -> str | None:
    proc = await asyncio.create_subprocess_exec(
        "x-ui", "version",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    return stdout.decode().strip() if proc.returncode == 0 else None


async def _do_update() -> tuple[bool, str]:
    """Выполняет обновление 3X-UI. Возвращает (success, message)."""
    # Бэкап перед обновлением
    ROLLBACK_DIR.mkdir(parents=True, exist_ok=True)
    if XUI_DB_PATH.exists():
        shutil.copy2(XUI_DB_PATH, ROLLBACK_DIR / "x-ui.db.bak")

    # Запуск обновления
    proc = await asyncio.create_subprocess_exec(
        "bash", "-c",
        "echo 'y' | bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await proc.communicate()

    if proc.returncode != 0:
        return False, f"Ошибка установки: {stderr.decode()[:200]}"

    # Ожидание запуска
    await asyncio.sleep(10)

    # Проверка
    check = await asyncio.create_subprocess_exec(
        "systemctl", "is-active", "x-ui",
        stdout=asyncio.subprocess.PIPE,
    )
    stdout, _ = await check.communicate()
    if stdout.decode().strip() != "active":
        # Откат
        if (ROLLBACK_DIR / "x-ui.db.bak").exists():
            shutil.copy2(ROLLBACK_DIR / "x-ui.db.bak", XUI_DB_PATH)
            await asyncio.create_subprocess_exec("systemctl", "restart", "x-ui")
            await asyncio.sleep(5)

            # Проверка после отката
            check2 = await asyncio.create_subprocess_exec(
                "systemctl", "is-active", "x-ui",
                stdout=asyncio.subprocess.PIPE,
            )
            stdout2, _ = await check2.communicate()
            if stdout2.decode().strip() != "active":
                return False, "❌ Откат не помог — требуется ручное вмешательство"

        return False, "❌ Обновление не удалось, выполнен откат"

    return True, "✅ Обновление завершено успешно"


@router.callback_query(F.data == "update")
async def cb_update(callback: CallbackQuery) -> None:
    current = await get_current_version()
    latest = await get_latest_version()

    if latest and current and latest == current:
        await callback.message.edit_text(
            f"🔄 3X-UI: {current}\nОбновлений нет.",
            reply_markup=back_button(),
        )
    elif latest:
        await callback.message.edit_text(
            f"🔄 Текущая: {current or '?'}\nДоступна: {latest}\n\nОбновить?",
            reply_markup=update_buttons(),
        )
    else:
        await callback.message.edit_text(
            "⚠️ Не удалось проверить обновления",
            reply_markup=back_button(),
        )
    await callback.answer()


@router.callback_query(F.data == "update_confirm")
async def cb_update_confirm(callback: CallbackQuery) -> None:
    await callback.message.edit_text("⏳ Обновляю 3X-UI...")
    await callback.answer()

    success, msg = await _do_update()
    await callback.message.edit_text(msg, reply_markup=back_button())
```

- [ ] **Step 2: Зарегистрировать роутер**

- [ ] **Step 3: Коммит**

```bash
git add bot/handlers/update.py bot/handlers/__init__.py
git commit -m "feat: 3X-UI update handler with rollback"
```

---

## Task 15: Фоновый мониторинг (monitor.py)

**Files:**
- Create: `bot/services/monitor.py`
- Create: `tests/test_monitor.py`

- [ ] **Step 1: Написать failing test**

```python
# tests/test_monitor.py
import pytest


def test_check_thresholds_cpu():
    from bot.services.monitor import check_thresholds

    alerts = check_thresholds(
        cpu_percent=95.0,
        cpu_high_since=310,  # > 300 секунд (5 мин)
        disk_percent=50.0,
        xui_active=True,
        xray_active=True,
        traffic_ratio=1.0,
    )
    assert any("CPU" in a for a in alerts)


def test_check_thresholds_disk():
    from bot.services.monitor import check_thresholds

    alerts = check_thresholds(
        cpu_percent=10.0,
        cpu_high_since=0,
        disk_percent=90.0,
        xui_active=True,
        xray_active=True,
        traffic_ratio=1.0,
    )
    assert any("Disk" in a or "Диск" in a for a in alerts)


def test_check_thresholds_service_down():
    from bot.services.monitor import check_thresholds

    alerts = check_thresholds(
        cpu_percent=10.0,
        cpu_high_since=0,
        disk_percent=50.0,
        xui_active=False,
        xray_active=True,
        traffic_ratio=1.0,
    )
    assert any("x-ui" in a for a in alerts)


def test_check_thresholds_anomaly_traffic():
    from bot.services.monitor import check_thresholds

    alerts = check_thresholds(
        cpu_percent=10.0,
        cpu_high_since=0,
        disk_percent=50.0,
        xui_active=True,
        xray_active=True,
        traffic_ratio=4.0,  # > 3x
    )
    assert any("трафик" in a.lower() or "traffic" in a.lower() for a in alerts)


def test_no_alerts_when_healthy():
    from bot.services.monitor import check_thresholds

    alerts = check_thresholds(
        cpu_percent=20.0,
        cpu_high_since=0,
        disk_percent=50.0,
        xui_active=True,
        xray_active=True,
        traffic_ratio=1.0,
    )
    assert alerts == []
```

- [ ] **Step 2: Запустить — падает**

Run: `python -m pytest tests/test_monitor.py -v`
Expected: FAIL

- [ ] **Step 3: Реализовать monitor.py**

```python
# bot/services/monitor.py
from __future__ import annotations

import asyncio
import logging
import time

import psutil

logger = logging.getLogger(__name__)

CPU_THRESHOLD = 90.0
CPU_DURATION = 300  # 5 минут
DISK_THRESHOLD = 85.0
TRAFFIC_RATIO_THRESHOLD = 3.0
CHECK_INTERVAL = 300  # 5 минут


def check_thresholds(
    cpu_percent: float,
    cpu_high_since: float,
    disk_percent: float,
    xui_active: bool,
    xray_active: bool,
    traffic_ratio: float,
) -> list[str]:
    """Проверяет метрики и возвращает список алертов."""
    alerts: list[str] = []

    if cpu_percent > CPU_THRESHOLD and cpu_high_since > CPU_DURATION:
        alerts.append(f"🔴 CPU > {CPU_THRESHOLD}% более 5 минут ({cpu_percent}%)")

    if disk_percent > DISK_THRESHOLD:
        alerts.append(f"🔴 Диск > {DISK_THRESHOLD}% ({disk_percent}%)")

    if not xui_active:
        alerts.append("🔴 Сервис x-ui не запущен!")

    if not xray_active:
        alerts.append("🔴 Сервис xray не запущен!")

    if traffic_ratio > TRAFFIC_RATIO_THRESHOLD:
        alerts.append(f"🟡 Аномальный трафик: {traffic_ratio:.1f}x от среднего")

    return alerts


async def _is_service_active(name: str) -> bool:
    proc = await asyncio.create_subprocess_exec(
        "systemctl", "is-active", name,
        stdout=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    return stdout.decode().strip() == "active"


class Monitor:
    """Фоновый мониторинг с алертами каждые 5 минут."""

    def __init__(self, bot, chat_id: int) -> None:
        self._bot = bot
        self._chat_id = chat_id
        self._cpu_high_since: float = 0
        self._last_net_bytes: int = 0
        self._last_net_time: float = 0
        self._traffic_history: list[float] = []  # байт/сек за последние 24 часа

    async def run(self) -> None:
        while True:
            try:
                alerts = await self._check()
                if alerts:
                    text = "⚠️ <b>Алерты мониторинга</b>\n\n" + "\n".join(alerts)
                    await self._bot.send_message(self._chat_id, text, parse_mode="HTML")
            except Exception as e:
                logger.error(f"Monitor error: {e}")

            await asyncio.sleep(CHECK_INTERVAL)

    async def _check(self) -> list[str]:
        cpu = psutil.cpu_percent(interval=1)
        now = time.time()

        # Отслеживание длительности высокого CPU
        if cpu > CPU_THRESHOLD:
            if self._cpu_high_since == 0:
                self._cpu_high_since = now
            cpu_duration = now - self._cpu_high_since
        else:
            self._cpu_high_since = 0
            cpu_duration = 0

        disk = psutil.disk_usage("/").percent

        xui_active = await _is_service_active("x-ui")
        xray_active = await _is_service_active("xray")

        # Трафик
        net = psutil.net_io_counters()
        current_bytes = net.bytes_recv + net.bytes_sent
        traffic_ratio = 1.0
        if self._last_net_time > 0:
            elapsed = now - self._last_net_time
            if elapsed > 0:
                rate = (current_bytes - self._last_net_bytes) / elapsed
                self._traffic_history.append(rate)
                # Хранить ~288 записей (24ч * 60/5)
                if len(self._traffic_history) > 288:
                    self._traffic_history = self._traffic_history[-288:]
                if len(self._traffic_history) > 1:
                    avg = sum(self._traffic_history[:-1]) / len(self._traffic_history[:-1])
                    if avg > 0:
                        traffic_ratio = rate / avg

        self._last_net_bytes = current_bytes
        self._last_net_time = now

        return check_thresholds(
            cpu_percent=cpu,
            cpu_high_since=cpu_duration,
            disk_percent=disk,
            xui_active=xui_active,
            xray_active=xray_active,
            traffic_ratio=traffic_ratio,
        )
```

- [ ] **Step 4: Тесты проходят**

Run: `python -m pytest tests/test_monitor.py -v`
Expected: 5 passed

- [ ] **Step 5: Коммит**

```bash
git add bot/services/monitor.py tests/test_monitor.py
git commit -m "feat: background monitor — CPU, disk, services, traffic anomaly alerts"
```

---

## Task 16: Точка входа бота (bot.py)

**Files:**
- Create: `bot/bot.py`

- [ ] **Step 1: Реализовать bot.py**

```python
# bot/bot.py
from __future__ import annotations

import asyncio
import logging
import sys
from pathlib import Path

import aiohttp
from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from dotenv import load_dotenv

from bot.config import load_config
from bot.handlers import register_all_routers
from bot.middleware import AuthMiddleware
from bot.services.monitor import Monitor
from bot.services.xui_api import XUIClient

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("/opt/vps-setup/logs/bot.log"),
    ],
)
logger = logging.getLogger(__name__)






def _seconds_until_utc_hour(hour: int) -> float:
    """Вычисляет количество секунд до следующего hour:00 UTC."""
    from datetime import datetime, timezone, timedelta
    now = datetime.now(timezone.utc)
    target = now.replace(hour=hour, minute=0, second=0, microsecond=0)
    if target <= now:
        target += timedelta(days=1)
    return (target - now).total_seconds()


async def _daily_backup(bot: Bot, chat_id: int) -> None:
    """Ежедневный бэкап в 04:00 UTC."""
    from bot.handlers.backup import create_backup
    from aiogram.types import FSInputFile
    import os

    while True:
        sleep_sec = _seconds_until_utc_hour(4)
        logger.info(f"Next backup in {sleep_sec:.0f}s")
        await asyncio.sleep(sleep_sec)

        try:
            path = await asyncio.to_thread(create_backup)
            size = os.path.getsize(path)
            from datetime import datetime, timezone
            now = datetime.now(timezone.utc)
            if size <= 45 * 1024 * 1024:
                doc = FSInputFile(path)
                await bot.send_document(chat_id, doc, caption=f"💾 Авто-бэкап {now:%Y-%m-%d}")
            else:
                await bot.send_message(chat_id, f"💾 Авто-бэкап сохранён на сервере: {path} ({size // (1024*1024)} MB)")
        except Exception as e:
            logger.error(f"Daily backup failed: {e}")

        # Ждём минимум 60 секунд чтобы не сработать дважды
        await asyncio.sleep(60)


async def _daily_update_check(bot: Bot, chat_id: int) -> None:
    """Ежедневная проверка обновлений 3X-UI."""
    from bot.handlers.update import get_current_version, get_latest_version
    from bot.keyboards import update_buttons

    while True:
        await asyncio.sleep(86400)  # 24 часа
        try:
            current = await get_current_version()
            latest = await get_latest_version()
            if latest and current and latest != current:
                await bot.send_message(
                    chat_id,
                    f"🔄 Доступно обновление 3X-UI: {current} → {latest}",
                    reply_markup=update_buttons(),
                )
        except Exception as e:
            logger.error(f"Update check failed: {e}")


async def main() -> None:
    # Загрузка .env из /opt/vps-setup/.env
    env_path = Path("/opt/vps-setup/.env")
    if env_path.exists():
        load_dotenv(env_path)

    config = load_config()
    logger.info("Config loaded, starting bot...")

    bot = Bot(
        token=config.bot_token,
        default=DefaultBotProperties(parse_mode="HTML"),
    )

    dp = Dispatcher()

    # Регистрация middleware
    root_router = register_all_routers()
    root_router.message.middleware(AuthMiddleware(config.chat_id))
    root_router.callback_query.middleware(AuthMiddleware(config.chat_id))
    dp.include_router(root_router)

    # Инициализация сервисов
    session = aiohttp.ClientSession()
    xui_client = XUIClient(config, session=session)
    await xui_client.login()

    # Прокидываем зависимости через bot storage
    bot["config"] = config
    bot["xui_client"] = xui_client
    bot["link_gen_params"] = {
        "server_ip": config.server_ip,
        "public_key": config.public_key,
        "short_id": config.short_id,
        "sni": config.sni,
    }

    # Фоновые задачи
    monitor = Monitor(bot, config.chat_id)
    asyncio.create_task(monitor.run())
    asyncio.create_task(_daily_backup(bot, config.chat_id))
    asyncio.create_task(_daily_update_check(bot, config.chat_id))

    logger.info("Bot started successfully")
    await bot.send_message(config.chat_id, "🟢 Бот запущен!")

    try:
        await dp.start_polling(bot)
    finally:
        await session.close()
        await bot.session.close()


if __name__ == "__main__":
    asyncio.run(main())
```

- [ ] **Step 2: Финализировать handlers/__init__.py со всеми роутерами**

```python
# bot/handlers/__init__.py
from aiogram import Router

from bot.handlers.start import router as start_router
from bot.handlers.status import router as status_router
from bot.handlers.network import router as network_router
from bot.handlers.users import router as users_router
from bot.handlers.traffic import router as traffic_router
from bot.handlers.diagnostics import router as diagnostics_router
from bot.handlers.backup import router as backup_router
from bot.handlers.tips import router as tips_router
from bot.handlers.update import router as update_router


def register_all_routers() -> Router:
    root = Router()
    root.include_router(start_router)
    root.include_router(status_router)
    root.include_router(network_router)
    root.include_router(users_router)
    root.include_router(traffic_router)
    root.include_router(diagnostics_router)
    root.include_router(backup_router)
    root.include_router(tips_router)
    root.include_router(update_router)
    return root
```

- [ ] **Step 3: Коммит**

```bash
git add bot/bot.py bot/handlers/__init__.py
git commit -m "feat: bot.py entry point — wires config, services, handlers, background tasks"
```

---

## Task 17: setup.sh — Bash-установщик (часть 1: система и безопасность)

**Files:**
- Create: `setup.sh`

- [ ] **Step 1: Создать setup.sh — шапка, проверки, обновление системы**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ===== НАСТРОЙКИ — заполнить перед первым запуском =====
BOT_TOKEN="ВСТАВЬ_ТОКЕН_СЮДА"
CHAT_ID="ВСТАВЬ_CHAT_ID_СЮДА"
# ========================================================

INSTALL_DIR="/opt/vps-setup"
LOG_DIR="/var/log/vps-setup"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1" >&2; }

# --- Проверки ---

if [[ $EUID -ne 0 ]]; then
    err "Запустите от root: sudo bash setup.sh"
    exit 1
fi

if [[ "$BOT_TOKEN" == "ВСТАВЬ_ТОКЕН_СЮДА" || "$CHAT_ID" == "ВСТАВЬ_CHAT_ID_СЮДА" ]]; then
    err "Заполните BOT_TOKEN и CHAT_ID в начале скрипта"
    exit 1
fi

# Проверка Ubuntu
if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
    err "Поддерживается только Ubuntu"
    exit 1
fi

SERVER_IP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)
if [[ -z "$SERVER_IP" ]]; then
    err "Не удалось определить IP сервера"
    exit 1
fi

log "IP сервера: $SERVER_IP"

# --- Деинсталляция ---

if [[ "${1:-}" == "--uninstall" ]]; then
    log "Деинсталляция..."
    systemctl stop vps-bot.service 2>/dev/null || true
    systemctl disable vps-bot.service 2>/dev/null || true
    rm -f /etc/systemd/system/vps-bot.service
    systemctl daemon-reload

    # Удаление cron
    crontab -l 2>/dev/null | grep -v "vps-setup" | crontab - || true

    read -rp "Удалить $INSTALL_DIR? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        log "Удалён $INSTALL_DIR"
    fi

    rm -rf "$LOG_DIR"

    warn "Оставлены (удалите вручную при необходимости):"
    warn "  - 3X-UI (x-ui uninstall)"
    warn "  - UFW правила (ufw status)"
    warn "  - SSH-конфиг (/etc/ssh/sshd_config)"
    warn "  - sysctl настройки (/etc/sysctl.d/99-vps-setup.conf)"
    warn "  - fail2ban (/etc/fail2ban/jail.local)"
    log "Деинсталляция завершена"
    exit 0
fi

# --- Обновление системы ---

log "Обновление системы..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y curl wget jq python3 python3-pip python3-venv ufw fail2ban unzip

# Автообновления безопасности
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# --- SSH-порт ---

read -rp "SSH-порт (текущий: 22, Enter для 22): " SSH_PORT
SSH_PORT="${SSH_PORT:-22}"

if [[ "$SSH_PORT" != "22" ]]; then
    log "Смена SSH-порта на $SSH_PORT..."
    sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
fi

# SSH hardening
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

if [[ -s ~/.ssh/authorized_keys ]]; then
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    log "Парольная аутентификация отключена (ключи найдены)"
else
    warn "authorized_keys пуст — парольная аутентификация оставлена"
fi

systemctl restart sshd

# --- Файрвол ---

log "Настройка UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp comment 'SSH'
ufw allow 443/tcp comment 'VLESS Reality'
echo "y" | ufw enable

# --- Fail2ban ---

log "Настройка fail2ban..."
cat > /etc/fail2ban/jail.local << 'JAIL'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
JAIL

# Подставить кастомный порт
sed -i "s/^port = ssh/port = $SSH_PORT/" /etc/fail2ban/jail.local
systemctl restart fail2ban

# --- Сетевая оптимизация ---

log "Оптимизация сети (BBR)..."
cat > /etc/sysctl.d/99-vps-setup.conf << 'SYSCTL'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192
net.ipv4.ip_forward = 1
SYSCTL
sysctl --system > /dev/null

# --- Проверка Telegram ---

log "Проверка Telegram-бота..."
RESPONSE=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="🟢 VPS Setup запущен на $SERVER_IP")

if ! echo "$RESPONSE" | jq -e '.ok' > /dev/null 2>&1; then
    err "Не удалось отправить сообщение в Telegram. Проверьте BOT_TOKEN и CHAT_ID"
    err "Ответ: $RESPONSE"
    exit 1
fi
log "Telegram OK"
```

- [ ] **Step 2: Коммит**

```bash
chmod +x setup.sh
git add setup.sh
git commit -m "feat: setup.sh part 1 — system update, SSH hardening, UFW, fail2ban, BBR"
```

---

## Task 18: setup.sh — часть 2: 3X-UI, Reality, бот, systemd

**Files:**
- Modify: `setup.sh` (дописать в конец)

- [ ] **Step 1: Дописать установку 3X-UI**

```bash
# --- 3X-UI ---

log "Установка 3X-UI..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<< "y"

# Генерация секретов
XUI_USER="admin_$(openssl rand -hex 4)"
XUI_PASS="$(openssl rand -base64 16)"
XUI_PATH="/panel-$(openssl rand -hex 8)"

# Настройка панели: только localhost, кастомный путь
x-ui setting -username "$XUI_USER" -password "$XUI_PASS"
x-ui setting -webBasePath "$XUI_PATH"
x-ui setting -listen 127.0.0.1
x-ui setting -port 2053

systemctl restart x-ui
sleep 3

log "3X-UI установлен: user=$XUI_USER path=$XUI_PATH"
```

- [ ] **Step 2: Дописать выбор SNI и настройку Reality**

```bash
# --- SNI Selection ---

log "Выбор лучшего SNI..."
SNI_CANDIDATES=("www.microsoft.com" "www.google.com" "www.yahoo.com" "www.apple.com" "www.amazon.com")
BEST_SNI="www.microsoft.com"
BEST_TIME=999

for sni in "${SNI_CANDIDATES[@]}"; do
    total=0
    success=0
    for i in 1 2 3; do
        t=$(curl --connect-timeout 3 -s -o /dev/null -w "%{time_connect}" "https://$sni" 2>/dev/null || echo "999")
        total=$(echo "$total + $t" | bc)
        if [[ "$t" != "999" ]]; then
            ((success++)) || true
        fi
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

KEYS_OUTPUT=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS_OUTPUT" | grep "Private" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS_OUTPUT" | grep "Public" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

log "Reality keys сгенерированы"

# --- Конфиг inbound через API ---

# Ждём готовности API
sleep 5

# Login — сохраняем cookie в файл
COOKIE_FILE=$(mktemp)
curl -s -c "$COOKIE_FILE" "http://127.0.0.1:2053${XUI_PATH}/login" \
    -d "username=$XUI_USER&password=$XUI_PASS" > /dev/null

# Создание inbound с VLESS Reality через API
INBOUND_JSON=$(cat << ENDJSON
{
  "up": 0, "down": 0, "total": 0, "remark": "vless-reality",
  "enable": true, "expiryTime": 0,
  "listen": "", "port": 443, "protocol": "vless",
  "settings": "{\"clients\":[],\"decryption\":\"none\",\"fallbacks\":[]}",
  "streamSettings": "{\"network\":\"tcp\",\"security\":\"reality\",\"realitySettings\":{\"show\":false,\"dest\":\"${BEST_SNI}:443\",\"xver\":0,\"serverNames\":[\"${BEST_SNI}\"],\"privateKey\":\"${PRIVATE_KEY}\",\"shortIds\":[\"${SHORT_ID}\"]},\"tcpSettings\":{\"header\":{\"type\":\"none\"}}}",
  "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\"]}"
}
ENDJSON
)

curl -s -b "$COOKIE_FILE" \
    "http://127.0.0.1:2053${XUI_PATH}/xui/API/inbounds/add" \
    -H "Content-Type: application/json" \
    -d "$INBOUND_JSON" > /dev/null

rm -f "$COOKIE_FILE"

log "VLESS Reality inbound создан на порту 443"
```

- [ ] **Step 3: Дописать развёртывание бота**

```bash
# --- Python Bot ---

log "Развёртывание Telegram-бота..."
mkdir -p "$INSTALL_DIR"/{data/backups,logs}

# Копирование файлов бота
# Если запущен из git-репозитория — копируем bot/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/bot" ]]; then
    cp -r "$SCRIPT_DIR/bot" "$INSTALL_DIR/"
else
    # Скачиваем из репозитория (fallback)
    err "Директория bot/ не найдена рядом со скриптом"
    exit 1
fi

# Виртуальное окружение
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/bot/requirements.txt"

# .env
cat > "$INSTALL_DIR/.env" << ENVFILE
BOT_TOKEN=$BOT_TOKEN
CHAT_ID=$CHAT_ID
XUI_USER=$XUI_USER
XUI_PASS=$XUI_PASS
XUI_PATH=$XUI_PATH
SERVER_IP=$SERVER_IP
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
BEST_SNI=$BEST_SNI
ENVFILE
chmod 600 "$INSTALL_DIR/.env"

# --- Systemd ---

cat > /etc/systemd/system/vps-bot.service << SERVICE
[Unit]
Description=VPS Telegram Bot
After=network.target x-ui.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python -m bot.bot
EnvironmentFile=$INSTALL_DIR/.env
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable vps-bot.service
systemctl start vps-bot.service

# --- Logrotate ---

cat > /etc/logrotate.d/vps-setup << 'LOGROTATE'
/opt/vps-setup/logs/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
LOGROTATE

# --- Итоговое сообщение ---

log "=========================================="
log "  Установка завершена!"
log "=========================================="
log ""
log "  IP: $SERVER_IP"
log "  SSH порт: $SSH_PORT"
log "  3X-UI: http://127.0.0.1:2053$XUI_PATH"
log "  Логин: $XUI_USER"
log "  Пароль: $XUI_PASS"
log ""
log "  SSH-туннель к панели:"
log "  ssh -L 2053:127.0.0.1:2053 -p $SSH_PORT root@$SERVER_IP"
log ""
log "  Reality SNI: $BEST_SNI"
log "  Public Key: $PUBLIC_KEY"
log ""
log "  Бот: @vps_dm_bot"
log "=========================================="

# Отправка в Telegram
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d parse_mode="HTML" \
    -d text="✅ <b>VPS настроен!</b>

🖥 IP: <code>$SERVER_IP</code>
🔑 SSH: <code>ssh -p $SSH_PORT root@$SERVER_IP</code>
🌐 Панель: <code>ssh -L 2053:127.0.0.1:2053 -p $SSH_PORT root@$SERVER_IP</code>

SNI: $BEST_SNI
Public Key: <code>$PUBLIC_KEY</code>" > /dev/null
```

- [ ] **Step 4: Коммит**

```bash
git add setup.sh
git commit -m "feat: setup.sh part 2 — 3X-UI, Reality, bot deploy, systemd"
```

---

## Task 19: Интеграционная проверка и .gitignore

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Создать .gitignore**

```gitignore
__pycache__/
*.pyc
.env
venv/
*.egg-info/
.pytest_cache/
data/backups/
logs/
```

- [ ] **Step 2: Прогнать все тесты**

Run: `python -m pytest tests/ -v --tb=short`
Expected: Все тесты проходят

- [ ] **Step 3: Проверить синтаксис setup.sh**

Run: `bash -n setup.sh`
Expected: Нет ошибок

- [ ] **Step 4: Финальный коммит**

```bash
git add .gitignore
git commit -m "chore: add .gitignore, project ready for deployment"
```

---

## Итого: 19 тасков

| # | Таск | Тесты |
|---|------|-------|
| 1 | Scaffolding + Config loader | 2 |
| 2 | Auth middleware | 2 |
| 3 | Keyboards | 2 |
| 4 | xui_api.py | 4 |
| 5 | link_gen.py | 2 |
| 6 | /start handler | — |
| 7 | Status handler (+ версии) | 1 |
| 8 | Network handler | — |
| 9 | Users handlers | 2 |
| 10 | Traffic handler | — |
| 11 | Diagnostics handler (+ fallback) | — |
| 12 | Backup handler | 1 |
| 13 | Tips handler | — |
| 14 | Update handler | — |
| 15 | Monitor service | 5 |
| 16 | bot.py entry point | — |
| 17 | setup.sh (система) | — |
| 18 | setup.sh (3X-UI, бот) | — |
| 19 | .gitignore, проверки | — |

**Всего: ~21 юнит-тест**
