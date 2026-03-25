import asyncio
import psutil
import time
from aiogram import Router
from aiogram.types import CallbackQuery

from bot.keyboards import back_button

router = Router()


async def _get_version(cmd: list[str]) -> str:
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await proc.communicate()
        return stdout.decode().strip() or "?"
    except Exception:
        return "?"


def _get_system_status() -> dict:
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    swap = psutil.swap_memory()
    uptime_sec = time.time() - psutil.boot_time()
    days, rem = divmod(int(uptime_sec), 86400)
    hours, rem = divmod(rem, 3600)
    minutes = rem // 60
    load = psutil.getloadavg()

    return {
        "cpu_percent": psutil.cpu_percent(interval=0),
        "mem_used_gb": round(mem.used / (1024 ** 3), 1),
        "mem_total_gb": round(mem.total / (1024 ** 3), 1),
        "disk_used_gb": round(disk.used / (1024 ** 3), 1),
        "disk_total_gb": round(disk.total / (1024 ** 3), 1),
        "swap_used_gb": round(swap.used / (1024 ** 3), 1),
        "swap_total_gb": round(swap.total / (1024 ** 3), 1),
        "uptime_str": f"{days}d {hours}h {minutes}m",
        "load_avg": f"{load[0]:.2f}, {load[1]:.2f}, {load[2]:.2f}",
        "kernel": "",
        "xui_version": "",
        "xray_version": "",
    }


def format_status(data: dict) -> str:
    return (
        f"📊 <b>Статус сервера</b>\n\n"
        f"CPU: {data['cpu_percent']}%\n"
        f"RAM: {data['mem_used_gb']}/{data['mem_total_gb']} GB\n"
        f"Disk: {data['disk_used_gb']}/{data['disk_total_gb']} GB\n"
        f"Swap: {data['swap_used_gb']}/{data['swap_total_gb']} GB\n"
        f"Load: {data['load_avg']}\n"
        f"Uptime: {data['uptime_str']}\n\n"
        f"Kernel: {data['kernel']}\n"
        f"3X-UI: {data['xui_version']}\n"
        f"Xray: {data['xray_version']}"
    )


@router.callback_query(lambda c: c.data == "status")
async def cb_status(callback: CallbackQuery) -> None:
    data = _get_system_status()
    data["kernel"] = await _get_version(["uname", "-r"])
    data["xui_version"] = await _get_version(["x-ui", "version"])
    data["xray_version"] = await _get_version(["xray", "version"])
    await callback.message.edit_text(
        format_status(data), reply_markup=back_button(), parse_mode="HTML"
    )
    await callback.answer()
