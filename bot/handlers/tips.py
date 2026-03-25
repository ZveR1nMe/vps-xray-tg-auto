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
