"""Tests for the upstream changelog helper."""

import datetime as dt
import json
from pathlib import Path

from update_changelog import load_entries, update_changelog


def test_update_changelog_adds_one_release_block(tmp_path: Path):
    metadata_path = tmp_path / "metadata-komodo.json"
    metadata_path.write_text(
        json.dumps(
            {
                "device_name": "Pixel 9 Pro XL",
                "codename": "komodo",
                "zip_name": "Komodo_beta_DP11.261016.003.zip",
                "sha256": "abc123",
                "build_desc": "generic_system_google-user 17 DP11.261016.003",
            }
        ),
        encoding="utf-8",
    )
    changelog_path = tmp_path / "CHANGELOG.md"
    changelog_path.write_text("# Changelog\n", encoding="utf-8")

    entries = load_entries([str(metadata_path)])

    assert update_changelog(changelog_path, entries) is True
    content = changelog_path.read_text(encoding="utf-8")
    today = dt.datetime.now(dt.UTC).date().isoformat()
    assert content.count(f"## [{today}]") == 1
    assert "Pixel 9 Pro XL (Komodo)" in content
    assert "Komodo_beta_DP11.261016.003.zip" in content
    assert update_changelog(changelog_path, entries) is False
