# Security Policy

## Reporting

Please open a private security advisory on GitHub if you find a security issue.

## Scope

Macster shells out to Apple system tools:

- `/usr/bin/pmset`
- `/usr/bin/caffeinate`
- `/bin/launchctl`
- `/usr/bin/osascript`
- `/usr/bin/sudo`

Administrator approval is requested through macOS' standard authorization prompt for one-time helper installation. After setup, Macster uses a sudoers allowlist that permits only the current user to run:

```text
/usr/local/libexec/macsterctl enable
/usr/local/libexec/macsterctl disable
```

The helper is installed at:

```text
/usr/local/libexec/macsterctl
```

The sudoers file is installed at:

```text
/etc/sudoers.d/macster
```

The helper only toggles Macster's `launchd` keep-awake job and the relevant `pmset` settings.

## Data

Macster stores one local backup file with power settings:

```text
~/Library/Application Support/Macster/power-settings-backup.json
```

It does not store credentials, secrets, device identifiers, or network data.
