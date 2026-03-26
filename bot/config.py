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
    awg_config: str = "/etc/amneziawg/awg0.conf"
    install_mode: str = "both"
    awg_port: int = 0
    awg_server_pubkey: str = ""
    awg_jc: int = 4
    awg_jmin: int = 40
    awg_jmax: int = 70
    awg_s1: int = 52
    awg_s2: int = 52
    awg_h1: int = 1
    awg_h2: int = 2
    awg_h3: int = 3
    awg_h4: int = 4

    @property
    def tg_proxy_link(self) -> str:
        return f"tg://socks?server={self.server_ip}&port={self.socks_port}&user={self.socks_user}&pass={self.socks_pass}"

    @property
    def has_vless(self) -> bool:
        return self.install_mode in ("vless", "both")

    @property
    def has_awg(self) -> bool:
        return self.install_mode in ("awg", "both")


def load_config() -> Config:
    install_mode = os.environ.get("INSTALL_MODE", "both")

    if install_mode in ("vless", "both"):
        try:
            public_key = os.environ["PUBLIC_KEY"]
            short_id = os.environ["SHORT_ID"]
            sni = os.environ["BEST_SNI"]
            socks_port = int(os.environ["SOCKS_PORT"])
            socks_user = os.environ["SOCKS_USER"]
            socks_pass = os.environ["SOCKS_PASS"]
        except KeyError as e:
            print(f"Missing env var for VLESS: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        public_key = ""
        short_id = ""
        sni = ""
        socks_port = 0
        socks_user = ""
        socks_pass = ""

    try:
        return Config(
            bot_token=os.environ["BOT_TOKEN"],
            chat_id=int(os.environ["CHAT_ID"]),
            server_ip=os.environ["SERVER_IP"],
            public_key=public_key,
            short_id=short_id,
            sni=sni,
            socks_port=socks_port,
            socks_user=socks_user,
            socks_pass=socks_pass,
            remote_doh=os.environ.get("REMOTE_DOH", "https://dns.google/dns-query"),
            remote_doh_ip=os.environ.get("REMOTE_DOH_IP", "8.8.8.8"),
            domestic_doh=os.environ.get("DOMESTIC_DOH", "https://common.dot.dns.yandex.net/dns-query"),
            domestic_doh_ip=os.environ.get("DOMESTIC_DOH_IP", "77.88.8.8"),
            install_mode=install_mode,
            awg_port=int(os.environ.get("AWG_PORT", "0")),
            awg_server_pubkey=os.environ.get("AWG_SERVER_PUBKEY", ""),
            awg_config=os.environ.get("AWG_CONFIG", "/etc/amneziawg/awg0.conf"),
            awg_jc=int(os.environ.get("AWG_JC", "4")),
            awg_jmin=int(os.environ.get("AWG_JMIN", "40")),
            awg_jmax=int(os.environ.get("AWG_JMAX", "70")),
            awg_s1=int(os.environ.get("AWG_S1", "52")),
            awg_s2=int(os.environ.get("AWG_S2", "52")),
            awg_h1=int(os.environ.get("AWG_H1", "1")),
            awg_h2=int(os.environ.get("AWG_H2", "2")),
            awg_h3=int(os.environ.get("AWG_H3", "3")),
            awg_h4=int(os.environ.get("AWG_H4", "4")),
        )
    except KeyError as e:
        print(f"Missing env var: {e}", file=sys.stderr)
        sys.exit(1)
