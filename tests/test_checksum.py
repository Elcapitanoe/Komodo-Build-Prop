"""Tests for cryptographic checksum operations."""

import hashlib
from pathlib import Path

import pytest

from komodo_tools.core.checksum import (
    calculate_sha256,
    generate_checksum_file,
    parse_checksum_file,
    verify_checksum,
)


def test_calculate_sha256(tmp_path: Path):
    test_file = tmp_path / "sample.bin"
    test_file.write_bytes(b"hello world")
    expected = hashlib.sha256(b"hello world").hexdigest()

    assert calculate_sha256(test_file) == expected


def test_generate_and_verify_checksum(tmp_path: Path):
    test_file = tmp_path / "artifact.zip"
    test_file.write_bytes(b"zip binary payload")

    chk_file = generate_checksum_file(test_file)
    assert chk_file.is_file()

    expected_hash = hashlib.sha256(b"zip binary payload").hexdigest()
    assert parse_checksum_file(chk_file) == expected_hash

    is_valid, exp, act = verify_checksum(test_file, chk_file)
    assert is_valid is True
    assert exp == expected_hash
    assert act == expected_hash


def test_verify_checksum_mismatch(tmp_path: Path):
    test_file = tmp_path / "tampered.zip"
    test_file.write_bytes(b"original content")
    chk_file = generate_checksum_file(test_file)

    # Tamper file
    test_file.write_bytes(b"modified content")

    is_valid, exp, act = verify_checksum(test_file, chk_file)
    assert is_valid is False
    assert exp != act


def test_nonexistent_file():
    with pytest.raises(FileNotFoundError):
        calculate_sha256(Path("/non/existent/path.zip"))
