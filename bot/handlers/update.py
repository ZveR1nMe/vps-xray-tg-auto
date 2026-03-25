from __future__ import annotations

import asyncio
import logging
import shutil
from pathlib import Path

import aiohttp
from aiogram import F, Router
from aiogram.types import CallbackQuery

from bot.keyboards import back_button, update_buttons

router = Router()
logger = logging.getLogger(__name__)

GITHUB_API = "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest"
XUI_DB_PATH = Path("/etc/x-ui/x-ui.db")
XUI_BIN_PATH = Path("/usr/local/x-ui")
ROLLBACK_DIR = Path("/opt/vps-setup/data/rollback")


async def get_latest_version() -> str | None:
    try:
        async with aiohttp.ClientSession() as session:
            resp = await session.get(GITHUB_API, timeout=aiohttp.ClientTimeout(total=10))
            if resp.status != 200:
                return None
            data = await resp.json()
            return data.get("tag_name")
    except Exception:
        return None


async def get_current_version() -> str | None:
    proc = await asyncio.create_subprocess_exec(
        "x-ui", "version",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    return stdout.decode().strip() if proc.returncode == 0 else None


async def _do_update() -> tuple[bool, str]:
    """Выполняет обновление 3X-UI. Возвращает (success, message)."""
    ROLLBACK_DIR.mkdir(parents=True, exist_ok=True)
    if XUI_DB_PATH.exists():
        shutil.copy2(XUI_DB_PATH, ROLLBACK_DIR / "x-ui.db.bak")

    proc = await asyncio.create_subprocess_exec(
        "bash", "-c",
        "echo 'y' | bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await proc.communicate()

    if proc.returncode != 0:
        return False, f"Ошибка установки: {stderr.decode()[:200]}"

    await asyncio.sleep(10)

    check = await asyncio.create_subprocess_exec(
        "systemctl", "is-active", "x-ui",
        stdout=asyncio.subprocess.PIPE,
    )
    stdout, _ = await check.communicate()
    if stdout.decode().strip() != "active":
        if (ROLLBACK_DIR / "x-ui.db.bak").exists():
            shutil.copy2(ROLLBACK_DIR / "x-ui.db.bak", XUI_DB_PATH)
            await asyncio.create_subprocess_exec("systemctl", "restart", "x-ui")
            await asyncio.sleep(5)

            check2 = await asyncio.create_subprocess_exec(
                "systemctl", "is-active", "x-ui",
                stdout=asyncio.subprocess.PIPE,
            )
            stdout2, _ = await check2.communicate()
            if stdout2.decode().strip() != "active":
                return False, "❌ Откат не помог — требуется ручное вмешательство"

        return False, "❌ Обновление не удалось, выполнен откат"

    return True, "✅ Обновление завершено успешно"


@router.callback_query(F.data == "update")
async def cb_update(callback: CallbackQuery) -> None:
    current = await get_current_version()
    latest = await get_latest_version()

    if latest and current and latest == current:
        await callback.message.edit_text(
            f"🔄 3X-UI: {current}\nОбновлений нет.",
            reply_markup=back_button(),
        )
    elif latest:
        await callback.message.edit_text(
            f"🔄 Текущая: {current or '?'}\nДоступна: {latest}\n\nОбновить?",
            reply_markup=update_buttons(),
        )
    else:
        await callback.message.edit_text(
            "⚠️ Не удалось проверить обновления",
            reply_markup=back_button(),
        )
    await callback.answer()


@router.callback_query(F.data == "update_confirm")
async def cb_update_confirm(callback: CallbackQuery) -> None:
    await callback.message.edit_text("⏳ Обновляю 3X-UI...")
    await callback.answer()

    success, msg = await _do_update()
    await callback.message.edit_text(msg, reply_markup=back_button())
