# Contributing to Vela

[简体中文](CONTRIBUTING.zh-CN.md)

You can help by testing a device combination, reproducing a problem, improving a translation, or fixing a bug. Issues and pull requests are welcome in English and Chinese.

## Report a problem

Search existing issues, then use the bug report form. Include enough detail for someone with the same devices to reproduce it. [Open an issue](https://github.com/AbyssSkb/Vela/issues/new/choose)

- Give the Vela version, device model, and operating system on both ends.
- Explain what you tried, what you expected, and what happened.
- For connection and background issues, include the send direction, network or VPN, and whether each app was open, in the background, or waking from sleep. On Android, include the manufacturer and relevant battery settings.
- Remove device codes, QR codes, credentials, IP addresses, personal paths, and content from logs and screenshots. Send security vulnerabilities through the private reporting channel. [Security policy](SECURITY.md)

## Set up

Use Flutter **3.47.9** with Dart **3.13.7**, and Rust **1.98.1**, matching CI. Install Flutter from the SDK archive and Rust through rustup. [Flutter SDK archive](https://docs.flutter.dev/install/archive) · [rustup](https://rustup.rs/)

| Target | Build requirements |
| --- | --- |
| Android | Android SDK and NDK, JDK 17, a connected device or emulator |
| macOS | macOS 12 or later, Xcode and its command-line tools, CocoaPods |
| Windows x64 | Visual Studio desktop C++ tools and CMake |
| Linux x64 | Clang, CMake, Ninja, GTK 3, libsecret, libnotify, and Ayatana AppIndicator development packages |

In the repository root, fetch dependencies and list devices.

```sh
flutter pub get --enforce-lockfile
flutter devices
```

Run `flutter run -d DEVICE_ID` with an ID from the list. Build Windows, Linux, and macOS targets on their respective operating systems. Cargokit builds the Rust library as part of the Flutter build. [Architecture and test entry points](docs/architecture.md)

### iPhone and iPad preview

The iOS runner targets foreground pairing and transfers with iOS and iPadOS 15 or later. To build on a Mac with the iOS simulator tools installed, run `flutter build ios --simulator --debug`. Xcode signs the simulator build locally so Vela can access Keychain. For personal device testing, open `ios/Runner.xcworkspace` in Xcode and select your Personal Team and a unique bundle identifier. Free device provisioning expires after seven days. The simulator workflow checks startup on an iPad without a signing account. [Apple developer accounts](https://developer.apple.com/help/account/basics/about-your-developer-account)

### Local signing on macOS

Ad-hoc development builds can trigger a fresh Keychain prompt after rebuilding. To keep a stable local identity, add the following to `macos/Runner/Configs/LocalSigning.xcconfig` and substitute the certificate fingerprint.

```xcconfig
VELA_CODE_SIGN_IDENTITY = certificate SHA-1 fingerprint
VELA_CODE_SIGN_STYLE = Manual
```

The app and share extension use this identity for development builds. Git ignores the config file. Keep the private key in Keychain.

## Make a change

Discuss changes to protocols, platform support, or large features in an issue first. Use one pull request per logical change. Include a focused regression test when behavior changes, and keep user data, pairing consent, cancellation, and trust revocation intact. [English PR template](.github/pull_request_template.md) · [Chinese PR template](.github/pull_request_template.zh-CN.md)

- Maintain project documentation in English and Simplified Chinese. Use the default filename for English and add `.zh-CN` to the translation's filename. Update both versions together.
- Edit strings in `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb`, then run `flutter gen-l10n`.
- For Rust bridge changes, edit the Rust API and regenerate with `flutter_rust_bridge_codegen` **2.13.0** and `flutter_rust_bridge.yaml`. The generated files are in `lib/src/rust/` and `rust/src/frb_generated.rs`.
- Include lockfile changes with intentional dependency changes. Keep local configs, signing keys, device identities, relay credentials, and received files outside commits.

## Verify

Start with `git diff --check` and the checks that cover your change. The commands below use installed tools and avoid native builds.

```sh
dart --disable-dart-dev tool/check_core_contracts.dart
dart format --output=none --set-exit-if-changed lib test test_driver tool
cargo fmt --manifest-path rust/Cargo.toml --check
python3 -m unittest discover -s tool/release -p 'test_*.py'
python3 -m unittest discover -s packaging/linux -p 'test_*.py'
```

Use GitHub for full Flutter analysis, Flutter and Rust tests, and installation packages. Flutter tests use mock Rust and platform interfaces. For changes to system sharing, sleep, background receiving, updates, or networking, include the actual device checks you ran and their results. The two-instance debug drivers in `test_driver/` can change the system clipboard. [CI](https://github.com/AbyssSkb/Vela/actions/workflows/ci.yml) · [Installation packages](https://github.com/AbyssSkb/Vela/actions/workflows/build.yml) · [External relay tests](.github/workflows/relay-tests.yml)

## Release changes

Check update behavior with a signed package when a change affects release or installation. Review identity and file retention, busy-state gating, and rejection of tampered packages. The release guide covers signing, drafts, and update feeds. [Release guide](docs/releasing.md)

Contributions use the project's [MIT license](LICENSE).
