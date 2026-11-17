#!/usr/bin/env bash
set -euo pipefail

: "${VERSION:?Set VERSION to the application version}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
[[ "${ARCH:-x64}" == x64 ]] || { echo 'Unsupported Linux architecture' >&2; exit 1; }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
bundle="${1:-$repo/build/linux/x64/release/bundle}"
[[ -x "$bundle/vela" && -d "$bundle/data" && -d "$bundle/lib" ]] || { echo "Missing built bundle: $bundle" >&2; exit 1; }
[[ "$(uname -s)" == Linux ]] || { echo 'Package on a Linux runner' >&2; exit 1; }

stage="$(mktemp -d "${TMPDIR:-/tmp}/vela-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
appdir="$stage/Vela.AppDir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/icons/hicolor/256x256/apps" "$appdir/usr/share/doc/vela" "$repo/dist"
cp -a "$bundle/." "$appdir/usr/bin/"
cp "$repo/LICENSE" "$appdir/usr/share/doc/vela/LICENSE"
cp "$repo/rust_builder/cargokit/LICENSE" "$appdir/usr/share/doc/vela/Cargokit-LICENSE"
mkdir -p "$appdir/usr/share/doc/vela/third-party-notices"
cp "$repo"/build/release-notices/* "$appdir/usr/share/doc/vela/third-party-notices/"
convert "$repo/assets/branding/vela-icon.png" -resize 256x256 "$appdir/usr/share/icons/hicolor/256x256/apps/io.github.abyssskb.vela.png"

fetch() {
  local url="$1" checksum="$2" output="$3"
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$url" -o "$output"
  printf '%s  %s\n' "$checksum" "$output" | sha256sum --check --status
  chmod +x "$output"
}

# Pins come from the upstream release asset digests; downloads happen only on CI.
fetch 'https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage' \
  c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d "$stage/linuxdeploy"
fetch 'https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage' \
  ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0 "$stage/appimagetool"
curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
  -H 'Accept: application/octet-stream' \
  -H "Authorization: Bearer ${GH_TOKEN:?Set a read-only GitHub token for the pinned runtime asset}" \
  'https://api.github.com/repos/AppImage/type2-runtime/releases/assets/657374641' -o "$stage/runtime-x86_64"
printf '%s  %s\n' 617aa77314d57c8b8e4fae9c3f0b35af7b30d5529cb69e98f64f92510ed98a46 "$stage/runtime-x86_64" | sha256sum --check --status
fetch 'https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/7a3fbc31a9e5075073ff8790f26effbac5f84453/linuxdeploy-plugin-gtk.sh' \
  b0f4cbc684a0103a9651f0955b635eaea0096b3a66c0f5a2c2aa337960375171 "$stage/linuxdeploy-plugin-gtk.sh"

export APPIMAGE_EXTRACT_AND_RUN=1 DEPLOY_GTK_VERSION=3
export PATH="$stage:$PATH"
"$stage/linuxdeploy" --appdir "$appdir" \
  --executable "$appdir/usr/bin/vela" \
  --desktop-file "$repo/packaging/linux/vela.desktop" \
  --icon-file "$appdir/usr/share/icons/hicolor/256x256/apps/io.github.abyssskb.vela.png" \
  --plugin gtk
# Respect the user's Wayland/X11 selection instead of the GTK plugin's forced X11.
sed -i '/^export GDK_BACKEND=x11 /d' "$appdir/apprun-hooks/linuxdeploy-plugin-gtk.sh"
export ARCH=x86_64
"$stage/appimagetool" --no-appstream --runtime-file "$stage/runtime-x86_64" \
  "$appdir" "$repo/dist/Vela-$VERSION-linux-x64.AppImage"
