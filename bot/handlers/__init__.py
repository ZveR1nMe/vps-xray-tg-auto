from aiogram import Router

from bot.handlers.start import router as start_router
from bot.handlers.status import router as status_router
from bot.handlers.network import router as network_router


def register_all_routers() -> Router:
    """Создаёт корневой роутер и подключает все хэндлеры."""
    root = Router()
    root.include_router(start_router)
    root.include_router(status_router)
    root.include_router(network_router)
    return root
