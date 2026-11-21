# 发布签名与开发者验证

[English](release-signing.md)

政策核查日期为 2026 年 11 月 21 日。Vela 的 Ed25519 签名用于验证更新清单及其指定的安装包。首次安装由操作系统或分发渠道检查发布者身份。[Vela 发布流程](releasing.zh-CN.md)

| 平台 | 目前的公开产物 | 可信分发路径 |
| --- | --- | --- |
| Android | `com.example.vela` 的正式签名 APK | 按安装渠道注册现有包名和签名证书。国内 ColorOS 优先走 OPPO 应用验证。 |
| macOS | DMG 和 Sparkle 更新 ZIP 中的应用使用临时签名 | 用 Developer ID Application 签名，提交 Apple 公证并附上公证票据。 |
| Windows | Inno Setup 安装程序，无 Authenticode 签名 | 对 GitHub 安装包做 Authenticode 签名，或另做 MSIX 走 Microsoft Store。 |
| Linux | x64 AppImage 和有签名的更新清单 | 便携包可加 OpenPGP 签名。面向包管理器的发行可走已签名的仓库。 |
| iOS 和 iPadOS | GitHub Actions 模拟器预览 | 自己的真机用 Xcode Personal Team。公开测试和公开发行分别用 TestFlight 和 App Store。 |

