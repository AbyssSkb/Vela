<p align="center">
  <img src="assets/branding/vela-icon.png" width="96" height="96" alt="Vela icon">
</p>

<h1 align="center">Vela</h1>

<p align="center"><strong>Share easily between your devices.</strong></p>

<p align="center">
  English · <a href="README.zh-CN.md">简体中文</a><br>
  <a href="#download">Download</a> · <a href="docs/user-guide.md">User guide</a> · <a href="CONTRIBUTING.md">Contribute</a>
</p>

Vela lets you share between your personal devices, even when they run different operating systems. Start in Vela, use the system share menu where available, or drag files into the desktop app.

## Download

Vela is available for Android, macOS, Windows, and Linux. Choose a release with a version number and download the installer for your device. Each release includes installation notes and SHA-256 checksums. [Download Vela](https://github.com/AbyssSkb/Vela/releases)

## Sharing between devices

- **Pair.** Show the device code on one device and enter it on the other. On Android, you can also scan the QR code. Compare the code through a trusted channel, then approve the request on the device showing it. Once paired, you can share again without an account.
- **Send.** Share files, folders, text, or your clipboard. Check the content and destination before sending, then follow the transfer or cancel it.
- **Receive.** The receiving device asks for approval by default. You can enable automatic acceptance in settings. Open **Received** to find files, text, and links. Choose where files are saved in settings.

For background receiving, enable the service on Android, leave Vela in the menu bar on macOS, or keep it running in the system tray on Windows or Linux. [Background receiving setup](docs/user-guide.md#receive-in-the-background)

## Connections and privacy

You can share on the same network or across networks when both devices are running Vela and can reach each other. Vela uses a direct or relayed connection, with encryption between your devices on either path. Pairing records and receive history stay on your device. Identity keys are kept in your system's secure storage.

## Build from source

Install the Flutter and Rust versions listed in the [contributing guide](CONTRIBUTING.md), along with the build tools for your target.

| Target | Build tools |
| --- | --- |
| Android | Android SDK and NDK, JDK 17, a connected device or emulator |
| macOS | macOS 12+, Xcode with command line tools, CocoaPods |
| Windows x64 | Visual Studio desktop C++ tools and CMake |
| Linux x64 | Clang, CMake, Ninja, GTK 3, libsecret, libnotify, and Ayatana AppIndicator development packages |

Install dependencies and list the available devices.

```sh
flutter pub get --enforce-lockfile
flutter devices
```

Run `flutter run -d DEVICE_ID` with a device from the list. Flutter builds the Rust library through Cargokit.

## Contribute

Reports about how Vela works across devices, fixes, and translations are welcome. See the [contributing guide](CONTRIBUTING.md), [architecture](docs/architecture.md), and [release workflow](docs/releasing.md).

## License

[MIT](LICENSE). Third-party components retain their own licenses, including [Cargokit](rust_builder/cargokit/LICENSE).
