from bot.keyboards import main_menu, users_menu


def test_main_menu_has_expected_buttons():
    kb = main_menu()
    texts = [btn.text for row in kb.inline_keyboard for btn in row]
    assert "📊 Статус" in texts
    assert "👥 Пользователи" in texts
    assert "🌐 Сеть" in texts
    assert "🔍 Диагностика" in texts
    assert "💾 Бэкап" in texts
    assert "💡 Советы" in texts


def test_users_menu_has_expected_buttons():
    kb = users_menu()
    texts = [btn.text for row in kb.inline_keyboard for btn in row]
    assert "📋 Список" in texts
    assert "➕ Добавить" in texts
    assert "🔙 Назад" in texts
