#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist build
xcodebuild -project CodexMac.xcodeproj -scheme CodexMac -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
app="$PWD/build/DerivedData/Build/Products/Release/CodexMac.app"
extension="$app/Contents/PlugIns/UsageWidget.appex"
for executable in "$app/Contents/MacOS/CodexMac" "$extension/Contents/MacOS/UsageWidget"; do
  lipo -verify_arch arm64 x86_64 "$executable"
done
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/CodexMac" --screenshots "$PWD/dist"
for name in Floating-Bar Expanded-Bar Dashboard; do test -s "dist/$name.png"; done
stage="$(mktemp -d)"
mount="$(mktemp -d)"
trap 'hdiutil detach "$mount" >/dev/null 2>&1 || true; rm -rf "$stage" "$mount"' EXIT
ditto "$app" "$stage/CodexMac.app"
ln -s /Applications "$stage/Applications"
hdiutil create -ov -volname CodexMac -fs HFS+ -srcfolder "$stage" -format UDZO dist/CodexMac.dmg
hdiutil verify dist/CodexMac.dmg
hdiutil attach -readonly -nobrowse -mountpoint "$mount" dist/CodexMac.dmg
codesign --verify --deep --strict "$mount/CodexMac.app"
(cd dist && shasum -a 256 CodexMac.dmg > SHA256SUMS.txt)
