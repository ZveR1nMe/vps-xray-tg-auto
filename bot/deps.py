"""Глобальные зависимости — заполняются при старте."""
from __future__ import annotations
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from bot.config import Config
    from bot.services.xray_manager import XrayManager

config: Config = None  # type: ignore
xray_mgr: XrayManager = None  # type: ignore
