from __future__ import annotations

import asyncio
import logging
import time
from collections import deque

import psutil

logger = logging.getLogger(__name__)


async def is_process_running(pattern: str) -> bool:
    proc = await asyncio.create_subprocess_exec(
        "pgrep", "-f", pattern,
        stdout=asyncio.subprocess.PIPE,
    )
    await proc.communicate()
    return proc.returncode == 0


async def is_awg_running() -> bool:
    """Проверка AWG через awg show (kernel-модуль не виден через pgrep)."""
    proc = await asyncio.create_subprocess_exec(
        "awg", "show", "awg0",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    await proc.communicate()
    return proc.returncode == 0


class Monitor:
    def __init__(self, bot, chat_id: int) -> None:
        self._bot = bot
        self._chat_id = chat_id
        self._cpu_high_since: float = 0
        self._traffic_history: deque[float] = deque(maxlen=288)
        self._last_net_bytes: int = 0
        self._last_net_time: float = 0

    async def run(self) -> None:
        while True:
            try:
                alerts = await self._check()
                if alerts:
                    text = "⚠️ <b>Алерты</b>\n\n" + "\n".join(alerts)
                    await self._bot.send_message(self._chat_id, text, parse_mode="HTML")
            except Exception as e:
                logger.error("Monitor check failed: %s", e, exc_info=True)
            await asyncio.sleep(300)

    async def _check(self) -> list[str]:
        alerts: list[str] = []
        cpu = psutil.cpu_percent(interval=0)
        now = time.time()

        if cpu > 90:
            if self._cpu_high_since == 0:
                self._cpu_high_since = now
            elif now - self._cpu_high_since > 300:
                alerts.append(f"🔴 CPU {cpu}% более 5 минут")
        else:
            self._cpu_high_since = 0

        disk = psutil.disk_usage("/").percent
        if disk > 85:
            alerts.append(f"🔴 Диск {disk}%")

        from bot import deps as _deps_module
        config = _deps_module.config

        if config.has_vless:
            xray_ok = await is_process_running("xray")
            if not xray_ok:
                alerts.append("🔴 xray не запущен!")

        if config.has_awg:
            awg_ok = await is_awg_running()
            if not awg_ok:
                alerts.append("🔴 amneziawg не запущен!")

        return alerts
