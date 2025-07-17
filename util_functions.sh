#!/system/bin/busybox sh

# Get the module path from script location
MODPATH="${0%/*}"

# Fallback to current directory if MODPATH is invalid
[ -z "$MODPATH" ] || ! echo "$MODPATH" | grep -q '/data/adb/modules/' &&
  MODPATH="$(dirname "$(readlink -f "$0")")"

# Normalize boolean values and return exit code
boolval() {
  case "$(printf "%s" "${1:-}" | tr '[:upper:]' '[:lower:]')" in
  1 | true | on | enabled) return 0 ;;
  0 | false | off | disabled) return 1 ;;
  *) return 1 ;;
  esac
}

# Check if value is a valid boolean
is_bool() {
  case "$(printf "%s" "${1:-}" | tr '[:upper:]' '[:lower:]')" in
  1 | true | on | enabled | 0 | false | off | disabled) return 0 ;;
  *) return 1 ;;
  esac
}

# Print message to user interface
ui_print() { echo "$1"; }

# Abort script execution with error message
abort() {
  message="$1"
  remove_module="${2:-true}"

  ui_print " [!] $message"

  # Mark module for removal on next reboot
  if boolval "$remove_module"; then
    touch "$MODPATH/remove"
    ui_print " ! The module will be removed on next reboot !"
    ui_print ""
    sleep 5
    exit 1
  fi

  sleep 5
  return 1
}

# Find all property files in specified directory
find_prop_files() {
  dir="$1"
  maxdepth="$2"
  maxdepth=${maxdepth:-3}

  find "$dir" -maxdepth "$maxdepth" -type f -name '*.prop' -print 2>/dev/null
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

# Set file permissions safely without errors
set_permissions() {
  [ -e "$1" ] && chmod "$2" "$1" &>/dev/null
}

# Build resetprop arguments based on property name
_build_resetprop_args() {
  prop_name="$1"
  shift

  case "$prop_name" in
  persist.*) set -- -p -v "$prop_name" ;;
  *) set -- -n -v "$prop_name" ;;
  esac
  echo "$@"
}

# Reset property if it exists
exist_resetprop() {
  getprop "$1" | grep -q '.' && resetprop $(_build_resetprop_args "$1") ""
}

# Reset property if value doesn't match desired value
check_resetprop() {
  VALUE="$(resetprop -v "$1")"
  [ -n "$VALUE" ] && [ "$VALUE" != "$2" ] && resetprop $(_build_resetprop_args "$1") "$2"
}

# Reset property if it matches specified pattern
maybe_resetprop() {
  VALUE="$(resetprop -v "$1")"
  [ -n "$VALUE" ] && echo "$VALUE" | grep -q "$2" && resetprop $(_build_resetprop_args "$1") "$3"
}

# Replace substring in property value
replace_value_resetprop() {
  VALUE="$(resetprop -v "$1")"
  [ -z "$VALUE" ] && return
  VALUE_NEW="$(echo -n "$VALUE" | sed "s|${2}|${3}|g")"
  [ "$VALUE" == "$VALUE_NEW" ] || resetprop $(_build_resetprop_args "$1") "$VALUE_NEW"
}

