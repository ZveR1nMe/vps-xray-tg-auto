from aiogram import Router

from bot.handlers.start import router as start_router


def register_all_routers() -> Router:
    """Создаёт корневой роутер и подключает все хэндлеры."""
    root = Router()
    root.include_router(start_router)
    return root
