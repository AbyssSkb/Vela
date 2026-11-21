# Release Vela

[简体中文](releasing.zh-CN.md)

Prepare a draft with signed packages, check its packages and upgrade behavior, then publish the draft the maintainer approved. [Release acceptance checklist](launch-checklist.md)

## Choose a version

Start when the maintainer asks to ship. Read the changes since the previous public release and propose the next version with the draft.

- During the `0.1.0` beta series, increment `N` in `0.1.0-beta.N`. Propose stable `0.1.0` after the acceptance checks pass and the maintainer is ready to ship it.
- After the first stable release, increment the patch version for compatible fixes and the minor version for a feature milestone. Explain compatibility breaks and migration in the release notes.
- Use a build number in `1..65535` greater than every published Vela build. A candidate written as `0.1.0-beta.3+8` in `pubspec.yaml` uses the tag `v0.1.0-beta.3`.

Public betas use the rolling `updates` feeds. Split stable and beta update channels before publishing the first stable build.

## Prepare and review the draft

1. Merge the proposed `pubspec.yaml` version through the PR workflow. Push the matching `v*` tag to prepare a draft. For an existing tag, run **Release** manually with `tag` set and `publish=false`. [Repository workflow](../AGENTS.md)
2. Confirm the draft points to the intended tag and commit. Check all five public installers, update feeds, payloads, and `SHA256SUMS`. Android x86_64 is a preview test target. Record clean-install and previous-version upgrade results for the candidate. [Release acceptance checklist](launch-checklist.md)
3. Write English notes in the draft. Use the release layout and link the English and Chinese user guides at the release tag. Check that the download links lead to the uploaded assets. [Release notes layout](../AGENTS.md#github-releases)
4. Sign in to `gh` with access to the draft. Use the candidate's tag in the fingerprint command.

   ```sh
   GH_REPO=AbyssSkb/Vela python3 tool/release/publication.py fingerprint v0.1.0-beta.3
   ```

5. Ask the maintainer to approve the version, draft, tag, commit, asset digests, verification results, and fingerprint together. If the reviewed draft changes, calculate the new fingerprint and request approval again.

## Publish the approved draft

Run **Release** manually with the reviewed `tag`, `publish=true`, and the approved `approved_fingerprint`. The workflow checks the fingerprint, publishes the same draft and assets, then refreshes the rolling `updates` feeds. Open the public version and check that the feeds point to it.

If the version is public and refreshing the feeds failed, rerun with the same tag and approved fingerprint. Publish a new version and tag to replace a broken installer.

## Workflows

| Workflow | When to use it |
| --- | --- |
| [CI](../.github/workflows/ci.yml) | Checks and tests on PRs and main pushes. Also available manually. |
| [Installation packages](../.github/workflows/build.yml) | Builds preview installers for qualifying PRs or manual runs. The release workflow uses it to build signed packages. |
| [Release](../.github/workflows/release.yml) | A version tag or manual run prepares the draft. A separate manual run publishes it after approval. |
| [Packaged desktop startup smoke](../.github/workflows/package-smoke.yml) | Supply the package run ID to test Windows installation and startup and Linux AppImage startup on hosted runners. |
| [External relay tests](../.github/workflows/relay-tests.yml) | Choose `public` or `private` to test relay behavior separately from PR CI. |

The preview matrix covers Android ARM64 and x86_64, macOS Apple silicon and Intel, Windows x64, and Linux x64. Preview artifacts expire after seven days. Android previews use a debug key. App updates require release configuration and are disabled in preview packages.

## Configure release credentials once

Set the secrets under **Repository Settings → Secrets and variables → Actions**. Store the keys and passwords in a secure location outside the checkout and reuse them for subsequent versions.

| Secret | Value |
| --- | --- |
| `UPDATE_PRIVATE_KEY_PEM` | Ed25519 private key, PKCS#8 PEM |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the Android release keystore on a single line |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Release signing key alias |
| `ANDROID_KEY_PASSWORD` | Key password |

Set `VELA_UPDATE_PUBLIC_KEY` to the raw 32-byte Ed25519 public key encoded in Base64. The release workflow checks that this value matches the private key. Protect the `release` environment and keep signing material outside PR jobs.

For the first release, create the keys in a private directory outside the checkout.

```sh
umask 077
openssl genpkey -algorithm Ed25519 -out vela-update.pem
keytool -genkeypair -keystore vela-release.jks -alias vela -keyalg RSA -keysize 3072 -validity 10000
```

From the checkout, derive the value for the public variable.

```sh
python3 tool/release/feeds.py --key /path/to/private/vela-update.pem --print-public-key
```

Existing installations rely on the same application IDs, Android signing key, and pinned update key. Reuse them for in-place upgrades. If coming from a debug-signed Android build, back up received files before uninstalling it and installing the public build.

## Build and update configuration

`tool/release/build.sh` passes `VELA_VERSION`, `VELA_BUILD_NUMBER`, `VELA_UPDATE_ARCH`, `VELA_UPDATE_REPOSITORY`, and `VELA_UPDATE_PUBLIC_KEY` as Dart build values. `VELA_PREVIEW_BUILD=true` permits Android debug signing for preview packages. Signed Android packaging requires release credentials.

Public desktop builds use ad-hoc macOS signing and a Windows installer without Authenticode. The Ed25519 update key verifies Vela update feeds and payloads. The macOS build retains the app sandbox and Windows bundles its compiler runtime DLLs with the app.

See [release signing and publisher trust](release-signing.md) for platform registration, signing, and installation checks.

Clients verify manifest targets, signatures, file sizes, and SHA-256 before installing. macOS hands Sparkle the verified ZIP through a local appcast after the user confirms. Windows runs the verified installer after shutdown. The Linux helper replaces the full AppImage. Android hands the APK to the system installer.

## Verify networking separately

The public relay test checks traffic through a public relay. Private mode uses `VELA_RELAY_TEST_URL` and `VELA_RELAY_TEST_TOKEN` from the `relay-tests` environment. The workflow uses a temporary token file and removes it after the run. The custom-discovery test permits a direct path. The relay-only cases verify traffic with direct transport disabled.

Use contribution checks for small local changes and target runners for compilation and packages. Record actual transfer, background, and upgrade results separately from CI. [Local checks](../CONTRIBUTING.md#verify)
