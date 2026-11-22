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
for lang in en pl uk de fr ar; do
  grep -q '^"NSFaceIDUsageDescription" = ' "Ortus/Resources/$lang.lproj/InfoPlist.strings" || { echo "check: $lang has no Face ID text" >&2; exit 1; }
done
# The App Store listing in every language, within Apple's limits.
for loc in en-US pl uk de-DE fr-FR ar-SA; do
  for f in name:30 subtitle:30 promotional_text:170 keywords:100 description:4000 release_notes:4000; do
    file="store/ios/listing/$loc/${f%%:*}.txt"
    [ -s "$file" ] || { echo "check: $file is missing" >&2; exit 1; }
    [ "$(tr -d '\n' < "$file" | wc -m)" -le "${f##*:}" ] || { echo "check: $file is over ${f##*:} characters" >&2; exit 1; }
  done
done
(cd OrtusKit && swift test)
if command -v xcodebuild > /dev/null && command -v xcodegen > /dev/null; then
  xcodegen generate
  xcodebuild test -project Ortus.xcodeproj -scheme Ortus -destination 'platform=iOS Simulator,name=iPhone 16' | tail -n 40
else
  echo "check: no Xcode here; the app and its simulator tests run in CI on macOS"
fi
echo "all checks passed"
