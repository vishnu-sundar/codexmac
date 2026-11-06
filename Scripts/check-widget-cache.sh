#!/usr/bin/env bash
# Exercise the extension's actual sandbox file entitlement on a clean CI account.
set -euo pipefail
cd "$(dirname "$0")/.."
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
cat > "$temp/main.swift" <<'SWIFT'
import Foundation
let marker = ProcessInfo.processInfo.arguments[2]
guard let file = Cache.file else { exit(1) }
switch ProcessInfo.processInfo.arguments[1] {
case "write":
    guard !FileManager.default.fileExists(atPath: file.path) else { exit(2) }
    try Cache.write(Reading(issue: marker))
case "read":
    guard Cache.read().issue == marker else { exit(3) }
default:
    guard Cache.read().issue == marker else { exit(4) }
    try FileManager.default.removeItem(at: file)
}
SWIFT
swiftc Core/Cache.swift Core/Usage.swift "$temp/main.swift" -o "$temp/host"
# App Sandbox initializes from the main bundle's Info.plist and code signature.
probe="$temp/CacheProbe.app"
mkdir -p "$probe/Contents/MacOS"
cp "$temp/host" "$probe/Contents/MacOS/CacheProbe"
cat > "$probe/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.codexmac.monitor.cacheprobe</string>
<key>CFBundleExecutable</key><string>CacheProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleName</key><string>CacheProbe</string>
</dict></plist>
PLIST
codesign --force --sign - --entitlements Config/Widget.entitlements "$probe"
marker="$(uuidgen)"
"$temp/host" write "$marker"
if ! "$probe/Contents/MacOS/CacheProbe" read "$marker"; then
  /usr/bin/log show --last 1m --style compact --predicate 'process == "CacheProbe"' | tail -40
  exit 1
fi
"$temp/host" clean "$marker"
echo "Sandboxed widget cache round-trip passed."
