from urllib.parse import quote


def generate_vless_link(
    uuid: str,
    server_ip: str,
    public_key: str,
    short_id: str,
    sni: str,
    name: str,
) -> str:
    """Генерация vless:// ссылки для VLESS + Reality."""
    params = (
        f"type=tcp"
        f"&security=reality"
        f"&fp=chrome"
        f"&pbk={public_key}"
        f"&sid={short_id}"
        f"&sni={sni}"
        f"&flow=xtls-rprx-vision"
    )
    fragment = quote(name, safe="")
    return f"vless://{uuid}@{server_ip}:443?{params}#{fragment}"
