# Changelog

## 0.2.0

A rewrite. Macster now lives in the menu bar and changes only the one setting it needs.

- Change only `pmset disablesleep`. Macster no longer touches display sleep, disk sleep, standby, or Power Nap, no
  longer runs `caffeinate`, and no longer keeps a backup file of your settings.
- Show the state at all times with a menu bar icon: outlined while the Mac sleeps normally, filled while it stays awake.
- Turn off when Macster quits. A small watchdog turns normal sleep back on if Macster crashes or is force quit, and
  Macster turns off a session left over from a power loss the next time it opens.
- Fix the status disagreeing with the message ("Enabled." without the green indicator): the state is read from the
  kernel, a change counts only once the kernel confirms it, and outside changes are followed live.
- Add an auto-off timer, and one-off durations (30 minutes to 8 hours) in the right-click menu.
- Add safeties: turn off at a battery level you choose (10% by default), and when the battery passes 45 °C or macOS
  reports critical heat. A notification says why Macster turned off; it needs no permission prompt.
- Add a global keyboard shortcut, recorded in the panel. It needs no Accessibility permission.
- Add the `macster` command (`on 2h`, `off`, `toggle`, `status`, `open`, `diagnose`) and `macster://` URLs for
  Shortcuts and its automations, Raycast, and Alfred.
- Add `macster run -- <command>`: stay awake until the command exits, then turn off.
- Turn the screen off when the lid closes and back on when it opens (on by default). With sleep disabled, macOS can
  leave the built-in screen lit behind the lid. Screens are left alone when a monitor is connected.
- Add Open at Login.
- Replace the root helper and its sudo rule with a rule for exactly `pmset -a disablesleep 1` and `0`. Setup undoes
  everything 0.1 changed, in the same password prompt.
- Add `macster diagnose`, unified logging, a test suite, and universal (Apple silicon and Intel) release builds.
- Require macOS 14.

## 0.1.2

- Remove helper-installation implementation details from the main UI.
- Add more top spacing so the logo stays comfortably below the window controls.
- Refresh README and project docs with screenshots, badges, and clearer open-source guidance.
- Re-audit the project for local paths, device-specific values, secrets, and hardcoded network addresses.

## 0.1.1

- Add one-time bundled helper installation for passwordless normal toggles.
- Remove the noisy power-settings summary card.
- Add top padding so the logo stays clear of the macOS title bar.
- Keep the UI focused on the current enabled/disabled state and primary action.

## 0.1.0

- Initial public release.
- Add native SwiftUI toggle UI.
- Add `pmset` backup and restore flow.
- Add user-level `launchd` keep-awake assertion.
- Add `.app`, `.zip`, and `.dmg` release packaging.
