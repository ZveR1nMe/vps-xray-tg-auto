import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from aiohttp import ClientSession


@pytest.fixture
def mock_session():
    session = AsyncMock(spec=ClientSession)
    return session


@pytest.mark.asyncio
async def test_login_sets_cookie(mock_session, config):
    from bot.services.xui_api import XUIClient

    resp = AsyncMock()
    resp.status = 200
    resp.json = AsyncMock(return_value={"success": True})
    mock_session.post = AsyncMock(return_value=resp)

    client = XUIClient(config, session=mock_session)
    await client.login()

    mock_session.post.assert_called_once()
    call_url = mock_session.post.call_args[0][0]
    assert "/login" in call_url


@pytest.mark.asyncio
async def test_list_inbounds(mock_session, config):
    from bot.services.xui_api import XUIClient

    resp = AsyncMock()
    resp.status = 200
    resp.json = AsyncMock(return_value={
        "success": True,
        "obj": [{"id": 1, "remark": "vless-reality", "settings": "{}"}],
    })
    mock_session.post = AsyncMock(return_value=resp)

    client = XUIClient(config, session=mock_session)
    client._logged_in = True
    result = await client.list_inbounds()

    assert len(result) == 1
    assert result[0]["id"] == 1


@pytest.mark.asyncio
async def test_add_client(mock_session, config):
    from bot.services.xui_api import XUIClient

    resp = AsyncMock()
    resp.status = 200
    resp.json = AsyncMock(return_value={"success": True})
    mock_session.post = AsyncMock(return_value=resp)

    client = XUIClient(config, session=mock_session)
    client._logged_in = True
    result = await client.add_client(
        inbound_id=1, uuid="test-uuid", email="friend1"
    )

    assert result is True


@pytest.mark.asyncio
async def test_auto_relogin_on_401(mock_session, config):
    from bot.services.xui_api import XUIClient

    resp_401 = AsyncMock()
    resp_401.status = 401
    resp_ok = AsyncMock()
    resp_ok.status = 200
    resp_ok.json = AsyncMock(return_value={"success": True, "obj": []})

    login_resp = AsyncMock()
    login_resp.status = 200
    login_resp.json = AsyncMock(return_value={"success": True})

    mock_session.post = AsyncMock(side_effect=[resp_401, login_resp, resp_ok])

    client = XUIClient(config, session=mock_session)
    client._logged_in = True
    result = await client.list_inbounds()

    assert result == []
    assert mock_session.post.call_count == 3  # 401 + login + retry
