# Macster

Macster is a tiny macOS app for toggling lid-close awake mode.

It is intentionally small: one native SwiftUI window, no analytics, no network calls, no background updater, and no bundled services. The app only wraps the macOS power-management commands needed to enable or disable lid-close awake behavior.

## What It Does

- Shows whether lid-close awake mode is enabled.
- Enables the mode with one button.
- Disables the mode with one button.
- Stores the current `pmset` power values before enabling.
- Restores the stored `pmset` values when disabling.
- Keeps a lightweight `caffeinate` assertion running through `launchd` while enabled.
- Installs its bundled helper on first use so normal toggles do not need repeated password prompts.

## Install

Download the latest `.dmg` from the GitHub Releases page, open it, and drag `Macster.app` into Applications.

The app is ad-hoc signed for local/open-source distribution. macOS may show a Gatekeeper warning on first launch if the release is not notarized.

## Usage

Open Macster and press the main button:

- `Keep Awake on Lid Close` enables lid-close awake mode.
- `Let Lid Close Sleep` restores normal lid-close behavior.

The first enable or disable installs Macster's bundled helper and may ask for administrator approval. After that setup, normal toggles use a narrow passwordless sudo allowlist for Macster's own helper command.

Touch ID availability for the one-time administrator prompt is controlled by macOS. If your Mac allows Touch ID for administrator authorization, macOS can offer it; otherwise it will ask for the account password.

Macster does not install Homebrew packages, third-party runtimes, or external dependencies. Release builds include everything the app needs, and the app only calls macOS tools that ship with macOS.

## How It Works

When enabling, Macster:

1. Reads the current AC and battery power settings with `pmset -g custom`.
2. Saves the settings it changes under Application Support.
3. Installs Macster's bundled helper if it is missing or outdated.
4. Starts a user-level `launchd` job running `/usr/bin/caffeinate -d -i -s`.
5. Uses the helper to run `pmset` as root.

When disabling, Macster:

1. Installs Macster's bundled helper if it is missing or outdated.
2. Removes the managed keep-awake `launchd` job.
3. Turns `SleepDisabled` off.
4. Restores the saved power settings if a backup exists.

Backup path:

```text
~/Library/Application Support/Macster/power-settings-backup.json
```

Helper path:

```text
/usr/local/libexec/macsterctl
```

Sudoers allowlist:

```text
/etc/sudoers.d/macster
```

The allowlist only permits the current macOS user to run these exact commands without repeated password prompts:

```text
/usr/local/libexec/macsterctl enable
/usr/local/libexec/macsterctl disable
```

## Commands Used

Enable:

```sh
/usr/bin/sudo -n /usr/local/libexec/macsterctl enable
```

The helper runs:

```sh
/bin/launchctl submit -l io.github.macster.keepawake -- /usr/bin/caffeinate -d -i -s
/usr/bin/pmset -a sleep 0 disksleep 0 displaysleep 0 standby 0 powernap 0
/usr/bin/pmset -a disablesleep 1
```

Disable:

```sh
/usr/bin/sudo -n /usr/local/libexec/macsterctl disable
```

If a backup exists, Macster also restores the prior AC and battery values for `sleep`, `disksleep`, `displaysleep`, `standby`, and `powernap`.

## Limitations

Macster controls macOS sleep behavior. Some MacBook models still blank the built-in panel when the physical lid is closed because that behavior is handled by macOS and hardware. The practical goal is to keep the Mac awake for clamshell use, external displays, remote sessions, long-running tasks, and downloads.

## Build From Source

Requirements:

- macOS 13 or newer
- Swift 6 or newer
- Command Line Tools for Xcode

Build:

```sh
./scripts/build-release.sh
```

Artifacts are written to `dist/`:

- `Macster.app`
- `Macster-<version>.dmg`
- `Macster-<version>.zip`
- `checksums.txt`

## Development

Run locally:

```sh
swift run Macster
```

Build release artifacts:

```sh
VERSION=0.1.1 ./scripts/build-release.sh
```

## Privacy

Macster does not collect telemetry, does not make network requests, and does not store personal data. It stores only the local power settings needed to restore your previous state.

## License

MIT
