# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-21

### Added
- Initial public release
- Configurable on-prem realm suffix matching (supports multiple AD domains)
- Configurable cloud realm pattern exclusion
- Configurable check interval (default 2 minutes)
- Configurable organization identifier for file paths
- Automatic log rotation (configurable retention period)
- LaunchAgent for automatic execution
- Silent operation when already using correct ticket
- Comprehensive README with troubleshooting guide
- MIT License

### Technical Details
- Uses `kswitch -p` (by principal name) which works with Platform SSO's `API:` credential caches
- Runs as user-context LaunchAgent (not system daemon)
- Logs only when switching occurs to minimize disk I/O
