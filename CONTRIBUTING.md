# Contributing

Thanks for improving Macster. The goal is intentionally narrow: a fast, native, trustworthy way to keep a Mac awake with
the lid closed.

## Project rules

| Rule | Why |
| --- | --- |
| Change only `disablesleep` | Every other power setting belongs to the user. Macster 0.1 changed more and left Macs in odd states. |
| Never leave it on silently | While sleep is disabled, the icon says so, and quitting or crashing turns it off. |
| Trust the kernel, not the last command | A change counts only once `IOPMrootDomain` reports it. |
| No polling, no network | Use system notifications and kernel events, keep work off the hot path, and send nothing anywhere. The one exception is the battery temperature, read once a minute only while Macster keeps the Mac awake, because macOS doesn't announce changes to it. |
| Keep it native | AppKit and SwiftUI, no third-party dependencies. |
| No local assumptions | Don't commit user names, local paths, IP addresses, host names, device names, or secrets. |

## Local setup

```sh
git clone https://github.com/ApocalixDeLuque/Macster.git
cd Macster
./scripts/test.sh
./scripts/install-local.sh
```

## Layout

| Target | Contents |
| --- | --- |
| `MacsterCore` | Code that can be tested without touching the system: `pmset` and `sudo -l` parsing, the setup script and sudo rule, quoting, timer, safety, and lid rules, `macster://` URLs and command-line arguments, keyboard shortcuts, session ownership, the process runner. |
| `MacsterApp` | `AppModel` (the state machine), system integration (`RootDomain`, `SleepControl`, `Watchdog`, `PowerSourceMonitor`, `LidMonitor`, `Screens`, `GlobalHotKey`, `Notifier`), the `macster` command, and the UI. |
| `MacsterWatchdog` | The helper that restores sleep if Macster dies. Darwin only. |
| `Tools/MacsterSnapshots` | Renders the panel's states to PNG files for review. |

## Verification checklist

- [ ] `./scripts/test.sh` passes.
- [ ] `./scripts/build-release.sh` builds a universal app, DMG, ZIP, and `checksums.txt`.
- [ ] `macster diagnose` shows what you expect.
- [ ] `macster on 1m` turns on, and the icon and `macster status` agree until the timer turns it off.
- [ ] Turning it on and off from the panel updates the icon, and `pmset -g` shows `SleepDisabled` matching.
- [ ] `sudo -n pmset -a disablesleep 1` in Terminal flips the icon to on within a second, and `0` flips it back.
- [ ] With it on, `kill -9` Macster: `pmset -g` shows `SleepDisabled 0` within a second.
- [ ] With it on, quit Macster: sleep is back on.
- [ ] With it on and no monitor connected, close the lid for a few seconds: `pmset -g log` shows the display turning
      off and back on, and no `Entering Sleep`.
- [ ] For UI changes, run `MacsterSnapshots` and check light and dark.

GitHub Actions runs the tests and builds the universal app for every pull request, on the same runner as releases.

## Pull requests

Use concise conventional commits:

```text
feat: add a keyboard shortcut
fix: follow sleep changes made while the panel is open
docs: explain the watchdog
```

For UI changes, include a screenshot in the PR description.
