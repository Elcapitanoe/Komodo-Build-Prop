#!/system/bin/sh

# Define PlayIntegrityFix configuration paths
PIF_DIRS="/data/adb/modules/playintegrityfix/pif.json"

# Restore PlayIntegrityFix configuration if module exists
if [ -d "/data/adb/modules/playintegrityfix" ]; then
  # Process each PIF configuration file
  for PIF_DIR in $PIF_DIRS; do
    # Restore backup if available
    [ -f "${PIF_DIR}.old" ] && mv "${PIF_DIR}.old" "$PIF_DIR"

    # Download default PIF configuration if missing
    if [ ! -f "$PIF_DIR" ]; then
      ui_print " -+ Missing $PIF_DIR, Downloading stable one for you."
      wget -O -q --show-progress "$PIF_DIR" "https://raw.githubusercontent.com/chiteroman/PlayIntegrityFix/main/module/pif.json"
    fi
  done
fi

# Restore default permissions for recovery scripts
find /vendor/bin /system/bin -name install-recovery.sh -exec chmod 755 {} \;

# Restore default permissions for sensitive files and directories
chmod 644 /proc/cmdline
chmod 644 /proc/net/unix
chmod 755 /system/addon.d
chmod 755 /sdcard/TWRP
