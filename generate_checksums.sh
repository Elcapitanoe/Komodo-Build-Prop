#!/usr/bin/env bash
set -euo pipefail

if ! command -v sha256sum &> /dev/null; then
    echo "[ERROR] 'sha256sum' executable not found." >&2
    exit 1
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <file1> [file2 ...]" >&2
    exit 1
fi

for target_file in "$@"; do
    if [[ ! -f "${target_file}" ]]; then
        echo "[WARNING] File not found, skipping: ${target_file}" >&2
        continue
    fi

    hashfile="${target_file}.sha256"
    tempfile="${hashfile}.tmp"

    if sha256sum "${target_file}" > "${tempfile}"; then
        mv -f "${tempfile}" "${hashfile}"
        echo "Generated: ${hashfile}"
    else
        rm -f "${tempfile}"
        echo "[ERROR] Failed to hash ${target_file}" >&2
    fi
done
