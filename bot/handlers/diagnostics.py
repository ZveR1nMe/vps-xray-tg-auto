import asyncio
import aiohttp
from aiogram import Router
from aiogram.types import CallbackQuery

from bot.keyboards import back_button

router = Router()

CHECK_HOST_API = "https://check-host.net"


async def _check_from_russia(server_ip: str, session: aiohttp.ClientSession) -> dict | None:
    """Проверка доступности IP из РФ через check-host.net API."""
    try:
        headers = {"Accept": "application/json"}
        resp = await session.get(
            f"{CHECK_HOST_API}/check-tcp?host={server_ip}:443",
            headers=headers,
            timeout=aiohttp.ClientTimeout(total=15),
        )
        if resp.status != 200:
            return None

        data = await resp.json()
        request_id = data.get("request_id")
        if not request_id:
            return None

        await asyncio.sleep(5)

        resp2 = await session.get(
            f"{CHECK_HOST_API}/check-result/{request_id}",
            headers=headers,
            timeout=aiohttp.ClientTimeout(total=15),
        )
        if resp2.status != 200:
            return None

        results = await resp2.json()

        ru_nodes = {k: v for k, v in results.items() if ".ru" in k or "russia" in k.lower()}
        if not ru_nodes:
            return {"status": "no_ru_nodes", "results": results}

        reachable = 0
        total = len(ru_nodes)
        for node, result in ru_nodes.items():
            if result and isinstance(result, list) and result[0] and result[0].get("error") is None:
                reachable += 1

        return {"reachable": reachable, "total": total}

    except Exception:
        return None


async def _check_isitdown(server_ip: str, session: aiohttp.ClientSession) -> dict | None:
    """Fallback: проверка через isitdown.site."""
    try:
        resp = await session.get(
            f"https://isitdown.site/api/v3/{server_ip}",
            timeout=aiohttp.ClientTimeout(total=15),
        )
        if resp.status != 200:
            return None
        data = await resp.json()
        is_down = data.get("isitdown", False)
        if is_down:
            return {"reachable": 0, "total": 1}
        return {"reachable": 1, "total": 1}
    except Exception:
        return None


async def _check_xray_running() -> bool:
    proc = await asyncio.create_subprocess_exec(
        "systemctl", "is-active", "x-ui",
        stdout=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    return stdout.decode().strip() == "active"


@router.callback_query(lambda c: c.data == "diagnostics")
async def cb_diagnostics(callback: CallbackQuery) -> None:
    await callback.answer("⏳ Запускаю диагностику...")

    config = callback.bot["config"]
    lines = ["🔍 <b>Диагностика</b>\n"]

    xray_ok = await _check_xray_running()
    lines.append(f"xray/x-ui: {'✅ работает' if xray_ok else '❌ не запущен!'}")

    async with aiohttp.ClientSession() as session:
        result = await _check_from_russia(config.server_ip, session)
        if result is None:
            result = await _check_isitdown(config.server_ip, session)

    if result is None:
        lines.append("\n🌐 Проверка из РФ: ⚠️ Оба API недоступны (check-host.net, isitdown.site)")
    elif result.get("status") == "no_ru_nodes":
        lines.append("\n🌐 Проверка из РФ: ⚠️ нет RU-нод в результатах")
    else:
        r = result["reachable"]
        t = result["total"]
        if r == t:
            lines.append(f"\n🌐 Из РФ: ✅ доступен ({r}/{t} нод)")
        elif r > 0:
            lines.append(f"\n🌐 Из РФ: ⚠️ частично ({r}/{t} нод)")
        else:
            lines.append(
                f"\n🌐 Из РФ: ❌ заблокирован ({r}/{t} нод)\n"
                f"💡 Рекомендация: смените IP у провайдера"
            )

    await callback.message.edit_text(
        "\n".join(lines), reply_markup=back_button(), parse_mode="HTML"
    )
