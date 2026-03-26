# Phase 1: AmneziaWG Server + AWG Manager — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AmneziaWG 2.0 server installation to setup.sh with install mode selection, and create awg_manager.py service for managing AWG peers programmatically.

**Architecture:** setup.sh gets a mode selector (vless/awg/both) and a new AWG installation section. awg_manager.py mirrors xray_manager.py's interface but manages /etc/amneziawg/awg0.conf using INI-style parsing and awg CLI tools. Config.py and deps.py are extended with AWG fields.

**Tech Stack:** Bash (setup.sh), Python 3.10+ (awg_manager.py), asyncio subprocess for awg CLI, PPA ppa:amnezia/ppa

**Spec:** `docs/superpowers/specs/2026-03-27-amneziawg-router-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `setup.sh` | Modify | Add install mode selector + AWG installation section |
| `bot/config.py` | Modify | Add AWG fields (port, server pubkey, obfuscation params, install_mode) |
| `bot/deps.py` | Modify | Add awg_mgr slot |
| `bot/bot.py` | Modify | Initialize awg_mgr conditionally based on INSTALL_MODE |
| `bot/services/awg_manager.py` | Create | AWG peer management (add/delete/list/get_config) |

---

### Task 1: Add install mode selector to setup.sh

**Files:**
- Modify: `setup.sh:1-10` (add mode variable)
- Modify: `setup.sh:28-42` (add mode prompt after Telegram credentials)

- [ ] **Step 1: Add mode selection prompt after Telegram credentials block**

Insert after line 42 (after `fi` closing Telegram credentials block) in `setup.sh`:

```bash
# --- Режим установки ---

echo ""
log "Выберите режим установки:"
echo "  1) Только VLESS Reality"
echo "  2) Только AmneziaWG 2.0"
echo "  3) VLESS + AmneziaWG (оба)"
echo ""
read -rp "Режим [1/2/3]: " INSTALL_MODE_INPUT
case "${INSTALL_MODE_INPUT:-3}" in
    1) INSTALL_MODE="vless" ;;
    2) INSTALL_MODE="awg" ;;
    3) INSTALL_MODE="both" ;;
    *) warn "Неверный выбор, ставлю оба"; INSTALL_MODE="both" ;;
esac
log "Режим: $INSTALL_MODE"
```

- [ ] **Step 2: Wrap VLESS-specific sections in conditionals**

Wrap the VLESS-specific code (xray installation, keys, config, systemd) in a conditional. Around line 157:

```bash
# --- Установка xray ---
if [[ "$INSTALL_MODE" == "vless" || "$INSTALL_MODE" == "both" ]]; then

log "Установка xray..."
# ... existing xray code lines 159-370 ...

fi  # end VLESS
```

Wrap the UFW 443/tcp rule (line 94) similarly:

```bash
if [[ "$INSTALL_MODE" == "vless" || "$INSTALL_MODE" == "both" ]]; then
    ufw allow 443/tcp comment 'VLESS Reality'
fi
```

- [ ] **Step 3: Wrap SOCKS5 proxy in conditional**

SOCKS5 proxy (lines 269-275) is for Telegram via VLESS. Wrap:

```bash
if [[ "$INSTALL_MODE" == "vless" || "$INSTALL_MODE" == "both" ]]; then
    SOCKS_PORT=$(shuf -i 10000-60000 -n 1)
    SOCKS_USER=$(openssl rand -hex 5)
    SOCKS_PASS=$(openssl rand -hex 5)
    log "SOCKS5 прокси: порт $SOCKS_PORT"
    ufw allow "$SOCKS_PORT"/tcp comment 'SOCKS5 Telegram'
else
    SOCKS_PORT=""
    SOCKS_USER=""
    SOCKS_PASS=""
fi
```

- [ ] **Step 4: Test mode selector locally**

Run: `bash -n setup.sh` (syntax check)
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add setup.sh
git commit -m "feat: add install mode selector (vless/awg/both) to setup.sh"
```

---

### Task 2: Add AmneziaWG server installation to setup.sh

**Files:**
- Modify: `setup.sh` (add AWG section after VLESS section, before Python Bot section)

- [ ] **Step 1: Add AWG installation section**

