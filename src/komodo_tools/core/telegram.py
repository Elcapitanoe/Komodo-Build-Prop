"""Telegram bot notification client with connection pooling and retries."""

import html
import logging
from pathlib import Path
from typing import Any

import requests
from requests.adapters import HTTPAdapter
from urllib3.util import Retry

logger = logging.getLogger(__name__)

TELEGRAM_API_BASE = "https://api.telegram.org"
MAX_MESSAGE_LENGTH = 4000


class TelegramNotifier:
    """Production-grade Telegram Bot client for alerts and asset releases."""

    def __init__(self, token: str, chat_id: str, timeout: int = 15):
        if not token or not chat_id:
            raise ValueError("Both token and chat_id are required for TelegramNotifier.")
        self.token = token
        self.chat_id = chat_id
        self.timeout = timeout

        self.session = requests.Session()
        retries = Retry(
            total=3,
            backoff_factor=1.5,
            status_forcelist=[429, 500, 502, 503, 504],
            raise_on_status=False,
        )
        adapter = HTTPAdapter(max_retries=retries)
        self.session.mount("https://", adapter)
        self.session.mount("http://", adapter)

    def _api_url(self, method: str) -> str:
        return f"{TELEGRAM_API_BASE}/bot{self.token}/{method}"

    @staticmethod
    def escape(text: str) -> str:
        """Escape dynamic text for Telegram HTML parse mode."""
        return html.escape(text, quote=True)

    def send_message(self, text: str, parse_mode: str = "HTML") -> list[dict[str, Any]]:
        """Send a message to the target chat, splitting into chunks if necessary."""
        chunks = self._chunk_message(text)
        responses: list[dict[str, Any]] = []

        for chunk in chunks:
            payload = {
                "chat_id": self.chat_id,
                "text": chunk,
                "parse_mode": parse_mode,
                "disable_web_page_preview": True,
            }
            try:
                response = self.session.post(
                    self._api_url("sendMessage"),
                    json=payload,
                    timeout=self.timeout,
                )
                response.raise_for_status()
                responses.append(response.json())
            except requests.RequestException as exc:
                logger.error("Failed to send Telegram message: %s", exc)
                raise

        return responses

    def send_document(
        self, file_path: Path, caption: str = "", parse_mode: str = "HTML"
    ) -> dict[str, Any]:
        """Upload and send a document file with optional caption."""
        if not file_path.is_file():
            raise FileNotFoundError(f"Document file not found: {file_path}")

        url = self._api_url("sendDocument")
        data = {
            "chat_id": self.chat_id,
            "caption": caption[:1024],  # Telegram caption character limit
            "parse_mode": parse_mode,
        }

        try:
            with file_path.open("rb") as f:
                files = {"document": (file_path.name, f)}
                response = self.session.post(
                    url, data=data, files=files, timeout=max(self.timeout, 60)
                )
                response.raise_for_status()
                return response.json()
        except requests.RequestException as exc:
            logger.error("Failed to send document '%s' to Telegram: %s", file_path.name, exc)
            raise

    @staticmethod
    def _chunk_message(text: str, limit: int = MAX_MESSAGE_LENGTH) -> list[str]:
        """Split text cleanly across line breaks to respect Telegram size limits."""
        if len(text) <= limit:
            return [text]

        chunks: list[str] = []
        lines = text.splitlines(keepends=True)
        current_chunk: list[str] = []
        current_len = 0

        for line in lines:
            if current_len + len(line) > limit:
                if current_chunk:
                    chunks.append("".join(current_chunk))
                    current_chunk = [line]
                    current_len = len(line)
                else:
                    # Single line exceeds limit: hard split
                    chunks.append(line[:limit])
                    current_chunk = [line[limit:]]
                    current_len = len(current_chunk[0])
            else:
                current_chunk.append(line)
                current_len += len(line)

        if current_chunk:
            chunks.append("".join(current_chunk))

        return chunks
