"""Управление xray конфигом напрямую через JSON файл."""
from __future__ import annotations

import asyncio
import base64
import json
import logging
import uuid as uuid_mod
from pathlib import Path
from urllib.parse import quote

logger = logging.getLogger(__name__)


class XrayManager:
    def __init__(self, config_path: str, server_ip: str, public_key: str, short_id: str, sni: str) -> None:
        self._path = Path(config_path)
        self._server_ip = server_ip
        self._public_key = public_key
        self._short_id = short_id
        self._sni = sni

    def _read_config(self) -> dict:
        return json.loads(self._path.read_text())

    def _write_config(self, config: dict) -> None:
        self._path.write_text(json.dumps(config, indent=2))

    def _get_vless_inbound(self, config: dict) -> dict | None:
        for ib in config.get("inbounds", []):
            if ib.get("protocol") == "vless":
                return ib
        return None

    async def _restart_xray(self) -> None:
        proc = await asyncio.create_subprocess_exec(
            "systemctl", "restart", "xray",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        await proc.communicate()

    def list_clients(self) -> list[dict]:
        config = self._read_config()
        ib = self._get_vless_inbound(config)
        if not ib:
            return []
        return ib.get("settings", {}).get("clients", [])

    async def add_client(self, name: str) -> str:
        """Добавляет клиента, возвращает vless:// ссылку."""
        config = self._read_config()
        ib = self._get_vless_inbound(config)
        if not ib:
            raise RuntimeError("No VLESS inbound found")

        client_uuid = str(uuid_mod.uuid4())
        clients = ib["settings"].get("clients", [])
        clients.append({
            "id": client_uuid,
            "flow": "xtls-rprx-vision",
            "email": name,
        })
        ib["settings"]["clients"] = clients
        self._write_config(config)
        await self._restart_xray()

        return self._make_link(client_uuid, name)

    async def delete_client(self, email: str) -> bool:
        config = self._read_config()
        ib = self._get_vless_inbound(config)
        if not ib:
            return False

        clients = ib["settings"].get("clients", [])
        new_clients = [c for c in clients if c.get("email") != email]
        if len(new_clients) == len(clients):
            return False

        ib["settings"]["clients"] = new_clients
        self._write_config(config)
        await self._restart_xray()
        return True

    def get_link(self, email: str) -> str | None:
        for c in self.list_clients():
            if c.get("email") == email:
                return self._make_link(c["id"], email)
        return None

    def _make_link(self, client_uuid: str, name: str) -> str:
        params = (
            f"type=tcp"
            f"&security=reality"
            f"&fp=chrome"
            f"&pbk={self._public_key}"
            f"&sid={self._short_id}"
            f"&sni={self._sni}"
            f"&flow=xtls-rprx-vision"
        )
        fragment = quote(name, safe="")
        return f"vless://{client_uuid}@{self._server_ip}:443?{params}#{fragment}"

    @staticmethod
    def get_happ_routing_link() -> str:
        """Генерирует happ://routing/add/ deep link с split-tunneling для РФ."""
        profile = {
            "Name": "VPS Split-Tunnel RU",
            "GlobalProxy": "true",
            "RemoteDNSType": "DoH",
            "RemoteDNSDomain": "https://dns.google/dns-query",
            "RemoteDNSIP": "8.8.8.8",
            "DomesticDNSType": "DoH",
            "DomesticDNSDomain": "https://common.dot.dns.yandex.net/dns-query",
            "DomesticDNSIP": "77.88.8.8",
            "Geoipurl": "",
            "Geositeurl": "",
            "LastUpdated": "",
            "DnsHosts": {},
            "DirectSites": [
                "geosite:category-ru",
                "geosite:geolocation-ru",
            ],
            "DirectIp": [
                "geoip:ru",
                "geoip:private",
            ],
            "ProxySites": [],
            "ProxyIp": [],
            "BlockSites": [
                "geosite:category-ads-all",
            ],
            "BlockIp": [],
            "DomainStrategy": "IPIfNonMatch",
            "FakeDNS": "false",
        }
        json_str = json.dumps(profile, indent=4, ensure_ascii=False)
        b64 = base64.b64encode(json_str.encode()).decode()
        return f"happ://routing/add/{b64}"
