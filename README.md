<div align="center">

# Komodo Pixel Props

**Spoof your device fingerprint to Google Pixel 9 Pro XL (`komodo`) effortlessly.**

<br>

![Total Downloads](https://img.shields.io/github/downloads/Elcapitanoe/Komodo-Build-Prop/total?style=flat-square&color=7490ac&label=Total%20Downloads)
![Latest Stable](https://img.shields.io/github/v/release/Elcapitanoe/Komodo-Build-Prop?style=flat-square&color=7490ac&label=Latest%20Version)
![Release Date](https://img.shields.io/github/release-date/Elcapitanoe/Komodo-Build-Prop?style=flat-square&color=7490ac&label=Released)
![Last Commit](https://img.shields.io/github/last-commit/Elcapitanoe/Komodo-Build-Prop/main?style=flat-square&color=7490ac&label=Last%20Update)

<br>

</div>

## Overview
Komodo Pixel Props is a systemless root module that modifies build properties, attestation flags, and system configurations to identify your device as a Google Pixel 9 Pro XL (`komodo`). It includes automated integration for Play Integrity Fix, TrickyStore, and custom ROM property sanitation.

## Features
- **System Property Spoofing:** Sets device identity (`model`, `brand`, `manufacturer`, `fingerprint`, `build ID`) across all partitions (`system`, `vendor`, `product`, `system_ext`, `odm`).
- **Attestation & Integrity Integration:**
  - **PlayIntegrityFix (PIF):** Automatically generates or syncs `pif.json` targeting the Pixel 9 Pro XL fingerprint.
  - **TrickyStore:** Generates and maintains `/data/adb/tricky_store/target.txt`, with automatic broken-TEE detection fallback (`teeBroken=true`).
  - **PropImitationHooks (PIHooks):** Automatic internal property spoofing when standalone PIF is not present.
- **Custom ROM Sanitization:** Removes common custom ROM identifiers (`test-keys`, `lineage_`, `userdebug`, `aosp_` prefixes) and sets bootloader flags to green/locked status across major OEMs (OnePlus, Oppo, Realme, Samsung warranty bit).
- **Pixel Features (Sysconfig):** Bundles Google Pixel experience configs including Adaptive Charging, Quick Tap, and Next-Generation Assistant (NGA).
- **Integrated WebUI:** Built-in dashboard for KernelSU and APatch to inspect active properties, manage PIF/TrickyStore targets, and check OTA status.

## Prerequisites
- **Supported Root Managers:**
  - Magisk v26.3 or newer
  - KernelSU v0.9.3 (daemon 10818) or newer
  - APatch v10763 or newer
- **Installation Environment:** Must be installed from your root manager app while Android is booted. **Flashing via custom recovery (TWRP/OrangeFox) is strictly unsupported.**

## Installation & Interactive Setup
1. Download the latest release `.zip` from GitHub Releases:
   `https://github.com/Elcapitanoe/Komodo-Build-Prop/releases`
2. Open Magisk, KernelSU, or APatch.
3. Go to **Modules** -> **Install from storage** and select the downloaded archive.
4. **Hardware Key Configuration:**
   During installation, the script requests user input to configure sensitive property checks (`SAFE_DEVICE`, `SAFE_SECURITY_PATCH`, `SAFE_SOC`, `SAFE_SDK`):
   - `Volume Up (+)` : **Yes (Enable safe check)**
   - `Volume Down (-)` : **No (Disable check)**
   - `Power Button` : **Cancel installation**
   *(Note: Users without physical volume keys can pre-configure these values in `config.prop` inside the zip).*
5. The installer writes your selected choices to `config.prop`, generates initial attestation configs, and verifies SHA-256 script integrity.
6. Reboot your device.

## Action Script & WebUI
- In KernelSU / APatch / Magisk, you can trigger the module **Action** button to:
  - Regenerate `pif.json` for PlayIntegrityFix.
  - Refresh target packages for TrickyStore (`target.txt`).
- On KernelSU and APatch, access the module WebUI from the module details page to review active props and manage integrations.

## Troubleshooting
If your device experiences boot issues after installation:
1. Boot into Safe Mode or access your device storage via custom recovery / ADB root.
2. Disable or remove the module directory:
   - Remove `/data/adb/modules/Komodo_beta_Props` (or `/data/adb/modules/Komodo_Props`).
   - Alternatively, create an empty file at `/data/adb/modules/Komodo_beta_Props/disable`.
3. Reboot to system.

## Verification
Confirm spoofing is active via terminal or ADB:

```bash
getprop ro.product.model
```
Expected output: `Pixel 9 Pro XL`

Check fingerprint status:
```bash
getprop ro.product.build.fingerprint
```

## Developer CLI & Automation
This repository includes a Python CLI toolchain (`komodo-tools`) for automated OTA release tracking, checksum operations, and Telegram distribution.

### Setup
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

### Usage
```bash
# Scan upstream Google OTA releases
komodo-tools ota scan --devices komodo

# Generate SHA-256 checksums
komodo-tools checksum generate file.zip

# Verify SHA-256 checksum
komodo-tools checksum verify file.zip

# Run test suite and linter
pytest
ruff check .
```

## Changelog
See `CHANGELOG.md` for release history, build IDs, and property updates.

## Credits
- **Maintainer:** [Elcapitanoe](https://github.com/Elcapitanoe)
- **Module Scripts & Logic:** [Tesla](https://t.me/PixelProps) / [0x11DFE](https://github.com/0x11DFE)

## Support & Feedback
- Issue tracker: `https://github.com/Elcapitanoe/Komodo-Build-Prop/issues`
- Discussions: `https://github.com/Elcapitanoe/Komodo-Build-Prop/discussions`
