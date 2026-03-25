import asyncio
from aiogram import Router
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup

router = Router()

TARGETS = [("Google DNS", "8.8.8.8"), ("Cloudflare", "1.1.1.1")]


async def _ping(host: str, count: int = 4) -> dict:
    proc = await asyncio.create_subprocess_exec(
        "ping", "-c", str(count), "-W", "3", host,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    output = stdout.decode()
    avg_ms, loss = None, "100%"
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


@router.callback_query(lambda c: c.data == "network")
async def cb_network(callback: CallbackQuery) -> None:
    await callback.answer("⏳ Проверяю...")

    results = await asyncio.gather(*[_ping(h) for _, h in TARGETS])

    lines = ["🌐 <b>Сеть</b>\n"]
    for (name, _), res in zip(TARGETS, results):
        ms = f"{res['avg_ms']} ms" if res["avg_ms"] else "timeout"
        lines.append(f"{name}: {ms} (loss: {res['loss']})")

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🔙 Назад", callback_data="main_menu")],
    ])
    await callback.message.edit_text("\n".join(lines), reply_markup=kb, parse_mode="HTML")
