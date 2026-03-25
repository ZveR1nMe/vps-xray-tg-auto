from urllib.parse import urlparse, parse_qs, unquote


def test_generate_vless_link():
    from bot.services.link_gen import generate_vless_link

    link = generate_vless_link(
        uuid="abc-123",
        server_ip="1.2.3.4",
        public_key="pubkey123",
        short_id="deadbeef",
        sni="www.microsoft.com",
        name="friend1",
    )

    assert link.startswith("vless://abc-123@1.2.3.4:443?")
    assert "security=reality" in link
    assert "fp=chrome" in link
    assert "pbk=pubkey123" in link
    assert "sid=deadbeef" in link
    assert "sni=www.microsoft.com" in link
    assert "flow=xtls-rprx-vision" in link
    assert link.endswith("#friend1")


def test_generate_vless_link_name_with_spaces():
    from bot.services.link_gen import generate_vless_link

    link = generate_vless_link(
        uuid="abc-123",
        server_ip="1.2.3.4",
        public_key="pk",
        short_id="aa",
        sni="www.google.com",
        name="Вася Пупкин",
    )

    # Имя должно быть URL-encoded во фрагменте
    assert "#" in link
    fragment = link.split("#", 1)[1]
    assert unquote(fragment) == "Вася Пупкин"
