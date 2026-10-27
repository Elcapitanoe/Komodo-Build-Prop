"""Tests for CLI orchestration and state safety."""

from argparse import Namespace
from unittest.mock import patch

from komodo_tools.cli import handle_ota_scan


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
