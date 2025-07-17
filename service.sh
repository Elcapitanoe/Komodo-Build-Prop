#!/system/bin/busybox sh

# Get the module path from script location
MODPATH="${0%/*}"

# Fallback to current directory if MODPATH is invalid
[ -z "$MODPATH" ] || ! echo "$MODPATH" | grep -q '/data/adb/modules/' &&
  MODPATH="$(dirname "$(readlink -f "$0")")"

# Load utility functions or abort if missing
[ -f "$MODPATH/util_functions.sh" ] && . "$MODPATH/util_functions.sh" || abort "! util_functions.sh not found!"

# Wait for system boot to complete
while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done

# Wait for device decryption after first unlock
until [ -d "/sdcard/Android" ]; do sleep 3; done

# Validate and set module property configuration paths
for prop_file in "system.prop" "config.prop"; do
  prop_path="$MODPATH/$prop_file"
  prop_key_upper=$(echo "${prop_file%%.*}" | tr '[:lower:]' '[:upper:]')

  # Ensure property files exist and are writable
  [ ! -f "$prop_path" ] || [ ! -w "$prop_path" ] && abort " ! $prop_file not found or not writable !"

  # Create dynamic variable for property file paths
  eval "MODPATH_${prop_key_upper}_PROP=\$prop_path"
done

# Find and read all property files
MODPROP_FILES=$(find_prop_files "$MODPATH/" 1)
SYSPROP_FILES=$(find_prop_files "/" 3)
MODPROP_CONTENT=$(echo "$MODPROP_FILES" | xargs cat)
SYSPROP_CONTENT=$(echo "$SYSPROP_FILES" | xargs cat)

# Generic property management function
manage_prop() {
  local action=$1 prop_name=$2 mod_prop_val=$3 mod_prop_key=$4
  ui_print " - $prop_name=$mod_prop_val, ${action}ing property…"

  # Build sed command for comment/uncomment operations
  local comment_cmd="s/^${mod_prop_key}/# ${mod_prop_key}/"
  local uncomment_cmd="s/^# ${mod_prop_key}/${mod_prop_key}/"
  eval "local sed_cmd=\$${action}_cmd"

  sed -i "$sed_cmd" "$MODPATH_SYSTEM_PROP" ||
    ui_print " ! Warning: Failed to $action property $mod_prop_key"
}

# Comment out a property in system.prop
comment_prop() { manage_prop "comment" "$@"; }

# Uncomment a property in system.prop
uncomment_prop() { manage_prop "uncomment" "$@"; }

# Check property values and update based on comparison
check_and_update_prop() {
  local sys_prop_key=$1 mod_prop_key=$2 prop_name=$3 comparison=$4

  # Extract property values from system and module
  sys_prop=$(grep_prop "$sys_prop_key" "$SYSPROP_CONTENT")
  mod_prop=$(grep_prop "$mod_prop_key" "$MODPROP_CONTENT")

  # Skip if module property is missing
  [ -z "$mod_prop" ] && {
    ui_print " - $prop_name is missing in either system or module props, skipping…"
    return
  }

  local result
  # Perform comparison based on specified operator
  case "$comparison" in
  eq) [ "$sys_prop" = "$mod_prop" ] && result=0 ;;
  ne) [ "$sys_prop" != "$mod_prop" ] && result=0 ;;
  lt) [ "$sys_prop" -lt "$mod_prop" ] 2>/dev/null && result=0 ;;
  le) [ "$sys_prop" -le "$mod_prop" ] 2>/dev/null && result=0 ;;
  gt) [ "$sys_prop" -gt "$mod_prop" ] 2>/dev/null && result=0 ;;
  ge) [ "$sys_prop" -ge "$mod_prop" ] 2>/dev/null && result=0 ;;
  esac

  # Apply property changes based on comparison result
  [ "$result" = 0 ] &&
    comment_prop "$prop_name" "$mod_prop" "$mod_prop_key" ||
    uncomment_prop "$prop_name" "$mod_prop" "$mod_prop_key"
}

# Initialize sensitive property configuration
init_config() {
  local prop_keys="device security_patch soc sdk props pihooks"

  # Process each sensitive property configuration
  for prop_key in $prop_keys; do
    prop_val=$(grep_prop "pixelprops.sensitive.$prop_key" "$MODPROP_CONTENT")
    prop_key_upper=$(echo "$prop_key" | tr '[:lower:]' '[:upper:]')
    eval "SAFE_$prop_key_upper=\${prop_val:-true}"

    # Prompt user for missing configuration values
    [ -z "$prop_val" ] && {
      ui_print " - Sensitive config property not found for $prop_key_upper, requesting user input…"
      volume_key_event_setval "SAFE_$prop_key_upper" true false "SAFE_$prop_key_upper"

      # Save user choice to config file
      var_name="SAFE_$prop_key_upper"
      eval "prop_value=\$$var_name"
      echo "pixelprops.sensitive.$prop_key=$prop_value" >>"$MODPATH_CONFIG_PROP"
    }
  done
}

