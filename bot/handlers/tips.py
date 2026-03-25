from aiogram import Router
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup

router = Router()

TIPS_TEXT = (
    "💡 <b>Как подключиться</b>\n\n"
    "1. Установи <b>Hiddify</b>:\n"
    "   • <a href='https://apps.apple.com/app/hiddify-proxy-vpn/id6596777532'>iOS</a>\n"
    "   • <a href='https://play.google.com/store/apps/details?id=app.hiddify.com'>Android</a>\n"
    "   • <a href='https://github.com/hiddify/hiddify-app/releases/latest'>Windows / macOS</a>\n\n"
    "2. Скопируй vless:// ссылку из бота\n\n"
    "3. В Hiddify нажми <b>+</b> → <b>Буфер обмена</b>\n\n"
    "4. Нажми кнопку подключения ▶\n\n"
    "5. Настройки → Регион → <b>Россия</b> (чтобы RU-сайты шли напрямую)"
)


@router.callback_query(lambda c: c.data == "tips")
async def cb_tips(callback: CallbackQuery) -> None:
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔙 Назад", callback_data="main_menu")],
    ])
    await callback.message.edit_text(TIPS_TEXT, reply_markup=kb, parse_mode="HTML", disable_web_page_preview=True)
    await callback.answer()
