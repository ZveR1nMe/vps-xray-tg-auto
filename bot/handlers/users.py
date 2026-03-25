from __future__ import annotations

import io
import functools

import qrcode
from aiogram import F, Router
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import (
    CallbackQuery, Message, BufferedInputFile,
    InlineKeyboardButton, InlineKeyboardMarkup, CopyTextButton,
)

router = Router()

HAPP_DOWNLOAD_TEXT = (
    "📲 <b>Скачать Happ:</b>\n"
    "• <a href='https://apps.apple.com/ru/app/happ-proxy-utility-plus/id6746188973'>iOS (App Store RU)</a>\n"
    "• <a href='https://github.com/Happ-proxy/happ-android/releases/latest/download/Happ.apk'>Android (APK)</a>\n"
    "• <a href='https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.macOS.universal.dmg'>macOS</a>\n"
    "• <a href='https://github.com/Happ-proxy/happ-desktop/releases/latest/download/setup-Happ.x64.exe'>Windows</a>"
)


class AddUser(StatesGroup):
    waiting_name = State()


def _get_mgr():
    from bot import deps
    return deps.xray_mgr


def _get_tg_proxy() -> str:
    from bot import deps
    return deps.config.tg_proxy_link


@functools.cache
def _get_routing_link() -> str:
    from bot.services.xray_manager import XrayManager
    return XrayManager.get_happ_routing_link()


async def _send_user_card(
    send_photo,
    send_text,
    name: str,
    link: str,
    caption_prefix: str,
    back_callback: str,
) -> None:
    """Отправляет QR + ссылки + роутинг + скачивание."""
    tg_proxy = _get_tg_proxy()

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📋 Скопировать VPN", copy_text=CopyTextButton(text=link))],
        [InlineKeyboardButton(text="📱 Прокси для Telegram", url=tg_proxy)],
        [InlineKeyboardButton(text="🔙 Назад", callback_data=back_callback)],
    ])

    qr = qrcode.make(link)
    buf = io.BytesIO()
    qr.save(buf, format="PNG")
    buf.seek(0)

    await send_photo(
        BufferedInputFile(buf.read(), filename=f"qr_{name}.png"),
        caption=(
            f"{caption_prefix}\n\n"
            f"🔑 VPN:\n<code>{link}</code>\n\n"
            f"📱 Прокси для Telegram:\n<a href='{tg_proxy}'>Нажми чтобы подключить</a>"
        ),
        parse_mode="HTML",
        reply_markup=kb,
    )
    await send_text(
        f"⚡ <b>Роутинг для Happ (split-tunnel):</b>\n"
        f"<code>{_get_routing_link()}</code>\n\n"
        f"{HAPP_DOWNLOAD_TEXT}",
        parse_mode="HTML",
        disable_web_page_preview=True,
    )


@router.callback_query(F.data == "users")
async def cb_users(callback: CallbackQuery) -> None:
    mgr = _get_mgr()
    clients = mgr.list_clients()

    rows = []
    for c in clients:
        email = c["email"]
        rows.append([
            InlineKeyboardButton(text=f"👤 {email}", callback_data=f"user_link:{email}"),
            InlineKeyboardButton(text="🗑", callback_data=f"del_ask:{email}"),
        ])
    rows.append([
        InlineKeyboardButton(text="➕ Добавить", callback_data="users_add"),
        InlineKeyboardButton(text="🔙 Назад", callback_data="main_menu"),
    ])

    text = f"👥 <b>Пользователи ({len(clients)})</b>" if clients else "👥 Нет пользователей"
    kb = InlineKeyboardMarkup(inline_keyboard=rows)

    try:
        await callback.message.edit_text(text, reply_markup=kb, parse_mode="HTML")
    except Exception:
        await callback.message.delete()
        await callback.message.answer(text, reply_markup=kb, parse_mode="HTML")
    await callback.answer()


@router.callback_query(F.data.startswith("user_link:"))
async def cb_user_link(callback: CallbackQuery) -> None:
    email = callback.data.split(":", 1)[1]
    mgr = _get_mgr()
    link = mgr.get_link(email)
    if not link:
        await callback.answer("Пользователь не найден")
        return

    await callback.message.delete()
    await _send_user_card(
        send_photo=callback.message.answer_photo,
        send_text=callback.message.answer,
        name=email,
        link=link,
        caption_prefix=f"👤 <b>{email}</b>",
        back_callback="users",
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
        await message.answer("Имя не может быть пустым:")
        return

    mgr = _get_mgr()
    try:
        link = await mgr.add_client(name)
    except Exception as e:
        await message.answer(f"❌ Ошибка: {e}")
        await state.clear()
        return

    await _send_user_card(
        send_photo=message.answer_photo,
        send_text=message.answer,
        name=name,
        link=link,
        caption_prefix=f"✅ <b>{name}</b> добавлен!",
        back_callback="users",
    )
    await state.clear()


@router.callback_query(F.data.startswith("del_ask:"))
async def cb_del_ask(callback: CallbackQuery) -> None:
    email = callback.data.split(":", 1)[1]
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="✅ Да", callback_data=f"del_confirm:{email}"),
            InlineKeyboardButton(text="❌ Нет", callback_data="users"),
        ],
    ])
    await callback.message.edit_text(f"Удалить <b>{email}</b>?", parse_mode="HTML", reply_markup=kb)
    await callback.answer()


@router.callback_query(F.data.startswith("del_confirm:"))
async def cb_del_confirm(callback: CallbackQuery) -> None:
    email = callback.data.split(":", 1)[1]
    mgr = _get_mgr()
    try:
        deleted = await mgr.delete_client(email)
    except Exception as e:
        await callback.message.edit_text(f"❌ Ошибка: {e}")
        await callback.answer()
        return

    if deleted:
        await callback.answer(f"✅ {email} удалён")
        await cb_users(callback)
    else:
        await callback.message.edit_text(f"❌ {email} не найден")
        await callback.answer()
