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

## Prerequisites
Before flashing, ensure your environment meets the following criteria:

- **Root Access:** Magisk (v24+) or KernelSU.
- **Recovery:** A custom recovery (TWRP/OFRP) is recommended for emergency backups.

## Installation Guide
1. **Download:** Grab the latest `.zip` from [GitHub Releases](https://github.com/Elcapitanoe/Komodo-Build-Prop/releases) or the [Official Website](https://pixelprop.pages.dev).
2. **Flash:** Open your root manager (Magisk/KernelSU), navigate to **Modules**, and select **Install from storage**.
3. **Configure:** The installer script uses hardware keys for selection:
   - `Volume Up (+)` : **Confirm / Yes**
   - `Volume Down (-)` : **Decline / No**
4. **Apply:** Once installation is complete, **Reboot** your device to apply changes.

## Troubleshooting (Bootloop Rescue)
If your device hangs at boot or encounters a "soft brick" after installation:

1. Boot into **Custom Recovery** (TWRP/OrangeFox).
2. Launch the **File Manager**.
3. Navigate to: `/data/adb/modules/`
4. Delete the folder: `Komodo_Props` (or `Komodo_beta_Props`).
5. Reboot System.

## Verification
To confirm the spoof is active, run the following command in a terminal emulator or ADB shell:

```bash
getprop ro.product.model
```

Expected output: `Pixel 9 Pro XL`

For Play Integrity status, use the official checker app from Google Play.

## Changelog
See the [CHANGELOG.md](CHANGELOG.md) file for a complete history of changes, fingerprint updates, and bug fixes.

## Credits
- **Core Logic:** [0x11DFE](https://github.com/0x11DFE)
- **Maintainer:** [Elcapitanoe](https://github.com/Elcapitanoe)

## Feedback & Support
- **Bug Reports:** Open an issue on the [Issues Page](https://github.com/Elcapitanoe/Komodo-Build-Prop/issues).
- **Discussions:** Use GitHub Discussions for general questions and suggestions.

<div align="center">
</div>
