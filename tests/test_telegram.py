"""Tests for Telegram API response handling."""

from unittest.mock import MagicMock

import pytest

from komodo_tools.core.telegram import TelegramAPIError, TelegramNotifier


def test_send_message_rejects_telegram_application_error():
    notifier = TelegramNotifier("token", "chat")
    response = MagicMock()
    response.json.return_value = {"ok": False, "description": "chat not found"}
    notifier.session.post = MagicMock(return_value=response)

    with pytest.raises(TelegramAPIError, match="chat not found"):
        notifier.send_message("hello")
