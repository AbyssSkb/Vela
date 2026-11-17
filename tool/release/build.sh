#!/usr/bin/env bash
set -euo pipefail

: "${VERSION:?}" "${BUILD_NUMBER:?}" "${PLATFORM:?}" "${ARCH:?}" "${VELA_UPDATE_REPOSITORY:?}"
mkdir -p dist
defines=(
  "--dart-define=VELA_VERSION=$VERSION"
  "--dart-define=VELA_BUILD_NUMBER=$BUILD_NUMBER"
  "--dart-define=VELA_UPDATE_ARCH=$ARCH"
  "--dart-define=VELA_UPDATE_REPOSITORY=$VELA_UPDATE_REPOSITORY"
  "--dart-define=VELA_UPDATE_PUBLIC_KEY=${VELA_UPDATE_PUBLIC_KEY:-}"
)

case "$PLATFORM" in
  macos)
    case "$ARCH" in
      arm64) xcode_arch=arm64; excluded_arch=x86_64 ;;
      x64) xcode_arch=x86_64; excluded_arch=arm64 ;;
      *) exit 2 ;;
    esac
    # Flutter's CI build path disables the sandbox; configure only, then use normal Xcode entitlements.
    flutter build macos --release --no-pub --config-only "${defines[@]}"
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
    flutter build windows --release --no-pub "${defines[@]}"
    '/c/Program Files (x86)/Inno Setup 6/ISCC.exe' \
      "/DAppVersion=$VERSION" "/DAppVersionNumeric=${WINDOWS_VERSION:?}" \
      "/DBundleDir=$(cygpath -w "$PWD/build/windows/x64/runner/Release")" \
      "/DOutputDir=$(cygpath -w "$PWD/dist")" packaging/windows/vela.iss
    cmake --build build/windows/x64 --config Release --target vela_updater_test
    build/windows/x64/runner/Release/vela_updater_test.exe
    ;;
  linux)
    flutter build linux --release --no-pub "${defines[@]}"
    python3 linux/runner/updater_helper_test.py build/linux/x64/release/bundle/vela_update_helper
    bash packaging/linux/package.sh
    ;;
  android)
    case "$ARCH" in
      arm64) android_target=android-arm64 ;;
      x64) android_target=android-x64 ;;
      *) exit 2 ;;
    esac
    flutter build apk --release --no-pub --target-platform "$android_target" "${defines[@]}"
    suffix=''
    if [[ "${VELA_PREVIEW_BUILD:-true}" == true ]]; then suffix=-preview; fi
    if [[ "$ARCH" == x64 ]]; then suffix=-test; fi
    cp build/app/outputs/flutter-apk/app-release.apk "dist/Vela-$VERSION-android-$ARCH$suffix.apk"
    signer=$(find "$ANDROID_HOME/build-tools" -name apksigner -type f | sort -V | tail -n 1)
    "$signer" verify "dist/Vela-$VERSION-android-$ARCH$suffix.apk"
    if [[ "$ARCH" == arm64 ]]; then
      (cd android && ./gradlew testReleaseUnitTest)
    fi
    ;;
  *) printf 'Unsupported package platform: %s\n' "$PLATFORM" >&2; exit 2 ;;
esac
