#!/usr/bin/env python3
"""Backward-compatible entry point delegating to komodo_tools CLI."""

import sys

from komodo_tools.cli import main

if __name__ == "__main__":
    # Pass 'ota' 'scan' as default subcommands, appending any extra CLI flags
    sys.exit(main(["ota", "scan", *sys.argv[1:]]))
