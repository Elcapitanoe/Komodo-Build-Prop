"""Command-line interface for Komodo automation tools."""

import argparse
import logging
import os
import sys
from pathlib import Path

from komodo_tools import __version__
from komodo_tools.core.checksum import generate_checksum_file, verify_checksum
from komodo_tools.core.ota import (
    fetch_all_manifest_links,
    filter_links_for_device,
    format_ota_notification,
    load_state,
    resolve_manifest_urls,
    save_state_atomic,
)
from komodo_tools.core.release import publish_release_to_telegram
from komodo_tools.core.telegram import TelegramNotifier


def setup_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="[%(asctime)s] [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def emit_github_output(key: str, value: str) -> None:
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if gh_output:
        with open(gh_output, "a", encoding="utf-8") as fh:
            print(f"{key}={value}", file=fh)


def handle_ota_scan(args: argparse.Namespace) -> int:
    state_path = Path(args.state_file)
    devices = [d.strip() for d in args.devices.split(",") if d.strip()]
    if not devices:
        logging.error("No target devices specified.")
        return 1

    logging.info("Starting scan for devices: %s", devices)
    manifest_urls = resolve_manifest_urls(
        custom_url=args.url, include_stable=not args.no_stable
    )
    all_links = fetch_all_manifest_links(urls=manifest_urls)
    current_state = load_state(state_path)

    new_updates: dict[str, list[str]] = {}
    updated_state: dict[str, list[str]] = dict(current_state)

    for device in devices:
        device_links = filter_links_for_device(all_links, device)
        old_links = current_state.get(device, [])
        unseen = sorted(set(device_links) - set(old_links))

        if unseen:
            logging.info("[%s] Found %d new update(s).", device, len(unseen))
            new_updates[device] = unseen
            updated_state[device] = device_links
        else:
            updated_state[device] = device_links

    if new_updates:
        message = format_ota_notification(new_updates)

        token = os.environ.get("TELEGRAM_BOT_TOKEN")
        chat_id = os.environ.get("TELEGRAM_CHAT_ID")

        if token and chat_id and not args.dry_run:
            try:
                notifier = TelegramNotifier(token, chat_id)
                notifier.send_message(message)
                logging.info("Dispatched Telegram alert successfully.")
            except Exception as exc:
                logging.error("Failed to deliver Telegram notification: %s", exc)
        else:
            logging.info("Telegram notification skipped (dry-run or missing credentials).")

        if not args.dry_run:
            save_state_atomic(state_path, updated_state)

        emit_github_output("updated", "true")
    else:
        logging.info("Scan complete. No new updates found.")
        emit_github_output("updated", "false")

    return 0


def handle_checksum_generate(args: argparse.Namespace) -> int:
    for target in args.files:
        path = Path(target)
        if not path.is_file():
            logging.warning("Skipping non-existent file: %s", path)
            continue
        out_file = generate_checksum_file(path)
        print(f"Generated: {out_file}")
    return 0


def handle_checksum_verify(args: argparse.Namespace) -> int:
    path = Path(args.file)
    chk_path = Path(args.checksum_file) if args.checksum_file else None

    try:
        is_valid, expected, actual = verify_checksum(path, chk_path)
    except Exception as exc:
        logging.error("Verification error: %s", exc)
        return 2

    if is_valid:
        print(f"Verification Successful: {path}")
        return 0

    logging.error("Verification Failed for %s!", path)
    print(f"Expected: {expected}\nActual:   {actual}", file=sys.stderr)
    return 1


def handle_release_telegram(args: argparse.Namespace) -> int:
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID")
    gh_token = os.environ.get("GITHUB_TOKEN")

    if not token or not chat_id:
        logging.error("TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID environment variables are required.")
        return 1

    repo = args.repo or os.environ.get("GITHUB_REPOSITORY", "Elcapitanoe/Komodo-Build-Prop")
    tag = args.tag or None
    assets_dir = Path(args.assets_dir)

    try:
        notifier = TelegramNotifier(token, chat_id)
        publish_release_to_telegram(
            notifier=notifier,
            repo=repo,
            tag=tag,
            assets_dir=assets_dir,
            github_token=gh_token,
        )
        return 0
    except Exception as exc:
        logging.error("Release distribution failed: %s", exc)
        return 1


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="komodo-tools",
        description="CLI utilities and automation for Komodo Pixel Props",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose debug logs")

    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    # Subcommand: ota scan
    ota_parser = subparsers.add_parser("ota", help="OTA monitoring operations")
    ota_sub = ota_parser.add_subparsers(dest="ota_action", required=True)
    scan_parser = ota_sub.add_parser("scan", help="Scan upstream OTA manifest")
    scan_parser.add_argument(
        "--url",
        default=None,
        help="Optional explicit manifest URL (defaults to auto-discovery of active Beta + Stable)",
    )
    scan_parser.add_argument(
        "--no-stable",
        action="store_true",
        help="Skip scanning stable Android OTA releases",
    )
    scan_parser.add_argument(
        "--devices",
        default=os.environ.get("DEVICE_CONFIG_RAW", "komodo"),
        help="Comma-separated device codenames to monitor",
    )
    scan_parser.add_argument(
        "--state-file",
        default=os.environ.get("STATE_FILE", "ota_state.json"),
        help="Path to JSON state file",
    )
    scan_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Perform scan without writing state or notifying",
    )

    # Subcommand: checksum
    chk_parser = subparsers.add_parser("checksum", help="Cryptographic checksum operations")
    chk_sub = chk_parser.add_subparsers(dest="checksum_action", required=True)

    gen_parser = chk_sub.add_parser("generate", help="Generate .sha256 checksum file(s)")
    gen_parser.add_argument("files", nargs="+", help="Target file paths")

    ver_parser = chk_sub.add_parser("verify", help="Verify file against .sha256 checksum")
    ver_parser.add_argument("file", help="Target file path")
    ver_parser.add_argument("--checksum-file", help="Optional path to .sha256 file")

    # Subcommand: release telegram
    rel_parser = subparsers.add_parser("release", help="Release pipeline operations")
    rel_sub = rel_parser.add_subparsers(dest="release_action", required=True)

    tg_parser = rel_sub.add_parser("telegram", help="Publish release assets to Telegram")
    tg_parser.add_argument("--repo", help="Target GitHub repository (owner/repo)")
    tg_parser.add_argument("--tag", help="Specific release tag name (defaults to latest)")
    tg_parser.add_argument("--assets-dir", default="assets", help="Directory to cache assets")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = create_parser()
    args = parser.parse_args(argv)
    setup_logging(args.verbose)

    if args.subcommand == "ota" and args.ota_action == "scan":
        return handle_ota_scan(args)
    elif args.subcommand == "checksum" and args.checksum_action == "generate":
        return handle_checksum_generate(args)
    elif args.subcommand == "checksum" and args.checksum_action == "verify":
        return handle_checksum_verify(args)
    elif args.subcommand == "release" and args.release_action == "telegram":
        return handle_release_telegram(args)

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
