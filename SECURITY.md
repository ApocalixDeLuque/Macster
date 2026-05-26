# Security

Macster is a local utility. Its security model is simple: it should only change the macOS power settings required for lid-close awake mode, and it should not collect or transmit data.

## Scope

| Component | Path | Purpose |
| --- | --- | --- |
| App | `Macster.app` | Native SwiftUI interface. |
| Helper | `/usr/local/libexec/macsterctl` | Runs Macster's enable/disable actions as root. |
| Allowlist | `/etc/sudoers.d/macster` | Allows only the helper's exact enable/disable commands. |
| Backup | `~/Library/Application Support/Macster/power-settings-backup.json` | Stores previous power settings for restore. |

## Privileged Commands

The sudoers allowlist permits only:

```text
/usr/local/libexec/macsterctl enable
/usr/local/libexec/macsterctl disable
```

The helper uses Apple-provided tools:

| Tool | Use |
| --- | --- |
| `/usr/bin/pmset` | Power setting changes. |
| `/usr/bin/caffeinate` | Keep-awake assertion. |
| `/bin/launchctl` | User-level job management. |

## Data Handling

Macster does not store:

- credentials
- secrets
- device identifiers
- IP addresses
- hostnames
- analytics events
- network data

Macster stores only the power-setting values needed to restore the previous state.

## Reporting

Please use GitHub Security Advisories for private reports:

[Open a security advisory](https://github.com/ApocalixDeLuque/Macster/security/advisories/new)
