# 发布 Vela

[English](releasing.md)

先准备包含签名产物的草稿，检查安装包和升级行为，再发布维护者确认的草稿。 [发布验收清单](launch-checklist.zh-CN.md)

## 选择版本

维护者提出发布后，查看上一个公开版以来的改动，随草稿一并提出新版本。

- 在 `0.1.0` 测试阶段，递增 `0.1.0-beta.N` 中的 `N`。验收通过且维护者准备发布时，再提出稳定版 `0.1.0`。
- 首个稳定版之后，兼容修复递增补丁版本，功能里程碑递增次版本。兼容性变化和迁移步骤写入发布说明。
- 构建号在 `1..65535` 内，并且大于此前所有已发布的 Vela 构建号。例如，`pubspec.yaml` 中的 `0.1.0-beta.3+8` 对应标签 `v0.1.0-beta.3`。

公开测试版使用滚动的 `updates` 更新源。发布首个稳定版前，分开稳定版和测试版的更新渠道。

## 准备和审阅草稿

1. 通过 PR 合并 `pubspec.yaml` 中的候选版本，再推送对应的 `v*` 标签生成草稿。已有标签可手动运行 **Release**，填写 `tag` 并令 `publish=false`。 [仓库工作流程](../AGENTS.zh-CN.md)
2. 核对草稿的标签和提交。检查五个公开安装包、更新源、更新包和 `SHA256SUMS`。Android x86_64 用于预览测试。记录候选版的全新安装和从上一版升级的结果。 [发布验收清单](launch-checklist.zh-CN.md)
3. 在草稿中写英文发布说明，按格式链接该标签下的中英文使用指南。核对下载链接确实指向已上传的安装包。 [发布说明格式](../AGENTS.zh-CN.md#github-发行)
4. 登录有草稿权限的 `gh`，用候选标签计算指纹。

   ```sh
   GH_REPO=AbyssSkb/Vela python3 tool/release/publication.py fingerprint v0.1.0-beta.3
   ```

5. 把版本、草稿、标签、提交、资源摘要、验收结果和指纹一起交给维护者确认。草稿变动时重新计算指纹并重新确认。

## 发布已确认的草稿

手动运行 **Release**，填入审阅过的 `tag`、`publish=true` 和已确认的 `approved_fingerprint`。工作流会核对指纹、发布该草稿和资源，再刷新滚动的 `updates` 更新源。打开公开版本页，并检查更新源是否指向该版本。

如果版本已公开但更新源刷新失败，可以用相同的标签和指纹重跑。安装包有问题时，用新版本和新标签发布修复。

## 工作流

| 工作流 | 什么时候用 |
| --- | --- |
| [CI](../.github/workflows/ci.yml) | 在 PR、推送到 main 或手动运行时执行检查和测试。 |
| [Installation packages](../.github/workflows/build.yml) | 在符合触发条件的 PR 或手动运行时构建预览安装包。发布流程复用它构建签名包。 |
| [Release](../.github/workflows/release.yml) | 版本标签或手动运行可以准备草稿。确认后另行手动发布。 |
| [Packaged desktop startup smoke](../.github/workflows/package-smoke.yml) | 提供打包运行 ID，在托管 runner 上测试 Windows 安装与启动、Linux AppImage 启动。 |
| [External relay tests](../.github/workflows/relay-tests.yml) | 选择 `public` 或 `private`，独立于 PR CI 验证中继行为。 |

预览构建覆盖 Android ARM64 和 x86_64、macOS Apple 芯片和 Intel、Windows x64、Linux x64。产物保留七天，Android 预览使用调试签名。应用内更新需要发行配置，预览包关闭更新。

## 初次配置发布凭据

到仓库的 **Settings → Secrets and variables → Actions** 设置以下秘密变量。密钥和密码保存在仓库外的安全位置，后续版本继续使用同一份。

| 秘密变量 | 值 |
| --- | --- |
| `UPDATE_PRIVATE_KEY_PEM` | PKCS#8 PEM 格式的 Ed25519 私钥 |
| `ANDROID_KEYSTORE_BASE64` | Android 发行密钥库的单行 Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | 密钥库密码 |
| `ANDROID_KEY_ALIAS` | 发行签名密钥的别名 |
| `ANDROID_KEY_PASSWORD` | 密钥密码 |

将 `VELA_UPDATE_PUBLIC_KEY` 设为原始 32 字节 Ed25519 公钥的 Base64。发布工作流会核对它与私钥是否对应。保护 `release` 环境，PR 工作流使用预览配置。

首个版本的密钥在仓库之外的私密目录生成。

```sh
umask 077
openssl genpkey -algorithm Ed25519 -out vela-update.pem
keytool -genkeypair -keystore vela-release.jks -alias vela -keyalg RSA -keysize 3072 -validity 10000
```

回到仓库目录，生成公钥变量的值。

```sh
python3 tool/release/feeds.py --key /path/to/private/vela-update.pem --print-public-key
```

覆盖升级依赖相同的应用标识、Android 签名密钥和固定更新公钥。从 Android 调试签名版换到公开版时，先备份收到的文件，再卸载旧版并安装公开版。

## 构建和更新配置

`tool/release/build.sh` 将 `VELA_VERSION`、`VELA_BUILD_NUMBER`、`VELA_UPDATE_ARCH`、`VELA_UPDATE_REPOSITORY` 和 `VELA_UPDATE_PUBLIC_KEY` 传给 Dart。设置 `VELA_PREVIEW_BUILD=true` 时，Android 预览包可使用调试签名。签名发行包需要配置发行凭据。

公开桌面构建使用 macOS 临时签名和无 Authenticode 签名的 Windows 安装程序。Ed25519 更新密钥用于校验 Vela 的更新源与更新包。macOS 发行包保留应用沙盒，Windows 将编译器运行库随应用打包。

客户端在安装前核对清单目标、签名、文件大小和 SHA-256。用户确认后，macOS 通过本机 appcast 将已验证的 ZIP 交给 Sparkle。Windows 退出应用后运行已验证的安装程序，Linux 通过辅助程序替换完整 AppImage，Android 把 APK 交给系统安装器。

## 单独验证联网

公开中继测试检查经过公共中继的流量。私有模式从 `relay-tests` 环境读取 `VELA_RELAY_TEST_URL` 和 `VELA_RELAY_TEST_TOKEN`。工作流使用临时 token 文件，运行结束后删除。自定义发现测试允许直连。其余中继测试关闭直连来验证中继流量。

小改动可先用贡献指南中的检查命令，完整编译和打包交给目标平台的 runner。真实收发、后台和升级结果单独记录。 [本地检查](../CONTRIBUTING.zh-CN.md#验证)
