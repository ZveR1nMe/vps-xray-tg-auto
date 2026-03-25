from __future__ import annotations

import asyncio
import os
import tarfile
import tempfile
from datetime import datetime
from pathlib import Path

from aiogram import Router
from aiogram.types import CallbackQuery, FSInputFile

from bot.keyboards import back_button

router = Router()

BACKUP_DIR = "/opt/vps-setup/data/backups"
XUI_DB_PATH = "/etc/x-ui/x-ui.db"
XRAY_CONFIG_PATH = "/usr/local/x-ui/bin/config.json"
MAX_BACKUP_SIZE = 45 * 1024 * 1024
MAX_BACKUPS = 7


def rotate_backups(backup_dir: str, max_backups: int = MAX_BACKUPS) -> None:
    """Удаляет старейшие бэкапы, оставляя max_backups."""
    backups = sorted(
        Path(backup_dir).glob("*.tar.gz"),
        key=lambda f: f.stat().st_mtime,
    )
    while len(backups) > max_backups:
        oldest = backups.pop(0)
        oldest.unlink()


def create_backup() -> str:
    """Создаёт tar.gz архив с БД и конфигом xray. Возвращает путь к файлу."""
    os.makedirs(BACKUP_DIR, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = os.path.join(BACKUP_DIR, f"backup_{timestamp}.tar.gz")

    with tarfile.open(backup_path, "w:gz") as tar:
        if os.path.exists(XUI_DB_PATH):
            tar.add(XUI_DB_PATH, arcname="x-ui.db")
        if os.path.exists(XRAY_CONFIG_PATH):
            tar.add(XRAY_CONFIG_PATH, arcname="xray-config.json")

    rotate_backups(BACKUP_DIR)
    return backup_path


@router.callback_query(lambda c: c.data == "backup")
async def cb_backup(callback: CallbackQuery) -> None:
    await callback.answer("⏳ Создаю бэкап...")

    backup_path = await asyncio.to_thread(create_backup)
    file_size = os.path.getsize(backup_path)

    if file_size > MAX_BACKUP_SIZE:
        await callback.message.edit_text(
            f"💾 Бэкап создан: {backup_path}\n"
            f"⚠️ Размер ({file_size // (1024*1024)} MB) превышает лимит Telegram.\n"
            f"Файл сохранён только на сервере.",
            reply_markup=back_button(),
        )
    else:
        doc = FSInputFile(backup_path)
        await callback.message.answer_document(doc, caption=f"💾 Бэкап {datetime.now():%Y-%m-%d %H:%M}")
        await callback.message.edit_text("💾 Бэкап отправлен ↑", reply_markup=back_button())
