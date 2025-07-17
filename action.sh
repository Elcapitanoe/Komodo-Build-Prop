#!/system/bin/busybox sh

# Get the module path from script location
MODPATH="${0%/*}"

# Fallback to current directory if MODPATH is invalid
[ -z "$MODPATH" ] || ! echo "$MODPATH" | grep -q '/data/adb/modules/' &&
  MODPATH="$(dirname "$(readlink -f "$0")")"

# Load utility functions or abort if missing
[ -f "$MODPATH"/util_functions.sh ] && . "$MODPATH"/util_functions.sh || abort "! util_functions.sh not found!"

# Find and read all property files
MODPROP_FILES=$(find_prop_files "$MODPATH/" 1)
SYSPROP_FILES=$(find_prop_files "/" 2)
MODPROP_CONTENT=$(echo "$MODPROP_FILES" | xargs cat)
SYSPROP_CONTENT=$(echo "$SYSPROP_FILES" | xargs cat)

# Build JSON object from property list
build_json() {
  echo '{'
  for PROP in $1; do
    printf "\"%s\": \"%s\",\n" "$PROP" "$(eval "echo \$$PROP")"
  done | sed '$s/,//'
  echo '}'
}

# Clear Google apps data and force stop services
handle_google_apps() {
  GOOGLE_APPS="com.google.android.gsf com.google.android.gms com.google.android.googlequicksearchbox"

  for google_app in $GOOGLE_APPS; do
    su -c am force-stop "$google_app"
    am broadcast -a android.settings.ACTION_BLUETOOTH_PRIVATE_DATA_GRANTED --es package "$google_app" --ei value 0
    am broadcast -a android.settings.ACTION_BLUETOOTH_PRIVATE_DATA_GRANTED --es package "$google_app" --ei value 1
    su -c pm clear "$google_app"
    ui_print " ? Cleanned $google_app"
  done
}

