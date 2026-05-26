# Contributing

Thanks for improving Macster. The project goal is intentionally narrow: a fast, native, trustworthy toggle for lid-close awake mode.

## Project Rules

| Rule | Why |
| --- | --- |
| Keep it native | The app should stay small and responsive. |
| Avoid extra services | Only the explicit keep-awake assertion should run in the background. |
| Avoid network calls | Macster does not need telemetry, analytics, or remote config. |
| Preserve user settings | Always backup before changing `pmset`, then restore on disable. |
| Avoid local assumptions | Do not commit user names, local paths, IP addresses, hostnames, device names, or secrets. |

## Local Setup

```sh
git clone https://github.com/ApocalixDeLuque/Macster.git
cd Macster
swift run Macster
```

## Build

```sh
swift build -c release --product Macster
swift build -c release --product MacsterCtl
./scripts/build-release.sh
```

## Verification Checklist

- [ ] `swift build -c release --product Macster` passes.
- [ ] `swift build -c release --product MacsterCtl` passes.
- [ ] `./scripts/build-release.sh` creates `.app`, `.dmg`, `.zip`, and `checksums.txt`.
- [ ] `hdiutil verify dist/Macster-<version>.dmg` passes.
- [ ] The app opens.
- [ ] First-use helper installation requests administrator approval.
- [ ] Later enable/disable toggles do not ask for a password.
- [ ] `pmset -g` reflects the expected enabled/disabled state.
- [ ] Scan the source for accidental local paths, network addresses, hostnames, tokens, and machine-specific values.

## Pull Requests

Use concise conventional commits:

```text
feat: add focused status handling
fix: restore saved power settings
docs: refresh release instructions
```

For UI changes, include a screenshot in the PR description when possible.
