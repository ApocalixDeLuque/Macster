#!/usr/bin/env bash
# Builds Macster for this Mac's architecture and installs it into /Applications, restarting it if it's running.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ARCHS="$(uname -m)" ./scripts/build-release.sh

# Quitting turns keep-awake off first, the same as choosing Quit in the menu.
osascript -e 'tell application id "io.github.macster.Macster" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 100); do
  pgrep -qx Macster || break
  sleep 0.1
done

rm -rf /Applications/Macster.app
ditto dist/Macster.app /Applications/Macster.app
open /Applications/Macster.app
echo "Installed and opened /Applications/Macster.app"
