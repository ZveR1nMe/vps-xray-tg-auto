import os
import pytest
from unittest.mock import patch, MagicMock


def test_rotate_backups_keeps_only_7(tmp_path):
    from bot.handlers.backup import rotate_backups

    for i in range(8):
        f = tmp_path / f"backup_{i:02d}.tar.gz"
        f.write_text("data")
        os.utime(f, (1000 + i, 1000 + i))

    rotate_backups(str(tmp_path), max_backups=7)

    remaining = list(tmp_path.glob("*.tar.gz"))
    assert len(remaining) == 7
    assert not (tmp_path / "backup_00.tar.gz").exists()
