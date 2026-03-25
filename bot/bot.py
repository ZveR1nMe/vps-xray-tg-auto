from __future__ import annotations

import asyncio
import logging
import sys
from pathlib import Path

from aiogram import Bot, Dispatcher, BaseMiddleware
from aiogram.client.default import DefaultBotProperties
from aiogram.types import BotCommand, TelegramObject
from dotenv import load_dotenv

from bot.config import load_config
from bot.services.xray_manager import XrayManager
from bot.services.monitor import Monitor

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


class AuthMiddleware(BaseMiddleware):
    def __init__(self, allowed_chat_id: int) -> None:
        self.allowed_chat_id = allowed_chat_id

    async def __call__(self, handler, event: TelegramObject, data: dict) -> any:
        chat = getattr(event, "chat", None)
        if chat is None:
            msg = getattr(event, "message", None)
            if msg:
                chat = getattr(msg, "chat", None)
        if chat is None or chat.id != self.allowed_chat_id:
            return None
        return await handler(event, data)


async def main() -> None:
    env_path = Path("/opt/vps-setup/.env")
    if env_path.exists():
        load_dotenv(env_path)

    config = load_config()

    from bot import deps
    deps.config = config
    deps.xray_mgr = XrayManager(
        config_path=config.xray_config,
        server_ip=config.server_ip,
        public_key=config.public_key,
        short_id=config.short_id,
        sni=config.sni,
    )

    bot = Bot(token=config.bot_token, default=DefaultBotProperties(parse_mode="HTML"))
    dp = Dispatcher()

    from bot.handlers.start import router as start_router
    from bot.handlers.users import router as users_router
    from bot.handlers.status import router as status_router
    from bot.handlers.network import router as network_router
    from bot.handlers.tips import router as tips_router

    root = start_router
    root.include_router(users_router)
    root.include_router(status_router)
    root.include_router(network_router)
    root.include_router(tips_router)

    root.message.middleware(AuthMiddleware(config.chat_id))
    root.callback_query.middleware(AuthMiddleware(config.chat_id))
    dp.include_router(root)

    monitor = Monitor(bot, config.chat_id)
    asyncio.create_task(monitor.run())

    await bot.set_my_commands([BotCommand(command="start", description="Главное меню")])

    logger.info("Bot started")
    await bot.send_message(config.chat_id, "🟢 Бот запущен!")

    try:
        await dp.start_polling(bot)
    finally:
        await bot.session.close()


if __name__ == "__main__":
    asyncio.run(main())
