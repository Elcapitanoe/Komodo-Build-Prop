"""Google Android OTA manifest monitor and state manager."""

import json
import logging
import os
import re
import tempfile
from pathlib import Path
from typing import Any

import requests

from komodo_tools.core.telegram import TelegramNotifier

logger = logging.getLogger(__name__)

DEFAULT_OTA_URL = "https://developer.android.com/about/versions/17/qpr2/download-ota"
DEFAULT_STABLE_URL = "https://developers.google.com/android/ota?partial=1"
UPSTREAM_STATE_URL = (
    "https://raw.githubusercontent.com/Elcapitanoe/Build-Prop-BETA/main/data/state.json"
)

# Matches both Beta (/developers/android/.../images/ota/...) and Stable (/dl/android/aosp/...)
OTA_REGEX = re.compile(
    r"https://dl\.google\.com/(?:developers/android/[a-zA-Z0-9]+/images/ota|dl/android/aosp)/[a-zA-Z0-9_.-]+\.zip"
)

DEFAULT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
    )
}
DEFAULT_COOKIES = {
    "devsite_wall_acks": "nexus-ota-tos"
}


def discover_active_beta_url(timeout: int = 10) -> str:
    """Dynamically discover the latest Android Beta/QPR OTA manifest URL.

    Resolution order:
    1. Query upstream Build-Prop-BETA data/state.json for active_target.
    2. Scrape developer.android.com/about/versions for latest major and QPR branch.
    3. Fallback to DEFAULT_OTA_URL.
    """
    # 1. Check upstream state definition
    try:
        res = requests.get(UPSTREAM_STATE_URL, timeout=timeout)
        if res.status_code == 200:
            data = res.json()
            upstream_url = data.get("active_target", {}).get("url")
            if upstream_url:
                logger.info("Resolved active beta URL from upstream state: %s", upstream_url)
                return upstream_url
    except Exception as exc:
        logger.debug("Failed to query upstream state (%s); proceeding to web discovery", exc)

    # 2. Autonomous web discovery on developer.android.com
    try:
        base = "https://developer.android.com"
        res = requests.get(
            f"{base}/about/versions",
            headers=DEFAULT_HEADERS,
            cookies=DEFAULT_COOKIES,
            timeout=timeout,
        )
        if res.status_code == 200:
            versions = sorted(
                {int(m) for m in re.findall(r"/about/versions/(\d+)", res.text) if int(m) >= 15}
            )
            if versions:
                latest_major = versions[-1]
                res_major = requests.get(
                    f"{base}/about/versions/{latest_major}",
                    headers=DEFAULT_HEADERS,
                    cookies=DEFAULT_COOKIES,
                    timeout=timeout,
                )
                qpr_matches = re.findall(
                    rf"/about/versions/{latest_major}/(qpr\d+)/download-ota",
                    res_major.text,
                )
                if qpr_matches:
                    latest_qpr = sorted(qpr_matches, key=lambda x: int(x.replace("qpr", "")))[-1]
                    discovered = f"{base}/about/versions/{latest_major}/{latest_qpr}/download-ota"
                    logger.info("Dynamically discovered active beta URL: %s", discovered)
                    return discovered

                if f"/about/versions/{latest_major}/download-ota" in res_major.text:
                    discovered = f"{base}/about/versions/{latest_major}/download-ota"
                    logger.info("Dynamically discovered active beta URL: %s", discovered)
                    return discovered
    except Exception as exc:
        logger.debug("Failed dynamic web discovery (%s); falling back to default", exc)

    logger.info("Using default fallback beta URL: %s", DEFAULT_OTA_URL)
    return DEFAULT_OTA_URL


def resolve_manifest_urls(
    custom_url: str | None = None, include_stable: bool = True
) -> list[str]:
    """Resolve all manifest URLs to scan (active Beta + Stable)."""
    if custom_url:
        return [custom_url]

    urls = [discover_active_beta_url()]
    if include_stable:
        urls.append(DEFAULT_STABLE_URL)
    return urls


def fetch_ota_manifest(url: str = DEFAULT_OTA_URL, timeout: int = 20) -> list[str]:
    """Scrape a single OTA download page and extract Google OTA zip links."""
    logger.info("Fetching OTA manifest from: %s", url)
    response = requests.get(
        url, headers=DEFAULT_HEADERS, cookies=DEFAULT_COOKIES, timeout=timeout
    )
    response.raise_for_status()

    links = OTA_REGEX.findall(response.text)
    logger.info("Discovered %d OTA candidate links on manifest page", len(links))
    return links


def fetch_all_manifest_links(urls: list[str], timeout: int = 20) -> list[str]:
    """Scrape multiple manifest URLs and return deduplicated OTA links."""
    combined_links: set[str] = set()
    for url in urls:
        try:
            links = fetch_ota_manifest(url=url, timeout=timeout)
            combined_links.update(links)
        except requests.RequestException as exc:
            logger.error("Failed to fetch manifest from %s: %s", url, exc)

    return sorted(combined_links)


def filter_links_for_device(all_links: list[str], codename: str) -> list[str]:
    """Filter links matching the given device codename (e.g. 'komodo')."""
    lowered = codename.lower()
    return sorted(
        {
            link
            for link in all_links
            if f"/{lowered}_" in link.lower()
            or f"/{lowered}-" in link.lower()
            or f"{lowered}_" in link.split("/")[-1].lower()
            or f"{lowered}-" in link.split("/")[-1].lower()
        }
    )


def load_state(state_path: Path) -> dict[str, list[str]]:
    """Load previous OTA state. Recovers legacy list format without resetting."""
    if not state_path.is_file():
        logger.info("No prior state file found at %s. Initializing empty state.", state_path)
        return {}

    try:
        with state_path.open("r", encoding="utf-8") as f:
            data = json.load(f)

        if isinstance(data, list):
            logger.warning("Legacy list state format detected; wrapping under 'komodo' key.")
            return {"komodo": data}

        if isinstance(data, dict):
            return {k: list(v) for k, v in data.items() if isinstance(v, list)}

        logger.warning("Unrecognized state format in %s; defaulting to empty.", state_path)
        return {}
    except (json.JSONDecodeError, OSError) as exc:
        logger.error("Failed to read state file (%s). Preserving existing file.", exc)
        return {}


def save_state_atomic(state_path: Path, state: dict[str, Any]) -> None:
    """Atomically persist state to disk using a temporary file replacement."""
    state_path.parent.mkdir(parents=True, exist_ok=True)
    temp_dir = state_path.parent

    with tempfile.NamedTemporaryFile("w", dir=temp_dir, delete=False, encoding="utf-8") as tf:
        json.dump(state, tf, indent=2)
        tf.flush()
        os.fsync(tf.fileno())
        temp_name = tf.name

    Path(temp_name).replace(state_path)
    logger.info("State successfully persisted to %s", state_path)


def format_ota_notification(new_updates: dict[str, list[str]]) -> str:
    """Format Telegram HTML notification with safe entity escaping."""
    lines = [
        "<b>System Notification: Multi-Device OTA Update Report</b>\n",
    ]

    for device, links in sorted(new_updates.items()):
        escaped_device = TelegramNotifier.escape(device.capitalize())
        lines.append(f"<b>Device: {escaped_device}</b> ({len(links)} updates)")
        for link in links:
            filename = link.split("/")[-1]
            escaped_file = TelegramNotifier.escape(filename)
            escaped_link = TelegramNotifier.escape(link)
            lines.append(f"File: <code>{escaped_file}</code>")
            lines.append(f"Link: {escaped_link}")
        lines.append("")

    return "\n".join(lines).strip()