# Generate and update PlayIntegrityFix configuration
PlayIntegrityFix() {
  PIF_MODULE_DIR="/data/adb/modules/playintegrityfix"
  PIF_DIRS="$PIF_MODULE_DIR/pif.json"

  # Validate PlayIntegrityFix module installation and version
  if [[ -z "$PIF_MODULE_DIR" ]] || [[ ! -s "$PIF_MODULE_DIR/module.prop" ]]; then
    abort "PlayIntegrityFix module is missing or is not accessible, Skipping !" false
  elif grep -q "Fork" "$PIF_MODULE_DIR/module.prop"; then
    abort "Detected a Fork version of PlayIntegrityFix, Please install the official version" false
  else
    ui_print " - Detected an official version of PlayIntegrityFix, Proceeding Building PIF.json for official version…"

    # Define properties for PIF.json generation
    PIF_LIST="MODEL MANUFACTURER FINGERPRINT SECURITY_PATCH DEVICE_INITIAL_SDK_INT"

    # Extract property values from module configuration
    MODEL=$(grep_prop "ro.product.model" "$MODPROP_CONTENT")
    MANUFACTURER=$(grep_prop "ro.product.manufacturer" "$MODPROP_CONTENT")
    PRODUCT=$(grep_prop "ro.product.product.name" "$MODPROP_CONTENT")
    FINGERPRINT=$(grep_prop "ro.product.build.fingerprint" "$MODPROP_CONTENT")
    SECURITY_PATCH=$(grep_prop "ro.vendor.build.security_patch" "$MODPROP_CONTENT")
    DEVICE_INITIAL_SDK_INT=$(grep_prop "ro.product.first_api_level" "$SYSPROP_CONTENT")
    [ -z "$DEVICE_INITIAL_SDK_INT" ] && DEVICE_INITIAL_SDK_INT=$(grep_prop "ro.product.build.version.sdk" "$SYSPROP_CONTENT")

    # Set PIF.json output location
    CWD_PIF="$MODPATH"/pif.json
    shift

    # Remove existing PIF file
    [ -f "$CWD_PIF" ] && rm -f "$CWD_PIF"

    update_count=0
    # Handle beta vs stable module builds
    case "$PRODUCT" in
    *beta*)
      ui_print "  - Building PlayIntegrityFix PIF.json from current (BETA) module properties…"

      # Generate JSON from current properties
      build_json "$PIF_LIST" >"$CWD_PIF"
      ;;
    *)
      ui_print "  - Non BETA module detected"
      ui_print "  - Download the PIF.json from GitHub? (chiteroman/PlayIntegrityFix)"

      # Prompt user for PIF.json source preference
      volume_key_event_setval "DOWNLOAD_PIF_GITHUB" true false "ACTION_DOWNLOAD_PIF_GITHUB"

      # Download or build PIF.json based on user choice
      if boolval "$ACTION_DOWNLOAD_PIF_GITHUB"; then
        download_file "https://raw.githubusercontent.com/chiteroman/PlayIntegrityFix/main/module/pif.json" "$CWD_PIF"
      else
        ui_print " - Crawling the latest Google Pixel Beta OTA Releases…"

        # Fetch GSI release information
        download_file https://developer.android.com/topic/generic-system-image/releases DL_GSI_HTML

        # Parse release date from GSI page
        RELEASE_DATE="$(date -D '%B %e, %Y' -d "$(grep -m1 -o 'Date:.*' DL_GSI_HTML | cut -d\  -f2-4)" '+%Y-%m-%d' | head -n1)"

        # Extract release version from GSI page
        RELEASE_VERSION="$(awk '/\(Beta\)/ {flag=1} /versions/ && flag {print; flag=0}' DL_GSI_HTML | sed -n 's/.*\/versions\/\([0-9]*\).*/\1/p' | head -n1)"

        # Extract build IDs from GSI page
        RELEASE_IDS="$(awk '/\(Beta\)/ {flag=1} /Build:/ && flag {print; flag=0}' DL_GSI_HTML | sed -n 's/.*Build: \([A-Z0-9.]*\).*/\1/p')"

        # Display available beta releases
        ui_print "  - Latest Available Beta Releases ($RELEASE_DATE)"

        # Build release selection list
        RELEASE_LIST=""

        # Process each release ID
        for ID in $RELEASE_IDS; do
          # Extract version and incremental for current ID
          RELEASE_VERSION=$(awk -v id="$ID" '$0 ~ id {flag=1} /Android [0-9]+/ && flag {print; flag=0}' DL_GSI_HTML | sed -n 's/.*Android \([0-9]*\).*/\1/p' | head -n1)
          INCREMENTAL=$(grep -o "$ID-[0-9]*-" DL_GSI_HTML | sed "s/$ID-//g" | sed 's/-//g' | head -n1)

          # Format release information
          RELEASE_INFO="A$RELEASE_VERSION-$ID-$INCREMENTAL"

          # Add to release list
          [ -z "$RELEASE_LIST" ] &&
            RELEASE_LIST="$RELEASE_INFO" ||
            RELEASE_LIST="$RELEASE_LIST $RELEASE_INFO"

          # Display release details
          ui_print "   - Android Version: $RELEASE_VERSION ($ID) [$INCREMENTAL]"
        done

        # Let user select release version
        volume_key_event_setoption "RELEASE" "$RELEASE_LIST" "SELECTED_RELEASE"

        # Parse selected release components
        SELECTED_RELEASE_ID=$(echo "$SELECTED_RELEASE" | cut -d- -f2)
        SELECTED_RELEASE_VERSION=$(echo "$SELECTED_RELEASE" | cut -d- -f1 | tr -d 'A')
        SELECTED_RELEASE_INCREMENTAL=$(echo "$SELECTED_RELEASE" | cut -d- -f3)

        # Fetch OTA download page for device selection
        download_file "https://developer.android.com/about/versions/$SELECTED_RELEASE_VERSION/download-ota" DL_OTA_HTML

        # Extract device lists from OTA page
        DEVICE_LIST="$(grep -A1 'tr id=' DL_OTA_HTML | awk -F '[<>"]' '
            /tr id=/ { id = $3 }
            /<td>/ {
                devices = devices ? devices sprintf(",%s (%s)", $3, id) : sprintf("%s (%s)", $3, id)
            }
            END { print devices }
        ')"

        CODENAME_LIST="$(grep -A1 'tr id=' DL_OTA_HTML | awk -F '[<>"]' '
          /tr id=/ {
              codenames = codenames ? codenames "," $3 : $3
          }
          END { print codenames }
      ')"

        # Display available devices
        ui_print "  - Devices Available:"
        echo "$DEVICE_LIST" | tr ',' '\n' | while read -r device; do
          ui_print "   - $device"
        done

        # Let user select device codename
        volume_key_event_setoption "CODENAME" "$(echo "$CODENAME_LIST" | tr ',' ' ')" "SELECTED_CODENAME"

        # Extract model name from selected codename
        SELECTED_MODEL=$(echo "$DEVICE_LIST" | tr ',' '\n' | awk -F'[(,]' -v c="$SELECTED_CODENAME" '$0~c{print $1}')

        # Generate security patch date
        SECURITY_PATCH_DATE="${RELEASE_DATE%-*}"-05

        # Handle Android version naming for newer releases
        SELECTED_RELEASE_VERSION_OR_CODENAME=$([ "$SELECTED_RELEASE_VERSION" -gt 15 ] && echo "Baklava" || echo "$SELECTED_RELEASE_VERSION")

        # Define properties for custom PIF.json
        PIF_LIST="MODEL MANUFACTURER FINGERPRINT SECURITY_PATCH DEVICE_INITIAL_SDK_INT"

        # Set property values for selected device
        MODEL="$SELECTED_MODEL"
        MANUFACTURER="Google"
        FINGERPRINT="google/${SELECTED_CODENAME}_beta/$SELECTED_CODENAME:$SELECTED_RELEASE_VERSION_OR_CODENAME/$SELECTED_RELEASE_ID/$SELECTED_RELEASE_INCREMENTAL:user/release-keys"
        SECURITY_PATCH="$SECURITY_PATCH_DATE"

        # Generate PIF.json with custom properties
        build_json "$PIF_LIST" >"$CWD_PIF"

        # Remove temporary files
        rm -f DL_*_HTML
      fi
      ;;
    esac

    # Update PIF configuration files if changes detected
    for PIF_DIR in $PIF_DIRS; do
      # Check if generated PIF file is valid
      if [ ! -s "$CWD_PIF" ]; then
        ui_print "  ! Built PIF file does not exist or is empty."
      elif [ ! -s "$PIF_DIR" ]; then
        update_count=$((update_count + 1))

        # Create new PIF configuration
        cp "$CWD_PIF" "$PIF_DIR"
        ui_print "  ++ Config file has been created at \"$PIF_DIR\"."
      elif ! cmp -s "$CWD_PIF" "$PIF_DIR"; then
        update_count=$((update_count + 1))

        # Backup existing and update PIF configuration
        mv "$PIF_DIR" "${PIF_DIR}.old" 2>/dev/null
        cp "$CWD_PIF" "$PIF_DIR"
        ui_print "  ++ Config file has been updated and saved to \"$PIF_DIR\"."
      else
        ui_print "  - No changes detected in \"$PIF_DIR\"."
      fi
    done

    # Display post-installation instructions if PIF was updated
    if [ $update_count -gt 0 ]; then
      ui_print "***************************************"
      ui_print "  ? Please disconnect your device from your Google account: https://myaccount.google.com/device-activity"
      ui_print "  ? Clean the data from Google system apps such as GMS, GSF, and Google apps."
      ui_print "  ? Then restart and make sure to reconnect to your device, Make sure if your device is logged as \"$MODEL\"."
      ui_print "  ? More info: https://t.me/PixelProps/157"
      ui_print "***************************************"
    fi
  fi
}

