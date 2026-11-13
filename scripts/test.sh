#!/usr/bin/env bash
# Runs the test suite. Works with full Xcode or with only the Command Line Tools installed.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The watchdog tests launch the real helper binary.
swift build --product macster-watchdog

developer_dir="$(xcode-select -p)"
if [[ "$developer_dir" == *CommandLineTools* ]]; then
  # The Command Line Tools ship Swift Testing but don't put it on the default search paths.
  frameworks="$developer_dir/Library/Developer/Frameworks"
  libraries="$developer_dir/Library/Developer/usr/lib"
  exec swift test \
    -Xswiftc -F"$frameworks" \
    -Xlinker -F"$frameworks" \
    -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$libraries" \
    "$@"
fi

exec swift test "$@"
