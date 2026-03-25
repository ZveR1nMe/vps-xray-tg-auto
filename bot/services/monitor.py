from __future__ import annotations

import asyncio
import logging
import time

import psutil

logger = logging.getLogger(__name__)

CPU_THRESHOLD = 90.0
CPU_DURATION = 300
DISK_THRESHOLD = 85.0
TRAFFIC_RATIO_THRESHOLD = 3.0
CHECK_INTERVAL = 300


def check_thresholds(
    cpu_percent: float,
    cpu_high_since: float,
    disk_percent: float,
    xui_active: bool,
    xray_active: bool,
    traffic_ratio: float,
) -> list[str]:
    """Проверяет метрики и возвращает список алертов."""
    alerts: list[str] = []

    if cpu_percent > CPU_THRESHOLD and cpu_high_since > CPU_DURATION:
        alerts.append(f"🔴 CPU > {CPU_THRESHOLD}% более 5 минут ({cpu_percent}%)")

    if disk_percent > DISK_THRESHOLD:
        alerts.append(f"🔴 Диск > {DISK_THRESHOLD}% ({disk_percent}%)")

    if not xui_active:
        alerts.append("🔴 Сервис x-ui не запущен!")

    if not xray_active:
        alerts.append("🔴 Сервис xray не запущен!")

    if traffic_ratio > TRAFFIC_RATIO_THRESHOLD:
        alerts.append(f"🟡 Аномальный трафик: {traffic_ratio:.1f}x от среднего")

    return alerts


async def _is_service_active(name: str) -> bool:
    proc = await asyncio.create_subprocess_exec(
        "systemctl", "is-active", name,
        stdout=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    return stdout.decode().strip() == "active"


class Monitor:
    """Фоновый мониторинг с алертами каждые 5 минут."""

    def __init__(self, bot, chat_id: int) -> None:
        self._bot = bot
        self._chat_id = chat_id
        self._cpu_high_since: float = 0
        self._last_net_bytes: int = 0
        self._last_net_time: float = 0
        self._traffic_history: list[float] = []

    async def run(self) -> None:
        while True:
            try:
                alerts = await self._check()
                if alerts:
                    text = "⚠️ <b>Алерты мониторинга</b>\n\n" + "\n".join(alerts)
                    await self._bot.send_message(self._chat_id, text, parse_mode="HTML")
            except Exception as e:
                logger.error(f"Monitor error: {e}")

            await asyncio.sleep(CHECK_INTERVAL)

    async def _check(self) -> list[str]:
        cpu = psutil.cpu_percent(interval=1)
        now = time.time()

        if cpu > CPU_THRESHOLD:
            if self._cpu_high_since == 0:
                self._cpu_high_since = now
            cpu_duration = now - self._cpu_high_since
        else:
            self._cpu_high_since = 0
            cpu_duration = 0

        disk = psutil.disk_usage("/").percent

        xui_active = await _is_service_active("x-ui")
        xray_active = await _is_service_active("xray")

        net = psutil.net_io_counters()
        current_bytes = net.bytes_recv + net.bytes_sent
        traffic_ratio = 1.0
        if self._last_net_time > 0:
            elapsed = now - self._last_net_time
            if elapsed > 0:
                rate = (current_bytes - self._last_net_bytes) / elapsed
                self._traffic_history.append(rate)
                if len(self._traffic_history) > 288:
                    self._traffic_history = self._traffic_history[-288:]
                if len(self._traffic_history) > 1:
                    avg = sum(self._traffic_history[:-1]) / len(self._traffic_history[:-1])
                    if avg > 0:
                        traffic_ratio = rate / avg

        self._last_net_bytes = current_bytes
        self._last_net_time = now

        return check_thresholds(
            cpu_percent=cpu,
            cpu_high_since=cpu_duration,
            disk_percent=disk,
            xui_active=xui_active,
            xray_active=xray_active,
            traffic_ratio=traffic_ratio,
        )
