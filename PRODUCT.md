# Product

<!-- impeccable:product-schema 1 -->

[简体中文](PRODUCT.zh-CN.md)

## Platform

adaptive

## Users

People who want to share easily between their own devices. Every supported combination of devices has equal design priority.

## Product Purpose

Make sharing between personal devices feel as natural and easy as AirDrop, whichever ecosystems the devices come from.

## Positioning

Sharing requires no account. Devices establish trust through pairing. They can connect directly or through a relay, with end-to-end encryption on either path. Pairings and receive history stay on the device. The system's secure storage protects device identity keys.

## Operating Context

- **Pair.** One device shows a code and the other enters it. Devices that support scanning can read the QR code. Users compare the code through a trusted channel before approving the pairing. Removing a device revokes trust locally.
- **Send.** Users can choose content in Vela, hand it off through the system share menu, or drop files into the app and send them to the destination. They can see progress and speed or cancel the transfer.
- **Receive.** The receiving device asks for approval by default. Users can turn on automatic acceptance in settings. They can find incoming content in local receive history and choose where files are saved.
- **Run in the background.** Vela can receive while the user is in another app. Setup currently varies by platform. Users can check this device's receiving status and see what they can do to restore it.

## Capabilities and Constraints

- The current release supports Android, macOS, Windows, and Linux. The interface is available in English and Simplified Chinese. QR scanning, system sharing, drag and drop, notifications, and background operation vary by platform.
- Clipboard sharing is explicit and supports text, an image, or one file. File selection supports batches. Vela packages folders for the receiving user to restore manually.
- **Destination reachability** reflects what the sender currently knows about the connection. The device may be reachable, temporarily unreachable, being checked, or of unknown status.
- **Local background receiving status** reflects the conditions on this device, including service state, notification permissions, and sleep settings.
- Pairing and transfers require both apps to be running and reachable. Sleep, quitting, stopping the app, permissions, and power policies can interrupt background receiving.
- Update-enabled releases check, download, and verify updates in the background. Users confirm installation after any transfer, pairing, or folder operation finishes.

## Brand Commitments

The product is Vela. The repository headline is “Share easily between your devices.” Use the existing [Vela mark](assets/branding/vela-icon.png).

## Evidence on Hand

- The [English user guide](docs/user-guide.md) and [Chinese user guide](docs/user-guide.zh-CN.md) describe platform support, how to use Vela, and troubleshooting.
- The [release checklist](docs/launch-checklist.md) covers real-device tests for background receiving, cross-platform transfers, and upgrades. Use results from the relevant version to assess availability and transfer behavior.

## Product Principles

1. Every sharing path should feel natural and easy. Carry the user's choice of content or receiving device through the steps that follow. Keep pairing and transfer rules consistent across platforms, and follow each system's sharing, notification, and background conventions.
2. When both devices are reachable, sharing on the same network and across networks should feel the same. Users choose the receiving device. Vela establishes the connection and handles the choice between direct and relayed paths.
3. Background receiving is the default experience. When the system allows it, Vela should continue receiving requests from paired devices in the background. Show the sender whether the target device is reachable. When users check this device's receiving status, explain known constraints and offer a recovery step where one is available.
4. Let the sender confirm the content and destination and cancel the transfer. Let the receiver decide whether to accept it, and let users revoke device trust.
