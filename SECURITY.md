# Security Policy

## Reporting

Please open a private security advisory on GitHub if you find a security issue.

## Scope

Macster shells out to Apple system tools:

- `/usr/bin/pmset`
- `/usr/bin/caffeinate`
- `/bin/launchctl`
- `/usr/bin/osascript`

Administrator approval is requested only through macOS' standard authorization prompt for the `pmset` changes.

## Data

Macster stores one local backup file with power settings:

```text
~/Library/Application Support/Macster/power-settings-backup.json
```

It does not store credentials, secrets, device identifiers, or network data.
