# Security

Macster is a local utility. It changes one system setting, `pmset disablesleep`, and it doesn't collect or send data.

## What runs with privileges

| When | What runs as root | How |
| --- | --- | --- |
| Once, at setup | The setup script shown by `macster diagnose` | macOS's administrator password prompt (`do shell script … with administrator privileges`). The script is passed as an argument and never written to disk. |
| Each time you turn Macster on or off | `/usr/bin/pmset -a disablesleep 1` or `0` | `sudo -n`, allowed by `/etc/sudoers.d/macster`. |

The sudo rule names your account and exactly those two command lines. It doesn't allow other `pmset` arguments, other
programs, or a shell. Setup validates it with `visudo` before it takes effect and removes it if the full sudo
configuration fails to check afterwards.

There's no root helper or daemon. The watchdog (`macster-watchdog`) runs as you and turns sleep back on through the same
rule.

Everything else runs as you, without privileges: reading the sleep flag, the battery, and the lid from IOKit, turning
the screen off when the lid closes (`pmset displaysleepnow`), and turning it back on when the lid opens.

## What the rule means

Any program running as your user can run those two commands without a password, so it could keep your Mac awake or let
it sleep. It can't do anything else with the rule. To revoke it, choose **⋯ → Remove Macster's Permission…** in the
panel, or run `sudo rm /etc/sudoers.d/macster`.

## URLs and the command line

Any app can open `macster://` URLs, and the `macster` command uses them too. They can turn Macster on or off and show
its panel; they can't start setup, so they never trigger a password prompt, and the low-battery and heat safeties still
apply. This adds nothing to what the sudo rule already allows programs running as you.

The keyboard shortcut uses Carbon's hot key API, which delivers only that key combination to Macster. Macster doesn't
see other typing and doesn't ask for Accessibility or Input Monitoring permission.

## Data

Macster stores only its preferences (the timer, the battery level, the heat and screen switches, and the keyboard
shortcut) in the `io.github.macster.Macster` defaults domain. It makes no network connections and has no analytics or updater.

## Upgrading from 0.1

Macster 0.1 installed a root helper at `/usr/local/libexec/macsterctl` that restored power settings from a JSON file in
your home folder. Setup in 0.2 deletes that helper and replaces its sudo rule.

## Reporting

Please use GitHub Security Advisories for private reports:

[Open a security advisory](https://github.com/ApocalixDeLuque/Macster/security/advisories/new)
