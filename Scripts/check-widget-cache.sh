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
cp "$temp/host" "$temp/widget"
codesign --force --sign - --identifier io.codexmac.monitor.widget.cacheprobe --entitlements Config/Widget.entitlements "$temp/widget"
marker="$(uuidgen)"
"$temp/host" write "$marker"
"$temp/widget" read "$marker"
"$temp/host" clean "$marker"
echo "Sandboxed widget cache round-trip passed."
