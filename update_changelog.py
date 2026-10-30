"""Update the release changelog from upstream build metadata."""

from __future__ import annotations

import datetime as dt
import glob
import json
import os
from pathlib import Path
from typing import Any


def load_entries(metadata_paths: list[str]) -> list[str]:
    """Render unique changelog entries from metadata files."""
    entries: list[str] = []
    seen: set[str] = set()

    for metadata_path in metadata_paths:
        with Path(metadata_path).open(encoding="utf-8") as metadata_file:
            metadata: dict[str, Any] = json.load(metadata_file)

        zip_name = str(metadata.get("zip_name", ""))
        if not zip_name or zip_name in seen:
            continue
        seen.add(zip_name)

        device_name = str(metadata.get("device_name", ""))
        codename = str(metadata.get("codename", ""))
        sha256 = str(metadata.get("sha256", ""))
        build_description = str(metadata.get("build_desc", ""))

        entry = (
            f"- **{device_name} ({codename.capitalize()})**: `{zip_name}`\n"
            f"  - SHA256: `{sha256}`\n"
        )
        if build_description:
            entry += f"  - Build: `{build_description}`\n"
        entries.append(entry)

    return entries


def update_changelog(changelog_path: Path, entries: list[str]) -> bool:
    """Insert today's release block and report whether the file changed."""
    if not entries:
        return False

    today = dt.datetime.now(dt.UTC).date().isoformat()
    block = f"## [{today}]\n" + "".join(entries) + "\n"

    if not changelog_path.exists():
        changelog_path.write_text(f"# Changelog\n\n{block}", encoding="utf-8")
        return True

    body = changelog_path.read_text(encoding="utf-8")
    if f"## [{today}]" in body:
        return False

    if "\n## " in body:
        index = body.index("\n## ")
        body = body[: index + 1] + block + body[index + 1 :]
    else:
        body = body.rstrip() + "\n\n" + block

    changelog_path.write_text(body, encoding="utf-8")
    return True


def main() -> None:
    metadata_paths = sorted(glob.glob("new_modules/metadata-*.json"))
    if not metadata_paths:
        print("No metadata files found.")
        return

    changelog_path = Path(os.environ.get("CHANGELOG_PATH", "CHANGELOG.md"))
    entries = load_entries(metadata_paths)
    if update_changelog(changelog_path, entries):
        print(f"Updated {changelog_path}.")
    else:
        print(f"No changelog update needed for {changelog_path}.")


if __name__ == "__main__":
    main()
