# bot/config.py
from __future__ import annotations

import os
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    bot_token: str
    chat_id: int
    xui_user: str
    xui_pass: str
    xui_path: str
    server_ip: str
    public_key: str
    short_id: str
    sni: str

    @property
    def xui_base_url(self) -> str:
        return f"http://127.0.0.1:2053{self.xui_path}"


def load_config() -> Config:
    """Загрузка конфигурации из переменных окружения."""
    try:
        return Config(
            bot_token=os.environ["BOT_TOKEN"],
            chat_id=int(os.environ["CHAT_ID"]),
            xui_user=os.environ["XUI_USER"],
            xui_pass=os.environ["XUI_PASS"],
            xui_path=os.environ["XUI_PATH"],
            server_ip=os.environ["SERVER_IP"],
            public_key=os.environ["PUBLIC_KEY"],
            short_id=os.environ["SHORT_ID"],
            sni=os.environ["BEST_SNI"],
        )
    except KeyError as e:
        print(f"Missing env var: {e}", file=sys.stderr)
        sys.exit(1)
