"""Tests for CLI orchestration and state safety."""

from argparse import Namespace
from unittest.mock import patch

from komodo_tools.cli import handle_ota_scan, handle_release_telegram


def test_ota_scan_does_not_persist_state_when_notification_fails(tmp_path):
    args = Namespace(
        state_file=str(tmp_path / "ota_state.json"),
        devices="komodo",
        url="https://example.com/ota",
        no_stable=True,
        dry_run=False,
    )

    with (
        patch.dict(
            "os.environ",
            {"TELEGRAM_BOT_TOKEN": "token", "TELEGRAM_CHAT_ID": "chat"},
        ),
        patch("komodo_tools.cli.fetch_all_manifest_links", return_value=["ota-link"]),
        patch("komodo_tools.cli.load_state", return_value={}),
        patch("komodo_tools.cli.filter_links_for_device", return_value=["ota-link"]),
        patch("komodo_tools.cli.format_ota_notification", return_value="update"),
        patch("komodo_tools.cli.TelegramNotifier") as notifier_cls,
        patch("komodo_tools.cli.save_state_atomic") as save_state,
    ):
        notifier_cls.return_value.send_message.side_effect = RuntimeError("telegram down")

        assert handle_ota_scan(args) == 2
        save_state.assert_not_called()


def test_ota_scan_persists_state_and_succeeds_without_telegram_credentials(tmp_path):
    args = Namespace(
        state_file=str(tmp_path / "ota_state.json"),
        devices="komodo",
        url="https://example.com/ota",
        no_stable=True,
        dry_run=False,
    )

    github_output = tmp_path / "github_output"

    with (
        patch.dict(
            "os.environ",
            {"TELEGRAM_BOT_TOKEN": "token", "GITHUB_OUTPUT": str(github_output)},
            clear=True,
        ),
        patch("komodo_tools.cli.fetch_all_manifest_links", return_value=["ota-link"]),
        patch("komodo_tools.cli.load_state", return_value={}),
        patch("komodo_tools.cli.filter_links_for_device", return_value=["ota-link"]),
        patch("komodo_tools.cli.format_ota_notification", return_value="update"),
        patch("komodo_tools.cli.TelegramNotifier") as notifier_cls,
        patch("komodo_tools.cli.save_state_atomic") as save_state,
    ):
        assert handle_ota_scan(args) == 0
        save_state.assert_called_once_with(
            tmp_path / "ota_state.json", {"komodo": ["ota-link"]}
        )
        notifier_cls.assert_not_called()
        assert github_output.read_text(encoding="utf-8") == "updated=true\n"


def test_release_telegram_succeeds_without_telegram_credentials(tmp_path):
    args = Namespace(
        repo="example/repo",
        tag=None,
        assets_dir=str(tmp_path / "assets"),
    )

    with (
        patch.dict("os.environ", {}, clear=True),
        patch("komodo_tools.cli.publish_release_to_telegram") as publish,
    ):
        assert handle_release_telegram(args) == 0
        publish.assert_not_called()
