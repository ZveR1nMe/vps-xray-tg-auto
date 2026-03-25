from __future__ import annotations

import asyncio
import logging
import sys
from pathlib import Path

import aiohttp
from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from dotenv import load_dotenv

from bot.config import load_config
from bot.handlers import register_all_routers
from bot.middleware import AuthMiddleware
from bot.services.monitor import Monitor
from bot.services.xui_api import XUIClient

_log_handlers: list[logging.Handler] = [logging.StreamHandler(sys.stdout)]
_log_dir = Path("/opt/vps-setup/logs")
if _log_dir.exists():
    _log_handlers.append(logging.FileHandler(_log_dir / "bot.log"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=_log_handlers,
)
logger = logging.getLogger(__name__)


def _seconds_until_utc_hour(hour: int) -> float:
    """Вычисляет количество секунд до следующего hour:00 UTC."""
    from datetime import datetime, timezone, timedelta
    now = datetime.now(timezone.utc)
    target = now.replace(hour=hour, minute=0, second=0, microsecond=0)
    if target <= now:
        target += timedelta(days=1)
    return (target - now).total_seconds()


async def _daily_backup(bot: Bot, chat_id: int) -> None:
    """Ежедневный бэкап в 04:00 UTC."""
    from bot.handlers.backup import create_backup
    from aiogram.types import FSInputFile
    import os

    while True:
        sleep_sec = _seconds_until_utc_hour(4)
        logger.info(f"Next backup in {sleep_sec:.0f}s")
        await asyncio.sleep(sleep_sec)

        try:
            path = await asyncio.to_thread(create_backup)
            size = os.path.getsize(path)
            from datetime import datetime, timezone
            now = datetime.now(timezone.utc)
            if size <= 45 * 1024 * 1024:
                doc = FSInputFile(path)
                await bot.send_document(chat_id, doc, caption=f"💾 Авто-бэкап {now:%Y-%m-%d}")
            else:
                await bot.send_message(chat_id, f"💾 Авто-бэкап сохранён на сервере: {path} ({size // (1024*1024)} MB)")
        except Exception as e:
            logger.error(f"Daily backup failed: {e}")

        await asyncio.sleep(60)


async def _daily_update_check(bot: Bot, chat_id: int) -> None:
    """Ежедневная проверка обновлений 3X-UI."""
    from bot.handlers.update import get_current_version, get_latest_version
    from bot.keyboards import update_buttons

    while True:
        await asyncio.sleep(86400)
        try:
            current, latest = await asyncio.gather(
                get_current_version(), get_latest_version()
            )
            if latest and current and latest != current:
                await bot.send_message(
                    chat_id,
                    f"🔄 Доступно обновление 3X-UI: {current} → {latest}",
                    reply_markup=update_buttons(),
                )
        except Exception as e:
            logger.error(f"Update check failed: {e}")


async def main() -> None:
    env_path = Path("/opt/vps-setup/.env")
    if env_path.exists():
        load_dotenv(env_path)

    config = load_config()
    logger.info("Config loaded, starting bot...")

    bot = Bot(
        token=config.bot_token,
        default=DefaultBotProperties(parse_mode="HTML"),
    )

    dp = Dispatcher()

    root_router = register_all_routers()
    root_router.message.middleware(AuthMiddleware(config.chat_id))
    root_router.callback_query.middleware(AuthMiddleware(config.chat_id))
    dp.include_router(root_router)

    session = aiohttp.ClientSession(cookie_jar=aiohttp.CookieJar(unsafe=True))
    xui_client = XUIClient(config, session=session)
    await xui_client.login()

    from bot import deps
    deps.config = config
    deps.xui_client = xui_client
    deps.link_gen_params = {
        "server_ip": config.server_ip,
        "public_key": config.public_key,
        "short_id": config.short_id,
        "sni": config.sni,
    }

    monitor = Monitor(bot, config.chat_id)
    asyncio.create_task(monitor.run())
    asyncio.create_task(_daily_backup(bot, config.chat_id))
    asyncio.create_task(_daily_update_check(bot, config.chat_id))

    # Регистрируем кнопку меню в Telegram
    from aiogram.types import BotCommand
    await bot.set_my_commands([
        BotCommand(command="start", description="Главное меню"),
    ])

    logger.info("Bot started successfully")
    await bot.send_message(config.chat_id, "🟢 Бот запущен!")

    try:
        await dp.start_polling(bot)
    finally:
        await session.close()
        await bot.session.close()


if __name__ == "__main__":
    asyncio.run(main())
