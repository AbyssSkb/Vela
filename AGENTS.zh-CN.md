# Vela 开发流程

[English](AGENTS.md)

1. **从当前检出开始。** 查看 `git status --short --branch`、`git diff` 和 `git diff --cached`。保留用户已有的改动。只有在用户要求时才创建工作树。

2. **在本地运行轻量检查。** 条件允许时先复现问题。运行 `git diff --check` 和贡献指南中的轻量检查。使用现有工具和依赖运行针对性测试，避免编译原生代码或生成大缓存。完整测试、原生编译和打包交给 GitHub Actions。本地平台构建或下载大型工具链前，先征求用户同意。 [贡献指南](CONTRIBUTING.zh-CN.md)

3. **及时提交每项逻辑变更。** 适用的本地检查通过后，在开始下一项改动或报告完成前提交。需要时可以做中间提交。只暂存本任务的文件或代码块，并用 `git diff --cached` 和 `git diff --cached --check` 审阅实际将要提交的内容。保留无关的暂存改动。如果无法安全分离本任务的改动，先保留为待提交状态。

4. **每个 PR 交付一项逻辑变更。** 除非用户限制范围，每项可独立审阅的改动用单独的 `codex/*` 分支。实现、回归测试、必需的生成文件和锁文件更新进入同一个 PR。独立 PR 指向 `main`，有依赖时叠放在前置 PR 上。核对待推送的提交范围，只推送已授权的提交。

   跟进 CI，需要原生编译或安装包时使用安装包工作流。核实检查覆盖 PR 的实际 head，在任务范围内修复回归并跟进到检查结束。所需检查和验证通过后，如果 PR 仍在范围内，将它 squash 为 `main` 上的一次提交。叠放的 PR 从最底层开始合并。如果必需检查或 squash 合并受阻，或遇到会改变范围的决定，请征求用户意见。直接推送 `main` 和强制推送需要明确授权。 [CI](.github/workflows/ci.yml) · [安装包工作流](.github/workflows/build.yml)

5. **说明验证结果。** 提交报告应包括 PR、提交哈希、本地检查、运行过的 GitHub Actions 链接和结果，以及剩余的设备检查。必需检查无法运行时，说明具体原因。

## 提交信息

使用 Conventional Commits，格式为 `<type>[(<scope>)][!]: <description>`。

- 英文标题简短，以祈使动词开头。改动明确归属某个模块时填写小写 scope，其他情况可省略。
- 新功能用 `feat`，缺陷修复用 `fix`，性能改进用 `perf`，保持行为的结构调整用 `refactor`。适用时使用 `docs`、`test`、`build`、`ci`、`chore`、`style` 或 `revert`。
- 实质性变更在标题下留一空行，再写英文正文。说明改动原因、内容、相关验证和验证范围。squash 提交也适用。
- 有破坏性变更时，用 `!` 和 `BREAKING CHANGE:` 页脚说明影响和迁移方式。

示例

- `fix(android): honor the default PDF viewer from notifications`
- `ci: verify packaged desktop startup`
- `chore(release): prepare v0.1.0-beta.3`

## GitHub 发行

仅在用户要求发布一批改动时开始准备发行。该请求授权版本提交、候选标签和含签名产物的草稿。按发布流程提出版本、在 GitHub Actions 上构建并核验草稿。使用 `v<version>` 标签和 `Vela <version>` 标题，二者都省略构建号。带预发行后缀的版本标记为 **Pre-release**。 [发布流程](docs/releasing.zh-CN.md)

把英文发布说明写入 GitHub 草稿。查看上一个已发布版本以来的改动，说明用户能看到的变化。链接中文指南。核对下载链接与已上传的安装包一致，并链接 `SHA256SUMS`。按照下面的格式编写，有内容时才保留可选章节。没有上一个已发布版本时，省略完整变更链接。

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

将拟发布版本、已核对的草稿和验证结果一起交给用户，请用户明确确认一次。使用已批准的指纹发布。发布后核对公开版本和滚动更新源，再报告完成。 [发布流程](docs/releasing.zh-CN.md)
