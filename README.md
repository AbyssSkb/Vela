<p align="center">
  <img src="docs/assets/vela-mark.png" width="96" height="96" alt="">
</p>

<h1 align="center">Vela</h1>

<p align="center"><strong>Share easily between your devices.</strong></p>

<p align="center">
  <a href="#download">Download</a> · <a href="docs/user-guide.md">User guide</a> · <a href="README.zh-CN.md">简体中文</a>
</p>

Vela is an open-source app for sharing between your own devices, even across operating systems and networks. Send a photo from your phone to your computer, a folder from one computer to another, or a link you just copied. Once paired, either device can send or receive. No account required.

## Download

Open a release with a version number and choose the package for each device. The release page includes installation notes and SHA-256 checksums. [Download Vela on GitHub](https://github.com/AbyssSkb/Vela/releases)

| Platform | Package |
| --- | --- |
| Android | APK for ARM64 |
| macOS | DMG for Apple silicon or Intel |
| Windows | Setup EXE for x64 |
| Linux | AppImage for x64 |

[Installation guide](docs/user-guide.md#install-a-build)

## Pair once, then send

1. Open Vela on both devices. Choose **Show device code** on one and **Add device** on the other. Enter the code or scan the QR code on Android, then choose **Connect**. Compare the requesting device’s code through a trusted channel. Approve the pairing on the device that showed its code.
2. Select what to send and choose the recipient. You can start in Vela, use the system share menu on Android or macOS, or drop files into the desktop app.
3. The receiving device asks you to approve each transfer. Find what arrived under **Received**. To accept transfers from paired devices automatically, enable **Auto accept** in Settings.

To receive while using other apps, enable background receiving on Android or keep Vela running in the menu bar or system tray on desktop. [Background receiving setup](docs/user-guide.md#receive-in-the-background)

## How devices connect

Choose the same paired device whether it’s on your network or another. Both devices need to be running Vela and able to reach each other. Vela establishes a direct connection when it can and uses a relay when needed. Content is encrypted between the devices on either path.

Pairing records and receive history are stored on each device. Remove a device from your list to revoke the pairing. Vela uses public Iroh relays by default, and you can configure your own in Settings. [Connection troubleshooting](docs/user-guide.md#troubleshooting)

## Contribute

You can help by reporting how transfers behave on your devices, improving translations, or submitting a fix. [Contributing guide and build instructions](CONTRIBUTING.md)

## License

[MIT](LICENSE). [Cargokit](rust_builder/cargokit/LICENSE) is distributed under its own license.
