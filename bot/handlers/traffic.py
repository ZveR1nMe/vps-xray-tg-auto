from aiogram import Router
from aiogram.types import CallbackQuery

from bot.handlers.users import parse_clients
from bot.keyboards import back_button

router = Router()


def _format_bytes(b: int) -> str:
    if b < 1024:
        return f"{b} B"
    elif b < 1024 ** 2:
        return f"{b / 1024:.1f} KB"
    elif b < 1024 ** 3:
        return f"{b / (1024 ** 2):.1f} MB"
    return f"{b / (1024 ** 3):.2f} GB"


@router.callback_query(lambda c: c.data == "traffic")
async def cb_traffic(callback: CallbackQuery) -> None:
    from bot import deps
    xui = deps.xui_client
    inbounds = await xui.list_inbounds()

    lines = ["📈 <b>Трафик по пользователям</b>\n"]
    for ib in inbounds:
        clients = parse_clients(ib)
        client_stats = ib.get("clientStats", [])

        stat_map = {s["email"]: s for s in client_stats} if client_stats else {}

        for c in clients:
            email = c["email"]
            stats = stat_map.get(email, {})
            up = stats.get("up", 0)
            down = stats.get("down", 0)
            lines.append(f"👤 {email}: ↑{_format_bytes(up)} ↓{_format_bytes(down)}")

    if len(lines) == 1:
        lines.append("Нет данных о трафике")

    await callback.message.edit_text(
        "\n".join(lines), reply_markup=back_button(), parse_mode="HTML"
    )
    await callback.answer()
