import asyncio
import psutil
from aiogram import Router
from aiogram.types import CallbackQuery

from bot.keyboards import back_button

router = Router()

PING_TARGETS = [
    ("Google DNS", "8.8.8.8"),
    ("Cloudflare", "1.1.1.1"),
    ("Moscow IX", "195.208.208.1"),
]


async def _ping(host: str, count: int = 4) -> dict:
    proc = await asyncio.create_subprocess_exec(
        "ping", "-c", str(count), "-W", "3", host,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    output = stdout.decode()

    avg_ms = None
    loss = "100%"
    for line in output.splitlines():
        if "packet loss" in line:
            for part in line.split(","):
                if "packet loss" in part:
                    loss = part.strip().split()[0]
        if "avg" in line:
            parts = line.split("=")[-1].strip().split("/")
            if len(parts) >= 2:
                avg_ms = parts[1]

    return {"avg_ms": avg_ms, "loss": loss}


async def _get_bandwidth() -> tuple[float, float]:
    """Текущая скорость in/out за 2 секунды (KB/s)."""
    net1 = psutil.net_io_counters()
    await asyncio.sleep(2)
    net2 = psutil.net_io_counters()
    rx = (net2.bytes_recv - net1.bytes_recv) / 2 / 1024
    tx = (net2.bytes_sent - net1.bytes_sent) / 2 / 1024
    return round(rx, 1), round(tx, 1)


@router.callback_query(lambda c: c.data == "network")
async def cb_network(callback: CallbackQuery) -> None:
    await callback.answer("⏳ Проверяю сеть...")

    results = await asyncio.gather(*[_ping(host) for _, host in PING_TARGETS])
    rx, tx = await _get_bandwidth()

    lines = ["🌐 <b>Сеть</b>\n"]
    for (name, _), res in zip(PING_TARGETS, results):
        ms = f"{res['avg_ms']} ms" if res["avg_ms"] else "timeout"
        lines.append(f"{name}: {ms} (loss: {res['loss']})")

    lines.append(f"\n📥 In: {rx} KB/s | 📤 Out: {tx} KB/s")

    big_ping = await _ping("8.8.8.8", count=20)
    lines.append(f"\nПотеря пакетов (20 пакетов → Google): {big_ping['loss']}")

    await callback.message.edit_text(
        "\n".join(lines), reply_markup=back_button(), parse_mode="HTML"
    )
