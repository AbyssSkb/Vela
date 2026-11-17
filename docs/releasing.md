# Building and releasing Vela

Vela builds on GitHub-hosted runners. Keep local verification small when disk is limited; the workflows compile Flutter, Rust, and native code on their target OS.

## Workflows

| Workflow | Trigger and result |
| --- | --- |
| [CI](../.github/workflows/ci.yml) | Push/PR/manual: Dart checks/tests, Rust format/tests on Linux/macOS/Windows, release-script checks |
| [Installation packages](../.github/workflows/build.yml) | Main/PR/manual: preview installers; reusable by the release workflow for configured release packages |
| [Release](../.github/workflows/release.yml) | Version tag or manual run: validate credentials/version, build all packages, sign feeds, assemble a draft; optional publication |
| [External relay tests](../.github/workflows/relay-tests.yml) | Manual public/private relay verification, separate from normal PR checks |

The package matrix builds macOS ARM64/Intel, Windows x64, Linux x64, Android ARM64, and an Android x86_64 test package. Preview artifacts expire after seven days. Previews contain no trusted update key; Android previews explicitly use a disposable debug key. They are not public update releases.

The zero-cost desktop route uses ad-hoc macOS signing and an EXE installer without Windows Authenticode. Update authenticity uses the project's own Ed25519 key; it does not provide Apple notarization or Windows publisher trust. The macOS build preserves the existing sandbox. Future paid certificates can improve OS trust without replacing the update-signing key.

## Configure release credentials once

Use repository **Settings → Secrets and variables → Actions**. Configure these secrets and keep secure backups outside the checkout:

| Secret | Value |
| --- | --- |
| `UPDATE_PRIVATE_KEY_PEM` | Ed25519 private key in PKCS#8 PEM format |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the durable Android release keystore, without line wrapping |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Alias of the release signing key |
| `ANDROID_KEY_PASSWORD` | Key password |

Set the repository variable **`VELA_UPDATE_PUBLIC_KEY`** to the raw 32-byte Ed25519 public key encoded in Base64. The prepare job derives the public key from the private key and refuses a mismatch. Configure the `release` environment with suitable deployment protection; PR builds never receive signing material.

If creating keys for the first public release, use OpenSSL with Ed25519 support and JDK `keytool` in a private directory outside the checkout:

```sh
openssl genpkey -algorithm Ed25519 -out vela-update.pem
keytool -genkeypair -keystore vela-release.jks -alias vela -keyalg RSA -keysize 3072 -validity 10000
```

`keytool` prompts for passwords. With the checkout's `tool/release/feeds.py`, derive the public variable value:

```sh
python3 tool/release/feeds.py --key /path/to/private/vela-update.pem --print-public-key
```

Generate these keys once, retain the originals and passwords, and reuse them for later releases. Replacing the Android key breaks APK overwrite upgrades; replacing the update key breaks trust in existing clients. Never print private keys or passwords in workflow logs or attach them to a release.

Existing macOS/Android application IDs are intentionally retained to preserve current profiles. A debug-signed Android build still cannot be overwritten with the public key: users need a clean first public install after saving received files, and uninstalling can remove app-local identity/history. Later public releases must keep their signing identity and application IDs.

## Create a version

1. Increment the semantic version and build number in `pubspec.yaml`. For example, `1.0.1+6` maps to tag `v1.0.1`. The build number must increase and fit `1..65535`.
2. Push the version commit and matching tag. `v*` tag pushes start the release workflow and leave a complete draft by default.
3. Check all package jobs and inspect the draft artifacts. Run a clean installation and an old-to-new upgrade before advertising the release.
4. Run **Release** manually for the existing tag with **publish** enabled when ready. The workflow publishes versioned installers first, then updates the machine-readable feeds under the rolling `updates` release.

Already published versions are immutable to the publisher script: use a new version/tag to replace a broken build. Android x86_64 test APKs are removed from public release assets. Versioned releases include installation packages, update payloads/feeds, and `SHA256SUMS`.

All platforms consume signed JSON manifests with exact package size and SHA-256. The common download code checks the pinned key and validates the repository/target before installation. macOS JSON also carries the ZIP's Sparkle `edSignature`; only after explicit installation consent does the native code expose the cached ZIP via a temporary loopback appcast to Sparkle. The five rolling feeds are JSON, with no remote XML feed to let Sparkle stage an installation early. The Linux helper replaces a complete verified AppImage without an additional AppImageUpdate engine. Windows uses the verified installer plus a shutdown/install helper.

## Build configuration

`tool/release/build.sh` supplies these Dart compile-time values; ordinary source/preview builds without a release public key leave updates disabled:

| Value | Meaning |
| --- | --- |
| `VELA_VERSION` | Semantic application version |
| `VELA_BUILD_NUMBER` | Monotonically increasing build number |
| `VELA_UPDATE_ARCH` | `arm64` or `x64` |
| `VELA_UPDATE_REPOSITORY` | GitHub `owner/repo`, normally `AbyssSkb/Vela` |
| `VELA_UPDATE_PUBLIC_KEY` | Pinned update verification key |

`VELA_PREVIEW_BUILD=true` is an environment flag permitting debug signing only for disposable Android preview packages. A release package without configured Android signing must fail instead of silently using a debug key.

## Verify updates and networking

Release acceptance includes old-to-new upgrade with identity/pairings/history/files retained, busy-state installation blocked, tampered packages rejected, download/installation failure leaving the current version usable, and platform-specific install/restart behavior. CI and native-helper tests cover code paths; they do not establish real desktop or phone behavior.

For external relay tests, run **External relay tests** with `public` or `private`. The private mode reads `VELA_RELAY_TEST_URL` and `VELA_RELAY_TEST_TOKEN` from the `relay-tests` environment and fails if they are missing. The runner creates a temporary token file and removes it afterward. The custom-discovery test permits direct connections; the other two tests disable direct transports to check actual relay traffic.

For small local script checks, use the commands in [CONTRIBUTING.md](../CONTRIBUTING.md). Do not run full platform builds locally solely to validate release-script edits on a space-constrained machine.
