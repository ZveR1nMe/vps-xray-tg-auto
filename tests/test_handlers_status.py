import pytest
from unittest.mock import AsyncMock, patch, MagicMock


@pytest.mark.asyncio
async def test_status_formats_output():
    from bot.handlers.status import format_status

    data = {
        "cpu_percent": 25.0,
        "mem_used_gb": 1.2,
        "mem_total_gb": 4.0,
        "disk_used_gb": 10.5,
        "disk_total_gb": 40.0,
        "uptime_str": "5d 3h 12m",
        "load_avg": "0.15, 0.10, 0.05",
        "swap_used_gb": 0.0,
        "swap_total_gb": 1.0,
        "kernel": "5.15.0-91-generic",
        "xui_version": "2.5.4",
        "xray_version": "1.8.24",
    }
    text = format_status(data)

    assert "CPU" in text
    assert "25.0%" in text
    assert "RAM" in text
    assert "1.2" in text
    assert "Uptime" in text
    assert "5.15.0" in text
    assert "2.5.4" in text
