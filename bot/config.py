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
    socks_port: int
    socks_user: str
    socks_pass: str
    remote_doh: str = "https://dns.google/dns-query"
    remote_doh_ip: str = "8.8.8.8"
    domestic_doh: str = "https://common.dot.dns.yandex.net/dns-query"
    domestic_doh_ip: str = "77.88.8.8"
    xray_config: str = "/opt/vps-setup/xray-config.json"

    @property
    def tg_proxy_link(self) -> str:
        return f"tg://socks?server={self.server_ip}&port={self.socks_port}&user={self.socks_user}&pass={self.socks_pass}"


def load_config() -> Config:
    try:
        return Config(
            bot_token=os.environ["BOT_TOKEN"],
            chat_id=int(os.environ["CHAT_ID"]),
            server_ip=os.environ["SERVER_IP"],
            public_key=os.environ["PUBLIC_KEY"],
            short_id=os.environ["SHORT_ID"],
            sni=os.environ["BEST_SNI"],
            socks_port=int(os.environ["SOCKS_PORT"]),
            socks_user=os.environ["SOCKS_USER"],
            socks_pass=os.environ["SOCKS_PASS"],
            remote_doh=os.environ.get("REMOTE_DOH", "https://dns.google/dns-query"),
            remote_doh_ip=os.environ.get("REMOTE_DOH_IP", "8.8.8.8"),
            domestic_doh=os.environ.get("DOMESTIC_DOH", "https://common.dot.dns.yandex.net/dns-query"),
            domestic_doh_ip=os.environ.get("DOMESTIC_DOH_IP", "77.88.8.8"),
        )
    except KeyError as e:
        print(f"Missing env var: {e}", file=sys.stderr)
        sys.exit(1)
