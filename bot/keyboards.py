from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup


def main_menu() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="📊 Статус", callback_data="status"),
            InlineKeyboardButton(text="👥 Пользователи", callback_data="users"),
        ],
        [
            InlineKeyboardButton(text="🌐 Сеть", callback_data="network"),
            InlineKeyboardButton(text="📈 Трафик", callback_data="traffic"),
        ],
        [
            InlineKeyboardButton(text="🔍 Диагностика", callback_data="diagnostics"),
            InlineKeyboardButton(text="💾 Бэкап", callback_data="backup"),
        ],
        [
            InlineKeyboardButton(text="💡 Советы", callback_data="tips"),
            InlineKeyboardButton(text="🔄 Обновление", callback_data="update"),
        ],
    ])


def users_menu() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="📋 Список", callback_data="users_list"),
            InlineKeyboardButton(text="➕ Добавить", callback_data="users_add"),
        ],
        [
            InlineKeyboardButton(text="❌ Удалить", callback_data="users_del"),
            InlineKeyboardButton(text="🔙 Назад", callback_data="main_menu"),
        ],
    ])


def back_button() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔙 Назад", callback_data="main_menu")],
    ])


def confirm_delete(email: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="✅ Да", callback_data=f"del_confirm:{email}"),
            InlineKeyboardButton(text="❌ Нет", callback_data="users"),
        ],
    ])


def update_buttons() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="🔄 Обновить", callback_data="update_confirm"),
            InlineKeyboardButton(text="⏭ Пропустить", callback_data="main_menu"),
        ],
    ])
