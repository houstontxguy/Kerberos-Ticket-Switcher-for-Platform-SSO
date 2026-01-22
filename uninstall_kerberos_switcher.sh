#!/bin/bash
#
# uninstall_kerberos_switcher.sh
#
# Removes the Kerberos ticket switcher LaunchAgent and script
#
# GitHub: https://github.com/houstontxguy/Kerberos-Ticket-Switcher-for-Platform-SSO
# License: MIT
#

# =============================================================================
# CONFIGURATION - Must match values used during installation
# =============================================================================

# Organization identifier (must match what was used in deploy script)
ORG_ID="${ORG_ID:-myorg}"

# =============================================================================
# UNINSTALLATION PATHS
# =============================================================================

SCRIPT_DIR="/Library/Scripts/${ORG_ID}"
SCRIPT_PATH="${SCRIPT_DIR}/switch_kerberos_default.sh"
PLIST_NAME="com.${ORG_ID}.kerberos.switchdefault.plist"
PLIST_PATH="/Library/LaunchAgents/${PLIST_NAME}"

# =============================================================================
# UNINSTALLATION
# =============================================================================

echo "Uninstalling Kerberos Ticket Switcher (org: ${ORG_ID})..."

# Unload LaunchAgent for all logged-in users
for uid in $(ps -axo uid,comm | grep -i "Finder.app" | awk '{print $1}' | sort -u); do
    echo "  Unloading LaunchAgent for UID $uid..."
    launchctl asuser "$uid" launchctl unload "$PLIST_PATH" 2>/dev/null
done

# Also try for console user
CURRENT_USER=$(stat -f "%Su" /dev/console 2>/dev/null)
if [[ -n "$CURRENT_USER" ]] && [[ "$CURRENT_USER" != "root" ]]; then
    CURRENT_UID=$(id -u "$CURRENT_USER")
    launchctl asuser "$CURRENT_UID" launchctl unload "$PLIST_PATH" 2>/dev/null
fi

# Remove LaunchAgent plist
if [[ -f "$PLIST_PATH" ]]; then
    rm -f "$PLIST_PATH"
    echo "  Removed: $PLIST_PATH"
else
    echo "  Not found: $PLIST_PATH"
fi

# Remove script
if [[ -f "$SCRIPT_PATH" ]]; then
    rm -f "$SCRIPT_PATH"
    echo "  Removed: $SCRIPT_PATH"
else
    echo "  Not found: $SCRIPT_PATH"
fi

# Remove organization scripts directory if empty
if [[ -d "$SCRIPT_DIR" ]] && [[ -z "$(ls -A "$SCRIPT_DIR" 2>/dev/null)" ]]; then
    rmdir "$SCRIPT_DIR"
    echo "  Removed empty directory: $SCRIPT_DIR"
fi

# Note about user logs
echo ""
echo "Kerberos Ticket Switcher uninstalled."
echo ""
echo "Note: User log files were not removed. To remove manually:"
echo "  rm ~/Library/Logs/${ORG_ID}/kerberos_switch.log"

exit 0
