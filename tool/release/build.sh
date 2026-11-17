#!/usr/bin/env bash
set -euo pipefail

: "${VERSION:?}" "${BUILD_NUMBER:?}" "${PLATFORM:?}" "${ARCH:?}" "${VELA_UPDATE_REPOSITORY:?}"
mkdir -p dist
case "$PLATFORM/$ARCH" in
  macos/arm64) rust_target=aarch64-apple-darwin ;;
  macos/x64) rust_target=x86_64-apple-darwin ;;
  windows/x64) rust_target=x86_64-pc-windows-msvc ;;
  linux/x64) rust_target=x86_64-unknown-linux-gnu ;;
  android/arm64) rust_target=aarch64-linux-android ;;
  android/x64) rust_target=x86_64-linux-android ;;
  *) printf 'Unsupported package target: %s/%s\n' "$PLATFORM" "$ARCH" >&2; exit 2 ;;
esac
mkdir -p build/release-notices
cargo metadata --locked --format-version 1 --manifest-path rust/Cargo.toml \
  --filter-platform "$rust_target" > build/release-notices-metadata.json
python tool/release/notices.py --metadata build/release-notices-metadata.json --output build/release-notices
cp LICENSE build/release-notices/VELA-LICENSE.txt
cp rust_builder/cargokit/LICENSE build/release-notices/CARGOKIT-LICENSE.txt
update_key="${VELA_UPDATE_PUBLIC_KEY:-}"
if [[ "$PLATFORM/$ARCH" == android/x64 ]]; then update_key=''; fi
defines=(
  "--dart-define=VELA_VERSION=$VERSION"
  "--dart-define=VELA_BUILD_NUMBER=$BUILD_NUMBER"
  "--dart-define=VELA_UPDATE_ARCH=$ARCH"
  "--dart-define=VELA_UPDATE_REPOSITORY=$VELA_UPDATE_REPOSITORY"
  "--dart-define=VELA_UPDATE_PUBLIC_KEY=$update_key"
)

case "$PLATFORM" in
  macos)
    case "$ARCH" in
      arm64) xcode_arch=arm64; excluded_arch=x86_64 ;;
      x64) xcode_arch=x86_64; excluded_arch=arm64 ;;
      *) exit 2 ;;
    esac
    # Flutter's CI build path disables the sandbox; configure only, then use normal Xcode entitlements.
    flutter build macos --release --config-only \
      --build-name="${VERSION%%-*}" --build-number="$BUILD_NUMBER" "${defines[@]}"
    xcode=(xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
      -derivedDataPath "$PWD/build/macos" -destination "platform=macOS,arch=$xcode_arch" \
      "ARCHS=$xcode_arch" "EXCLUDED_ARCHS=$excluded_arch" ONLY_ACTIVE_ARCH=YES \
      COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
      "VELA_UPDATE_PUBLIC_KEY=${VELA_UPDATE_PUBLIC_KEY:-}")
    "${xcode[@]}" build
    bash packaging/macos/package.sh
    if [[ "$ARCH" == arm64 ]]; then
      # Testability rebuilds happen after packaging, keeping test flags out of shipped binaries.
      "${xcode[@]}" test -only-testing:RunnerTests ENABLE_TESTABILITY=YES
    fi
    ;;
  windows)
    if ! flutter build windows --release "${defines[@]}"; then
      cmake --install build/windows/x64 --config Release --verbose || true
      exit 1
    fi
    for dll in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do
      test -s "build/windows/x64/runner/Release/$dll"
    done
    mkdir -p build/windows/x64/runner/Release/third_party_notices
    cp build/release-notices/* build/windows/x64/runner/Release/third_party_notices/
    MSYS_NO_PATHCONV=1 '/c/Program Files (x86)/Inno Setup 6/ISCC.exe' \
      "/DAppVersion=$VERSION" "/DAppVersionNumeric=${WINDOWS_VERSION:?}" \
      "/DBundleDir=$(cygpath -w "$PWD/build/windows/x64/runner/Release")" \
      "/DOutputDir=$(cygpath -w "$PWD/dist")" "$(cygpath -w "$PWD/packaging/windows/vela.iss")"
    cmake --build build/windows/x64 --config Release --target vela_updater_test
    build/windows/x64/runner/Release/vela_updater_test.exe
    ;;
  linux)
    flutter build linux --release "${defines[@]}"
    python3 linux/runner/updater_helper_test.py build/linux/x64/release/bundle/vela_update_helper
    bash packaging/linux/package.sh
    ;;
  android)
    case "$ARCH" in
      arm64) android_target=android-arm64 ;;
      x64) android_target=android-x64 ;;
      *) exit 2 ;;
    esac
    mkdir -p android/app/src/main/assets/third_party_notices
    cp build/release-notices/* android/app/src/main/assets/third_party_notices/
    flutter build apk --release --target-platform "$android_target" "${defines[@]}"
    suffix=''
    if [[ "${VELA_PREVIEW_BUILD:-true}" == true ]]; then suffix=-preview; fi
    if [[ "$ARCH" == x64 ]]; then suffix=-test; fi
    cp build/app/outputs/flutter-apk/app-release.apk "dist/Vela-$VERSION-android-$ARCH$suffix.apk"
    signer=$(find "$ANDROID_HOME/build-tools" -name apksigner -type f | sort -V | tail -n 1)
    "$signer" verify "dist/Vela-$VERSION-android-$ARCH$suffix.apk"
    if [[ "$ARCH" == arm64 ]]; then
      (cd android && ./gradlew -Pandroid.onlyEnableUnitTestForTheTestedBuildType=false \
        "-Ptarget-platform=$android_target" :app:testReleaseUnitTest)
    fi
    ;;
  *) printf 'Unsupported package platform: %s\n' "$PLATFORM" >&2; exit 2 ;;
esac
git diff --exit-code -- pubspec.lock