beta.7 和 beta.8 的公开 APK 均通过 Android v2 验签，签名证书 SHA-256 都是 `e77c9a0b8c47ac70c4aee4b223c464e3b393cce438a9835542b2b489acb8210b`。beta.8 的 Apple 芯片 ZIP 中应用为临时签名，DMG 无公证票据。Windows 安装程序的 Authenticode 证书表为空，Linux AppImage 的 OpenPGP 签名区为空。上述 beta.8 产物均匹配已发布的 SHA-256 校验和。[beta.8 下载页](https://github.com/AbyssSkb/Vela/releases/tag/v0.1.0-beta.8)

## Android

APK 验签检查包体完整性，并让 Android 在升级时识别原签名者。开发者验证把包名和签名证书绑定到经过审核的个人或组织。验证时沿用 `com.example.vela` 和已有正式签名，可用 `apksigner verify --verbose --print-certs Vela.apk` 核对证书。[Android 应用签名](https://developer.android.com/studio/publish/app-signing) · [apksigner](https://developer.android.com/tools/apksigner)

- **国内 ColorOS。** 在 OPPO 开放平台完成实名认证，按页面要求认领应用，然后进入 **应用分发 → 应用管理 → 应用验证**。上传用正式发行密钥签名的验证空包，核对包名和签名后提交。OPPO 说明审核结果会同步到其侧载安装环节，并与 vivo、小米、荣耀互认。具体机型、ROM 和同步时间以实际安装验证为准。[OPPO 验证指南](https://open.oppomobile.com/documentation/page/info?id=13895) · [小米验证说明](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2366)
- **Google 认证设备。** 2026 年 9 月的首批覆盖巴西、印度尼西亚、新加坡、泰国部分应用商店安装，设备需运行 Android 8 或更高版本。Google 计划自 2027 年 1 月起分阶段扩展到其他应用分发商，之后再覆盖各安装来源。仅在 GitHub 分发的公开应用可使用 Android Developer Console 完整分发账号，注册费为 25 美元。免费限量分发用于最多 50 台授权设备。开源仓库分发同样需要把签名关联到已验证开发者身份。以现有 APK 签名提交所有权证明，以便用户继续覆盖升级。[Google 时间表](https://developer.android.com/developer-verification) · [2027 年扩展安排](https://developer.android.com/blog/posts/android-developer-verification-2027) · [账号和费用](https://developer.android.com/developer-verification/guides/faq) · [限量分发](https://developer.android.com/developer-verification/guides/limited-distribution) · [开源仓库](https://developer.android.com/developer-verification/guides/open-source-app-registration)

认证通过后，用曾出现提示的零售设备验证同一下载入口、首次安装和覆盖升级。系统的安装来源授权与恶意软件检测仍由各安装器处理。[OPPO 验证指南](https://open.oppomobile.com/documentation/page/info?id=13895) · [Android 用户说明](https://support.google.com/android/answer/17065026)

## macOS

Apple Developer Program 的年费为 99 美元或当地等值价格。申请 **Developer ID Application** 后，在发行 CI 中使用相同身份签名应用、分享扩展和 Sparkle 辅助进程，保留各自所需权限，并启用 Hardened Runtime 和安全时间戳。先公证应用并附上票据，再生成 Sparkle 更新 ZIP 和 DMG。DMG 也执行签名、公证和附票。更新签名和校验和在产物定稿后生成。[Apple 加入计划](https://developer.apple.com/help/account/membership/program-enrollment/) · [Developer ID](https://developer.apple.com/developer-id/) · [Apple 公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [Sparkle 发布说明](https://sparkle-project.org/documentation/publishing/)

发行验收用 `codesign --verify --deep --strict`、`xcrun stapler validate` 和 `spctl --assess --type execute`。在干净的 Mac 上检查下载后首次打开，并实际试一次从 beta.8 的临时签名版升级，确认沙盒文件、钥匙串的设备身份、分享扩展和原有配对可用。[Apple 公证检查](https://developer.apple.com/documentation/security/resolving-common-notarization-issues) · [macOS 沙盒文件访问](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

## Windows

保留 GitHub 上的 Inno 安装器时，先评估面向开源的 **SignPath Foundation**。它需要审核源码和构建来源，证书显示的发布者为 SignPath Foundation。需核对第三方 DLL 签名规则、每次发布的人工审批和公开签名政策。微软 Azure Artifact Signing Public Trust 起价约每月 9.99 美元，个人资格限美国和加拿大，组织可用范围还包括欧盟和英国。也可选受 Windows 信任的 OV 证书。[SignPath 条款](https://signpath.org/terms) · [微软签名选项](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)

对 Vela 主程序、适用的自有 DLL、Inno 安装器和卸载器签名，附 RFC 3161 时间戳，验证最终文件。需保留 Inno 的 `AppId` 并测试覆盖升级。SmartScreen 还评估文件与发布者信誉，已签名的新包仍可能收到提示。Microsoft Store 可免费签名 **MSIX**，但现有 EXE/MSI 上架需要发布者先签名。若另做 MSIX，需要实测数据迁移、通知、自启动和更新通道。[Inno 签名](https://jrsoftware.org/inno-setup/documentation/topic_setup_signtool.htm) · [SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool) · [SmartScreen](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation) · [MSIX 更新](https://learn.microsoft.com/en-us/windows/msix/app-installer/app-installer-file-overview)

## Linux

AppImage 可加入 OpenPGP 签名，首次下载时用支持的工具和受信任的发布公钥校验。Vela 已用 Ed25519 验证应用内更新。若提供包管理器渠道，可评估有签名的 Flatpak 仓库和 Flathub 的发布者验证。该渠道由 Flatpak 管理更新，验收时检查沙盒下的设备发现、接收、通知和文件操作。[AppImage 签名](https://docs.appimage.org/packaging-guide/optional/signatures.html) · [Flatpak 仓库](https://docs.flatpak.org/en/latest/hosting-a-repository.html) · [Flathub 验证](https://docs.flathub.org/docs/for-app-authors/verification)

## iOS 和 iPadOS

个人真机测试可用 Xcode 的免费 **Personal Team**，并开启开发者模式。免费描述文件七天到期。付费 Apple Developer Program 同时支持 macOS 的 Developer ID 和 iOS/iPadOS 的 TestFlight。TestFlight 构建可测试 90 天，首次对外测试需经过审核，最多可邀请 10,000 名外部测试者。正式开放安装走 App Store 审核，地区替代渠道有各自的资格和分发要求。[Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account/) · [开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) · [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) · [地区替代分发](https://developer.apple.com/documentation/marketplacekit/participating-in-alternative-distribution-for-specific-regions)
