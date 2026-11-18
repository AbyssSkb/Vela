# Using Vela

[English overview](../README.md) · [中文说明](../README.zh-CN.md)

Vela shares content between paired Android, macOS, Windows, and Linux devices. Keep both apps running and reachable while pairing and transferring. Windows/Linux are new preview targets; check the current [build results](https://github.com/AbyssSkb/Vela/actions) and the notes on the version you install.

## Install a build

Published installers are listed in [Releases](https://github.com/AbyssSkb/Vela/releases); choose a versioned release rather than the machine-readable `updates` entry. The [Installation packages workflow](https://github.com/AbyssSkb/Vela/actions/workflows/build.yml) also produces temporary development previews, retained for seven days. Those previews disable automatic updates; Android previews use debug signing.

Choose the package matching your OS and CPU. On macOS, install the app from the DMG into a writable Applications location before updating. Windows uses a current-user installer. On Linux, keep the AppImage in a writable, stable location and make it executable; moving it later can invalidate its login-startup entry. Linux requires a desktop session with a Secret Service keyring for identity storage, and tray/notification support varies by desktop environment.

The current desktop distribution uses zero-cost signing and is not Apple-notarized or Authenticode-signed. Follow the release's system-specific installation notes; do not disable system security globally. Verify the published SHA-256 checksum before first use.

An Android debug/preview install and the signed public install use different keys. Android cannot overwrite one with the other: save received files before uninstalling a preview to install the public version. Uninstalling can remove local identity, pairings, and history. Subsequent public releases must retain the same package ID and signing key.

## Pair devices

1. On one device, choose **Show my QR code** on the empty home screen, or **This device** from the toolbar or menu.
2. Choose **Add device** on the other device and enter that code. Android can also scan the QR code.
3. Verify the code through a trusted channel and approve the request on the device displaying its code.

Paired devices retain their names and types. The device area adapts to available space and can display a list or a graph. Use the desktop selection button, or long-press a device on mobile, to enter multi-selection.

Removing a device immediately revokes local trust and closes related connections. When the peer reconnects with online monitoring enabled, it can learn that trust was revoked; an unreachable peer is shown as offline. Versions using the previous pairing protocol must pair again after upgrading, while retaining device identity, received files, and history.

## Send content

| Source | Behavior |
| --- | --- |
| Files | Select one or more files; a batch supports up to 100 files |
| Folder | Packages a folder into a `.vela-folder.zip` archive; restore it manually after receiving |
| Clipboard | Explicitly sends text, an image, or one file; multiple clipboard files are not supported |
| Text | Type a message or link; receiving typed text does not automatically replace the clipboard |
| Android photos and videos | Uses the system photo picker for multi-selection, without whole-library access |
| System share menu | Choose Vela from another app on Android or macOS |
| Desktop drag and drop | Drop files into Vela on macOS, Windows, or Linux |

Choose a sharing action and select the content. If several devices are paired, Vela shows what will be sent and each device's current connection status before you choose a recipient. With one paired device, Vela selects it automatically. Going back from the recipient picker keeps typed text in the editor. If a transfer fails, retry with the same prepared content or discard it from the home screen.

Incoming transfers request approval by default; settings include optional automatic acceptance. Transfers show progress and speed and can be cancelled.

Received files and images are offered to the system clipboard, although paste support depends on the destination app. Received HTTP(S) links can be opened in a browser.

Folder archives support at most 16 GiB of uncompressed content, 10,000 entries, and 64 levels of nesting. Symlinks are rejected. The app currently allows one active transfer per node.

## Receive in the background

### Android

Enable background reception in settings. Vela runs a foreground service with a persistent notification and holds a CPU wake lock. The background settings page shows notification permissions, battery restrictions, autostart controls where available, and node initialization status.

Incoming requests can be accepted or declined in notifications. Active transfers show progress notifications. Systems supporting live updates may promote them to a status-bar capsule; presentation depends on the OS and notification settings.

Vela attempts to restore the enabled service after a reboot and unlock. Vendor restrictions, power-saving policies, and force-stop can still interrupt reception. Background reception increases power use; turn it off when unnecessary. There is no push wake-up service.

### macOS

Closing the window leaves Vela running in the menu bar. Choose **Quit** to end the process.

The optional background availability setting prevents idle system sleep while allowing the display to turn off. It can increase power use and does not prevent lid-close or manual sleep from interrupting connectivity. On macOS 13+, login-at-start is a separate setting and requires any approval requested by macOS.

### Windows and Linux

Background receiving keeps Vela in the system tray after closing its window. Open the tray menu to restore the window or choose **Quit** to stop the process. Settings include separate background-reception and login-startup controls. If no usable tray is available, closing the window quits through the normal shutdown flow instead of hiding an inaccessible app.

Incoming notifications open Vela so you can approve a transfer. Desktop release builds restore the existing instance on a second launch. Sleep, logout, or quitting stops reception; the tray setting does not prevent system sleep. Linux tray and notification behavior must be tested in the desktop environment you use.

## Update Vela

Update-enabled releases check at startup and every 12 hours, download in the background, and show their state under **Settings → App updates**. You can also check there manually. Installation requires confirmation and remains unavailable while a transfer, folder operation, or pairing is active.

All platforms verify a signed update manifest and download the candidate before installation. After your installation confirmation, macOS hands the cached ZIP to Sparkle for verification and replacement; Sparkle does not stage an update before that confirmation. Windows runs the verified EXE after orderly shutdown. Linux replaces a complete verified AppImage through its helper; a read-only location must be moved before updating. Android launches the system installer and may ask you to allow Vela to install apps, then asks for installation confirmation.

Update manifests and payloads are checked against the public key bundled in the application, with size and content checks for downloaded packages. Failed verification leaves the installed version in place. Keep the current installation until the update succeeds; upgrades are designed to preserve identity, paired devices, history, and received files. Actual old-to-new upgrades remain part of release acceptance testing.

Source/development builds without release configuration display **Updates are unavailable in this build**. They can still share content. Maintainers configure keys, versions, and update feeds through [releasing.md](releasing.md).

## Files and local data

- Received files default to Downloads. Change the destination in settings.
- Search received history to find text, files, and links. Deleting a history entry can optionally delete its received file.
- Device identity keys and relay credentials use platform secure storage. Paired-device records, history, and ordinary settings remain local.
- Vela attempts direct peer connections and falls back to relays. The default setup uses public Iroh discovery and relay infrastructure. Custom relays can be configured in settings; when custom relays are enabled with a nonempty list, that list replaces the default relays.

Iroh encrypts endpoint traffic even when relayed; this protects content in transit. See [Iroh's transport documentation](https://docs.rs/iroh/1.4.1/iroh/#encryption).

## Troubleshooting

| Symptom | Check first |
| --- | --- |
| Cannot pair | Use matching current versions, verify the device code, keep both apps open, and confirm the request on the other device |
| Device appears offline | Check that the peer is running, its node initialized successfully, and its network is reachable; inspect any custom-relay configuration |
| Android stops receiving in the background | Check the background page for service, notification, battery, and autostart status; a force-stopped app must be opened again |
| Mac stops receiving | Check whether Vela was quit or the Mac entered system sleep |
| Windows/Linux stops receiving | Check that Vela is still running, tray support is available, and the computer has not slept or logged out |
| Received file cannot be found | Check the configured save location and the receive-history entry |
| Cannot paste received content | Check that the destination app accepts that clipboard content type; use the saved file instead |
| Folder is rejected | Check archive size, entry count, nesting depth, and symlinks |
| AppImage cannot update | Move it to a writable location and check the update again |
| Android update asks for permission | Allow app installation for Vela when prompted, then retry; Android still confirms installation |

For a bug report, include both device models, OS and app versions, transfer direction, network conditions, foreground/background state, and reproducible steps. Remove device codes, QR codes, relay credentials, personal paths, and content from logs and screenshots before sharing them. See [CONTRIBUTING.md](../CONTRIBUTING.md).

## Local development signing on Mac

The default macOS build uses ad-hoc signing, which may trigger renewed Keychain prompts after rebuilding. For a stable local development identity, create `macos/Runner/Configs/LocalSigning.xcconfig`:

```xcconfig
VELA_CODE_SIGN_IDENTITY = certificate SHA-1 fingerprint
VELA_CODE_SIGN_STYLE = Manual
```

Runner and the share extension use this identity during normal builds. This file is ignored by Git. Keep the private key in Keychain; a local self-signed certificate is not a public distribution signature.
