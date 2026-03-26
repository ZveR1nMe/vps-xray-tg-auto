# Phase 2: Bot Refactor — Unified User List + Key Types

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Refactor Telegram bot to support unified user list where each user can have multiple key types (VLESS, AWG mobile, AWG router).

**Architecture:** user_store.py coordinates between xray_manager and awg_manager. users.json stores metadata. users.py handler completely rewritten for new UI flow with user cards and key type selection.

**Tech Stack:** Python 3.10+, aiogram 3.x, JSON storage

**Spec:** `docs/superpowers/specs/2026-03-27-amneziawg-router-design.md` sections 3.1-3.13

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `bot/services/user_store.py` | Create | users.json CRUD, IP allocation, migration |
| `bot/handlers/users.py` | Rewrite | Unified user list, cards, key management UI |
| `bot/deps.py` | Modify | Add user_store |
| `bot/bot.py` | Modify | Initialize user_store, run migration |

---

### Task 1: Create user_store.py

**Files:**
- Create: `bot/services/user_store.py`

- [ ] **Step 1: Create user_store.py**

```python
"""Единое хранилище пользователей — координатор между менеджерами."""
from __future__ import annotations

import json
import logging
from datetime import datetime
from pathlib import Path

logger = logging.getLogger(__name__)

USERS_FILE = Path("/opt/vps-setup/users.json")


class UserStore:
    def __init__(self) -> None:
        self._path = USERS_FILE
        self._data: dict = {}
        self.load()

    def load(self) -> None:
        if self._path.exists():
            self._data = json.loads(self._path.read_text())
        else:
            self._data = {}

    def save(self) -> None:
        tmp = self._path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self._data, indent=2, ensure_ascii=False))
        tmp.rename(self._path)

    def list_users(self) -> list[str]:
        return list(self._data.keys())

    def get_user(self, name: str) -> dict | None:
        return self._data.get(name)

    def user_exists(self, name: str) -> bool:
        return name in self._data

    def add_user(self, name: str) -> None:
        if name not in self._data:
            self._data[name] = {}
            self.save()

    def add_key(self, name: str, key_type: str, data: dict) -> None:
        if name not in self._data:
            self._data[name] = {}
        data["created"] = datetime.now().isoformat(timespec="seconds")
        self._data[name][key_type] = data
        self.save()

    def delete_key(self, name: str, key_type: str) -> bool:
        if name in self._data and key_type in self._data[name]:
            del self._data[name][key_type]
            self.save()
            return True
        return False

    def delete_user(self, name: str) -> dict | None:
        """Remove user, return their data for cleanup."""
        if name in self._data:
            data = self._data.pop(name)
            self.save()
            return data
        return None

    def get_key(self, name: str, key_type: str) -> dict | None:
        user = self._data.get(name, {})
        return user.get(key_type)

    def user_key_types(self, name: str) -> list[str]:
        return list(self._data.get(name, {}).keys())

    def next_awg_ip(self) -> str:
        """Find next free IP in 10.8.1.0/24 subnet."""
        used = set()
        for user_data in self._data.values():
            for key_type in ("awg", "awg_router"):
                key_data = user_data.get(key_type, {})
                if "ip" in key_data:
                    used.add(key_data["ip"])
        for i in range(2, 255):
            ip = f"10.8.1.{i}"
            if ip not in used:
                return ip
        raise RuntimeError("No free AWG IPs (subnet full)")

    def migrate_from_xray(self, xray_mgr) -> int:
        """Import existing VLESS clients into users.json. Returns count."""
        if self._data:
            return 0  # Already has data, skip migration
        clients = xray_mgr.list_clients()
        count = 0
        for c in clients:
            email = c.get("email", "")
            if email and email not in self._data:
                self._data[email] = {
                    "vless": {
                        "uuid": c["id"],
                        "created": datetime.now().isoformat(timespec="seconds"),
                    }
                }
                count += 1
        if count:
            self.save()
            logger.info("Migrated %d VLESS users to users.json", count)
        return count
```

- [ ] **Step 2: Verify syntax**

Run: `python3 -c "import ast; ast.parse(open('bot/services/user_store.py').read()); print('OK')"`

