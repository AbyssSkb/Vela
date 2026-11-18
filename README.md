<p align="center">
  <img src="assets/branding/vela-icon.png" width="96" height="96" alt="Vela icon">
</p>

<h1 align="center">Vela</h1>

<p align="center"><strong>Share files and clipboard across your devices.</strong></p>
<p align="center">Pair your devices. Choose what to send. Keep going.</p>

<p align="center">
  English · <a href="README.zh-CN.md">简体中文</a><br>
  <a href="#try-vela">Try Vela</a> · <a href="docs/user-guide.md">User guide</a> · <a href="CONTRIBUTING.md">Contribute</a>
</p>

Vela connects your personal devices to share files, folders, text, and clipboard content without an account. Pair once, keep Vela available in the background, and choose what to send. Built with Flutter, Rust, and [Iroh](https://www.iroh.computer/).

**First public preview:** [v0.1.0-beta.2](https://github.com/AbyssSkb/Vela/releases/tag/v0.1.0-beta.2) is available for Android, macOS, Windows, and Linux. CI, package builds, and Windows/Linux startup checks passed. Cross-device transfers, background behavior, and upgrades still need release testing on real hardware.

## What you can do

- **Send files and folders.** Select multiple files, or package a folder and restore it on the receiving device. See progress and speed, and cancel a transfer in flight.
- **Share your clipboard.** Explicitly send text, an image, or a single file. You can also type a message or send a link.
- **Use familiar sharing actions.** Send from other Android and macOS apps, or drag files into Vela on desktop.
- **Keep trusted devices close.** Pair by device code or scan a QR code on Android. View paired devices as a list or a graph, and revoke trust by removing a device.
- **Receive in the background.** Enable Android's receiver, use the Mac menu bar, or leave Windows/Linux running in the system tray. Incoming transfers ask for approval by default; automatic acceptance is optional.
- **Keep Vela updated.** Release builds check and download verified updates automatically. You choose when to install; active transfers and pairing must finish first.
- **Find what you received.** Search local history, open received files and links, and choose where files are saved. The interface supports English and Simplified Chinese.

## Try Vela

### Installation packages

Download **v0.1.0-beta.2**: [release notes](https://github.com/AbyssSkb/Vela/releases/tag/v0.1.0-beta.2) · [SHA256 checksums](https://github.com/AbyssSkb/Vela/releases/download/v0.1.0-beta.2/SHA256SUMS).

| Platform | Architecture | Download |
| --- | --- | --- |
| macOS | Apple Silicon (ARM64) | [DMG](https://github.com/AbyssSkb/Vela/releases/download/v0.1.0-beta.2/Vela-0.1.0-beta.2-macos-arm64.dmg) |
| macOS | Intel (x64) | [DMG](https://github.com/AbyssSkb/Vela/releases/download/v0.1.0-beta.2/Vela-0.1.0-beta.2-macos-x64.dmg) |
| Windows | x64 | [EXE installer](https://github.com/AbyssSkb/Vela/releases/download/v0.1.0-beta.2/Vela-0.1.0-beta.2-windows-x64-setup.exe) |
| Linux | x64 | [AppImage](https://github.com/AbyssSkb/Vela/releases/download/v0.1.0-beta.2/Vela-0.1.0-beta.2-linux-x64.AppImage) |
| Android | ARM64 | [APK](https://github.com/AbyssSkb/Vela/releases/download/v0.1.0-beta.2/Vela-0.1.0-beta.2-android-arm64.apk) |

The [Installation packages workflow](https://github.com/AbyssSkb/Vela/actions/workflows/build.yml) also provides development snapshots retained for seven days, with automatic updates disabled. Android preview APKs use a debug key and cannot be upgraded in place to the public release key. Zero-cost desktop builds are not Apple-notarized or Windows Authenticode-signed; follow the installation and verification notes for the version you download. See [release setup](docs/releasing.md).

### Build from source

Use **Flutter 3.47.9 / Dart 3.13.7** and **Rust 1.98.1**, the development toolchain used for this project. Install Flutter from the [SDK archive](https://docs.flutter.dev/install/archive) and Rust with [rustup](https://rustup.rs/).

| Target | Additional requirements |
| --- | --- |
| macOS | macOS 12+, Xcode with command line tools, CocoaPods |
| Android | Android SDK and NDK, JDK 17, a connected phone or emulator |
| Windows | Windows x64, Visual Studio desktop C++ tools and CMake |
| Linux | Linux x64, Clang/CMake/Ninja, GTK 3, libsecret, libnotify, Ayatana AppIndicator development packages |

From the project root:

```sh
flutter pub get --enforce-lockfile
flutter run -d macos
```

On Windows or Linux, use `flutter run -d windows` or `flutter run -d linux` on that OS. For Android, use `flutter devices` to find your device, then `flutter run -d <device-id>`. The Rust library builds through the included Cargokit integration.

For limited local disk space, use the GitHub workflows for full builds and tests. The [contributing guide](CONTRIBUTING.md) includes lightweight local checks. Update-enabled builds require the release configuration in [releasing.md](docs/releasing.md).

### Make your first transfer

1. Open Vela on both devices. On one, choose **Show my QR code** on the empty home screen, or **This device** in the toolbar or menu.
2. Choose **Add device** on the other device and enter that code, or scan the QR code on Android. Verify the code through a trusted channel and approve the pairing request.
3. Choose a file, folder, text, or clipboard sharing action, then follow the prompts to select content and, if needed, a receiving device.
4. Approve the incoming transfer on the receiver. Received files go to Downloads by default; change the destination in settings.

Both apps need to be running and reachable. For background controls and troubleshooting, see the [user guide](docs/user-guide.md).

## Connections and privacy

Vela uses Iroh to attempt direct peer connections, with relay fallback when a direct path cannot be established. The default configuration uses Iroh's public discovery and relay services; custom relays can be configured in settings.

Iroh encrypts traffic between endpoints, including traffic forwarded by a relay. See the [Iroh transport documentation](https://docs.rs/iroh/1.4.1/iroh/#encryption). Vela keeps device identity keys in platform secure storage and pairing records and receive history locally.

## Current scope

- Android, macOS, Windows, and Linux are the current preview targets. iOS is planned after the desktop release work; the browser app is outside this phase.
- Clipboard sharing is manual. It currently supports one file at a time; use file selection for multiple files.
- Folders are transferred as archives and restored manually. Symlinks are rejected; current limits are 16 GiB of uncompressed content, 10,000 entries, and 64 levels of nesting. File batches support up to 100 files.
- Background reception depends on system permissions, tray availability, and power policies. System sleep, process exit, or Android force-stop can interrupt availability; there is no push wake-up service.
- Builds using the older pairing protocol need to pair again. Device identity, received files, and history are retained.

## Help shape Vela

Useful first contributions include testing transfers between platforms, reporting reproducible background or network failures, improving translations, and fixing focused bugs. Start with [CONTRIBUTING.md](CONTRIBUTING.md); issues and pull requests can be written in English or Chinese.

| Resource | Purpose |
| --- | --- |
| [User guide](docs/user-guide.md) | Sharing, background reception, storage, troubleshooting |
| [Contributing](CONTRIBUTING.md) | Development setup, checks, and change guidelines |
| [Release setup](docs/releasing.md) | Remote packages, signing keys, update feeds, and publication |
| [Architecture](docs/architecture.md) · 中文 | Source map, state ownership, and test entry points |
| [Launch checklist](docs/launch-checklist.md) · 中文 | Release blockers and the first public launch |

## License

[MIT](LICENSE). Third-party components retain their own licenses, including the bundled [Cargokit](rust_builder/cargokit/LICENSE).
