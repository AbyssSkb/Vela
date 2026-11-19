# Vela release acceptance checklist

[简体中文](launch-checklist.zh-CN.md)

Record results for each candidate. For each check, note the devices, operating systems, app versions, networks, send direction, and actual result. Record installer checks and real-device transfers separately. [Release workflow](releasing.md)

## Check the candidate

- [ ] Confirm the tag, commit, and version in `pubspec.yaml` agree.
- [ ] Check CI, packaging, and installer startup results for that commit.
- [ ] Confirm the build uses the existing Android signing key and update public key and can reuse application IDs and data locations.
- [ ] Check the draft's installers, signed update feeds, payloads, and SHA-256 checksums.
- [ ] Include steps for installation and upgrades. Android debug build users need to back up received files before uninstalling and installing the public build.
- [ ] Check sample files, screenshots, logs, and third-party license notices in public materials.

## Install and use Vela

| Platform | Check after installing |
| --- | --- |
| Android | Install the public ARM64 build. Pair, share from another app, receive through a background notification, and open what arrived. |
| macOS | Install the DMG on Apple silicon and Intel. Check the menu bar, Keychain, system sharing, launch at login, and system prompts. |
| Windows | Install as a normal user. Confirm a second launch opens the existing window, tray actions can open and quit Vela, and uninstall handles files and data as documented. |
| Linux | Run the AppImage in the desktop environment you record. Check Secret Service, tray, notifications, and clipboard behavior on X11 and Wayland. |

## Transfer matrix

- [ ] Pair and transfer in both directions across supported device combinations. Cover a single file, a batch, an image, text, a link, clipboard content, and packaging and restoring a folder.
- [ ] Test the same network, different networks, a network switch, and a VPN. Record whether each transfer used a direct or relayed connection. Test custom relay authentication and discovery as needed.
- [ ] Cover pairing approval, rejection, and cancellation. Reconnect after revoking trust. Test transfer approval, rejection, automatic acceptance, and cancellation.
- [ ] Check duplicate file names, low disk space, and failed saves. Change the save location, open a received file, remove a record while keeping its file, and remove both.
- [ ] Test system sharing, drag and drop, and the file and image clipboard where supported.
- [ ] On Android, test the lock screen, accepting from a notification, process reclamation, reboot and unlock, and reopening after force-stop.
- [ ] On macOS, test closing the window, idle sleep, and wake. On Windows/Linux, test tray behavior, launch at login, a second launch, and recovery after sleep.

## Upgrade and publish

- [ ] Upgrade from the previous public build. Check local identity, pairings, settings, history, and received files.
- [ ] Check that pairing, transfers, and folder operations block installation. Verify rejection of a tampered package and confirm the installed version remains usable after a controlled installation failure.
- [ ] Review the draft version, notes, assets, results, and fingerprint. Get the maintainer's approval to publish.
- [ ] After publishing, open the release page and download links. Check that the rolling feeds point to the new version.

## User-facing materials

Use the actual candidate and sample files for demos. Show the send action, receipt, and result, and identify the devices and network used. Include the file size and test environment with speed figures.

When updating download links, instructions, and screenshots, check that they match the release. Reproduce reported problems against the install, pairing, sharing, or upgrade steps before deciding what to fix next. [Report a problem](../CONTRIBUTING.md#report-a-problem)