# Apply sensitive property checks for module properties
mod_sensitive_checks() {
  ui_print "- Running Sensitive MODPROP checks…"

  # Define property check mappings
  function_map=$(
    cat <<EOF
DEVICE:device:ne
SECURITY_PATCH:security_patch:ne
SOC:soc:ne
SDK:sdk:lt
EOF
  )

  # Process each property check configuration
  echo "$function_map" | while IFS=: read -r safe_var prop_type comparison; do
    eval "local safe_val=\$SAFE_$safe_var"

    # Skip checks if safe mode is disabled
    if ! boolval "$safe_val"; then
      ui_print " - Safe Mode was manually disabled for \"SAFE_$safe_var\" !"
    else
      # Apply property checks based on type
      case "$prop_type" in
      device)
        check_and_update_prop "ro.product.product.device" "ro.product.device" "PRODUCT_DEVICE" "$comparison"
        check_and_update_prop "ro.product.vendor.device" "ro.product.vendor.device" "VENDOR_DEVICE" "$comparison"
        ;;
      security_patch)
        check_and_update_prop "ro.vendor.build.security_patch" "ro.vendor.build.security_patch" "VENDOR_SECURITY_PATCH" "$comparison"
        check_and_update_prop "ro.build.version.security_patch" "ro.build.version.security_patch" "BUILD_SECURITY_PATCH" "$comparison"
        ;;
      soc)
        check_and_update_prop "ro.soc.model" "ro.soc.model" "SOC_MODEL" "$comparison"
        check_and_update_prop "ro.soc.manufacturer" "ro.soc.manufacturer" "SOC_MANUFACTURER" "$comparison"
        ;;
      sdk)
        # Check first API level
        check_and_update_prop "ro.product.first_api_level" "ro.product.first_api_level" "FIRST_API_LEVEL" "$comparison"

        # Check all build version properties across partitions
        local prefixes="build product vendor vendor_dlkm system system_ext system_dlkm"
        local versions="sdk incremental release release_or_codename"

        for prefix in $prefixes; do
          for version in $versions; do
            prefix_upper=$(echo "$prefix" | tr '[:lower:]' '[:upper:]')
            version_upper=$(echo "$version" | tr '[:lower:]' '[:upper:]')

            # Build property name based on prefix
            [ "$prefix" = "build" ] &&
              prop_name="ro.${prefix}.version.${version}" ||
              prop_name="ro.${prefix}.build.version.${version}"

            check_and_update_prop "$prop_name" "$prop_name" "${prefix_upper}_BUILD_$version_upper" "$comparison"
          done
        done
        ;;
      esac
    fi
  done
}

