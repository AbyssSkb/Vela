# Building and releasing Vela

Vela builds on GitHub-hosted runners. Keep local verification small when disk is limited; the workflows compile Flutter, Rust, and native code on their target OS.

## Workflows

| Workflow | Trigger and result |
| --- | --- |
| [CI](../.github/workflows/ci.yml) | Push/PR/manual: Dart checks/tests, Rust format/tests on Linux/macOS/Windows, release-script checks |
| [Installation packages](../.github/workflows/build.yml) | Main/PR/manual: preview installers; reusable by the release workflow for configured release packages |
| [Release](../.github/workflows/release.yml) | A version tag or manual run prepares a signed draft. A manual run with the approved fingerprint publishes the reviewed draft and updates the rolling feeds. |
| [Packaged desktop startup smoke](../.github/workflows/package-smoke.yml) | Manual with a source workflow `run_id`: download its Windows/Linux artifacts and check package loading and window creation |
| [External relay tests](../.github/workflows/relay-tests.yml) | Manual public/private relay verification, separate from normal PR checks |

For the first public preview, [v0.1.0-beta.2](https://github.com/AbyssSkb/Vela/releases/tag/v0.1.0-beta.2), [CI](https://github.com/AbyssSkb/Vela/actions/runs/44120656381), [release packaging](https://github.com/AbyssSkb/Vela/actions/runs/44120654409), and [packaged startup checks](https://github.com/AbyssSkb/Vela/actions/runs/44212215724) passed. The startup check installs, opens, and uninstalls Windows; Linux opens the extracted AppImage under Xvfb/Mesa with a temporary Secret Service keyring, reaching identity, database, and node initialization. Real-hardware transfers, background behavior, and old-to-new upgrades remain separate release acceptance checks.

The package matrix builds macOS ARM64/Intel, Windows x64, Linux x64, Android ARM64, and an Android x86_64 test package. Preview artifacts expire after seven days. Previews contain no trusted update key; Android previews explicitly use a disposable debug key. They are not public update releases.

The zero-cost desktop route uses ad-hoc macOS signing and an EXE installer without Windows Authenticode. Windows bundles the compiler runtime DLLs beside Vela for current-user installation; app updates also carry those libraries. Update authenticity uses the project's own Ed25519 key; it does not provide Apple notarization or Windows publisher trust. The macOS build preserves the existing sandbox. Future paid certificates can improve OS trust without replacing the update-signing key.

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
umask 077
openssl genpkey -algorithm Ed25519 -out vela-update.pem
keytool -genkeypair -keystore vela-release.jks -alias vela -keyalg RSA -keysize 3072 -validity 10000
```

`keytool` prompts for passwords. Then, from the checkout, derive the public variable value:

```sh
python3 tool/release/feeds.py --key /path/to/private/vela-update.pem --print-public-key
```

Generate these keys once, retain the originals and passwords, and reuse them for later releases. Replacing the Android key breaks APK overwrite upgrades; replacing the update key breaks trust in existing clients. Never print private keys or passwords in workflow logs or attach them to a release.

Existing macOS/Android application IDs are intentionally retained to preserve current profiles. A debug-signed Android build still cannot be overwritten with the public key: users need a clean first public install after saving received files, and uninstalling can remove app-local identity/history. Later public releases must keep their signing identity and application IDs.

## Choose a version

Start release preparation when the maintainer asks to ship a batch of changes worth an upgrade. Review the changes since the previous public release and propose a version for the maintainer to approve with the draft. Conventional Commit types inform that decision. Version numbers are chosen per release.

- While targeting `0.1.0`, continue the series as `0.1.0-beta.N` and increment `N` for each new public beta.
- Propose stable `0.1.0` when the release acceptance checks pass and the maintainer is ready to ship it. After that, use `0.1.1` for compatible fixes and `0.2.0` for the next feature milestone. Call out compatibility breaks and the migration steps explicitly in the draft.
- Use a build number in `1..65535` that is greater than every previously published Vela build. Check the highest published number before preparing the release. If the highest is `7`, the next beta in the series could be `0.1.0-beta.3+8` in `pubspec.yaml`, tagged `v0.1.0-beta.3`.

Public betas continue to update the shared rolling `updates` feeds during the beta period. Split the beta and stable update channels before publishing the first stable version.

## Prepare and review the draft

1. Commit the proposed version in `pubspec.yaml` and deliver it through the [PR workflow](../AGENTS.md). Push the matching `v*` candidate tag to start **Release** in draft mode. To prepare for an existing tag, run **Release** manually with `tag` set and `publish=false`.
2. Confirm the package jobs pass and the draft targets the intended tag and commit. Check the uploaded installers, signed update feeds and payloads, and `SHA256SUMS`. Release packaging excludes the Android x86_64 test APK. Check a clean installation and an upgrade from a previous public version. Record the checks and their results for review.
3. Write English release notes into the GitHub draft using the [release page layout](../AGENTS.md#github-releases). Link `README.zh-CN.md` at the release tag, the installers, and the checksums. Review the saved notes and metadata against the uploaded assets.
4. From the checkout, use an authenticated `gh` session with access to the draft. Calculate its fingerprint once the draft is ready.

   ```sh
   GH_REPO=AbyssSkb/Vela python3 tool/release/publication.py fingerprint v0.1.0-beta.3
   ```

5. Present the version, draft link, tag, commit, package digests, release notes, check results, and fingerprint to the maintainer. Ask for one explicit approval of that version and draft before publishing. If the bound draft details change, recompute the fingerprint and obtain fresh approval.

## Publish the approved draft

Run **Release** manually with the reviewed `tag`, `publish=true`, and the approved `approved_fingerprint`. The workflow verifies the fingerprint, publishes the existing draft with its reviewed assets, and then updates the rolling `updates` release. Verify that the versioned release and the new rolling feeds are live.

If publication succeeded and the rolling feed update failed, rerun publication with the same tag and approved fingerprint to resume the feed update. Published releases keep their original installers. Use a new version and tag to replace a broken build.

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
