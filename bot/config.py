from __future__ import annotations

import os
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    bot_token: str
    chat_id: int
    server_ip: str
    public_key: str
    short_id: str
    sni: str
    xray_config: str = "/opt/vps-setup/xray-config.json"


def load_config() -> Config:
    try:
        return Config(
            bot_token=os.environ["BOT_TOKEN"],
            chat_id=int(os.environ["CHAT_ID"]),
            server_ip=os.environ["SERVER_IP"],
            public_key=os.environ["PUBLIC_KEY"],
            short_id=os.environ["SHORT_ID"],
            sni=os.environ["BEST_SNI"],
        )
    except KeyError as e:
        print(f"Missing env var: {e}", file=sys.stderr)
        sys.exit(1)
