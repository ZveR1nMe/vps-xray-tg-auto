from aiogram import Router
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup

router = Router()

TIPS_TEXT = (
    "💡 <b>Как подключиться</b>\n\n"
    "<b>Рекомендуемый клиент — Happ:</b>\n"
    "   • <a href='https://apps.apple.com/ru/app/happ-proxy-utility-plus/id6746188973'>Happ</a> (iOS — App Store RU)\n"
    "   • <a href='https://github.com/Happ-proxy/happ-android/releases/latest/download/Happ.apk'>Happ</a> (Android — APK)\n"
    "   • <a href='https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.macOS.universal.dmg'>Happ</a> (macOS)\n"
    "   • <a href='https://github.com/Happ-proxy/happ-desktop/releases/latest/download/setup-Happ.x64.exe'>Happ</a> (Windows)\n\n"
    "<b>Шаг 1 — Добавь сервер:</b>\n"
    "Скопируй <code>vless://</code> ссылку (кнопка 📋)\n"
    "В Happ → Добавить → Вставить из буфера\n\n"
    "<b>Шаг 2 — Настрой роутинг:</b>\n"
    "Нажми 📥 Роутинг для Happ\n"
    "Скопируй ссылку → открой в браузере\n"
    "🇷🇺 Российские сайты пойдут напрямую!\n\n"
    "<b>Другие клиенты:</b>\n"
    "   • <a href='https://github.com/MatsuriDayo/NekoBoxForAndroid/releases'>NekoBox</a> (Android)\n"
    "   • <a href='https://apps.apple.com/app/streisand/id6450534064'>Streisand</a> (iOS)\n"
    "   • <a href='https://github.com/MatsuriDayo/nekoray/releases'>Nekoray</a> (Windows / Linux)\n"
)


@router.callback_query(lambda c: c.data == "tips")
async def cb_tips(callback: CallbackQuery) -> None:
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔙 Назад", callback_data="main_menu")],
    ])
    await callback.message.edit_text(TIPS_TEXT, reply_markup=kb, parse_mode="HTML", disable_web_page_preview=True)
    await callback.answer()
