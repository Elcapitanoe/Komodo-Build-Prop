#!/bin/bash

for file in *.sh; do
  [ "$file" = "sha256.sh" ] && continue
  [ -e "$file" ] || continue

  hashfile="$file.sha256"
  [ -f "$hashfile" ] && echo "Replacing existing hash: $hashfile"

  sha256sum "$file" | awk '{ print $1 }' > "$hashfile"
  echo "SHA256 written: $hashfile"
done