Insert before `# --- Python Bot ---` (line 372):

```bash
# --- AmneziaWG 2.0 ---

if [[ "$INSTALL_MODE" == "awg" || "$INSTALL_MODE" == "both" ]]; then

log "Установка AmneziaWG 2.0..."

# PPA
add-apt-repository -y ppa:amnezia/ppa
apt update -qq
apt install -y amneziawg amneziawg-dkms amneziawg-tools

# Определение сетевого интерфейса
NET_IFACE=$(ip route show default | awk '{print $5}' | head -1)
if [[ -z "$NET_IFACE" ]]; then
    err "Не удалось определить сетевой интерфейс"
    exit 1
fi
log "Сетевой интерфейс: $NET_IFACE"

# Генерация ключей
AWG_SERVER_PRIVKEY=$(awg genkey)
AWG_SERVER_PUBKEY=$(echo "$AWG_SERVER_PRIVKEY" | awg pubkey)

# Рандомный UDP порт
AWG_PORT=$(shuf -i 10000-60000 -n 1)
log "AWG порт: $AWG_PORT"

# Параметры обфускации
AWG_JC=4
AWG_JMIN=40
AWG_JMAX=70
AWG_S1=52
AWG_S2=52
AWG_H1=1
AWG_H2=2
AWG_H3=3
AWG_H4=4

# Конфиг сервера
mkdir -p /etc/amneziawg
cat > /etc/amneziawg/awg0.conf << AWGCONF
[Interface]
PrivateKey = ${AWG_SERVER_PRIVKEY}
Address = 10.8.1.1/24
ListenPort = ${AWG_PORT}
PostUp = iptables -A FORWARD -i awg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${NET_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i awg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${NET_IFACE} -j MASQUERADE
Jc = ${AWG_JC}
Jmin = ${AWG_JMIN}
Jmax = ${AWG_JMAX}
S1 = ${AWG_S1}
S2 = ${AWG_S2}
H1 = ${AWG_H1}
H2 = ${AWG_H2}
H3 = ${AWG_H3}
H4 = ${AWG_H4}
AWGCONF
chmod 600 /etc/amneziawg/awg0.conf

# UFW
ufw allow ${AWG_PORT}/udp comment 'AmneziaWG'

# Systemd
cat > /etc/systemd/system/awg-quick@.service << 'SVC'
[Unit]
Description=AmneziaWG Tunnel %i
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/awg-quick up /etc/amneziawg/%i.conf
ExecStop=/usr/bin/awg-quick down /etc/amneziawg/%i.conf

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable awg-quick@awg0
systemctl start awg-quick@awg0
sleep 2

if ! awg show awg0 > /dev/null 2>&1; then
    err "AmneziaWG не запустился"
    journalctl -u awg-quick@awg0 --no-pager -n 10
    exit 1
fi
log "AmneziaWG запущен на порту $AWG_PORT (UDP)"

fi  # end AWG
```

- [ ] **Step 2: Add AWG variables to .env file**

Modify the `.env` generation section (around line 394). Replace the existing `cat > "$INSTALL_DIR/.env"` block:

```bash
# --- .env ---

cat > "$INSTALL_DIR/.env" << ENVFILE
BOT_TOKEN=$BOT_TOKEN
CHAT_ID=$CHAT_ID
SERVER_IP=$SERVER_IP
INSTALL_MODE=$INSTALL_MODE
ENVFILE

if [[ "$INSTALL_MODE" == "vless" || "$INSTALL_MODE" == "both" ]]; then
cat >> "$INSTALL_DIR/.env" << ENVFILE
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
BEST_SNI=$BEST_SNI
REMOTE_DOH=$BEST_REMOTE_DOH
REMOTE_DOH_IP=$BEST_REMOTE_DOH_IP
DOMESTIC_DOH=$BEST_DOMESTIC_DOH
DOMESTIC_DOH_IP=$BEST_DOMESTIC_DOH_IP
SOCKS_PORT=$SOCKS_PORT
SOCKS_USER=$SOCKS_USER
SOCKS_PASS=$SOCKS_PASS
ENVFILE
fi

if [[ "$INSTALL_MODE" == "awg" || "$INSTALL_MODE" == "both" ]]; then
cat >> "$INSTALL_DIR/.env" << ENVFILE
AWG_PORT=$AWG_PORT
AWG_SERVER_PUBKEY=$AWG_SERVER_PUBKEY
AWG_JC=$AWG_JC
AWG_JMIN=$AWG_JMIN
AWG_JMAX=$AWG_JMAX
AWG_S1=$AWG_S1
AWG_S2=$AWG_S2
AWG_H1=$AWG_H1
AWG_H2=$AWG_H2
AWG_H3=$AWG_H3
AWG_H4=$AWG_H4
AWG_CONFIG=/etc/amneziawg/awg0.conf
ENVFILE
fi

chmod 600 "$INSTALL_DIR/.env"
```

