<div align="center">

# Komodo Pixel Props
**Seamlessly spoof your device identity as a Pixel 9 Pro XL (`komodo`).**

<br> <img src="https://img.shields.io/github/downloads/Elcapitanoe/Komodo-Build-Prop/total?style=flat-square&color=7490ac&label=Downloads" alt="Total downloads">
<img src="https://img.shields.io/github/v/release/Elcapitanoe/Komodo-Build-Prop?style=flat-square&color=7490ac&label=Latest%20Stable" alt="Latest release version">
<img src="https://img.shields.io/github/release-date/Elcapitanoe/Komodo-Build-Prop?style=flat-square&color=7490ac&label=Release%20Date&display_date=published_at" alt="Last release date">
<img src="https://img.shields.io/github/last-commit/Elcapitanoe/Komodo-Build-Prop/main?style=flat-square&color=7490ac&label=Last%20Commit" alt="Last commit">

</div>

---

## Prerequisites

Before flashing, ensure your environment meets the following criteria:

-   **Root Access:** Magisk (v24+) or KernelSU.
-   **Recovery:** A custom recovery (TWRP/OFRP) is recommended for emergency backups.

## Installation Guide

1.  **Download:** Grab the latest `.zip` from [GitHub Releases](https://github.com/Elcapitanoe/Komodo-Build-Prop/releases) or the [Official Website](https://prop.domiadi.com).
2.  **Flash:** Open your root manager (Magisk/KernelSU), navigate to **Modules**, and select **Install from storage**.
3.  **Configure:** The installer script uses hardware keys for selection:
    -   `Volume Up (+)` : **Confirm / Yes**
    -   `Volume Down (-)` : **Decline / No**
4.  **Apply:** Once installation is complete, **Reboot** your device to apply changes.

## Troubleshooting (Bootloop Rescue)

If your device hangs at boot or encounters a "soft brick" after installation:

1.  Boot into **Custom Recovery** (TWRP/OrangeFox).
2.  Launch the **File Manager**.
3.  Navigate to: `/data/adb/modules/`
4.  Delete the folder: `Komodo_Props` (or `Komodo_beta_Props`).
5.  Reboot System.

## Credits & Support

-   **Core Logic:** [@0x11DFE](https://github.com/0x11DFE)
-   **Feedback:** Found a bug? Open a ticket on the [Issues Page](https://github.com/Elcapitanoe/Komodo-Build-Prop/issues).
