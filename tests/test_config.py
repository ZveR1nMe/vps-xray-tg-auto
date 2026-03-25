# tests/test_config.py
import os
import pytest
from unittest.mock import patch

from bot.config import load_config


def test_load_config_from_env():
    env = {
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
    with patch.dict(os.environ, env, clear=False):
        cfg = load_config()
        assert cfg.bot_token == "123:ABC"
        assert cfg.chat_id == 999
        assert cfg.xui_user == "admin"
        assert cfg.xui_pass == "secret"
        assert cfg.xui_path == "/panel-xyz"
        assert cfg.server_ip == "1.2.3.4"
        assert cfg.public_key == "pubkey123"
        assert cfg.xui_base_url == "http://127.0.0.1:2053/panel-xyz"


def test_load_config_missing_token():
    with patch.dict(os.environ, {}, clear=True):
        with pytest.raises(SystemExit):
            load_config()
