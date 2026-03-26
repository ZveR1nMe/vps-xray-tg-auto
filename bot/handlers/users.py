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