# Apply sensitive property checks for system properties
sys_sensitive_checks() {
  # Skip if sensitive_props module is already installed
  if [ -d "/data/adb/modules/sensitive_props" ]; then
    abort "Sensitive Props module is already present, Skipping !" false
  else
    ui_print "- Running Sensitive SYSPROP checks…"

    # Continuously remove custom ROM properties in background
    while true; do
      hexpatch_deleteprop "LSPosed" \
        "marketname" "custom.device" "modversion" \
        "lineage" "aospa" "pixelexperience" "evolution" "pixelos" "pixelage" "crdroid" "crDroid" "aospa" \
        "aicp" "arter97" "blu_spark" "cyanogenmod" "deathly" "elementalx" "elite" "franco" "hadeskernel" \
        "morokernel" "noble" "optimus" "slimroms" "sultan" "aokp" "bharos" "calyxos" "calyxOS" "divestos" \
        "emteria.os" "grapheneos" "indus" "iodéos" "kali" "nethunter" "omnirom" "paranoid" "replicant" \
        "resurrection" "rising" "remix" "shift" "volla" "icosa" "kirisakura" "infinity" "Infinity"

      # Wait one hour before next cleanup cycle
      sleep 3600
    done &

    # Clean custom ROM references from display properties
    replace_value_resetprop ro.build.flavor "lineage_" ""
    replace_value_resetprop ro.build.flavor "userdebug" "user"
    replace_value_resetprop ro.build.display.id "lineage_" ""
    replace_value_resetprop ro.build.display.id "userdebug" "user"
    replace_value_resetprop ro.build.display.id "dev-keys" "release-keys"
    replace_value_resetprop vendor.camera.aux.packagelist "lineageos." ""
    replace_value_resetprop ro.build.version.incremental "eng." ""

    # Fix Realme device fingerprint verification
    check_resetprop ro.boot.flash.locked 1
    check_resetprop ro.boot.realme.lockstate 1
    check_resetprop ro.boot.realmebootstate green

    # Fix Oppo device fingerprint verification
    check_resetprop ro.boot.vbmeta.device_state locked
    check_resetprop vendor.boot.vbmeta.device_state locked

    # Fix OnePlus device verification
    check_resetprop ro.is_ever_orange 0
    check_resetprop vendor.boot.verifiedbootstate green

    # Fix OnePlus/Oppo verification for newer firmware
    check_resetprop ro.boot.veritymode enforcing
    check_resetprop ro.boot.verifiedbootstate green

    # Fix Samsung warranty bit for verification
    for prop in ro.boot.warranty_bit ro.warranty_bit ro.vendor.boot.warranty_bit ro.vendor.warranty_bit; do
      check_resetprop "$prop" 0
    done

    # Apply general build property fixes across all partitions
    for prefix in bootimage odm odm_dlkm oem product system system_ext vendor vendor_dlkm; do
      check_resetprop ro.${prefix}.build.type user
      check_resetprop ro.${prefix}.keys release-keys
      check_resetprop ro.${prefix}.build.tags release-keys

      # Clean engineering build references
      replace_value_resetprop ro.${prefix}.build.version.incremental "eng." ""
    done

    # Reset recovery mode properties to normal values
    for prop in ro.bootmode ro.boot.bootmode ro.boot.mode vendor.bootmode vendor.boot.bootmode vendor.boot.mode; do
      maybe_resetprop "$prop" recovery unknown
    done

    # Fix MIUI cross-region flash properties
    for prop in ro.boot.hwc ro.boot.hwcountry; do
      maybe_resetprop "$prop" CN GLOBAL
    done

    # Set properties for banking app compatibility
    check_resetprop sys.oem_unlock_allowed 0
    check_resetprop ro.oem_unlock_supported 0
    check_resetprop net.tethering.noprovisioning true

    # Disable recovery service
    check_resetprop init.svc.flash_recovery stopped

    # Set encryption status for verification
    check_resetprop ro.crypto.state encrypted

    # Configure secure boot properties
    check_resetprop ro.secure 1
    check_resetprop ro.secureboot.devicelock 1
    check_resetprop ro.secureboot.lockstate locked

    # Disable debugging features for security
    check_resetprop ro.force.debuggable 0
    check_resetprop ro.debuggable 0
    check_resetprop ro.adb.secure 1

    # Remove hidden API policy restrictions
    for global_setting in hidden_api_policy hidden_api_policy_pre_p_apps hidden_api_policy_p_apps; do
      settings delete global "$global_setting" >/dev/null 2>&1
    done

    # Configure touch security settings
    for namespace in global system secure; do
      settings put "$namespace" "block_untrusted_touches" 0 >/dev/null 2>&1
    done

    # Hide SELinux status by restricting file permissions
    [ -f /sys/fs/selinux/enforce ] && [ "$(toybox cat /sys/fs/selinux/enforce)" == "0" ] && {
      set_permissions /sys/fs/selinux/enforce 640
      set_permissions /sys/fs/selinux/policy 440
    }

    # Restrict recovery script permissions
    find /vendor/bin /system/bin -name install-recovery.sh | while read -r file; do
      set_permissions "$file" 440
    done

    # Restrict permissions on sensitive files and directories
    set_permissions /proc/cmdline 440
    set_permissions /proc/net/unix 440
    set_permissions /system/addon.d 750
    set_permissions /sdcard/TWRP 750
  fi
}

