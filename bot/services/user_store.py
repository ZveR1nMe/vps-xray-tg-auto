"""Единое хранилище пользователей — координатор между менеджерами."""
from __future__ import annotations

import json
import logging
from datetime import datetime
from pathlib import Path

logger = logging.getLogger(__name__)

USERS_FILE = Path("/opt/vps-setup/users.json")


class UserStore:
    def __init__(self) -> None:
        self._path = USERS_FILE
        self._data: dict = {}
        self.load()

    def load(self) -> None:
        if self._path.exists():
            self._data = json.loads(self._path.read_text())
        else:
            self._data = {}

    def save(self) -> None:
        tmp = self._path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self._data, indent=2, ensure_ascii=False))
        tmp.rename(self._path)

    def list_users(self) -> list[str]:
        return list(self._data.keys())

    def get_user(self, name: str) -> dict | None:
        return self._data.get(name)

    def user_exists(self, name: str) -> bool:
        return name in self._data

    def add_user(self, name: str) -> None:
        if name not in self._data:
            self._data[name] = {}
            self.save()

    def add_key(self, name: str, key_type: str, data: dict) -> None:
        if name not in self._data:
            self._data[name] = {}
        data["created"] = datetime.now().isoformat(timespec="seconds")
        self._data[name][key_type] = data
        self.save()

    def delete_key(self, name: str, key_type: str) -> bool:
        if name in self._data and key_type in self._data[name]:
            del self._data[name][key_type]
            self.save()
            return True
        return False

    def delete_user(self, name: str) -> dict | None:
        if name in self._data:
            data = self._data.pop(name)
            self.save()
            return data
        return None

    def get_key(self, name: str, key_type: str) -> dict | None:
        user = self._data.get(name, {})
        return user.get(key_type)

    def user_key_types(self, name: str) -> list[str]:
        valid_types = ("vless", "awg", "awg_router")
        return [k for k in self._data.get(name, {}).keys() if k in valid_types]

    def next_awg_ip(self) -> str:
        used = set()
        for user_data in self._data.values():
            for key_type in ("awg", "awg_router"):
                key_data = user_data.get(key_type, {})
                if "ip" in key_data:
                    used.add(key_data["ip"])
        for i in range(2, 255):
            ip = f"10.8.1.{i}"
            if ip not in used:
                return ip
        raise RuntimeError("No free AWG IPs (subnet full)")

    def migrate_from_xray(self, xray_mgr) -> int:
        if self._data:
            return 0
        clients = xray_mgr.list_clients()
        count = 0
        for c in clients:
            email = c.get("email", "")
            if email and email not in self._data:
                self._data[email] = {
                    "vless": {
                        "uuid": c["id"],
                        "created": datetime.now().isoformat(timespec="seconds"),
                    }
                }
                count += 1
        if count:
            self.save()
            logger.info("Migrated %d VLESS users to users.json", count)
        return count