- [ ] **Step 3: Update final status message**

Update the final log/Telegram message (lines 448-470) to include AWG info:

```bash
log "=========================================="
log "  Установка завершена!"
log "=========================================="
log ""
log "  IP: $SERVER_IP"
log "  Режим: $INSTALL_MODE"
if [[ "$INSTALL_MODE" == "vless" || "$INSTALL_MODE" == "both" ]]; then
    log "  Xray: VLESS + Reality на порту 443"
    log "  SNI: $BEST_SNI"
    log "  Public Key: $PUBLIC_KEY"
fi
if [[ "$INSTALL_MODE" == "awg" || "$INSTALL_MODE" == "both" ]]; then
    log "  AmneziaWG: порт $AWG_PORT (UDP)"
    log "  AWG Public Key: $AWG_SERVER_PUBKEY"
fi
log ""
log "  Бот: напишите /start в Telegram"
log "=========================================="

TG_MSG="✅ <b>VPS настроен!</b>

🖥 IP: <code>$SERVER_IP</code>
🔑 SSH: <code>ssh root@$SERVER_IP</code>
📋 Режим: $INSTALL_MODE"

if [[ "$INSTALL_MODE" == "vless" || "$INSTALL_MODE" == "both" ]]; then
    TG_MSG+="
🌐 SNI: $BEST_SNI
🔐 VLESS Key: <code>$PUBLIC_KEY</code>"
fi
if [[ "$INSTALL_MODE" == "awg" || "$INSTALL_MODE" == "both" ]]; then
    TG_MSG+="
🛡 AWG: порт $AWG_PORT
🔐 AWG Key: <code>$AWG_SERVER_PUBKEY</code>"
fi
TG_MSG+="

Напишите /start боту для управления."

curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d parse_mode="HTML" \
    -d text="$TG_MSG" > /dev/null
```

- [ ] **Step 4: Syntax check**

Run: `bash -n setup.sh`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add setup.sh
git commit -m "feat: add AmneziaWG 2.0 server installation to setup.sh"
```

---

### Task 3: Create awg_manager.py

**Files:**
- Create: `bot/services/awg_manager.py`

- [ ] **Step 1: Create awg_manager.py with full implementation**

```python
"""Управление AmneziaWG конфигом через awg0.conf."""
from __future__ import annotations

import asyncio
import logging
import re
import tempfile
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
        skip = False
        found = False

        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if line == "[Peer]":
                # Look ahead for this peer's public key
                peer_lines = [lines[i]]
                j = i + 1
                while j < len(lines) and lines[j].strip() and lines[j].strip() != "[Peer]" and lines[j].strip() != "[Interface]":
                    peer_lines.append(lines[j])
                    j += 1
                # Check if this peer has the target public key
                peer_text = "\n".join(peer_lines)
                if f"PublicKey = {public_key}" in peer_text:
                    found = True
                    # Remove trailing empty line if present
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
```

- [ ] **Step 2: Verify syntax**

Run: `cd /Users/dmverlan/Documents/script_vps && python3 -c "import ast; ast.parse(open('bot/services/awg_manager.py').read()); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add bot/services/awg_manager.py
git commit -m "feat: add awg_manager.py for AmneziaWG peer management"
```

---

### Task 4: Extend config.py with AWG fields

**Files:**
- Modify: `bot/config.py`

- [ ] **Step 1: Add AWG fields to Config dataclass**

Add after line 23 (`xray_config` field):

```python
    awg_config: str = "/etc/amneziawg/awg0.conf"
    install_mode: str = "both"
    awg_port: int = 0
    awg_server_pubkey: str = ""
    awg_jc: int = 4
    awg_jmin: int = 40
    awg_jmax: int = 70
    awg_s1: int = 52
    awg_s2: int = 52
    awg_h1: int = 1
    awg_h2: int = 2
    awg_h3: int = 3
    awg_h4: int = 4