# Configure PIHooks properties for internal spoofing
sys_sensitive_pihooks_checks() {
  # Find existing PIHooks properties
  pihook_props=$(getprop | grep 'pihooks' | cut -d ':' -f 1 | tr -d '[]')
  PIF_MODULE_DIR="/data/adb/modules/playintegrityfix"
  use_pihooks=1

  # Disable PIHooks if PlayIntegrityFix is installed
  if [[ -d "$PIF_MODULE_DIR" ]] && [[ -s "$PIF_MODULE_DIR/module.prop" ]]; then
    use_pihooks=0
    ui_print "- PlayIntegrityFix module detected, Disabling PIHOOKS spoofing…"
  fi

  # Handle PIHooks configuration
  if [ -z "$pihook_props" ]; then
    ui_print "- No pihooks properties found (internal spoofing)"
    ui_print " ! Use PlayIntegrityFix instead ?"
  else
    ui_print "- Running Sensitive PIHOOKS checks (internal spoofing)…"

    # Extract property values for PIHooks spoofing
    BRAND=$(grep_prop "ro.product.brand" "$MODPROP_CONTENT")
    MODEL=$(grep_prop "ro.product.model" "$MODPROP_CONTENT")
    DEVICE=$(grep_prop "ro.product.device" "$MODPROP_CONTENT")
    MANUFACTURER=$(grep_prop "ro.product.manufacturer" "$MODPROP_CONTENT")
    PRODUCT=$(grep_prop "ro.product.product.name" "$MODPROP_CONTENT")
    FINGERPRINT=$(grep_prop "ro.product.build.fingerprint" "$MODPROP_CONTENT")
    SECURITY_PATCH=$(grep_prop "ro.vendor.build.security_patch" "$MODPROP_CONTENT")
    DEVICE_INITIAL_SDK_INT=$(grep_prop "ro.product.first_api_level" "$SYSPROP_CONTENT")
    [ -z "$DEVICE_INITIAL_SDK_INT" ] && DEVICE_INITIAL_SDK_INT=$(grep_prop "ro.product.build.version.sdk" "$SYSPROP_CONTENT")
    BUILD_ID=$(grep_prop "ro.product.build.id" "$MODPROP_CONTENT")
    BUILD_TAGS=$(grep_prop "ro.product.build.tags" "$MODPROP_CONTENT")
    BUILD_TYPE=$(grep_prop "ro.product.build.type" "$MODPROP_CONTENT")

    update_ph_count=0
    # Define essential properties for integrity verification
    essential_props="model manufacturer product fingerprint security_patch initial_sdk"
    
    # Count total essential properties
    total_essential_props=$(echo "$essential_props" | wc -w)

    # Configure PIHooks string properties
    for prop in $pihook_props; do
      prop_value=$(getprop "$prop")
      prop_lower=$(echo "$prop" | tr '[:upper:]' '[:lower:]')
      final_value=""

      # Process non-boolean properties
      if ! is_bool "$prop_value"; then
        # Map property names to values
        case "$prop_lower" in
        *"brand"*) final_value="$BRAND" ;;
        *"model"*) final_value="$MODEL" ;;
        *"device"*) final_value="$DEVICE" ;;
        *"manufacturer"*) final_value="$MANUFACTURER" ;;
        *"product"*) final_value="$PRODUCT" ;;
        *"fingerprint"*) final_value="$FINGERPRINT" ;;
        *"security_patch"*) final_value="$SECURITY_PATCH" ;;
        *"first_api"* | *"initial_sdk"*) final_value="$DEVICE_INITIAL_SDK_INT" ;;
        *"id"*) final_value="$BUILD_ID" ;;
        *"tags"*) final_value="$BUILD_TAGS" ;;
        *"type"*) final_value="$BUILD_TYPE" ;;
        esac

        # Track essential properties that are set
        for essential_prop in $essential_props; do
          if [[ "$prop_lower" == *"$essential_prop"* && -n "$final_value" ]]; then
            essential_props_set=$((essential_props_set + 1))
            break
          fi
        done

        # Apply property value
        check_resetprop "$prop" "$final_value"
        ui_print " ? Property $prop set to \"$final_value\""
      fi

      # Count successful property updates
      [ -n "$final_value" ] && update_ph_count=$((update_ph_count + 1))
    done

    # Warn if essential properties are missing
    if [ "$essential_props_set" -lt "$total_essential_props" ]; then
      ui_print "***************************************"
      ui_print " ! Warning: Not all essential properties for PIF-less spoofing are set. This means that relying solely on PIHooks for spoofing might not be approriate. We recommend using PlayIntegrityFix instead, as it provides more comprehensive spoofing capabilities. As a result, relevant PIHooks features will be disabled."
      ui_print "***************************************"
    fi

    # Configure PIHooks boolean properties
    for prop in $pihook_props; do
      prop_value=$(getprop "$prop")
      prop_lower=$(echo "$prop" | tr '[:upper:]' '[:lower:]')
      final_value="0"

      # Process boolean properties
      if is_bool "$prop_value"; then
        # Enable if all essential properties are set
        boolval "$use_pihooks" && [ "$essential_props_set" -ge "$total_essential_props" ] && final_value="1"

        # Handle disable properties with inverted logic
        if [[ "$prop_lower" == *"disable"* ]] &&
          [[ ! "$prop_lower" == *"game"* ]] &&
          [[ ! "$prop_lower" == *"photo"* ]] &&
          [[ ! "$prop_lower" == *"netflix"* ]]; then
          final_value="1"
          boolval "$use_pihooks" && [ "$essential_props_set" -ge "$total_essential_props" ] && final_value="0"
        fi

        # Apply boolean property value
        check_resetprop "$prop" "$final_value"
        ui_print " ? Property $prop set to \"$final_value\" ($(boolval "$final_value" && echo enabled || echo disabled))"
      fi
    done
  fi
}

# Execute all configuration and checks
init_config
mod_sensitive_checks
boolval "$SAFE_PROPS" && sys_sensitive_checks
boolval "$SAFE_PIHOOKS" && sys_sensitive_pihooks_checks
