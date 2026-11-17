# Vela 首发清单

目标是让第一次看到 Vela 的人看懂用途、完成安装和首次传输，再愿意推荐给别人。10k star 是结果指标；首发先验证真实用户能否顺利完成这条路径。

## 产品定位

英文首页主张：**Share files and clipboard between Android and Mac.**

首批用户优先考虑同时使用 Android 手机和 Mac 的人。演示围绕三个具体动作：从手机相册分享照片到 Mac、从 Mac 拖入文件发到手机、将手机链接或剪贴板文字发到 Mac。

[LocalSend](https://github.com/localsend/localsend#readme) 已覆盖本地网络文件分享，并提供多个平台的安装渠道。Vela 可以重点验证的方向是：持续配对的个人设备、系统分享入口，以及基于 Iroh 的跨网络连接。后者在完成真实不同网络和中继测试后，再作为首屏主卖点。避免先用“跨平台 AirDrop”概括全部价值，也不要列未经复现的竞品优劣表。

## 公开源码前

- [x] 英文 README 与中文说明，列出实际功能、运行入口和限制。
- [x] MIT 许可证，保留 Cargokit 自带许可。
- [x] 初步扫描当前目录，未发现凭据泄露；当前目录没有 Git 历史可供扫描。
- [ ] 确定 GitHub 仓库地址，将 Rust 插件 Podspec 中临时使用的维护者主页换成项目地址。
- [ ] 在首次提交前检查最终文件清单：包含两个主项目锁文件；排除本机配置、签名文件、密钥、数据库、日志、构建缓存、安装包和测试个人内容。若另有历史仓库，还需扫描其历史。
- [ ] 在仓库设置中开启 Issues 和私密漏洞报告，确认 `Security → Advisories → Report a vulnerability` 可用后，添加带有效入口的 `SECURITY.md`。GitHub 的[配置说明](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository)介绍了该开关。
- [ ] 在全新检出中运行 CI，确认格式、静态分析和测试通过；不要将本机通过等同于 GitHub Actions 已验证。

### 本轮本地验证（2026-11-17）

| 检查 | 结果 |
| --- | --- |
| 锁定 Flutter 依赖、Dart / Rust 格式 | 通过 |
| Flutter 静态分析 | 无 warning/error，保留 23 条原有 info；CI 使用 `--no-fatal-infos` |
| Flutter 测试 | 157 项通过 |
| Rust 测试 | 155 项通过，3 项外部中继测试按原有配置忽略；保留 6 条原有编译警告 |
| CI / Issue 表单 | actionlint 与 YAML 结构检查通过，远端运行待验证 |
| 文档与许可证路径 | 本地链接和两个 Podspec 的许可证路径通过 |

尚未验证完整平台构建。两份 Podspec 的 Ruby 语法通过；本机 CocoaPods 启动器与已安装 gems 的 Ruby 版本不一致，完整 CocoaPods 解析受阻，未改动全局开发环境。

## 公开安装包前

公开源码与分发安装包可以分开进行。以下项目是安装包首发门槛。

| 门槛 | 当前状态 | 完成标准 |
| --- | --- | --- |
| 固定应用标识 | Android 与 macOS 仍使用 `com.example.vela` | 同步检查 Android applicationId/namespace、macOS 主应用、分享扩展、测试 target 及相关存储配置；确认开发版数据迁移影响 |
| Android 签名 | release 使用 debug key | 使用持久发布密钥，安全备份，在测试机验证同密钥升级，凭据不入库 |
| macOS 分发 | 默认临时签名 | 完成 Developer ID 分发签名及公证，覆盖主应用和分享扩展；在另一台 Mac 验证安装、分享菜单和钥匙串访问 |
| 平台要求 | macOS 最低构建目标为 12；Android 最低版本来自工具链 | 从最终包核实最低系统版本和架构，并在真实设备上验证后列入下载表 |
| 版本 | `pubspec.yaml` 当前为 `1.0.0+5` | 决定首次公开版本号；若为预览版，在 GitHub Release 中标记 pre-release，并使包内版本与标签一致 |
| 安装入口 | 尚未准备公开 APK / macOS 下载 | 上传实际验证过的包、SHA-256 校验值、安装说明、已知问题和测试环境 |
| 第三方声明 | 源码保留 Cargokit 许可，依赖分别有各自许可 | 核对随二进制分发的依赖及许可声明，验证用户可以查看对应信息 |

修改应用标识会改变应用存储和身份作用域，可能影响现有开发版的设备配对和数据访问；应作为单独的发布配置变更验证。

GitHub 的 [Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) 可以附带可下载安装包；上传源码压缩包不能代替用户安装入口。

## 最小实测矩阵

每一项记录设备型号、系统和应用版本、网络、传输方向及结果。已有文档记载过 Android 35 模拟器与 Mac 的测试，首次公开安装包仍需用最终包重测。

- [ ] Android ↔ Mac：文件、多个文件、图片、文字、链接、剪贴板、文件夹发送和手动还原。
- [ ] 首次配对、拒绝配对、取消配对、删除设备后再次连接。
- [ ] 接收确认、拒绝、自动接收开关、取消传输、同名文件、磁盘空间不足。
- [ ] 两端同 Wi-Fi、不同网络、网络切换、VPN 和直连失败后的中继路径；自定义中继单独记录。
- [ ] Android 锁屏、后台、通知操作、服务被系统回收、重启解锁、强制停止后手动重开。
- [ ] Mac 关窗口、菜单栏接收、空闲睡眠、手动睡眠后恢复、登录启动。
- [ ] 从 Android 和 macOS 其他应用发起系统分享；Mac 拖入文件。
- [ ] 更换保存目录、打开历史文件、仅删记录与同时删文件、升级后身份和数据保留。

## 首页演示与下载入口

- [ ] 录制 20–30 秒真实设备演示：配对一次 → Android 系统分享 → Mac 接收 → Mac 拖入文件发回手机。字幕说明每一步，不展示个人设备码和文件。
- [ ] 从实际应用截取一张 Mac 和一张 Android 界面，放到首页首屏附近。使用英文 UI 和演示文件，中文版本可另配。
- [ ] 录制不同网络传输时，注明网络和中继条件；速度数字注明文件大小、设备和测试环境。
- [ ] 将 README 的源码预览说明替换为实际下载表，并保留开发者构建入口。
- [ ] 确认录像、截图、安装包和 README 展示的是同一版本。

目前首页使用现有品牌图标；真实应用截图和演示完成前不放模拟截图或空下载按钮。

## 仓库门面

可直接使用的 About 描述：

> Share files, folders, text, and clipboard between paired Android and macOS devices. Built with Flutter, Rust, and Iroh.

建议 topics：`file-sharing`、`clipboard`、`android`、`macos`、`flutter`、`rust`、`iroh`、`peer-to-peer`。GitHub 的 [topics 说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics)介绍了它们的展示和检索方式。

- [ ] 设置 About、topics 和真实演示的 social preview。
- [ ] 创建少量范围明确的贡献任务：真实设备问题复现、某条翻译、某个已知 bug；任务写清入口和验收方式，再标记 `good first issue`。
- [ ] 为贡献者补充实际可执行的社区行为规范及举报入口。
- [ ] 创建一个反馈汇总，持续记录安装失败、配对失败和后台接收失败的高频原因。

## 发布节奏

1. **小范围试用：**先邀请 5–10 位 Android + Mac 用户，用同一个候选包完成首次传输。记录安装成功、配对成功和传输成功的数量、耗时与失败原因。
2. **公开预览：**发布安装包和短演示，在适合的 Android、Mac、Flutter、Rust 或 Iroh 社区介绍一个实际场景。遵守各社区推广规则；文案围绕已验证能力。
3. **稳定迭代：**优先解决试用中重复出现的失败，每次更新展示一个可观察的改进，并请原报告者复测。

每轮看 Release 下载、首次传输反馈、重复问题和外部贡献，再看 star 增长。先确保用户下载后能用，再扩大曝光。