```

- [ ] **Step 2: Update load_config() to load AWG env vars**

Add after line 45 (after `domestic_doh_ip` line) inside `load_config()`:

```python
            install_mode=os.environ.get("INSTALL_MODE", "both"),
            awg_port=int(os.environ.get("AWG_PORT", "0")),
            awg_server_pubkey=os.environ.get("AWG_SERVER_PUBKEY", ""),
            awg_config=os.environ.get("AWG_CONFIG", "/etc/amneziawg/awg0.conf"),
            awg_jc=int(os.environ.get("AWG_JC", "4")),
            awg_jmin=int(os.environ.get("AWG_JMIN", "40")),
            awg_jmax=int(os.environ.get("AWG_JMAX", "70")),
            awg_s1=int(os.environ.get("AWG_S1", "52")),
            awg_s2=int(os.environ.get("AWG_S2", "52")),
            awg_h1=int(os.environ.get("AWG_H1", "1")),
            awg_h2=int(os.environ.get("AWG_H2", "2")),
            awg_h3=int(os.environ.get("AWG_H3", "3")),
            awg_h4=int(os.environ.get("AWG_H4", "4")),
```

- [ ] **Step 3: Add helper properties**

Add after `tg_proxy_link` property:

```python
    @property
    def has_vless(self) -> bool:
        return self.install_mode in ("vless", "both")

    @property
    def has_awg(self) -> bool:
        return self.install_mode in ("awg", "both")
```

- [ ] **Step 4: Verify syntax**

Run: `cd /Users/dmverlan/Documents/script_vps && python3 -c "import ast; ast.parse(open('bot/config.py').read()); print('OK')"`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add bot/config.py
git commit -m "feat: extend config.py with AWG fields and install_mode"
```

---

### Task 5: Update deps.py and bot.py for AWG

**Files:**
- Modify: `bot/deps.py`
- Modify: `bot/bot.py`

- [ ] **Step 1: Add awg_mgr to deps.py**

Replace entire `bot/deps.py`:

```python
"""Глобальные зависимости — заполняются при старте."""
from __future__ import annotations
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from bot.config import Config
    from bot.services.xray_manager import XrayManager
    from bot.services.awg_manager import AwgManager

config: Config = None  # type: ignore
xray_mgr: XrayManager = None  # type: ignore
awg_mgr: AwgManager | None = None
```

- [ ] **Step 2: Initialize awg_mgr in bot.py**

Add after line 14 (imports):

```python
from bot.services.awg_manager import AwgManager
```

Add after line 64 (after `deps.xray_mgr = XrayManager(...)`) — replace the existing `deps.xray_mgr` block with conditional initialization:

```python
    from bot import deps
    deps.config = config

    if config.has_vless:
        deps.xray_mgr = XrayManager(
            config_path=config.xray_config,
            server_ip=config.server_ip,
            public_key=config.public_key,
            short_id=config.short_id,
            sni=config.sni,
            remote_doh=config.remote_doh,
            remote_doh_ip=config.remote_doh_ip,
            domestic_doh=config.domestic_doh,
            domestic_doh_ip=config.domestic_doh_ip,
        )

    if config.has_awg:
        deps.awg_mgr = AwgManager(
            config_path=config.awg_config,
            server_ip=config.server_ip,
            server_pubkey=config.awg_server_pubkey,
            awg_port=config.awg_port,
            jc=config.awg_jc,
            jmin=config.awg_jmin,
            jmax=config.awg_jmax,
            s1=config.awg_s1,
            s2=config.awg_s2,
            h1=config.awg_h1,
            h2=config.awg_h2,
            h3=config.awg_h3,
            h4=config.awg_h4,
        )
```

- [ ] **Step 3: Handle missing env vars for vless-only or awg-only modes**

