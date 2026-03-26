"""Управление AmneziaWG конфигом через awg0.conf."""
from __future__ import annotations

import asyncio
import logging
from pathlib import Path

logger = logging.getLogger(__name__)


class AwgManager:
    def __init__(
        self,
        config_path: str,
        server_ip: str,
        server_pubkey: str,
        awg_port: int,
        jc: int = 4,
        jmin: int = 40,
        jmax: int = 70,
        s1: int = 52,
        s2: int = 52,
        h1: int = 1,
        h2: int = 2,
        h3: int = 3,
        h4: int = 4,
    ) -> None:
        self._path = Path(config_path)
        self._server_ip = server_ip
        self._server_pubkey = server_pubkey
        self._awg_port = awg_port
        self._jc = jc
        self._jmin = jmin
        self._jmax = jmax
        self._s1 = s1
        self._s2 = s2
        self._h1 = h1
        self._h2 = h2
        self._h3 = h3
        self._h4 = h4

    def _read_config(self) -> str:
        return self._path.read_text()

    def _write_config(self, content: str) -> None:
        tmp = self._path.with_suffix(".tmp")
        tmp.write_text(content)
        tmp.rename(self._path)

    async def _run_cmd(self, *args: str) -> str:
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await proc.communicate()
        if proc.returncode != 0:
            raise RuntimeError(f"Command failed: {' '.join(args)}: {stderr.decode()}")
        return stdout.decode().strip()

    async def _genkey(self) -> tuple[str, str]:
        privkey = await self._run_cmd("awg", "genkey")
        proc = await asyncio.create_subprocess_exec(
            "awg", "pubkey",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
        )
        stdout, _ = await proc.communicate(privkey.encode())
        pubkey = stdout.decode().strip()
        return privkey, pubkey

    async def _genpsk(self) -> str:
        return await self._run_cmd("awg", "genpsk")

    async def _restart_awg(self) -> None:
        proc = await asyncio.create_subprocess_exec(
            "systemctl", "restart", "awg-quick@awg0",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        await proc.communicate()

    def _parse_peers(self, config_text: str) -> list[dict]:
        """Parse [Peer] sections from config file."""
        peers = []
        current_peer = None
        for line in config_text.splitlines():
            line = line.strip()
            if line == "[Peer]":
                current_peer = {}
                peers.append(current_peer)
            elif line == "[Interface]":
                current_peer = None
            elif current_peer is not None and "=" in line:
                key, _, value = line.partition("=")
                current_peer[key.strip()] = value.strip()
        return peers

    def list_peers(self) -> list[dict]:
        """Return list of peers from config file."""
        config = self._read_config()
        return self._parse_peers(config)

    async def add_peer(self, comment: str, client_ip: str) -> dict:
        """Add a new peer. Returns dict with keys needed for client config."""
        privkey, pubkey = await self._genkey()
        psk = await self._genpsk()

        peer_block = (
            f"\n[Peer]\n"
            f"# {comment}\n"
            f"PublicKey = {pubkey}\n"
            f"PresharedKey = {psk}\n"
            f"AllowedIPs = {client_ip}/32\n"
        )

        config = self._read_config()
        config += peer_block
        self._write_config(config)
        await self._restart_awg()

        return {
            "private_key": privkey,
            "public_key": pubkey,
            "psk": psk,
            "ip": client_ip,
        }

    async def delete_peer(self, public_key: str) -> bool:
        """Remove a peer by public key."""
        config = self._read_config()
        lines = config.splitlines()
        new_lines = []
        found = False

        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if line == "[Peer]":
                # Collect all lines of this peer section
                peer_lines = [lines[i]]
                j = i + 1
                while j < len(lines) and lines[j].strip() and lines[j].strip() != "[Peer]" and lines[j].strip() != "[Interface]":
                    peer_lines.append(lines[j])
                    j += 1
                # Check if this peer has the target public key
                peer_text = "\n".join(peer_lines)
                if f"PublicKey = {public_key}" in peer_text:
                    found = True
                    # Skip trailing empty lines
                    while j < len(lines) and not lines[j].strip():
                        j += 1
                    i = j
                    continue
                else:
                    new_lines.extend(peer_lines)
                    i = j
                    continue
            else:
                new_lines.append(lines[i])
                i += 1

        if not found:
            return False

        self._write_config("\n".join(new_lines) + "\n")
        await self._restart_awg()
        return True

    def make_client_config(self, privkey: str, psk: str, ip: str, for_router: bool = False) -> str:
        """Generate client config string."""
        lines = ["[Interface]", f"PrivateKey = {privkey}"]
        if not for_router:
            lines.append(f"Address = {ip}/32")
            lines.append("DNS = 1.1.1.1, 8.8.8.8")
        lines.extend([
            f"Jc = {self._jc}",
            f"Jmin = {self._jmin}",
            f"Jmax = {self._jmax}",
            f"S1 = {self._s1}",
            f"S2 = {self._s2}",
            f"H1 = {self._h1}",
            f"H2 = {self._h2}",
            f"H3 = {self._h3}",
            f"H4 = {self._h4}",
            "",
            "[Peer]",
            f"PublicKey = {self._server_pubkey}",
            f"PresharedKey = {psk}",
            f"Endpoint = {self._server_ip}:{self._awg_port}",
            "AllowedIPs = 0.0.0.0/0",
            "PersistentKeepalive = 25",
        ])
        return "\n".join(lines) + "\n"

    async def get_status(self) -> str | None:
        """Run awg show and return output."""
        try:
            return await self._run_cmd("awg", "show", "awg0")
        except RuntimeError:
            return None
