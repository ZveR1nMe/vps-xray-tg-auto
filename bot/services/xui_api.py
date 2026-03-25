from __future__ import annotations

import json
import logging
from typing import Any

from aiohttp import ClientSession

from bot.config import Config

logger = logging.getLogger(__name__)


class XUIError(Exception):
    pass


class XUIClient:
    """HTTP-клиент для 3X-UI API."""

    def __init__(self, config: Config, session: ClientSession) -> None:
        self._config = config
        self._session = session
        self._base = config.xui_base_url
        self._logged_in = False

    async def login(self) -> None:
        resp = await self._session.post(
            f"{self._base}/login",
            data={"username": self._config.xui_user, "password": self._config.xui_pass},
        )
        body = await resp.json()
        if not body.get("success"):
            raise XUIError("Login failed")
        self._logged_in = True

    async def _request(self, method: str, path: str, **kwargs: Any) -> Any:
        """Выполнить запрос с автоматическим re-login при 401."""
        url = f"{self._base}{path}"
        resp = await self._session.post(url, **kwargs) if method == "POST" else await self._session.get(url, **kwargs)

        if resp.status == 401:
            logger.info("Got 401, re-logging in")
            await self.login()
            resp = await self._session.post(url, **kwargs) if method == "POST" else await self._session.get(url, **kwargs)

        if resp.status != 200:
            raise XUIError(f"HTTP {resp.status} from {path}")

        body = await resp.json()
        if not body.get("success"):
            raise XUIError(f"API error: {body}")
        return body

    async def list_inbounds(self) -> list[dict]:
        body = await self._request("POST", "/xui/API/inbounds/list")
        return body.get("obj", [])

    async def add_client(self, inbound_id: int, uuid: str, email: str) -> bool:
        settings = json.dumps({
            "clients": [{
                "id": uuid,
                "flow": "xtls-rprx-vision",
                "email": email,
                "totalGB": 0,
                "expiryTime": 0,
            }]
        })
        await self._request(
            "POST",
            "/xui/API/inbounds/addClient",
            data={"id": inbound_id, "settings": settings},
        )
        return True

    async def delete_client(self, inbound_id: int, client_uuid: str) -> bool:
        await self._request(
            "POST",
            f"/xui/API/inbounds/{inbound_id}/delClient/{client_uuid}",
        )
        return True

    async def get_client_traffic(self, email: str) -> dict:
        body = await self._request(
            "POST",
            f"/xui/API/inbounds/getClientTraffics/{email}",
        )
        return body.get("obj", {})

    async def server_status(self) -> dict:
        body = await self._request("GET", "/server/status")
        return body.get("obj", {})
