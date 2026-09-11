"""Tests for OTA parser and state management."""

from pathlib import Path
from unittest.mock import MagicMock, patch

from komodo_tools.core.ota import (
    DEFAULT_OTA_URL,
    DEFAULT_STABLE_URL,
    discover_active_beta_url,
    filter_links_for_device,
    format_ota_notification,
    load_state,
    resolve_manifest_urls,
    save_state_atomic,
)


def test_filter_links_for_device():
    sample_links = [
        "https://dl.google.com/developers/android/images/ota/komodo-ota-123.zip",
        "https://dl.google.com/developers/android/images/ota/komodo_beta-ota-456.zip",
        "https://dl.google.com/developers/android/images/ota/caiman-ota-789.zip",
        "https://dl.google.com/dl/android/aosp/komodo-ota-cp2a.260805.005.a1.zip",
    ]

    filtered = filter_links_for_device(sample_links, "komodo")
    assert len(filtered) == 3
    assert all("caiman" not in item for item in filtered)


def test_state_atomic_persistence(tmp_path: Path):
    state_file = tmp_path / "ota_state.json"
    initial_data = {"komodo": ["https://example.com/ota1.zip"]}

    save_state_atomic(state_file, initial_data)
    assert state_file.is_file()

    loaded = load_state(state_file)
    assert loaded == initial_data


def test_legacy_state_recovery(tmp_path: Path):
    state_file = tmp_path / "legacy.json"
    state_file.write_text('["https://example.com/legacy.zip"]', encoding="utf-8")

    loaded = load_state(state_file)
    assert loaded == {"komodo": ["https://example.com/legacy.zip"]}


def test_format_ota_notification_escaping():
    updates = {
        "komodo<test>": [
            "https://dl.google.com/developers/android/images/ota/komodo&file.zip"
        ]
    }
    rendered = format_ota_notification(updates)
    assert "&lt;test&gt;" in rendered
    assert "&amp;file.zip" in rendered


def test_discover_active_beta_url_upstream_mock():
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {
        "active_target": {
            "url": "https://developer.android.com/about/versions/18/qpr1/download-ota"
        }
    }

    with patch("requests.get", return_value=mock_resp):
        url = discover_active_beta_url()
        assert url == "https://developer.android.com/about/versions/18/qpr1/download-ota"


def test_resolve_manifest_urls():
    # Custom URL overrides auto discovery
    custom = resolve_manifest_urls(custom_url="https://custom.com/ota")
    assert custom == ["https://custom.com/ota"]

    # Default includes discovered beta and stable
    with patch(
        "komodo_tools.core.ota.discover_active_beta_url",
        return_value=DEFAULT_OTA_URL,
    ):
        urls = resolve_manifest_urls(include_stable=True)
        assert urls == [DEFAULT_OTA_URL, DEFAULT_STABLE_URL]

        urls_no_stable = resolve_manifest_urls(include_stable=False)
        assert urls_no_stable == [DEFAULT_OTA_URL]
