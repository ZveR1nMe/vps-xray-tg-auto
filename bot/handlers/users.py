from __future__ import annotations

import asyncio
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


class AddUser(StatesGroup):
    waiting_name = State()


def _get_mgr():
    from bot import deps
    return deps.xray_mgr


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
    await callback.message.edit_text(text, reply_markup=InlineKeyboardMarkup(inline_keyboard=rows), parse_mode="HTML")
    await callback.answer()


@router.callback_query(F.data.startswith("user_link:"))
async def cb_user_link(callback: CallbackQuery) -> None:
    email = callback.data.split(":", 1)[1]
    mgr = _get_mgr()
    link = mgr.get_link(email)
    if not link:
        await callback.answer("Пользователь не найден")
        return

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📋 Скопировать", copy_text=CopyTextButton(text=link))],
        [InlineKeyboardButton(text="🔙 Назад", callback_data="users")],
    ])

    qr = qrcode.make(link)
    buf = io.BytesIO()
    qr.save(buf, format="PNG")
    buf.seek(0)

    await callback.message.delete()
    await callback.message.answer_photo(
        BufferedInputFile(buf.read(), filename=f"qr_{email}.png"),
        caption=f"👤 <b>{email}</b>\n\n<code>{link}</code>",
        parse_mode="HTML",
        reply_markup=kb,
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

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📋 Скопировать ссылку", copy_text=CopyTextButton(text=link))],
        [InlineKeyboardButton(text="🔙 К пользователям", callback_data="users")],
    ])

    qr = qrcode.make(link)
    buf = io.BytesIO()
    qr.save(buf, format="PNG")
    buf.seek(0)

    await message.answer_photo(
        BufferedInputFile(buf.read(), filename=f"qr_{name}.png"),
        caption=(
            f"✅ <b>{name}</b> добавлен!\n\n"
            f"<code>{link}</code>\n\n"
            f"Отсканируй QR или скопируй ссылку → вставь в клиент"
        ),
        parse_mode="HTML",
        reply_markup=kb,
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
