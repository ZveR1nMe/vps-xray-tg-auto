# tests/conftest.py
import os
import pytest
from unittest.mock import patch


@pytest.fixture
def sample_env():
    """Стандартный набор env-переменных для тестов."""
    return {
        "BOT_TOKEN": "123:ABC",
        "CHAT_ID": "999",
        "XUI_USER": "admin",
        "XUI_PASS": "secret",
        "XUI_PATH": "/panel-xyz",
        "SERVER_IP": "1.2.3.4",
        "PUBLIC_KEY": "pubkey123",
        "SHORT_ID": "deadbeef",
        "BEST_SNI": "www.microsoft.com",
    }


@pytest.fixture
def config(sample_env):
    """Загруженный Config для тестов."""
    with patch.dict(os.environ, sample_env, clear=False):
        from bot.config import load_config
        return load_config()
