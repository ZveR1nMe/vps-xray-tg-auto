"""Глобальные зависимости бота — заполняются при старте в bot.py."""
from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from bot.config import Config
    from bot.services.xui_api import XUIClient

config: Config = None  # type: ignore
xui_client: XUIClient = None  # type: ignore
link_gen_params: dict = {}
