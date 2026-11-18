# Vela development workflow

1. **Start in the current checkout.** Review `git status --short --branch`,
   `git diff`, and `git diff --cached`. Preserve existing user changes.
   Create a worktree only when requested.

2. **Run lightweight checks locally.** Reproduce bugs when feasible. Run
   `git diff --check` and use the lightweight checks in [CONTRIBUTING.md](CONTRIBUTING.md).
   Run focused tests locally when they can use installed tools and dependencies
   without compiling native code or creating large caches. Use GitHub Actions
   for full test suites, native compilation, and packaging. Ask before running
   a local platform build or downloading a large toolchain.

3. **Commit each logical change promptly.** Once the applicable local checks
   pass, commit before starting the next change or reporting completion.
   Use intermediate commits as needed. Stage only this task's files or hunks.
   Review the exact staged diff with `git diff --cached` and
   `git diff --cached --check`. Preserve unrelated staged work and leave the
   commit pending if you cannot safely isolate the task's changes.

4. **Deliver one logical change per PR.** Unless the user limits the task, use
   a dedicated `codex/*` branch for each independently reviewable change. Keep
   its implementation, regression tests, and required generated files or
   lockfile updates in the same PR. Target `main` for independent PRs and stack
   dependent PRs. Verify the outgoing commit range and push only authorized
   commits.
   Follow [CI](.github/workflows/ci.yml) and use
   [Installation packages](.github/workflows/build.yml) when native compilation
   or an installer is needed. Verify the checks cover the exact PR head, fix
   regressions within scope, and follow the checks to completion. Squash each PR
   into one commit on `main` once required checks and verification pass and the
   PR remains in scope. Merge stacked PRs from the bottom up. Ask for input if
   a required check or squash merge is blocked, or a decision changes the scope.
   Direct pushes to `main` and force-pushes require explicit permission.

5. **Report what was verified.** Include the PR, commit hashes, local checks,
   GitHub Actions links and outcomes when run, and any remaining device checks.
   Give the specific blocker for any required check that could not run.

## Commit messages

Use Conventional Commits: `<type>[(<scope>)][!]: <description>`.

- Write a short English subject starting with an imperative verb. Use a
  lowercase scope when a module clearly owns the change. Otherwise omit it.
- Use `feat` for a new feature, `fix` for a bug fix, `perf` for performance,
  and `refactor` for restructuring that preserves behavior. Use `docs`,
  `test`, `build`, `ci`, `chore`, `style`, or `revert` when applicable.
- For substantive changes, add an English body after a blank line. Explain
  why the change is needed, what changed, and the relevant verification and
  its limits. Apply this rule to squash commits too.
- For breaking changes, use `!` and a `BREAKING CHANGE:` footer explaining the
  impact and migration.

Examples:

- `fix(android): honor the default PDF viewer from notifications`
- `ci: verify packaged desktop startup`
- `chore(release): prepare v0.1.0-beta.3`

## GitHub releases

Start release preparation only when the user asks to ship a batch of changes.
That request authorizes the version commit, candidate tag, and signed draft.
Follow [docs/releasing.md](docs/releasing.md) to propose a version, build on
GitHub Actions, and verify the draft. Use tag `v<version>` and title
`Vela <version>`, omitting the build number from both. Mark versions with a
prerelease suffix as **Pre-release**.

Write the English release notes into the GitHub draft. Review the diff from
the previous published version and describe what changes for users. Link the
Chinese guide. Verify download links against the uploaded installers and link
`SHA256SUMS`. Use the layout below. Omit optional sections with no content and
omit the changelog link when there is no previous published version.

```markdown
<One sentence summarizing the release and identifying a preview when applicable.>

## Downloads

| Platform and architecture | Download |
| --- | --- |
| <Platform and architecture> | [<Installer>](<asset URL>) |

[SHA-256 checksums](<SHA256SUMS URL>)

## What's changed

- <User-visible improvement or fix.>

## Installation and upgrade

- <Compatibility change, migration step, or action users need to take.>

## Known issues

- <Known limitation and available workaround.>

[Full changelog](<comparison URL>) · [English guide](<URL>) · [中文说明](<URL>)
```

Present the proposed version, the reviewed draft, and the release check results
together for one explicit approval before publication. Publish using the
approved fingerprint as described in [docs/releasing.md](docs/releasing.md).
Verify the public release and the rolling update feeds before reporting success.
