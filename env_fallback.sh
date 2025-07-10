# Fallback environment for non-Magisk shells (e.g. CI/CD environments)

# Assume BOOTMODE=true if not defined (prevents Magisk-specific recovery checks from failing)
if [ -z "$BOOTMODE" ]; then
  BOOTMODE=true
fi

# Define dummy ui_print if it's not available
if ! type ui_print >/dev/null 2>&1; then
  ui_print() { echo "$@"; }
fi

# Define dummy abort if it's not available
if ! type abort >/dev/null 2>&1; then
  abort() { echo "$@" >&2; exit 1; }
fi
