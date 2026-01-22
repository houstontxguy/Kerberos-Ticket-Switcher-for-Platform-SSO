#!/bin/bash
#
# deploy_kerberos_switcher.sh
# 
# Deploys a LaunchAgent that automatically switches the default Kerberos ticket
# from cloud (MICROSOFTONLINE) to on-premises Active Directory for macOS devices
# using Platform SSO.
#
# This solves the problem where browser SSO to internal web applications fails
# because the cloud Kerberos ticket is set as default instead of the on-prem ticket.
#
# GitHub: https://github.com/houstontxguy/Kerberos-Ticket-Switcher-for-Platform-SSO
# License: MIT
#

set -e

# =============================================================================
# CONFIGURATION - Customize these values for your organization
# =============================================================================

# Your organization's on-premises AD realm suffix (e.g., "CONTOSO.COM", "CORP.EXAMPLE.COM")
# The script will prefer any ticket matching *@*.${ONPREM_REALM_SUFFIX}
# Leave as "XOM.COM" or change to your domain
ONPREM_REALM_SUFFIX="${ONPREM_REALM_SUFFIX:-YOURDOMAIN.COM}"

# Cloud realm to exclude (typically Microsoft's cloud Kerberos realm)
CLOUD_REALM_PATTERN="${CLOUD_REALM_PATTERN:-MICROSOFTONLINE}"

# How often to check and switch tickets (in seconds)
# Default: 120 (2 minutes)
CHECK_INTERVAL="${CHECK_INTERVAL:-120}"

# Organization identifier for file naming (lowercase, no spaces)
ORG_ID="${ORG_ID:-myorg}"

# Log retention in days
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-5}"

# =============================================================================
# INSTALLATION PATHS - Generally don't need to change these
# =============================================================================

SCRIPT_DIR="/Library/Scripts/${ORG_ID}"
SCRIPT_PATH="${SCRIPT_DIR}/switch_kerberos_default.sh"
PLIST_NAME="com.${ORG_ID}.kerberos.switchdefault.plist"
PLIST_PATH="/Library/LaunchAgents/${PLIST_NAME}"

# =============================================================================
# INSTALLATION
# =============================================================================

echo "Deploying Kerberos Ticket Switcher..."
echo "  On-prem realm suffix: ${ONPREM_REALM_SUFFIX}"
echo "  Cloud realm pattern:  ${CLOUD_REALM_PATTERN}"
echo "  Check interval:       ${CHECK_INTERVAL}s"
echo "  Organization ID:      ${ORG_ID}"
echo ""

# Create directories
mkdir -p "${SCRIPT_DIR}"

# Create the switcher script
cat > "$SCRIPT_PATH" << SCRIPT
#!/bin/bash
#
# switch_kerberos_default.sh
# Switches default Kerberos ticket from cloud to on-premises AD
#
# Configuration:
#   ONPREM_REALM_SUFFIX: ${ONPREM_REALM_SUFFIX}
#   CLOUD_REALM_PATTERN: ${CLOUD_REALM_PATTERN}
#

LOG_FILE="\$HOME/Library/Logs/${ORG_ID}/kerberos_switch.log"
LOG_MAX_DAYS=${LOG_RETENTION_DAYS}

# On-prem realm suffix to match (e.g., "CONTOSO.COM" matches user@NA.CONTOSO.COM)
ONPREM_REALM_SUFFIX="${ONPREM_REALM_SUFFIX}"

# Cloud realm pattern to exclude
CLOUD_REALM_PATTERN="${CLOUD_REALM_PATTERN}"

# Ensure log directory exists
mkdir -p "\$(dirname "\$LOG_FILE")"

# Trim log to keep only last N days
if [[ -f "\$LOG_FILE" ]]; then
    CUTOFF=\$(date -v-\${LOG_MAX_DAYS}d "+%Y-%m-%d")
    TMP_FILE="\${LOG_FILE}.tmp"
    awk -v cutoff="\$CUTOFF" '\$1 >= cutoff { print }' "\$LOG_FILE" > "\$TMP_FILE" 2>/dev/null
    if [[ -s "\$TMP_FILE" ]]; then
        mv "\$TMP_FILE" "\$LOG_FILE"
    else
        rm -f "\$TMP_FILE"
    fi
