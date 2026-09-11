"""GitHub release asset downloader and Telegram distributor."""

import datetime
import logging
from pathlib import Path
from typing import Any

import requests

from komodo_tools.core.telegram import TelegramNotifier

logger = logging.getLogger(__name__)

GITHUB_API_BASE = "https://api.github.com"


def fetch_release_info(
    repo: str, tag: str | None = None, github_token: str | None = None
) -> dict[str, Any]:
    """Fetch release metadata from the GitHub REST API."""
    headers = {"Accept": "application/vnd.github.v3+json"}
    if github_token:
        headers["Authorization"] = f"token {github_token}"

    endpoint = f"tags/{tag}" if tag else "latest"
    url = f"{GITHUB_API_BASE}/repos/{repo}/releases/{endpoint}"

    logger.info("Fetching release metadata from: %s", url)
    response = requests.get(url, headers=headers, timeout=20)
    response.raise_for_status()
    return response.json()


def download_asset(url: str, target_dir: Path) -> Path:
    """Download an asset binary from GitHub release URL."""
    target_dir.mkdir(parents=True, exist_ok=True)
    filename = url.split("/")[-1]
    target_file = target_dir / filename

    logger.info("Downloading asset %s -> %s", filename, target_file)
    with requests.get(url, stream=True, timeout=60) as res:
        res.raise_for_status()
        with target_file.open("wb") as out:
            for chunk in res.iter_content(chunk_size=65536):
                if chunk:
                    out.write(chunk)

    return target_file


def publish_release_to_telegram(
    notifier: TelegramNotifier,
    repo: str,
    tag: str | None = None,
    assets_dir: Path = Path("assets"),
    github_token: str | None = None,
) -> None:
    """Download release assets and broadcast each document to Telegram."""
    info = fetch_release_info(repo=repo, tag=tag, github_token=github_token)

    actual_tag = info.get("tag_name", "latest")
    published_at = info.get("published_at")
    if published_at:
        date_str = published_at.split("T")[0]
    else:
        date_str = datetime.date.today().isoformat()

    assets = info.get("assets", [])
    if not assets:
        logger.warning("No downloadable assets found in release %s", actual_tag)
        return

    escaped_tag = TelegramNotifier.escape(actual_tag)
    escaped_date = TelegramNotifier.escape(date_str)
    escaped_repo = TelegramNotifier.escape(repo)

    caption = (
        "<b>New Update Released!</b>\n\n"
        f"Date: {escaped_date}\n"
        f"Version: <code>{escaped_tag}</code>\n\n"
        f'<a href="https://github.com/{escaped_repo}/releases/latest">GitHub Release</a> | '
        f'<a href="https://github.com/{escaped_repo}/issues">GitHub Issues</a>'
    )

    for asset_meta in assets:
        download_url = asset_meta.get("browser_download_url")
        if not download_url:
            continue

        asset_path = download_asset(download_url, target_dir=assets_dir)
        logger.info("Dispatching %s to Telegram...", asset_path.name)
        notifier.send_document(file_path=asset_path, caption=caption, parse_mode="HTML")

    logger.info("Successfully published all %d assets to Telegram", len(assets))
