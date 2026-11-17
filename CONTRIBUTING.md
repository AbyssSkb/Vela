# Contributing to Vela

Vela shares files and clipboard content between paired Android, macOS, Windows, and Linux devices. Useful contributions include reproducible bug reports, real-device testing, translations, and focused fixes. English and Chinese are welcome in issues and pull requests.

## Set up

Use Flutter **3.47.9** (Dart **3.13.7**) and Rust **1.98.1**, the versions used by CI. See the [README](README.md) for platform build requirements and the [architecture guide](docs/architecture.md) for state ownership and test entry points. The architecture guide is currently in Chinese.

```sh
flutter pub get --enforce-lockfile
flutter run -d macos
```

For Android, select the device ID from `flutter devices` with `flutter run -d <device-id>`.
Use `flutter run -d windows` or `flutter run -d linux` on the corresponding desktop OS. Runtime requirements and preview scope are listed in the README.

## Make a change

- Search existing issues before starting. Discuss protocol changes, platform support, and large features in an issue first.
- Keep each pull request focused on one problem. Include a regression test for behavior changes.
- Follow the surrounding code. Preserve user files, cancellation behavior, pairing consent, trust revocation, and identity/history across upgrades.
- Update both [English](README.md) and [Chinese](README.zh-CN.md) READMEs when changing documented behavior. UI strings live in `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb`; run `flutter gen-l10n` after editing them.
- Edit Rust API source and regenerate the bridge with `flutter_rust_bridge_codegen` **2.13.0** and `flutter_rust_bridge.yaml`. Generated files live in `lib/src/rust/` and `rust/src/frb_generated.rs`; do not edit them by hand.
- Commit intentional dependency changes with the relevant lockfile. Keep signing keys, device identities, relay tokens, received files, and local configuration out of commits.

## Verify

Full compilation and test runs belong on GitHub when local disk is limited. [CI](https://github.com/AbyssSkb/Vela/actions/workflows/ci.yml) runs Dart checks/tests on macOS and Rust tests across Linux, macOS, and Windows. The separate [package workflow](https://github.com/AbyssSkb/Vela/actions/workflows/build.yml) builds actual installers on their target OS. A successful unit test is not evidence that an installer or cross-device transfer works.

Lightweight local checks:

```sh
dart --disable-dart-dev tool/check_core_contracts.dart
dart format --output=none --set-exit-if-changed lib test test_driver tool
cargo fmt --manifest-path rust/Cargo.toml --check
python3 -m unittest discover -s tool/release -p 'test_*.py'
python3 -m unittest discover -s packaging/linux -p 'test_*.py'
```

If running checks locally is appropriate for the machine and change:

```sh
dart format --output=none --set-exit-if-changed lib test test_driver tool
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
cargo fmt --manifest-path rust/Cargo.toml --check
cargo test --locked --manifest-path rust/Cargo.toml --lib
```

Analysis reports existing informational lints without failing CI; warnings and errors fail the check. Flutter tests use mock Rust and platform interfaces; several cases are platform-specific. Rust tests cover the native core separately. For system sharing, sleep, background reception, updates, or networking changes, include devices, OS versions, network conditions, and manual results in your pull request. The two-app drivers in `test_driver/` require running debug instances and can change the system clipboard. Desktop release builds use a single instance; debug builds allow driver instances.

`check_core_contracts.dart` verifies content kinds, error codes, and retry cleanup in memory without creating build caches. External relay tests run separately via [relay-tests.yml](.github/workflows/relay-tests.yml); the public test needs network access, while private tests require the configured relay and credentials. Ignored tests must remain distinguishable from passing tests.

## Release changes

Follow [releasing.md](docs/releasing.md). Preview package builds carry no trusted update key and cannot advertise automatic updates. Versioned releases require a durable Android signing key, a pinned update public key, and signed update feeds. Never generate replacement release keys during normal CI runs. Keep installation blocked while transfers or pairing are active; verify old-to-new upgrades and tampered-package rejection.

## Report a problem

Use the bug report form and include the version on **both** devices, exact reproduction steps, and expected and actual behavior. For connection problems, describe Wi-Fi/cellular/VPN use and whether the apps were visible, in the background, or recovering from sleep. For Android background problems, include the device manufacturer and battery restrictions.

Review logs and screenshots before posting: remove device codes, QR codes, IP addresses, file paths, clipboard content, and credentials. Use [SECURITY.md](SECURITY.md) for private vulnerability reports; keep private files out of public issues.

## Work together

Be respectful and specific. Discuss behavior and evidence, assume good intent, and avoid personal attacks or publishing other people's private information. Describe what you checked and any remaining limitations when opening a pull request.

Contributions are provided under the project's [MIT license](LICENSE).
