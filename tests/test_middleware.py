import pytest
from unittest.mock import AsyncMock, MagicMock


@pytest.mark.asyncio
async def test_allows_authorized_chat():
    from bot.middleware import AuthMiddleware

    mw = AuthMiddleware(allowed_chat_id=999)
    event = MagicMock()
    event.chat = MagicMock(id=999)
    handler = AsyncMock(return_value="ok")

    result = await mw(handler, event, {})
    handler.assert_called_once()
    assert result == "ok"


@pytest.mark.asyncio
async def test_blocks_unauthorized_chat():
    from bot.middleware import AuthMiddleware

    mw = AuthMiddleware(allowed_chat_id=999)
    event = MagicMock()
    event.chat = MagicMock(id=123)
    handler = AsyncMock()

    result = await mw(handler, event, {})
    handler.assert_not_called()
    assert result is None
