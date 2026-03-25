import pytest
import json


@pytest.mark.asyncio
async def test_parse_clients_from_inbound():
    from bot.handlers.users import parse_clients

    inbound = {
        "id": 1,
        "settings": json.dumps({
            "clients": [
                {"id": "uuid-1", "email": "alice", "flow": "xtls-rprx-vision"},
                {"id": "uuid-2", "email": "bob", "flow": "xtls-rprx-vision"},
            ]
        }),
    }
    clients = parse_clients(inbound)
    assert len(clients) == 2
    assert clients[0]["email"] == "alice"
    assert clients[1]["id"] == "uuid-2"


def test_format_users_list():
    from bot.handlers.users import format_users_list

    clients = [
        {"email": "alice", "id": "uuid-1"},
        {"email": "bob", "id": "uuid-2"},
    ]
    text = format_users_list(clients)
    assert "alice" in text
    assert "bob" in text
