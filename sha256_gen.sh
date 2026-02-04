#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

if ! command -v sha256sum &> /dev/null; then
    echo "Error: 'sha256sum' executable not found." >&2
    exit 1
fi

current_script="$(basename "$0")"

for file in *.sh; do
    [[ "$file" == "$current_script" ]] && continue

    hashfile="${file}.sha256"
    tempfile="${hashfile}.tmp"

    if sha256sum "$file" | cut -d ' ' -f 1 > "$tempfile"; then
        mv -f "$tempfile" "$hashfile"
        echo "Generated: $hashfile"
    else
        rm -f "$tempfile"
        echo "Error: Failed to hash $file" >&2
        exit 1
    fi
done
