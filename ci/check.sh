#!/usr/bin/env bash
# Everything that can be checked on this machine. The shared code (OrtusKit)
# builds and is tested anywhere Swift runs; the app and its simulator tests
# need Xcode, so they run where it is (CI's macOS runner, or a Mac).
set -euo pipefail
cd "$(dirname "$0")/.."
for script in ci/*.sh; do bash -n "$script"; done
# No third-party packages: every line of the app is ours (and permissive).
if grep -q "\.package(" OrtusKit/Package.swift || grep -q "^  [A-Za-z]*:$" <(sed -n '/^packages:/,/^[a-z]/p' project.yml | grep -v "OrtusKit\|path:\|packages:"); then
  echo "check: a third-party package needs a licence review first" >&2
  exit 1
fi
# Every text in all six languages.
keys() { grep -o '^"[^"]*"' "Ortus/Resources/$1.lproj/Localizable.strings" | sort; }
for lang in pl uk de fr ar; do
  diff <(keys en) <(keys "$lang") > /dev/null || { echo "check: $lang texts differ from en" >&2; exit 1; }
done
(cd OrtusKit && swift test)
if command -v xcodebuild > /dev/null && command -v xcodegen > /dev/null; then
  xcodegen generate
  xcodebuild test -project Ortus.xcodeproj -scheme Ortus -destination 'platform=iOS Simulator,name=iPhone 16' | tail -n 40
else
  echo "check: no Xcode here; the app and its simulator tests run in CI on macOS"
fi
echo "all checks passed"