# Generate and update TrickyStore target configuration
TrickyStoreTarget() {
  # Verify TrickyStore installation
  if [ -d "/data/adb/tricky_store" ]; then
    ui_print " - Building TrickyStore (target.txt) packages…"

    # Set TrickyStore target file path
    TARGET_DIR="/data/adb/tricky_store/target.txt"

    # Set local target file path
    CWD_TARGET="$MODPATH"/target.txt
    shift

    # Remove existing target file
    [ -f "$CWD_TARGET" ] && rm -f "$CWD_TARGET"

    # Get list of installed packages
    PACKAGES=$(pm list packages | sed 's/package://g')

    # Define packages requiring special handling
    SPECIAL_PACKAGES="com.google.android.gms com.google.android.gsf com.android.vending"

    # Handle broken TEE (Trusted Execution Environment)
    if grep -qE "^teeBroken=(true|1)$" /data/adb/tricky_store/tee_status; then
      ui_print "  ! Hardware Attestation support not available (teeBroken=true)"
      ui_print "  ! Fallback to Broken TEE Support mode (!)"
      # Mark all packages for broken TEE mode
      PACKAGES=$(echo "$PACKAGES" | sed 's/$/!/g')
    else
      # Mark only special packages when TEE is working
      for pkg in $SPECIAL_PACKAGES; do
        PACKAGES=$(echo "$PACKAGES" | sed "s/^${pkg}$/${pkg}!/g")
      done
    fi

    # Write package list to target file
    echo "$PACKAGES" >"$CWD_TARGET"

    # Update TrickyStore configuration if changes detected
    if [ ! -s "$CWD_TARGET" ]; then
      ui_print "  ! Built target file does not exist or is empty."
    elif [ ! -s "$TARGET_DIR" ]; then
      # Create new target configuration
      cp "$CWD_TARGET" "$TARGET_DIR"
      ui_print "  ++ Target file has been created at \"$TARGET_DIR\"."
    elif ! cmp -s "$CWD_TARGET" "$TARGET_DIR"; then
      # Backup existing and update target configuration
      mv "$TARGET_DIR" "${TARGET_DIR}.old" 2>/dev/null
      cp "$CWD_TARGET" "$TARGET_DIR"
      ui_print "  ++ Target file has been updated and saved to \"$TARGET_DIR\"."
    else
      ui_print "  - No changes detected in \"$TARGET_DIR\"."
    fi
  fi
}

ui_print "- Building configuration file for PlayIntegrityFix & TrickyStore"

# Execute configuration builders
PlayIntegrityFix
TrickyStoreTarget

# Wait before exit to allow user to read output
sleep 5 && exit 0
