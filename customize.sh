#!/system/bin/busybox sh

# Find build and system property files in specified directory
find_prop_files() {
    dir="$1"
    maxdepth="$2"
    maxdepth=${maxdepth:-3}

    find "$dir" -maxdepth "$maxdepth" -type f \( -name 'build.prop' -o -name 'system.prop' \) -print 2>/dev/null
}

# Extract property value from file content
grep_prop() {
    PROP="$1"
    shift
    FILES_or_VAR="$@"

    if [ -n "$FILES_or_VAR" ]; then
        echo "$FILES_or_VAR" | grep -m1 "^$PROP=" 2>/dev/null | cut -d= -f2- | head -n 1
    fi
}

# Verify SHA256 checksums for all shell scripts and binaries
checksum_sha256() {
    for file in "$MODPATH"/*.sh "$MODPATH"/META-INF/com/google/android/update-binary "$MODPATH"/META-INF/com/google/android/updater-script; do
        if [ -f "$file" ]; then
            sha256_file="$file.sha256"

            if [ -s "$sha256_file" ]; then
                expected_hash=$(cat "$sha256_file")
                actual_hash=$(sha256sum "$file" | awk '{print $1}')

                if [ "$expected_hash" != "$actual_hash" ]; then
                    ui_print "***************************************"
                    ui_print " ! Warning: SHA256 mismatch for $file !"
                    ui_print " ! Expected: $expected_hash !"
                    ui_print " ! Actual:   $actual_hash !"
                    abort "***************************************"
                fi
            else
                ui_print " ! Warning: SHA256 file not found or empty for $file"
            fi
        fi
    done
}

# Ensure module won't be removed during installation
[ -f "$MODPATH/remove" ] && rm -f "$MODPATH/remove"

# Add root manager binary paths to PATH if busybox is missing
if ! command -v busybox >/dev/null 2>&1; then
    TOYS_PATH=$(find "/data/adb" -maxdepth 3 \( -name busybox -o -name ksu_susfs \) -exec dirname {} \; | sort -u | tr '\n' ':')
    export PATH="${PATH:+${PATH}:}${TOYS_PATH%:}"
fi

# Find and read all property files
MODPROP_FILES=$(find_prop_files "$MODPATH/" 1)
SYSPROP_FILES=$(find_prop_files "/" 2)

# Load property file contents into variables
MODPROP_CONTENT=$(echo "$MODPROP_FILES" | xargs cat)
SYSPROP_CONTENT=$(echo "$SYSPROP_FILES" | xargs cat)

# Extract key module properties for display
MODPROP_MODEL=$(grep_prop "ro.product.vendor.model" "$MODPROP_CONTENT")
MODPROP_PRODUCT=$(grep_prop "ro.product.vendor.name" "$MODPROP_CONTENT" | tr '[:lower:]' '[:upper:]')
MODPROP_VERSION=$(grep_prop "ro.build.version.release" "$MODPROP_CONTENT")
MODPROP_SECURITYPATCH=$(grep_prop "ro.build.version.security_patch" "$MODPROP_CONTENT")
MODPROP_SDK=$(grep_prop "ro.build.version.sdk" "$MODPROP_CONTENT")
MODPROP_VERSIONCODE=$(date -d "$MODPROP_SECURITYPATCH" '+%y%m%d')
MODPROP_MONTH=$(date -d "$MODPROP_SECURITYPATCH" '+%B')
MODPROP_YEAR=$(date -d "$MODPROP_SECURITYPATCH" '+%Y')

# Extract system SDK version for compatibility check
SYSPROP_SDK=$(grep_prop "ro.build.version.sdk" "$SYSPROP_CONTENT")

# Prevent installation from recovery mode
if ! $BOOTMODE; then
    ui_print "****************************************************"
    ui_print " ! Install from Recovery is NOT supported !"
    ui_print " ! Please install from Magisk / KernelSU / APatch !"
    ui_print " ! Recovery sucks !"
    abort "****************************************************"
fi

# Warn about potential compatibility issues
if [ "$SYSPROP_SDK" -lt "$MODPROP_SDK" ]; then
    ui_print "*************************************"
    ui_print " ! YOUR SYSTEM MIGHT SOFT-BRICK !"
    ui_print " ! SYSTEM SDK: $SYSPROP_SDK !"
    ui_print " ! MODULE SDK: $MODPROP_SDK !"
    ui_print " ! SENSITIVE/SAFE MODE RECOMMENDED !"
    ui_print "*************************************"
fi

# Display installation information
ui_print "- Installing, $MODPROP_MODEL ($MODPROP_PRODUCT) [A$MODPROP_VERSION-SP$MODPROP_VERSIONCODE] - $MODPROP_MONTH $MODPROP_YEAR"

# Verify file integrity
checksum_sha256

# Execute configuration scripts during installation
[ -f "$MODPATH/action.sh" ] && busybox sh "$MODPATH"/action.sh 2>&1

# Execute service script during installation
[ -f "$MODPATH/service.sh" ] && busybox sh "$MODPATH"/service.sh 2>&1

# Display completion message with credits
ui_print "- Script by Tesla, Telegram: @T3SL4 | t.me/PixelProps"