fi

log_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOG_FILE"
}

# Check if any tickets exist
TICKET_LIST=\$(klist -l 2>/dev/null)
if [[ \$? -ne 0 ]] || [[ -z "\$TICKET_LIST" ]]; then
    log_message "No Kerberos tickets found"
    exit 0
fi

# Get current default principal
CURRENT_DEFAULT=\$(klist 2>/dev/null | grep "Principal:" | head -1 | awk '{print \$2}')
if [[ -z "\$CURRENT_DEFAULT" ]]; then
    log_message "Could not determine current default principal"
    exit 0
fi

# Check if current default is already an on-prem ticket (matches realm suffix, not cloud)
if [[ "\$CURRENT_DEFAULT" == *"\${ONPREM_REALM_SUFFIX}"* ]] && [[ "\$CURRENT_DEFAULT" != *"\${CLOUD_REALM_PATTERN}"* ]]; then
    # Already using on-prem ticket - exit silently (no log entry)
    exit 0
fi

# Find any on-prem principal (matches realm suffix, excludes cloud pattern)
ONPREM_PRINCIPAL=\$(klist -l 2>/dev/null | grep -i "@.*\${ONPREM_REALM_SUFFIX}" | grep -vi "\${CLOUD_REALM_PATTERN}" | awk '{print \$1}' | sed 's/^\*//' | head -1)

if [[ -z "\$ONPREM_PRINCIPAL" ]]; then
    log_message "No on-prem ticket found for *@*.\${ONPREM_REALM_SUFFIX} (current: \$CURRENT_DEFAULT)"
    exit 0
fi

# Attempt to switch
if kswitch -p "\$ONPREM_PRINCIPAL" 2>/dev/null; then
    log_message "Switched default: \$CURRENT_DEFAULT -> \$ONPREM_PRINCIPAL"
else
    log_message "Failed to switch from \$CURRENT_DEFAULT to \$ONPREM_PRINCIPAL"
    exit 1
fi

exit 0
SCRIPT

chmod 755 "$SCRIPT_PATH"
chown root:wheel "$SCRIPT_PATH"

# Create the LaunchAgent plist
cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.${ORG_ID}.kerberos.switchdefault</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SCRIPT_PATH}</string>
    </array>
    <key>StartInterval</key>
    <integer>${CHECK_INTERVAL}</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>Nice</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>/tmp/${ORG_ID}_kerberos_switch.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/${ORG_ID}_kerberos_switch.err</string>
</dict>
</plist>
PLIST

chmod 644 "$PLIST_PATH"
chown root:wheel "$PLIST_PATH"

# Load for any currently logged-in users
CURRENT_USER=$(stat -f "%Su" /dev/console 2>/dev/null)
if [[ -n "$CURRENT_USER" ]] && [[ "$CURRENT_USER" != "root" ]]; then
    CURRENT_UID=$(id -u "$CURRENT_USER")
    # Unload first (ignore errors if not loaded)
    launchctl asuser "$CURRENT_UID" launchctl unload "$PLIST_PATH" 2>/dev/null || true
    # Load the agent
    launchctl asuser "$CURRENT_UID" launchctl load "$PLIST_PATH" 2>/dev/null || true
    echo "Loaded LaunchAgent for user: $CURRENT_USER"
fi

echo ""
echo "Kerberos Ticket Switcher deployed successfully!"
echo ""
echo "Files installed:"
echo "  Script:      $SCRIPT_PATH"
echo "  LaunchAgent: $PLIST_PATH"
echo "  Log:         ~/Library/Logs/${ORG_ID}/kerberos_switch.log"
echo ""
echo "The switcher will run every ${CHECK_INTERVAL} seconds and switch the default"
echo "Kerberos ticket to your on-premises AD ticket (*@*.${ONPREM_REALM_SUFFIX})"
echo "when the cloud ticket (${CLOUD_REALM_PATTERN}) is currently default."

exit 0