# Obfuscate property strings by replacing with random hex values
hexpatch_deleteprop() {
  # Locate magiskboot binary
  magiskboot_path=$(which magiskboot 2>/dev/null || find /data/adb /data/data/me.bmax.apatch/patch/ -name magiskboot -print -quit 2>/dev/null)
  [ -z "$magiskboot_path" ] && abort "magiskboot not found" false

  # Process each search string
  for search_string in "$@"; do
    # Convert search string to uppercase hex
    search_hex=$(echo -n "$search_string" | xxd -p | tr '[:lower:]' '[:upper:]')

    # Generate random replacement string of same length
    replacement_string=$(cat /dev/urandom | tr -dc '0-9a-f' | head -c ${#search_string})

    # Convert replacement to uppercase hex
    replacement_hex=$(echo -n "$replacement_string" | xxd -p | tr '[:lower:]' '[:upper:]')

    # Find and patch properties containing search string
    getprop | cut -d'[' -f2 | cut -d']' -f1 | grep "$search_string" | while read prop_name; do
      resetprop -Z "$prop_name" | cut -d' ' -f2 | cut -d':' -f3 | while read -r prop_file_name_base; do
        # Locate and patch property files
        find /dev/__properties__/ -name "*$prop_file_name_base*" | while read -r prop_file; do
          "$magiskboot_path" hexpatch "$prop_file" "$search_hex" "$replacement_hex" >/dev/null 2>&1

          # Report patch status
          if [ $? -eq 0 ]; then
            echo " ? Successfully patched $prop_file (replaced part of '$search_string' with '$replacement_string')"
          fi
        done
      done

      # Remove property to apply changes
      resetprop -n --delete "$prop_name"
      ret=$?

      if [ $ret -eq 0 ]; then
        echo " ? Successfully unset $prop_name"
      else
        echo " ! Failed to unset $prop_name"
      fi
    done
  done
}

# Download file with retry mechanism using curl or wget
download_file() {
  url="$1"
  file="$2"
  retries=5

  # Attempt download with available tool
  while [ $retries -gt 0 ]; do
    if command -v curl >/dev/null 2>&1; then
      if curl -sL --connect-timeout 10 -o "$file" "$url"; then
        return 0
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -qO "$file" "$url" --timeout=10; then
        return 0
      fi
    else
      abort " ! curl or wget not found, unable to download file"
    fi

    retries=$((retries - 1))
    [ $retries -gt 0 ] && sleep 5
  done

  # Clean up and abort on failure
  rm -f "$file"
  abort " ! Download failed after $retries attempts"
}

# Handle volume key input for binary choices
volume_key_event_setval() {
  if [ $# -ne 4 ]; then
    abort "Error: volume_key_event_setval() expects 4 arguments: option_name, option1, option2, result_var"
  fi

  option_name="$1"
  option1="$2"
  option2="$3"
  result_var="$4"

  # Validate variable name
  case "$result_var" in
  '' | *[!_a-zA-Z]* | *[!_a-zA-Z0-9]*)
    abort "Error: Invalid variable name provided: \"$result_var\""
    ;;
  esac

  key_yes="${KEY_YES:-VOLUMEUP}"
  key_no="${KEY_NO:-VOLUMEDOWN}"
  key_cancel="${KEY_CANCEL:-POWER}"
  
  # Display input instructions
  ui_print " *********************************"
  ui_print " *      [ VOL+ ] = [ YES ]       *"
  ui_print " *      [ VOL- ] = [ NO ]        *"
  ui_print " *      [ POWR ] = [ CANCEL ]    *"
  ui_print " *********************************"
  ui_print " * Choose your value for \"$option_name\""
  ui_print " *********************************"

  while :; do
    # Wait for key input
    key=$(getevent -lqc1 | grep -oE "$key_yes|$key_no|$key_cancel")
    ret=$?

    # Handle getevent failure
    if [ -z "$key" ] && [ $ret -ne 0 ]; then
      ui_print " ! Warning: getevent command failed. Retrying…" >&2
      sleep 1
      continue
    fi

    # Process key input
    case "$key" in
    "$key_yes")
      ui_print " - Option \"$option_name\" set to \"$option1\""
      ui_print " *********************************"
      eval "$result_var='$option1'"
      sleep 0.5
      return 0
      ;;
    "$key_no")
      ui_print " - Option \"$option_name\" set to \"$option2\""
      ui_print " *********************************"
      eval "$result_var='$option2'"
      sleep 0.5
      return 0
      ;;
    "$key_cancel")
      abort "Cancel key detected! Canceling…" true
      ;;
    esac
  done
}

# Handle volume key input for multiple choice selection
volume_key_event_setoption() {
  option_name="$1"
  options_list=$2
  result_var="$3"

  # Validate variable name
  case "$result_var" in
  '' | *[!_a-zA-Z]* | *[!_a-zA-Z0-9]*)
    abort "Error: Invalid variable name provided: \"$result_var\""
    ;;
  esac

  # Process arguments
  shift 1

  # Clean up options list
  options_list=$(echo "$options_list" | tr -s ' ')

  # Store original parameters
  original_options="$*"

  # Convert to positional parameters
  set -- $(echo "$options_list")
  total_options=$#

  # Auto-select if only one option
  if [ "$total_options" -eq 1 ]; then
    eval "$result_var='$1'"
    return 0
  fi

  key_yes="${KEY_YES:-VOLUMEUP}"
  key_no="${KEY_NO:-VOLUMEDOWN}"
  key_cancel="${KEY_CANCEL:-POWER}"
  
  # Display selection instructions
  ui_print " *********************************"
  ui_print " *    [ VOL+ ] = [ CONFIRM ]     *"
  ui_print " *  [ VOL- ] = [ NEXT OPTION ]   *"
  ui_print " *     [ POWR ] = [ CANCEL ]     *"
  ui_print " *********************************"
  ui_print " * Choose your value for \"$option_name\" !"
  ui_print " *********************************"

  selected_option=1

  # Restore original parameters
  set -- $original_options

  # Show initial selection
  eval "current_option=\$${selected_option}"
  ui_print " > $current_option"

  while :; do
    # Wait for key input
    key=$(getevent -lqc1 | grep -oE "$key_yes|$key_no|$key_cancel")
    ret=$?

    # Handle getevent failure
    if [ -z "$key" ] && [ $ret -ne 0 ]; then
      ui_print " ! Warning: getevent command failed. Retrying…" >&2
      sleep 1
      continue
    fi

    # Process key input
    case "$key" in
    "$key_yes")
      ui_print " - Option \"$option_name\" set to \"$current_option\""
      ui_print " *********************************"
      eval "$result_var='$current_option'"
      sleep 1
      return 0
      ;;
    "$key_no")
      # Cycle to next option
      selected_option=$((selected_option + 1))
      if [ "$selected_option" -gt "$total_options" ]; then
        selected_option=1
      fi

      # Get selected option
      set -- $original_options
      i=1
      while [ $i -lt $selected_option ]; do
        shift
        i=$((i + 1))
      done
      current_option="$1"
      ui_print " > $current_option"
      ;;
    "$key_cancel")
      abort "Cancel key detected, Cancelling…" true
      ;;
    esac

    # Brief delay before next input
    sleep 0.5
  done
}
