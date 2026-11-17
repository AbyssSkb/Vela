#!/usr/bin/env bash
set -euo pipefail

: "${VERSION:?Set VERSION to the application version}"
: "${ARCH:?Set ARCH to arm64 or x64}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
[[ "$ARCH" == arm64 || "$ARCH" == x64 ]] || { echo 'Unsupported macOS architecture' >&2; exit 1; }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
app="${1:-$repo/build/macos/Build/Products/Release/Vela.app}"
[[ -d "$app/Contents/MacOS" ]] || { echo "Missing built application: $app" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || { echo 'Package on a macOS runner' >&2; exit 1; }

stage="$(mktemp -d "${TMPDIR:-/tmp}/vela-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$repo/dist"
ditto "$app" "$stage/Vela.app"
app="$stage/Vela.app"
notices="$app/Contents/Resources/ThirdPartyNotices"
mkdir -p "$notices"
cp "$repo"/build/release-notices/* "$notices/"
sparkle_found=false
for license in "$repo"/build/macos/SourcePackages/checkouts/[Ss]parkle/LICENSE*; do
  if [[ -f "$license" ]]; then
    cp "$license" "$notices/Sparkle-${license##*/}"
    sparkle_found=true
  fi
done
[[ "$sparkle_found" == true ]] || { echo 'Missing Sparkle license in the resolved Swift package checkout' >&2; exit 1; }

# Seal nested code before its containing bundle; keep each helper's entitlements.
while IFS= read -r -d '' binary; do
  if /usr/bin/file -b "$binary" | grep -q 'Mach-O'; then
    codesign --force --sign - --preserve-metadata=identifier,entitlements,flags "$binary"
  fi
done < <(find "$app/Contents" -type f -print0)
while IFS= read -r -d '' bundle; do
  codesign --force --sign - --preserve-metadata=identifier,entitlements,flags "$bundle"
  codesign --verify --strict "$bundle"
done < <(find "$app/Contents" -depth -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o -name '*.appex' \) -print0)
codesign --force --sign - --entitlements "$repo/macos/Runner/Release.entitlements" "$app"
codesign --verify --strict "$app"

ditto -c -k --rsrc --extattr --keepParent "$app" "$repo/dist/Vela-$VERSION-macos-$ARCH.zip"
cp "$repo/LICENSE" "$stage/LICENSE.txt"
cp "$repo/rust_builder/cargokit/LICENSE" "$stage/Cargokit-LICENSE.txt"
ln -s /Applications "$stage/Applications"
hdiutil create -volname Vela -srcfolder "$stage" -ov -format UDZO "$repo/dist/Vela-$VERSION-macos-$ARCH.dmg"