- [ ] **Step 3: Commit**

```bash
git add bot/services/user_store.py
git commit -m "feat: add user_store.py for unified user management"
```

---

### Task 2: Wire user_store into deps.py and bot.py

**Files:**
- Modify: `bot/deps.py`
- Modify: `bot/bot.py`

- [ ] **Step 1: Add user_store to deps.py**

Add import and variable:
```python
if TYPE_CHECKING:
    from bot.services.user_store import UserStore
# ...
user_store: UserStore = None  # type: ignore
```

- [ ] **Step 2: Initialize user_store in bot.py**

After deps.config assignment, add:
```python
    from bot.services.user_store import UserStore
    deps.user_store = UserStore()

    # Migration from existing VLESS clients
    if config.has_vless and deps.xray_mgr:
        migrated = deps.user_store.migrate_from_xray(deps.xray_mgr)
        if migrated:
            logger.info("Migrated %d existing VLESS users", migrated)
```

- [ ] **Step 3: Verify and commit**

```bash
python3 -c "import ast; ast.parse(open('bot/deps.py').read()); ast.parse(open('bot/bot.py').read()); print('OK')"
git add bot/deps.py bot/bot.py
git commit -m "feat: wire user_store into deps and bot with VLESS migration"
```

---

### Task 3: Rewrite users.py handler

**Files:**
- Rewrite: `bot/handlers/users.py`

This is the biggest task. The handler needs to support:
- User list with click-to-open cards
- User card showing existing keys with add/delete options
- Key type selection (filtered by INSTALL_MODE and existing keys)
- VLESS key: QR + link + Happ routing
- AWG mobile key: .conf file + QR
- AWG router key: .conf file
- Delete individual key or entire user

- [ ] **Step 1: Rewrite users.py**

Complete replacement of `bot/handlers/users.py`:

