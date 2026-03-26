"""Глобальные зависимости — заполняются при старте."""
from __future__ import annotations
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from bot.config import Config
    from bot.services.xray_manager import XrayManager
    from bot.services.awg_manager import AwgManager
    from bot.services.user_store import UserStore

config: Config = None  # type: ignore
xray_mgr: XrayManager = None  # type: ignore
awg_mgr: AwgManager | None = None
user_store: UserStore = None  # type: ignore