In `bot/config.py`, update `load_config()` so that VLESS-specific required vars (PUBLIC_KEY, SHORT_ID, BEST_SNI, SOCKS_PORT, SOCKS_USER, SOCKS_PASS) are only required when install_mode includes vless. Replace the try/except block:

```python
def load_config() -> Config:
    install_mode = os.environ.get("INSTALL_MODE", "both")

    # VLESS fields — required only for vless/both modes
    if install_mode in ("vless", "both"):
        try:
            public_key = os.environ["PUBLIC_KEY"]
            short_id = os.environ["SHORT_ID"]
            sni = os.environ["BEST_SNI"]
            socks_port = int(os.environ["SOCKS_PORT"])
            socks_user = os.environ["SOCKS_USER"]
            socks_pass = os.environ["SOCKS_PASS"]
        except KeyError as e:
            print(f"Missing env var for VLESS: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        public_key = ""
        short_id = ""
        sni = ""
        socks_port = 0
        socks_user = ""
        socks_pass = ""

    try:
        return Config(
            bot_token=os.environ["BOT_TOKEN"],
            chat_id=int(os.environ["CHAT_ID"]),
            server_ip=os.environ["SERVER_IP"],
            public_key=public_key,
            short_id=short_id,
            sni=sni,
            socks_port=socks_port,
            socks_user=socks_user,
            socks_pass=socks_pass,
            remote_doh=os.environ.get("REMOTE_DOH", "https://dns.google/dns-query"),
            remote_doh_ip=os.environ.get("REMOTE_DOH_IP", "8.8.8.8"),
            domestic_doh=os.environ.get("DOMESTIC_DOH", "https://common.dot.dns.yandex.net/dns-query"),
            domestic_doh_ip=os.environ.get("DOMESTIC_DOH_IP", "77.88.8.8"),
            install_mode=install_mode,
            awg_port=int(os.environ.get("AWG_PORT", "0")),
            awg_server_pubkey=os.environ.get("AWG_SERVER_PUBKEY", ""),
            awg_config=os.environ.get("AWG_CONFIG", "/etc/amneziawg/awg0.conf"),
            awg_jc=int(os.environ.get("AWG_JC", "4")),
            awg_jmin=int(os.environ.get("AWG_JMIN", "40")),
            awg_jmax=int(os.environ.get("AWG_JMAX", "70")),
            awg_s1=int(os.environ.get("AWG_S1", "52")),
            awg_s2=int(os.environ.get("AWG_S2", "52")),
            awg_h1=int(os.environ.get("AWG_H1", "1")),
            awg_h2=int(os.environ.get("AWG_H2", "2")),
            awg_h3=int(os.environ.get("AWG_H3", "3")),
            awg_h4=int(os.environ.get("AWG_H4", "4")),
        )
    except KeyError as e:
        print(f"Missing env var: {e}", file=sys.stderr)
        sys.exit(1)
```

- [ ] **Step 4: Verify syntax for all modified files**

Run:
```bash
cd /Users/dmverlan/Documents/script_vps
python3 -c "import ast; ast.parse(open('bot/deps.py').read()); print('deps OK')"
python3 -c "import ast; ast.parse(open('bot/bot.py').read()); print('bot OK')"
python3 -c "import ast; ast.parse(open('bot/config.py').read()); print('config OK')"
```
Expected: All OK

- [ ] **Step 5: Commit**

```bash
git add bot/deps.py bot/bot.py bot/config.py
git commit -m "feat: wire up awg_manager in deps and bot with conditional init"
```

---

## Phase 1 Completion Criteria

After all 5 tasks:
- `setup.sh` asks for install mode and installs AWG server when selected
- `.env` contains all AWG variables
- `awg_manager.py` can add/delete/list peers and generate client configs
- `config.py` loads AWG settings from environment
- `bot.py` initializes `awg_mgr` conditionally
- Bot still works in VLESS-only mode (backwards compatible)

## Next Phases

- **Phase 2:** `user_store.py` + refactor `users.py` for unified user list with key types
- **Phase 3:** `data/router/keenetic.sh` + router setup in `setup.sh`
- **Phase 4:** DNS route lists + interactive menu for Keenetic
