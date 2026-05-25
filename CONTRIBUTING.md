# Contributing

Thanks for helping improve Macster.

## Principles

- Keep the app small and native.
- Avoid background services beyond the explicit `caffeinate` assertion.
- Avoid analytics, network calls, and device-specific assumptions.
- Preserve the user's existing power settings whenever possible.
- Keep the interface simple enough to understand at a glance.

## Local Setup

```sh
git clone https://github.com/ApocalixDeLuque/Macster.git
cd Macster
swift run Macster
```

## Release Build

```sh
VERSION=0.1.1 ./scripts/build-release.sh
```

## Pull Requests

Before opening a pull request:

1. Run `swift build -c release`.
2. Run `./scripts/build-release.sh`.
3. Confirm the app opens.
4. Confirm first-use helper installation asks for administrator approval.
5. Confirm later enabling and disabling do not ask for a password and update `pmset` as expected.

Do not include local paths, machine names, IP addresses, secrets, or personal configuration in commits.
