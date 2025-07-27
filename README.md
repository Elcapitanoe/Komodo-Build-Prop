<div align="center">
<img src="https://img.shields.io/github/downloads/Elcapitanoe/Komodo-Build-Prop/total?style=flat-square&color=7490ac&label=Total%20Download" alt="Total downloads">
<img src="https://img.shields.io/github/v/release/Elcapitanoe/Komodo-Build-Prop?style=flat-square&color=7490ac&label=Latest%20Version" alt="Latest release version">
<img src="https://img.shields.io/github/release-date/Elcapitanoe/Komodo-Build-Prop?style=flat-square&color=7490ac&label=Last%20Release&display_date=published_at" alt="Last release date">
<img src="https://img.shields.io/github/last-commit/Elcapitanoe/Komodo-Build-Prop/main?style=flat-square&color=7490ac&label=Last%20Commit" alt="Last commit">
</div>

<hr />

# Komodo Pixel Build Props

> **Spoof your Android device as the Pixel 9 Pro XL (`komodo/komodo_beta`).**

## Requirements

- Rooted Android device (Magisk **or** KernelSU)  
- Custom recovery (optional, for backup)

## Installation

1. Download the latest `.zip` from the [Releases](https://github.com/Elcapitanoe/Komodo-Build-Prop/releases) page.  
2. Transfer the file to your Android device.  
3. Open Magisk or KernelSU → **Install from storage** → select `Komodo_XXXXXX.zip`.  
4. Use volume (Volume Up = Yes, Volume Down = No, Power = Cancel).  
5. Reboot once installation finishes.

## Recovery (Bootloop / Soft-brick)

If your device fails to boot after installation:

1. Boot into custom recovery (e.g., TWRP).  
2. Remove the `Komodo_Props` or `Komodo_beta_Props` folder from `/data/adb/modules/`.  
3. Reboot your device.

## Disclaimer

- Use this at your own risk, it may lead to data loss or system instability.  
- **Strongly recommended to perform a full backup** before proceeding.

## How It Works

The `props` modules in this repository are generated using the configuration logic provided by @0x11DFE.
To ensure full transparency, the original source code has been added to this repository as a Git submodule under the folder `source-code`.

## Credits & Support

- **Configuration Logic by** [@0x11DFE](https://github.com/0x11DFE)
- Issues, bugs, and feature requests: please open them on the repository’s [Issues](https://github.com/Elcapitanoe/Komodo-Build-Prop/issues) page.
