# 下班啦：上架、安装与首次运行

本文区分开发版、签名归档和实际商店发布。工程已准备两个原生目标、macOS 沙盒和隐私文件；**没有完成签名分发、商店验证、上传或审核**。需要自己的 Apple Developer Program 账号、Team 和可用 App ID，不能用 ad-hoc 签名产物冒充商店安装包。

## 工程已经具备的内容

- `OffWorkNow`：macOS 13+ 原生菜单栏与桌面精灵；`OffWorkNow-iOS`：iOS 16+ 原生配套应用，共用 `WorkdayCore` 和四种矢量动画精灵。
- `PRODUCT_NAME` / `CFBundleDisplayName` 均为“下班啦”，版本 1.1.0、构建 2；后续上传不同构建须递增构建号。
- Bundle ID 保留 `com.workdaybuddy.app`，两个平台同 ID 便于未来同一商店记录；若这个 ID 不属于你的 Team，应在两个目标中统一替换成自己注册的唯一 ID（这会改变本地配置容器）。
- macOS `com.apple.security.app-sandbox=true`，增加用户所选文件只读访问用于 PNG 图集导入；不申请网络、辅助功能或屏幕录制权限。
- `PrivacyInfo.xcprivacy` 声明不跟踪、不收集离开设备的数据，UserDefaults 使用 `CA92.1`；App Store Connect 的隐私回答仍应按最终产品核实。
- macOS/iOS 所需图标、生产版本号、共享 Scheme、ArchiveAction 和导出模板。
- Release 不强制 ad-hoc 证书；账号就绪后使用 Xcode 自动签名。Debug 本地脚本显式使用 ad-hoc。

Apple 明确要求 Mac App Store 应用启用 App Sandbox；上架前仍需完成签名、隐私与分发验证。[Apple：准备分发](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)

## 开发者上架步骤

1. 在 Xcode → Settings → Accounts 登录开发者账号；两个应用目标的 Signing & Capabilities 选择自己的 Team。注册/确认同一 App ID，启用 macOS 能力；不要填写他人的 Team 或冒用已有商标名称。
2. 在 App Store Connect 创建“下班啦”应用记录，选择 iOS 和 macOS 平台、对应 Bundle ID、自己的 SKU。也可先创建 macOS 平台，之后添加 iOS。使用同一应用记录与 Bundle ID 可为未来 universal purchase 准备。[Apple：添加平台](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms)
3. 在 Xcode 中分别选择 `OffWorkNow` / `My Mac` 与 `OffWorkNow-iOS` / Any iOS Device，Product → Archive。或使用脚本：

   ```sh
   XBL_TEAM_ID=你的TeamID ./scripts/archive-app-store.sh macOS
   XBL_TEAM_ID=你的TeamID ./scripts/archive-app-store.sh iOS
   ```

   脚本仅生成 `build/OffWorkNow.xcarchive` 或 `build/OffWorkNow-iOS.xcarchive`，macOS 将 arm64 与 x86_64 传给应用和 Package 以构建通用归档；会使用开发者签名服务，不上传。此通用签名归档尚未实际执行，须在账号配置后验证。
4. Xcode Organizer → Validate App → Distribute App → App Store Connect。按 Xcode 指引使用 App Store 分发签名及描述文件，不选择用于商店外分发的 Developer ID 路线。导出时可参考 `Configuration/ExportOptions-AppStore.plist`（method=app-store-connect、destination=export）；上传必须是有意识的独立操作。[Apple：上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
5. 用 TestFlight 安装与真实账号、沙盒容器验证。分别检查菜单栏/精灵首次展示、通知允许/拒绝、默认 5 分钟及自定义加班间隔边界、弹性上班时间、打卡取消、喝水保存与杯量变更、登录项和升级迁移。
6. 补齐平台截图、描述、关键词、支持 URL、隐私政策公开 URL、年龄分级、版权、价格/地区、隐私问卷和审核联系方式。当前仓库有本地隐私说明，但尚无可直接填入商店的公开支持或政策 URL。
7. 填审核备注、选择经过 TestFlight 验收的构建，提交审核。通过后按选择的手动或自动方式发布。仅经过苹果实际审核才能称为“已上架”。

建议审核备注：

> macOS 是菜单栏应用，没有常驻 Dock 图标。首次启动显示欢迎页和可拖动桌面精灵；顶部太阳图标打开面板，面板设置可配置工作时间、工资、提醒、精灵和杯量。无需账号，可用虚拟工资测试。通知权限由用户按钮主动请求。下班打卡仅在本机记录，不接入公司考勤；工资按计划估算、不计算加班。iOS 精灵仅应用内展示，下班通知预约未来七天，加班文案只在前台展示，无持续后台运行。

## 用户通过商店安装

正式发布后，用户在 Mac App Store 搜索“下班啦”，点击获取/购买 → 安装 → 打开；系统负责下载、签名验证、安装和更新。**不需要自制安装器、拖拽 .dmg 或管理员权限步骤**。目前没有商店链接，因为尚未创建并发布对应记录。

首次打开显示欢迎页：认识菜单栏和桌面精灵 → 主动选择是否开启通知 → 开始使用。默认月薪为空、每杯水 500 ml、猫精灵；用户可在设置切换狗、打工人或小金鱼。macOS 登录启动默认关闭，开启后根据真实系统状态提示是否需批准。

iOS 用户在 App Store 获取同平台版本，按系统流程安装；它没有跨应用桌面悬浮权限，不将 macOS 精灵窗口行为移植为后台悬浮服务。

## 发行前仍需验证

- 自有证书、描述文件、App Store Connect 校验及 TestFlight 实际安装；这些均未执行。
- macOS 13 与 Intel 实机、通用归档、沙盒下本地配置/水杯/下班标记的升级迁移。
- 登录项在商店安装固定路径注册、撤销、需批准及重新登录后的启动。
- 不同系统的通知样式、专注模式、睡眠/锁屏语音静默及醒来不补发。
- iOS 真机的七天预约、修改时间/打卡取消、通知拒绝、后台行为和跨时区。
- 隐私政策和支持网页、截图与最终业务隐私问卷。

需要理由 API 的声明应与真实用途一致；当前只读写本应用的本地偏好，采用 Apple 的 `CA92.1` 理由。[Apple：必要理由 API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)
