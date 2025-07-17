#!/system/bin/sh

# Get module path and name from script location
MODPATH="${0%/*}"
MODNAME="${MODPATH##*/}"
MAGISKTMP="$(magisk --path)" || MAGISKTMP=/sbin

# Disable module if Magisk/KernelSU version is too old
if [ "$(magisk -V)" -lt 26302 ] || [ "$(/data/adb/ksud -V)" -lt 10818 ]; then
  touch "$MODPATH/disable"
fi

# Load utility functions or abort if missing
[ -f "$MODPATH/util_functions.sh" ] && . "$MODPATH/util_functions.sh" || abort "! util_functions.sh not found!"

# Skip if sensitive_props module is already installed
if [ -d "/data/adb/modules/sensitive_props" ]; then
  abort "Sensitive Props module is already present, Skipping !" false
else
  # Configure Magisk DenyList for Play Services
  if magisk --denylist status; then
    magisk --denylist rm com.google.android.gms
  else
    # Add to DenyList if Shamiko is installed without whitelist
    if [ -d "/data/adb/modules/zygisk_shamiko" ] && [ ! -f "/data/adb/shamiko/whitelist" ]; then
      magisk --denylist add com.google.android.gms com.google.android.gms.unstable
    fi
  fi

  # Set verified boot hash if available
  BOOT_HASH_FILE="/data/adb/boot.hash"
  if [ -s "$BOOT_HASH_FILE" ]; then
    resetprop -v -n ro.boot.vbmeta.digest "$(tr '[:upper:]' '[:lower:]' <"$BOOT_HASH_FILE")"
  fi

  # Clean AOSP and test-keys references from properties
  for prop in $(getprop | grep -E "aosp_|test-keys" | cut -d ":" -f 1 | tr -d '[]'); do
    replace_value_resetprop "$prop" "aosp_" ""
    replace_value_resetprop "$prop" "test-keys" "release-keys"
  done

  # Apply build property fixes across all partitions
  for prefix in system vendor system_ext product oem odm vendor_dlkm odm_dlkm bootimage; do
    # Set secure build properties
    check_resetprop "ro.${prefix}.build.tags" release-keys
    check_resetprop "ro.${prefix}.build.type" user

    # Clean AOSP references from build properties
    for prop in ro.${prefix}.build.description ro.${prefix}.build.fingerprint ro.product.${prefix}.name; do
      replace_value_resetprop "$prop" "aosp_" ""
    done
  done
fi
