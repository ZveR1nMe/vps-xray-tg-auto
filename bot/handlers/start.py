from aiogram import Router
from aiogram.filters import CommandStart
from aiogram.types import CallbackQuery, Message, InlineKeyboardButton, InlineKeyboardMarkup

router = Router()


def main_menu() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="📊 Статус", callback_data="status"),
            InlineKeyboardButton(text="👥 Пользователи", callback_data="users"),
        ],
        [
            InlineKeyboardButton(text="🌐 Сеть", callback_data="network"),
            InlineKeyboardButton(text="💡 Советы", callback_data="tips"),
        ],
    ])


@router.message(CommandStart())
async def cmd_start(message: Message) -> None:
    await message.answer("🖥 <b>VPS Control Panel</b>", reply_markup=main_menu(), parse_mode="HTML")


@router.callback_query(lambda c: c.data == "main_menu")
async def cb_main_menu(callback: CallbackQuery) -> None:
    await callback.message.edit_text("🖥 <b>VPS Control Panel</b>", reply_markup=main_menu(), parse_mode="HTML")
    await callback.answer()
