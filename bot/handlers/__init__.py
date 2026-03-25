from aiogram import Router

from bot.handlers.start import router as start_router
from bot.handlers.status import router as status_router
from bot.handlers.network import router as network_router
from bot.handlers.users import router as users_router
from bot.handlers.traffic import router as traffic_router
from bot.handlers.diagnostics import router as diagnostics_router
from bot.handlers.backup import router as backup_router
from bot.handlers.tips import router as tips_router
from bot.handlers.update import router as update_router


def register_all_routers() -> Router:
    """Создаёт корневой роутер и подключает все хэндлеры."""
    root = Router()
    root.include_router(start_router)
    root.include_router(status_router)
    root.include_router(network_router)
    root.include_router(users_router)
    root.include_router(traffic_router)
    root.include_router(diagnostics_router)
    root.include_router(backup_router)
    root.include_router(tips_router)
    root.include_router(update_router)
    return root