```python
"""Unified user management — list, cards, key types."""
from __future__ import annotations

import io
import qrcode
from aiogram import F, Router
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import (
    CallbackQuery, Message, BufferedInputFile,
    InlineKeyboardButton, InlineKeyboardMarkup, CopyTextButton,
)

router = Router()

KEY_LABELS = {
    "vless": "VLESS Reality",
    "awg": "AmneziaWG",
    "awg_router": "AWG Роутер",
}

HAPP_DOWNLOAD_TEXT = (
    "📲 <b>Скачать Happ:</b>\n"
    "• <a href='https://apps.apple.com/ru/app/happ-proxy-utility-plus/id6746188973'>iOS (App Store RU)</a>\n"
    "• <a href='https://github.com/Happ-proxy/happ-android/releases/latest/download/Happ.apk'>Android (APK)</a>\n"
    "• <a href='https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.macOS.universal.dmg'>macOS</a>\n"
    "• <a href='https://github.com/Happ-proxy/happ-desktop/releases/latest/download/setup-Happ.x64.exe'>Windows</a>"
)


class AddUser(StatesGroup):
    waiting_name = State()


def _deps():
    from bot import deps
    return deps


def _available_key_types(existing_keys: list[str]) -> list[str]:
    """Return key types that can be added (not yet created + allowed by mode)."""
    deps = _deps()
    available = []
    if deps.config.has_vless and "vless" not in existing_keys:
        available.append("vless")
    if deps.config.has_awg and "awg" not in existing_keys:
        available.append("awg")
    if deps.config.has_awg and "awg_router" not in existing_keys:
        available.append("awg_router")
    return available


def _make_qr(data: str) -> bytes:
    qr = qrcode.make(data)
    buf = io.BytesIO()
    qr.save(buf, format="PNG")
    buf.seek(0)
    return buf.read()


# --- User List ---

@router.callback_query(F.data == "users")
async def cb_users(callback: CallbackQuery) -> None:
    store = _deps().user_store
    users = store.list_users()

    rows = []
    for name in users:
        keys = store.user_key_types(name)
        key_icons = " ".join("🔑" for _ in keys) if keys else "—"
        rows.append([
            InlineKeyboardButton(
                text=f"👤 {name} ({key_icons})",
                callback_data=f"user:{name}",
            ),
        ])
    rows.append([
        InlineKeyboardButton(text="➕ Добавить", callback_data="users_add"),
        InlineKeyboardButton(text="🔙 Назад", callback_data="main_menu"),
    ])

    text = f"👥 <b>Пользователи ({len(users)})</b>" if users else "👥 Нет пользователей"
    kb = InlineKeyboardMarkup(inline_keyboard=rows)

    try:
        await callback.message.edit_text(text, reply_markup=kb, parse_mode="HTML")
    except Exception:
        await callback.message.delete()
        await callback.message.answer(text, reply_markup=kb, parse_mode="HTML")
    await callback.answer()


# --- Add User ---

@router.callback_query(F.data == "users_add")
async def cb_users_add(callback: CallbackQuery, state: FSMContext) -> None:
    await callback.message.edit_text("Введите имя нового пользователя:")
    await state.set_state(AddUser.waiting_name)
    await callback.answer()


@router.message(AddUser.waiting_name)
async def on_user_name(message: Message, state: FSMContext) -> None:
    name = message.text.strip()
    if not name:
        await message.answer("Имя не может быть пустым:")
        return

    store = _deps().user_store
    if store.user_exists(name):
        await message.answer(f"❌ Пользователь <b>{name}</b> уже существует", parse_mode="HTML")
        await state.clear()
        return

    store.add_user(name)
    await state.clear()
    await _show_user_card(message.answer, message.answer, name, f"✅ <b>{name}</b> добавлен!")


# --- User Card ---

async def _show_user_card(edit_or_send, answer_fn, name: str, title: str | None = None) -> None:
    store = _deps().user_store
    user = store.get_user(name)
    if not user:
        return

    if title is None:
        title = f"👤 <b>{name}</b>"

    keys = store.user_key_types(name)
    lines = [title, "", "<b>Ключи:</b>"]
    for kt in keys:
        lines.append(f"  ✅ {KEY_LABELS.get(kt, kt)}")
    if not keys:
        lines.append("  — нет ключей")

    rows = []
    # Existing keys — show config
    for kt in keys:
        rows.append([
            InlineKeyboardButton(
                text=f"📄 {KEY_LABELS.get(kt, kt)}",
                callback_data=f"user_key:{name}:{kt}",
            ),
            InlineKeyboardButton(
                text="🗑",
                callback_data=f"del_key_ask:{name}:{kt}",
            ),
        ])

    # Add key button
    available = _available_key_types(keys)
    if available:
        rows.append([
            InlineKeyboardButton(text="➕ Добавить ключ", callback_data=f"add_key_menu:{name}"),
        ])

    rows.append([
        InlineKeyboardButton(text="🗑 Удалить пользователя", callback_data=f"del_user_ask:{name}"),
        InlineKeyboardButton(text="🔙 Назад", callback_data="users"),
    ])

    kb = InlineKeyboardMarkup(inline_keyboard=rows)
    text = "\n".join(lines)

    try:
        await edit_or_send(text, reply_markup=kb, parse_mode="HTML")
    except Exception:
        await answer_fn(text, reply_markup=kb, parse_mode="HTML")


@router.callback_query(F.data.startswith("user:"))
async def cb_user_card(callback: CallbackQuery) -> None:
    name = callback.data.split(":", 1)[1]
    await _show_user_card(callback.message.edit_text, callback.message.answer, name)
    await callback.answer()


# --- Add Key ---

@router.callback_query(F.data.startswith("add_key_menu:"))
async def cb_add_key_menu(callback: CallbackQuery) -> None:
    name = callback.data.split(":", 1)[1]
    store = _deps().user_store
    existing = store.user_key_types(name)
    available = _available_key_types(existing)

    if not available:
        await callback.answer("Все типы ключей уже добавлены")
        return

    rows = []
    for kt in available:
        rows.append([
            InlineKeyboardButton(
                text=KEY_LABELS.get(kt, kt),
                callback_data=f"add_key:{name}:{kt}",
            ),
        ])
    rows.append([
        InlineKeyboardButton(text="🔙 Назад", callback_data=f"user:{name}"),
    ])

    kb = InlineKeyboardMarkup(inline_keyboard=rows)
    await callback.message.edit_text(
        f"Какой ключ добавить для <b>{name}</b>?",
        reply_markup=kb, parse_mode="HTML",
    )
    await callback.answer()


@router.callback_query(F.data.startswith("add_key:"))
async def cb_add_key(callback: CallbackQuery) -> None:
    _, name, key_type = callback.data.split(":", 2)
    deps = _deps()
    store = deps.user_store

    try:
        if key_type == "vless":
            link = await deps.xray_mgr.add_client(name)
            clients = deps.xray_mgr.list_clients()
            uuid = next((c["id"] for c in clients if c["email"] == name), "")
            store.add_key(name, "vless", {"uuid": uuid})
            await callback.message.delete()
            await _send_vless_card(callback.message.answer_photo, callback.message.answer, name, link)

        elif key_type in ("awg", "awg_router"):
            client_ip = store.next_awg_ip()
            comment = f"{name} ({key_type})"
            peer_data = await deps.awg_mgr.add_peer(comment, client_ip)
            store.add_key(name, key_type, {
                "private_key": peer_data["private_key"],
                "public_key": peer_data["public_key"],
                "psk": peer_data["psk"],
                "ip": client_ip,
            })
            for_router = key_type == "awg_router"
            config_text = deps.awg_mgr.make_client_config(
                peer_data["private_key"], peer_data["psk"], client_ip, for_router=for_router,
            )
            await callback.message.delete()
            await _send_awg_card(callback.message.answer_photo, callback.message.answer, name, key_type, config_text)

    except Exception as e:
        await callback.message.edit_text(f"❌ Ошибка: {e}")
    await callback.answer()


# --- Show Key ---

@router.callback_query(F.data.startswith("user_key:"))
async def cb_show_key(callback: CallbackQuery) -> None:
    _, name, key_type = callback.data.split(":", 2)
    deps = _deps()
    store = deps.user_store

    await callback.message.delete()

    if key_type == "vless":
        link = deps.xray_mgr.get_link(name)
        if link:
            await _send_vless_card(callback.message.answer_photo, callback.message.answer, name, link)
        else:
            await callback.message.answer(f"❌ VLESS ключ для {name} не найден")

    elif key_type in ("awg", "awg_router"):
        key_data = store.get_key(name, key_type)
        if key_data:
            for_router = key_type == "awg_router"
            config_text = deps.awg_mgr.make_client_config(
                key_data["private_key"], key_data["psk"], key_data["ip"], for_router=for_router,
            )
            await _send_awg_card(callback.message.answer_photo, callback.message.answer, name, key_type, config_text)
        else:
            await callback.message.answer(f"❌ Ключ не найден")

    await callback.answer()


# --- Delete Key ---

@router.callback_query(F.data.startswith("del_key_ask:"))
async def cb_del_key_ask(callback: CallbackQuery) -> None:
    _, name, key_type = callback.data.split(":", 2)
    label = KEY_LABELS.get(key_type, key_type)
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="✅ Да", callback_data=f"del_key_confirm:{name}:{key_type}"),
            InlineKeyboardButton(text="❌ Нет", callback_data=f"user:{name}"),
        ],
    ])
    await callback.message.edit_text(
        f"Удалить ключ <b>{label}</b> у <b>{name}</b>?",
        parse_mode="HTML", reply_markup=kb,
    )
    await callback.answer()


@router.callback_query(F.data.startswith("del_key_confirm:"))
async def cb_del_key_confirm(callback: CallbackQuery) -> None:
    _, name, key_type = callback.data.split(":", 2)
    deps = _deps()
    store = deps.user_store

    try:
        if key_type == "vless" and deps.xray_mgr:
            await deps.xray_mgr.delete_client(name)
        elif key_type in ("awg", "awg_router") and deps.awg_mgr:
            key_data = store.get_key(name, key_type)
            if key_data and "public_key" in key_data:
                await deps.awg_mgr.delete_peer(key_data["public_key"])

        store.delete_key(name, key_type)
        await callback.answer(f"✅ Ключ удалён")
    except Exception as e:
        await callback.answer(f"❌ {e}")

    await _show_user_card(callback.message.edit_text, callback.message.answer, name)


# --- Delete User ---

@router.callback_query(F.data.startswith("del_user_ask:"))
async def cb_del_user_ask(callback: CallbackQuery) -> None:
    name = callback.data.split(":", 1)[1]
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="✅ Да", callback_data=f"del_user_confirm:{name}"),
            InlineKeyboardButton(text="❌ Нет", callback_data=f"user:{name}"),
        ],
    ])
    await callback.message.edit_text(
        f"Удалить <b>{name}</b> и все ключи?",
        parse_mode="HTML", reply_markup=kb,
    )
    await callback.answer()


@router.callback_query(F.data.startswith("del_user_confirm:"))
async def cb_del_user_confirm(callback: CallbackQuery) -> None:
    name = callback.data.split(":", 1)[1]
    deps = _deps()
    store = deps.user_store
    user_data = store.get_user(name)

    if user_data:
        # Delete from service configs
        if "vless" in user_data and deps.xray_mgr:
            try:
                await deps.xray_mgr.delete_client(name)
            except Exception:
                pass
        for kt in ("awg", "awg_router"):
            if kt in user_data and deps.awg_mgr:
                try:
                    await deps.awg_mgr.delete_peer(user_data[kt]["public_key"])
                except Exception:
                    pass
        store.delete_user(name)

    await callback.answer(f"✅ {name} удалён")
    await cb_users(callback)


# --- Send Cards ---

async def _send_vless_card(send_photo, send_text, name: str, link: str) -> None:
    deps = _deps()
    tg_proxy = deps.config.tg_proxy_link

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📋 Скопировать VPN", copy_text=CopyTextButton(text=link))],
        [InlineKeyboardButton(text="📱 Прокси для Telegram", url=tg_proxy)],
        [InlineKeyboardButton(text="🔙 К пользователю", callback_data=f"user:{name}")],
    ])

    qr_data = _make_qr(link)
    await send_photo(
        BufferedInputFile(qr_data, filename=f"qr_{name}_vless.png"),
        caption=(
            f"👤 <b>{name}</b> — VLESS Reality\n\n"
            f"🔑 VPN:\n<code>{link}</code>\n\n"
            f"📱 Прокси для Telegram:\n<a href='{tg_proxy}'>Подключить</a>"
        ),
        parse_mode="HTML",
        reply_markup=kb,
    )
    routing_link = deps.xray_mgr.get_happ_routing_link()
    await send_text(
        f"⚡ <b>Роутинг для Happ:</b>\n"
        f"<code>{routing_link}</code>\n\n"
        f"{HAPP_DOWNLOAD_TEXT}",
        parse_mode="HTML",
        disable_web_page_preview=True,
    )


async def _send_awg_card(send_photo, send_text, name: str, key_type: str, config_text: str) -> None:
    label = KEY_LABELS.get(key_type, key_type)

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔙 К пользователю", callback_data=f"user:{name}")],
    ])

    # Send config as file
    await send_text(
        f"👤 <b>{name}</b> — {label}\n\n"
        f"<pre>{config_text}</pre>",
        parse_mode="HTML",
    )

    config_file = BufferedInputFile(
        config_text.encode(),
        filename=f"awg_{name}_{key_type}.conf",
    )
    await send_text(
        "📎 Конфиг-файл:",
        reply_markup=kb,
    )

    # Try QR (may be too long for router configs)
    try:
        qr_data = _make_qr(config_text)
        await send_photo(
            BufferedInputFile(qr_data, filename=f"qr_{name}_{key_type}.png"),
            caption=f"📱 QR для {label}",
            reply_markup=kb,
        )
    except Exception:
        pass  # Config too long for QR, skip
```

- [ ] **Step 2: Verify syntax**

Run: `python3 -c "import ast; ast.parse(open('bot/handlers/users.py').read()); print('OK')"`

- [ ] **Step 3: Commit**

```bash
git add bot/handlers/users.py
git commit -m "feat: rewrite users.py for unified user list with multi-key support"
```

---

## Phase 2 Completion Criteria

- user_store.py manages users.json with CRUD operations
- users.py shows unified list → user cards → key management
- Migration imports existing VLESS clients on first run
- Bot works in all three modes (vless/awg/both)
- Backwards compatible — existing VLESS users preserved
