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
    from bot import deps
    xui = deps.xui_client
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

    from bot import deps
    xui = deps.xui_client
    link_gen = deps.link_gen_params

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

    from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup, CopyTextButton, BufferedInputFile
    import qrcode
    import io

    copy_kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📋 Скопировать ссылку", copy_text=CopyTextButton(text=link))],
        [InlineKeyboardButton(text="🔙 Назад", callback_data="users")],
    ])

    # Генерируем QR-код
    qr = qrcode.make(link)
    buf = io.BytesIO()
    qr.save(buf, format="PNG")
    buf.seek(0)

    await message.answer_photo(
        BufferedInputFile(buf.read(), filename=f"qr_{name}.png"),
        caption=(
            f"✅ Пользователь <b>{name}</b> добавлен!\n\n"
            f"<code>{link}</code>\n\n"
            f"Отсканируй QR или скопируй ссылку → вставь в Hiddify через «Буфер обмена»."
        ),
        parse_mode="HTML",
        reply_markup=copy_kb,
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
    from bot import deps
    xui = deps.xui_client

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
