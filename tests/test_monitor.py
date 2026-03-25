import pytest


def test_check_thresholds_cpu():
    from bot.services.monitor import check_thresholds

    alerts = check_thresholds(
        cpu_percent=95.0,
        cpu_high_since=310,
        disk_percent=50.0,
        xui_active=True,
        xray_active=True,
        traffic_ratio=1.0,
    )
    assert any("CPU" in a for a in alerts)


def test_check_thresholds_disk():
    from bot.services.monitor import check_thresholds

    alerts = check_thresholds(
        cpu_percent=10.0,
        cpu_high_since=0,
        disk_percent=90.0,
        xui_active=True,
        xray_active=True,
        traffic_ratio=1.0,
    )
    assert any("Disk" in a or "Диск" in a for a in alerts)


def test_check_thresholds_service_down():
    from bot.services.monitor import check_thresholds

    alerts = check_thresholds(
        cpu_percent=10.0,
        cpu_high_since=0,
        disk_percent=50.0,
        xui_active=False,
        xray_active=True,
        traffic_ratio=1.0,
    )
    assert any("x-ui" in a for a in alerts)


def test_check_thresholds_anomaly_traffic():
    from bot.services.monitor import check_thresholds

    alerts = check_thresholds(
        cpu_percent=10.0,
        cpu_high_since=0,
        disk_percent=50.0,
        xui_active=True,
        xray_active=True,
        traffic_ratio=4.0,
    )
    assert any("трафик" in a.lower() or "traffic" in a.lower() for a in alerts)


def test_no_alerts_when_healthy():
    from bot.services.monitor import check_thresholds

    alerts = check_thresholds(
        cpu_percent=20.0,
        cpu_high_since=0,
        disk_percent=50.0,
        xui_active=True,
        xray_active=True,
        traffic_ratio=1.0,
    )
    assert alerts == []
