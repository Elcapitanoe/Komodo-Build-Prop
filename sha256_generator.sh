#!/bin/bash

# Loop through all .sh files in the current directory (except this script itself)
for file in *.sh; do
  # Skip if it's this script
  [ "$file" = "sha256.sh" ] && continue

  # Skip if no .sh files found
  [ -e "$file" ] || continue

  # Target hash file
  hashfile="$file.sha256"

  # If exists, overwrite
  if [ -f "$hashfile" ]; then
    echo "Replacing existing hash: $hashfile"
  fi

  # Generate SHA256 and overwrite
  sha256sum "$file" | awk '{ print $1 }' > "$hashfile"

  echo "SHA256 written: $hashfile"
done
