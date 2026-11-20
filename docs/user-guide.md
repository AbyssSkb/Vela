# Vela user guide

[简体中文](user-guide.zh-CN.md) · [Project overview](../README.md)

## Install a build

Download the package for your device from a versioned release. The release page lists the installers, installation notes, and SHA-256 checksums. [Download Vela](https://github.com/AbyssSkb/Vela/releases)

| Platform | Install |
| --- | --- |
| Android | Open the ARM64 APK and follow the system prompts. If you are switching from a debug-signed build, save received files before uninstalling it. Uninstalling can remove your app-local identity, pairings, and history. |
| macOS | Open the DMG for Apple silicon or Intel and copy Vela into a writable Applications folder. Follow the release notes for the system's first-open prompt. |
| Windows | Run the x64 setup EXE to install Vela for your user account. |
| Linux | Make the x64 AppImage executable and keep it in a writable location. Vela uses the desktop's Secret Service keyring for device identity. Keep the AppImage at the same path if you enable launch at login. |

The installation workflow also provides seven-day development previews. They use debug signing on Android and have app updates disabled. [Development builds](https://github.com/AbyssSkb/Vela/actions/workflows/build.yml)

## Pair devices

1. Open Vela on both devices. On one device, choose **Device code**.
2. On the other device, choose **Add device** and enter the code, or scan the QR code on Android. Choose **Connect**.
3. Compare the requesting device's code through a trusted channel. Approve the request on the device displaying its code.

Vela opens in the list on narrow screens and the graph in a wide, tall window. Use the toolbar to switch views. You can give a device a local alias. Removing a device revokes trust on this device and closes its existing connections. A peer with online monitoring enabled can learn about the removal when it reconnects.

If you upgrade from a build that used the previous pairing protocol, pair the devices again. The upgrade preserves device identity, received files, and history.

## Send content

Start in Vela, choose Vela from the system share menu on Android or macOS, or drop files into the desktop app.

On Android, choose **Vela** from a file's **Open with** menu or from the actions shown for selected text, then pick a device. If a document provider offers an export format for a virtual file, Vela can send that export. To send a folder, use **Folder** inside Vela.

On Android 10 and later, the system share menu can suggest paired Vela devices. Choose a device shortcut to send from your current app and follow progress in Android notifications. Choose the Vela app entry to pick a device. If background sending is unavailable, Vela opens so you can continue.

| What you want to send | Choose |
| --- | --- |
| One file or a batch | **Files**. A batch supports up to 100 files. |
| A folder | **Folder**. Vela packages the folder for the receiver to restore. |
| A message or link | **Text**. Going back from the recipient picker keeps the draft. |
| Your current clipboard | **Clipboard**. Supports text, an image, or one file. |
| Photos or videos on Android | **Photos**. Select items in the system photo picker. |

Check the destination before sending. If device names match, Vela adds a code to distinguish them. The recipient picker also shows the connection status and offers **Review content** for items such as a file batch or clipboard share.

Vela handles one transfer at a time. In Vela, you can watch progress or cancel the transfer. The send result briefly appears at the bottom of the screen. After a failure you can retry with the same content, choose another device, or discard the send.

## Receive and find content

The receiving device asks for approval by default. You can enable automatic acceptance in **Settings → Receiving**.

- **Files and links.** Open **Received** to find what arrived. Files go to Downloads by default. Change the destination in settings or choose **Copy files** in a received record when you want to paste files into another app.
- **Clipboard.** An accepted clipboard share replaces the receiving device's clipboard, including when automatic acceptance is on. You can also find the content in **Received**. Typed messages remain in history and leave the clipboard as it is.
- **Folders.** Open the received `.vela-folder.zip` record and choose **Restore folder** yourself. A folder archive supports up to 16 GiB uncompressed, 10,000 entries, and 64 levels of nesting. Use regular files and directories within the folder.
- **Remove a record.** Select the entries in **Received**, including from search results. You can clear a record and keep its file, or delete both.

## Receive in the background

Open **Settings → Receiving** to check whether this device is ready and to find the relevant system settings.

| Platform | Keep Vela available |
| --- | --- |
| Android | Enable **Allow background receiving**. The receiving service shows a persistent notification. You can accept or decline requests from notifications. Vela tries to restore the enabled service after reboot and unlock. If the system stops it, reopen Vela and check notification and battery settings. |
| macOS | Close the window to leave Vela in the menu bar. The optional **Keep available in background** setting prevents idle sleep. Closing the lid and manual sleep still suspend the connection. On macOS 13 or later, you can enable launch at login separately. |
| Windows and Linux | With background receiving enabled and a tray available, closing the window leaves Vela in the system tray. Open or quit it from the tray menu. If the tray is unavailable, keep the window open. Sleep or logout stops reception. |

On supported Android systems, transfer progress may also appear in a status-bar capsule. Keeping a device available in the background can increase power use.

## Update Vela

In an update-enabled release, Vela checks for updates in the background. To check or install manually, open **Settings → About Vela → App updates**. When an update is ready, finish any transfer, pairing, or folder operation before confirming installation.

Vela verifies the signed update and installer before handing off to the system. On Android, follow the system's installation and permission prompts. On Linux, move the AppImage to a writable location if the current one is read-only.

## Connections and local data

Keep Vela running on both devices. You can use the same sharing steps on one network or across networks. Vela connects directly when it can and uses a relay when needed. Traffic is encrypted between the devices on either path. Vela uses Iroh's public discovery and relay services by default. An enabled, nonempty custom relay list in **Settings → Troubleshooting** replaces the default relay list.

Pairings, app settings, and receive history stay on your device. Device identity keys and relay credentials are stored in the system's secure storage.

## Troubleshooting

| Problem | What to try |
| --- | --- |
| Vela won't start | Retry from the error screen or open **Diagnostics** there. |
| Pairing fails | Open Vela on both devices, use matching current versions, and confirm the request on the device displaying the code. |
| A device is temporarily unreachable | Check that Vela is running on the other device and both devices have network access. Refresh device status. If you use custom relays, test the relay from settings. |
| Background requests stop | Check the device's **Receiving** settings. Look at notification permissions and battery restrictions on Android, menu-bar and sleep state on macOS, or tray and sleep state on Windows/Linux. |
| A received file is missing or won't paste | Open its record in **Received**, check the save location, and try opening the saved file. Apps differ in which clipboard types they accept. |
| A folder archive is rejected | Check the uncompressed size, entry count, nesting depth, and whether the folder contains symbolic links. |
| The update can't install | Check app-installation permission on Android or the AppImage location on Linux. Try again from **About Vela**. |

Include both app versions, device models, operating systems, network, and transfer direction in a bug report. Add the steps that reproduce the problem and remove device codes, credentials, and private content from logs or screenshots. [Report a problem](../CONTRIBUTING.md#report-a-problem)
