#!/system/bin/busybox sh

# Get the module path from script location
MODPATH="${0%/*}"

# Fallback to current directory if MODPATH is invalid
[ -z "$MODPATH" ] || ! echo "$MODPATH" | grep -q '/data/adb/modules/' &&
  MODPATH="$(dirname "$(readlink -f "$0")")"

# Load utility functions or abort if missing
[ -f "$MODPATH/util_functions.sh" ] && . "$MODPATH/util_functions.sh" || abort "! util_functions.sh not found!"

# Remove GMS Doze bypass settings from XML configuration files
ALLOW_DOZE_PACKAGES="com.google.android.gms"
BLACKLISTED_CONFIGS="allow-in-power-save allow-in-data-usage-save"

ui_print "- Removing Doze/power-save bypass settings from XML files (GMS Doze)"

# Build grep pattern for blacklisted configurations
grep_pattern=$(echo "$BLACKLISTED_CONFIGS" | tr ' ' '|')

# Process all XML files in module directory
find "$MODPATH" -type f -name "*.xml" -print | while IFS= read -r file; do
  for allow_doze_package in $ALLOW_DOZE_PACKAGES; do
    # Check if file contains target package
    if grep -q "package=\"$allow_doze_package\"." "$file"; then
      if grep -Eq "$grep_pattern" "$file"; then
        # Build sed command to remove blacklisted configs
        sed_command=""
        for config in $BLACKLISTED_CONFIGS; do
          if [ -z "$sed_command" ]; then
            sed_command="/$config/d"
          else
            sed_command="$sed_command;/$config/d"
          fi
        done

        # Remove blacklisted configuration lines
        sed -i -e "$sed_command" "$file"

        # Display modification status
        relative_path=$(echo "$file" | sed "s|^$MODPATH/||")
        if [ $? -eq 0 ]; then
          ui_print " - Successfully modified: ./$relative_path"
        else
          ui_print " - Error modifying: ./$relative_path" >&2
        fi
      fi
    fi
  done
done
