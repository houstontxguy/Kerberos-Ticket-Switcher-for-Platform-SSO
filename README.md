# macOS Kerberos Ticket Switcher for Platform SSO

Automatically switches the default Kerberos ticket from cloud (Microsoft Entra ID / Azure AD) to on-premises Active Directory on macOS devices using Platform SSO.

## The Problem

When macOS devices use [Platform SSO](https://support.apple.com/guide/deployment/platform-sso-dep7bbb04ad3/web) with both cloud (Entra ID) and on-premises Active Directory Kerberos authentication, two separate Kerberos tickets are issued:

| Ticket | Realm Example | Used For |
|--------|---------------|----------|
| Cloud | `user@KERBEROS.MICROSOFTONLINE.COM` | Azure/Entra ID resources |
| On-Prem | `user@CORP.CONTOSO.COM` | Internal AD resources, file shares, intranet |

**The Issue:** The cloud ticket often becomes the "default" because Entra ID authentication happens first during login. This causes **browser SSO to internal web applications to fail** because browsers send the cloud ticket instead of the on-prem ticket that internal apps expect.

### Symptoms

- Internal web apps prompt for credentials despite having valid Kerberos tickets
- `klist` shows the cloud ticket as default (no `*` marker on on-prem ticket)
- Ticket Viewer shows `KERBEROS.MICROSOFTONLINE.COM` as the primary credential
- SPNEGO/Negotiate authentication fails to intranet sites

## The Solution

This tool installs a lightweight LaunchAgent that runs every 2 minutes (configurable) and:

1. Checks if the current default Kerberos ticket is the cloud ticket
2. If so, uses `kswitch -p` to switch the default to the on-prem ticket
3. Logs only when it actually switches (silent when already correct)

### Why `kswitch -p` Works

Platform SSO uses `API:` type credential caches. The `kswitch -c` command (by cache ID) doesn't work with these caches, but `kswitch -p` (by principal name) does:

```bash
# This doesn't work with Platform SSO:
kswitch -c "API:DDEE46A4-31FB-4D6C-8289-4E09DBA85950"

# This works:
kswitch -p "user@CORP.CONTOSO.COM"
```

## Requirements

- macOS 13 Ventura or later
- Platform SSO configured with Kerberos authentication
- On-premises Active Directory integration
- Admin access for installation

## Installation

### Quick Start

```bash
# Clone the repository
git clone https://github.com/YOUR_ORG/macos-kerberos-ticket-switcher.git
cd macos-kerberos-ticket-switcher

# Configure for your organization (edit the variables)
export ONPREM_REALM_SUFFIX="CONTOSO.COM"  # Your AD domain
export ORG_ID="contoso"                    # Your org identifier

# Install
sudo ./deploy_kerberos_switcher.sh
```

### Configuration Options

Set these environment variables before running the install script:

| Variable | Default | Description |
|----------|---------|-------------|
| `ONPREM_REALM_SUFFIX` | `YOURDOMAIN.COM` | Your on-prem AD realm suffix (e.g., `CONTOSO.COM`). Matches `*@*.CONTOSO.COM` |
| `CLOUD_REALM_PATTERN` | `MICROSOFTONLINE` | Pattern to identify cloud tickets to switch away from |
| `CHECK_INTERVAL` | `120` | How often to check/switch tickets (seconds) |
| `ORG_ID` | `myorg` | Organization identifier for file paths (lowercase, no spaces) |
| `LOG_RETENTION_DAYS` | `5` | Days of logs to retain |

### Examples

**Single AD domain:**
```bash
export ONPREM_REALM_SUFFIX="CORP.CONTOSO.COM"
export ORG_ID="contoso"
sudo ./deploy_kerberos_switcher.sh
```

**Multiple AD domains (uses suffix matching):**
```bash
# If you have NA.CONTOSO.COM, EU.CONTOSO.COM, AP.CONTOSO.COM
export ONPREM_REALM_SUFFIX="CONTOSO.COM"  # Matches all subdomains
export ORG_ID="contoso"
sudo ./deploy_kerberos_switcher.sh
```

### MDM Deployment (Intune, Jamf, etc.)

1. Customize the configuration variables at the top of `deploy_kerberos_switcher.sh`
2. Upload as a shell script to your MDM
3. Configure to run as root (not signed-in user)
4. Deploy to your Mac device group

**Intune Settings:**
| Setting | Value |
|---------|-------|
| Run script as signed-in user | No |
| Hide script notifications | Yes |
| Script frequency | Not configured |

## Files Installed

| Path | Purpose |
|------|---------|
| `/Library/Scripts/{ORG_ID}/switch_kerberos_default.sh` | Main switcher script |
| `/Library/LaunchAgents/com.{ORG_ID}.kerberos.switchdefault.plist` | LaunchAgent (runs every 2 min) |
| `~/Library/Logs/{ORG_ID}/kerberos_switch.log` | Per-user log file |

## Verification

```bash
# Check if LaunchAgent is loaded
launchctl list | grep kerberos.switchdefault

# View all Kerberos tickets (default marked with *)
klist -l

# Check current default ticket
klist | grep "Principal:"

# View switcher log
cat ~/Library/Logs/myorg/kerberos_switch.log
```

## Troubleshooting

### Log Messages

| Message | Meaning |
|---------|---------|
| (no entry) | On-prem ticket already default - working correctly |
| `Switched default: X -> Y` | Successfully switched from cloud to on-prem |
| `No Kerberos tickets found` | No tickets in cache - user needs to authenticate |
| `No on-prem ticket found` | Only cloud ticket exists - lock/unlock Mac |
| `Failed to switch` | `kswitch` command failed - check `klist -l` |

### Common Issues

**"No on-prem ticket found"**

The user only has a cloud ticket. This happens if:
- Platform SSO hasn't acquired the on-prem ticket yet
- VPN isn't connected (if required for AD access)
- User hasn't unlocked screen since boot

**Solution:** Lock and unlock the Mac to trigger Platform SSO ticket acquisition.

---

**Script not running**

```bash
# Check if loaded
launchctl list | grep kerberos.switchdefault

# Reload if needed
launchctl load /Library/LaunchAgents/com.myorg.kerberos.switchdefault.plist
```

---

**Still using cloud ticket after switch**

Some applications cache the Kerberos ticket. Try:
1. Quit and reopen the browser
2. Clear browser authentication cache
3. Wait for the app to re-authenticate

### Manual Testing

```bash
# Show all tickets
klist -l

# Show current default
klist

# Manually switch (replace with your principal)
kswitch -p "user@CORP.CONTOSO.COM"

# Verify
klist
```

## Uninstallation

```bash
# Set the same ORG_ID used during installation
export ORG_ID="contoso"
sudo ./uninstall_kerberos_switcher.sh
```

Or via MDM: Deploy `uninstall_kerberos_switcher.sh` with the same `ORG_ID`.

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                    Every 2 Minutes                              │
├─────────────────────────────────────────────────────────────────┤
│  1. Get current default ticket                                  │
│     └── klist | grep "Principal:"                               │
│                                                                 │
│  2. Check if already on-prem                                    │
│     └── If *@*.CONTOSO.COM (not MICROSOFTONLINE) → exit        │
│                                                                 │
│  3. Find on-prem ticket                                         │
│     └── klist -l | grep "@.*CONTOSO.COM" | grep -v MICROSOFTONLINE │
│                                                                 │
│  4. Switch default                                              │
│     └── kswitch -p "user@CORP.CONTOSO.COM"                     │
│                                                                 │
│  5. Log result (only if switched)                               │
└─────────────────────────────────────────────────────────────────┘
```

## Alternative Solutions

### MDM Profile Configuration

Microsoft documents a `custom_tgt_setting` option for Platform SSO that can disable cloud TGTs entirely:

```xml
<key>custom_tgt_setting</key>
<integer>1</integer>  <!-- 1 = On-Prem TGT Only -->
```

**Values:**
- `0` = Both (default)
- `1` = On-Prem Only
- `2` = Cloud Only

**Requirements:** Company Portal 5.2408.0+, macOS 14.6+

This approach is cleaner but may not work for all environments. See [Microsoft's documentation](https://learn.microsoft.com/en-us/entra/identity/devices/device-join-macos-platform-single-sign-on-kerberos-configuration).

### Why This Script Instead?

- Works on older macOS/Company Portal versions
- Doesn't require MDM profile changes
- Allows both tickets to remain available
- Easy to deploy and test
- Can be removed without affecting Platform SSO config

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test on macOS with Platform SSO
4. Submit a pull request

## License

MIT License - See [LICENSE](LICENSE) file.

## Acknowledgments

- Inspired by troubleshooting Platform SSO Kerberos issues in enterprise environments
- Thanks to the macOS admin community for documenting `kswitch` behavior

## Related Resources

- [Apple: Platform SSO Deployment Guide](https://support.apple.com/guide/deployment/platform-sso-dep7bbb04ad3/web)
- [Microsoft: Kerberos SSO in Platform SSO](https://learn.microsoft.com/en-us/entra/identity/devices/device-join-macos-platform-single-sign-on-kerberos-configuration)
- [Microsoft: Platform SSO Known Issues](https://learn.microsoft.com/en-us/entra/identity/devices/troubleshoot-macos-platform-single-sign-on-extension)
