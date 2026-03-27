import asyncio
import psutil
import time
from aiogram import Router
from bot.services.monitor import is_process_running, is_awg_running
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup

router = Router()


@router.callback_query(lambda c: c.data == "status")
async def cb_status(callback: CallbackQuery) -> None:
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    swap = psutil.swap_memory()
    uptime_sec = time.time() - psutil.boot_time()
    days, rem = divmod(int(uptime_sec), 86400)
    hours, rem = divmod(rem, 3600)
    minutes = rem // 60
    load = psutil.getloadavg()

    from bot import deps
    config = deps.config

    services_lines = []

    if config.has_vless:
        xray_ok = await is_process_running("xray")
        services_lines.append(f"Xray: {'✅' if xray_ok else '❌'}")

    if config.has_awg:
        awg_ok = await is_awg_running()
        services_lines.append(f"AWG: {'✅' if awg_ok else '❌'}")

    services_text = "\n".join(services_lines) if services_lines else "Сервисы: нет данных"

    text = (
        f"📊 <b>Статус сервера</b>\n\n"
        f"CPU: {await asyncio.to_thread(psutil.cpu_percent, 1)}%\n"
        f"RAM: {mem.used / (1024**3):.1f}/{mem.total / (1024**3):.1f} GB\n"
        f"Disk: {disk.used / (1024**3):.1f}/{disk.total / (1024**3):.1f} GB\n"
        f"Swap: {swap.used / (1024**3):.1f}/{swap.total / (1024**3):.1f} GB\n"
        f"Load: {load[0]:.2f}, {load[1]:.2f}, {load[2]:.2f}\n"
        f"Uptime: {days}d {hours}h {minutes}m\n\n"
        f"{services_text}"
    )

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔙 Назад", callback_data="main_menu")],
    ])
    await callback.message.edit_text(text, reply_markup=kb, parse_mode="HTML")
    await callback.answer()
