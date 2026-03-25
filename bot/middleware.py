from __future__ import annotations

from typing import Any, Awaitable, Callable

from aiogram import BaseMiddleware
from aiogram.types import TelegramObject


class AuthMiddleware(BaseMiddleware):
    """Пропускает только сообщения от разрешённого chat_id."""

    def __init__(self, allowed_chat_id: int) -> None:
        self.allowed_chat_id = allowed_chat_id

    async def __call__(
        self,
        handler: Callable[[TelegramObject, dict[str, Any]], Awaitable[Any]],
        event: TelegramObject,
        data: dict[str, Any],
    ) -> Any:
        chat = getattr(event, "chat", None)
        if chat is None or chat.id != self.allowed_chat_id:
            return None
        return await handler(event, data)
