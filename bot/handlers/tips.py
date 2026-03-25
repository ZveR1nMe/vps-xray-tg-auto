from aiogram import Router
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup

router = Router()

TIPS_TEXT = (
    "💡 <b>Как подключиться</b>\n\n"
    "1. Установи любой клиент с поддержкой VLESS+Reality:\n"
    "   • <a href='https://github.com/MatsuriDayo/NekoBoxForAndroid/releases'>NekoBox</a> (Android)\n"
    "   • <a href='https://apps.apple.com/app/streisand/id6450534064'>Streisand</a> (iOS)\n"
    "   • <a href='https://github.com/netchx/netch/releases'>Netch</a> (Windows)\n"
    "   • <a href='https://github.com/MatsuriDayo/nekoray/releases'>Nekoray</a> (Windows / Linux)\n"
    "   • <a href='https://apps.apple.com/app/v2box-v2ray-client/id6446814690'>V2Box</a> (macOS / iOS)\n\n"
    "2. Скопируй <code>vless://</code> ссылку из бота (кнопка 📋)\n\n"
    "3. В клиенте добавь профиль из буфера обмена или отсканируй QR\n\n"
    "4. Подключись ▶"
)


@router.callback_query(lambda c: c.data == "tips")
async def cb_tips(callback: CallbackQuery) -> None:
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔙 Назад", callback_data="main_menu")],
    ])
    await callback.message.edit_text(TIPS_TEXT, reply_markup=kb, parse_mode="HTML", disable_web_page_preview=True)
    await callback.answer()
