"""Cryptographic checksum utilities for release artifacts."""

import hashlib
from pathlib import Path


def calculate_sha256(file_path: Path) -> str:
    """Calculate the SHA-256 hash of a file using chunked binary reading."""
    if not file_path.is_file():
        raise FileNotFoundError(f"Target file not found: {file_path}")

    hasher = hashlib.sha256()
    with file_path.open("rb") as stream:
        if hasattr(hashlib, "file_digest"):
            return hashlib.file_digest(stream, "sha256").hexdigest().lower()
        while chunk := stream.read(65536):
            hasher.update(chunk)
    return hasher.hexdigest().lower()


def generate_checksum_file(file_path: Path) -> Path:
    """Generate a standard .sha256 checksum file for the target file."""
    digest = calculate_sha256(file_path)
    output_path = file_path.parent / f"{file_path.name}.sha256"
    temp_path = file_path.parent / f"{file_path.name}.sha256.tmp"

    # Standard coreutils sha256sum format: "<hash>  <filename>\n"
    content = f"{digest}  {file_path.name}\n"
    temp_path.write_text(content, encoding="utf-8")
    temp_path.replace(output_path)
    return output_path


def parse_checksum_file(checksum_path: Path) -> str:
    """Extract expected hex digest from a checksum file."""
    if not checksum_path.is_file():
        raise FileNotFoundError(f"Checksum file not found: {checksum_path}")

    content = checksum_path.read_text(encoding="utf-8").strip()
    if not content:
        raise ValueError(f"Checksum file is empty: {checksum_path}")

    first_line = content.splitlines()[0].strip()
    parts = first_line.split()
    if not parts:
        raise ValueError(f"Invalid format in checksum file: {checksum_path}")

    expected_hash = parts[0].lower()
    if len(expected_hash) != 64 or not all(c in "0123456789abcdef" for c in expected_hash):
        raise ValueError(f"Invalid SHA-256 hex format: '{expected_hash}'")

    return expected_hash


def verify_checksum(
    file_path: Path, checksum_path: Path | None = None
) -> tuple[bool, str, str]:
    """Verify that a file matches its expected SHA-256 hash.

    Returns:
        (is_valid, expected_hash, actual_hash)
    """
    if checksum_path is None:
        checksum_path = file_path.parent / f"{file_path.name}.sha256"

    expected_hash = parse_checksum_file(checksum_path)
    actual_hash = calculate_sha256(file_path)
    return expected_hash == actual_hash, expected_hash, actual_hash
