# 最新验证记录

## Version 1.2.2 and daily start-time navigation — 2026-10-19

Moved the macOS per-date start editor, saved-date list and Use Default actions into Work Schedule → Daily Start Times. The main form retains a localized entry with record count. The secondary page binds to the existing settings draft and selected date/time; Back preserves the draft, while the outer Save/Cancel behavior and menu-bar synchronization remain unchanged.

Validation: 16 existing localization and flexible-schedule XCTest tests passed with no failures. The final Release app and DMG include the navigation change, marketing version 1.2.2, build 2 and both arm64/x86_64 architectures. Read-only inspection verified the embedded app signature, minimum macOS 13.0, both language catalogs, checklist icon and Applications shortcut. The executable matches the final build, DMG verification and SHA-256 check passed, and the mounted image was detached. The package remains a local ad-hoc build without notarization.

Evidence: `build/daily-start-navigation-tests.log`, `build/offworknow-dmg-build.log`, `build/package-1.2.2-validation.json`. Native navigation clicks and a fresh iOS build are not claimed. See [packaging details](DMG.md).

## Assistant/checklist localization — 2026-10-19

Explicitly localized the AI Assistant tab/section, missing settings and usage labels, save-key feedback, and assistant-settings issue links. The task section now directly observes the shared language store for independent title/count/status refresh.

Validation: **165 XCTest cases plus four swift-testing cases passed**, and macOS Debug build succeeded. Logs: `build/checklist-localization-tests.log`, `build/checklist-localization-build.log`. Existing localization coverage checks catalog keys and placeholder parity. [English preview](assets/daily-report-checklist.png) and [Chinese preview](assets/daily-report-checklist-zh.png) were rendered from the real SwiftUI view using synthetic data and process-local language overrides; saved user language preferences were not changed. Native interactive language switching while editing remains a manual check.

## Editable diary checklist — 2026-10-19

The editor revision passed **165 existing XCTest tests and four new swift-testing tests**, with zero failures; macOS `OffWorkNow` Debug build succeeded. Local evidence: `build/editable-report-tests.log` and `build/editable-report-build.log`.

The four tests in `Tests/WorkdayCoreTests/DailyReportEditingTests.swift` cover save/reload, completion reversal, preservation of task identity and financial snapshots, rejection of blank/unknown edits, source/recalled-list synchronization, independent next-day copies and archive-only editing without the source conversation.

The actual SwiftUI preview harness also verified report-to-source callbacks, rejected source writes leaving the report archive unchanged, and restored edited tasks from an isolated preferences suite. Seven icons and 13 report records loaded. [Updated preview](assets/daily-report-checklist.png). Native keyboard/mouse interaction and a fresh iOS build are still not claimed.

## Checklist reports, artwork and download removal — 2026-10-19

This entry records checks completed against the current working-tree implementation before the documentation update. Documentation edits do not re-run or expand application validation. Technical behavior and unresolved limits are in [the specification](checklist-reports-spec.md).

| Check | Result | Local evidence |
|---|---|---|
| Swift package regression suite | **165 XCTest tests, zero failures** | `build/checklist-cleanup-tests.log` |
| macOS `OffWorkNow` Debug build | **BUILD SUCCEEDED** with `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` | `build/checklist-cleanup-build.log` |
| Actual SwiftUI report preview | 13 reports restored; seven icons loaded; corrupt archive preserved; long mixed-language tasks rendered below overtime | `scripts/render-report-preview.swift`, [preview](assets/daily-report-checklist.png) |
| Video removal audit | No product intent/executor, dedicated Downloads entitlement, related strings, tests or scripts found | Source/configuration review; historical chats not deleted |
| iOS task parity / fresh build | Not claimed for this revision | Mobile host still supplies an empty task array |
| Native carryover buttons, accessibility and write-failure recovery | Manual QA remains | See specification §14 and §16 |

Build logs are local ignored artifacts and may disappear after cleanup. The checked-in screenshot uses only synthetic data and is not evidence of end-to-end native mouse interaction. The diary intentionally uses its light paper palette in dark mode.

Documentation-only verification: `docs/checklist-reports-spec.md` contains 16 sections and ten Mermaid diagrams. Referenced paths and relative links exist, fences are balanced, and the proposed swift-testing example type-checks without diagnostics against the local module and Xcode Testing framework. The example was not added to or executed by the existing suite; no new application test/build result is claimed.

## Earlier validation history

自定义动画单帧修复（2026-10-13）：macOS **63 项测试、0 失败**，iOS Simulator 编译通过。新增回归覆盖：1×1 导入后调整为 6×6 自动从 1 增至 36 帧；喝水 31–36 时普通为 30 帧且帧索引实际前进/循环；旧单帧配置显式修复后重载保持 30；手动帧数保留；喝水范围修改/关闭；未完成及极大网格输入不溢出或清空帧数。桌面实际点击与配置界面交互仍需实机验收。

DMG 打包验证（2026-10-13）：`scripts/build-dmg.sh` 成功构建 Release 双架构（arm64 + x86_64），生成约 44 MB 的 `build/下班啦-1.1.0-macOS-universal.dmg`。映像 CRC 校验通过；只读挂载后确认应用签名有效、可执行文件包含两种架构、Applications 符号链接指向 `/Applications`，含中文安装说明，验证后已卸载映像。此包使用 ad-hoc 本地签名，未 Developer ID 签名或公证；未改动系统已安装应用。

耳机动画更新：五张透明 PNG 图集新增 30 帧，全部 **180 帧**加载通过，并查看实际 SwiftUI 听歌关键帧和导出 `pets-music.gif`。`scripts/validate-pet-clicks.swift` 对实际 NSView 事件处理器注入点击事件，覆盖延迟单击、双击取消单击、拖动不触发切换、移除视图取消待处理点击和非激活首次点击；不替代真实桌面命中区域、窗口拖动的人工验收。

2026-10-13 增量验证：macOS **59 项测试、0 失败**，iOS Simulator 构建通过。新增 5 项自定义图集测试（迁移、网格校验、循环/往返、喝水帧段、形象切换）与 5 项日报测试（1500 ml 和 15/30 分钟边界、文案、打卡冻结、跨日历史、回拨保护和损坏校验）。以下 2026-10-12 表格为上一版本基线。

- `scripts/validate-custom-pets.swift`：PNG 导入、本地副本在源文件移动后仍可用、24 帧读取、草稿清理，以及损坏/超大/缺失文件拒绝，全部通过。
- `scripts/render-pet-previews.swift`：五种内置精灵共 150 帧加载成功，查看喝水关键帧并导出 GIF。
- `scripts/render-report-preview.swift`：临时空间中 13 天记录重新加载一致，6 个图标加载成功，损坏存储保留原数据；预览使用合成数据，不改用户实际记录。
- 新的 macOS 文件权限仅为用户选定文件只读，用于 PNG 导入。普通构建不注入测试权限。
- 真实双击/拖动、文件选择器、日历点击与 iOS 真机交互仍需人工验收；离屏预览不等于桌面交互已验证。

2026-10-12（Asia/Shanghai）；Xcode 26.5（17F42）、Apple Silicon、Swift 6.3.2，源码语言模式 Swift 5。

## 实际执行

| 操作 | 结果 | 证据 |
|---|---|---|
| macOS `OffWorkNow` Debug 测试构建（含四种精灵、喝水及加班） | **49 个测试，0 失败** | `build/offworknow-macos-test.log`，`build/OffWorkNowDerivedData/Logs/Test/*.xcresult` |
| macOS 普通 Debug 构建，关闭调试基础权限注入 | 成功 | `build/offworknow-macos-build.log` |
| iOS `OffWorkNow-iOS`、generic iOS Simulator 目标编译 | 成功，未运行模拟器 | `build/offworknow-ios-build.log` |
| Xcode 工程、两个 Info.plist、沙盒权限和隐私清单 lint | 通过 | `plutil -lint` |
| 两个平台图标资源编译 | 通过 | Xcode asset catalog 编译日志 |
| 本地 ad-hoc 签名严格验证 | 通过 | `codesign --verify --deep --strict` |
| 成品显示名称/版本/系统下限/菜单栏属性 | 下班啦、1.1.0（2）、macOS 13、LSUIElement=true | `build/下班啦.app/Contents/Info.plist` |
| App Sandbox 权限 | 源配置仅 app-sandbox=true；普通本地打包不注入测试临时权限 | `Configuration/OffWorkNow.entitlements`，成品 codesign entitlement 输出 |
| imagegen 新美术资源 | 四种精灵共 96 帧、4 个 UI 图形；透明 PNG 与校准元数据已打包进两个平台 | `Resources/PetArt/`、`docs/pet-art-prompts.json` |
| 原生 SwiftUI 离屏精灵预览 | 验证 96 帧和 4 个按钮图片可加载，人工检查浅深色及动作关键帧；导出连续帧 GIF，未验证真实桌面交互 | `docs/assets/pets-light.png`、`docs/assets/pets-dark.png`、`docs/assets/pets-actions.gif` |
| 原第一版 Debug 启动 | 上一轮实际启动成功并确认进程；这不等于新版 UI 已人工验收 | 上一轮验证记录 |
| 自有证书签名、商店/通用归档、TestFlight、上传审核 | 未执行 | 缺少已配置的开发者账号，未进行外部提交 |

Xcode 测试构建会注入临时调试/测试权限；交付本地应用另以 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` 普通构建，不能把测试权限视为商店权限。归档脚本不主动上传或发布。

Xcode 26 的 XCTest 运行库要求 macOS 14，测试目标有系统下限链接提示；应用最低声明仍为 macOS 13，其实机运行待验。AppIntents 元数据提取跳过是未使用框架的工具提示，最终源码没有编译错误。

## 49 个自动测试的范围

- 16 个原始计算测试：需求工资样例与时间边界、午休、休息日/覆盖、跨月闰年/K=0、未设置/0、Decimal 校验舍入、隐藏、立即重算、迁移、时区与 DST。
- 10 个原始提醒测试：整点启动十秒窗口、工作/午休/下班边界、暂停与总开关、重启持久化去重、时钟跳变与不追补、随机类别文案、指定时区，以及半小时 DST 仍只用自然整点。
- 10 个下班/加班测试：打卡时段、加班 0/1 秒边界、加班冻结与次日重置、提前打卡、未来标记不应用、第一次五分钟与后续五分钟、指定轮换文案、当天提醒全部取消、时钟前后跳/重启去重、排队事件被打卡取消、跨午夜/休息日/关闭、暂停独立、不增加工资、新字段迁移。
- 7 个弹性/自定义间隔测试：默认 09:00、当天覆盖不影响次日、午休前/中/后上班的实际扣除、日期验证与持久化/删除、整点重排与下班不变、10 分钟文案/边界/非法输入、间隔变更重合事件去重与只预约未来、旧配置恢复默认 9 点/5 分钟。
- 6 个喝水测试：每次一杯/唯一 ID、保存当时杯量、修改 500→250 后正确累计、持久化、撤销一个/撤销空记录、跨日与休息日、时区切换和时钟回拨、杯量范围/非法输入/默认迁移、小金鱼可选择、水杯数据损坏拒绝。

## 桌面三层布局调整

顶部水杯/时间同排，中间精灵动画，底部打卡按钮。通过离屏预览核对下班前、刚归零、加班、已打卡四种布局状态；底部仅在 `work.state == .after && checkout.canCheckout` 时包含按钮，隐藏时保留高度。此次重新执行 macOS 和 iOS 编译及离屏渲染，没有重复运行上文已通过的 49 个核心测试。真实鼠标操作仍待验。

## 人工验收仍需进行

| 项目 | 状态 |
|---|---|
| 新版单菜单栏项、欢迎页、桌面精灵；旧副本退出后正常启动 | 待验 |
| 实际精灵拖动、右键、置顶、隐藏、位置保存及多显示器切换 | 待验 |
| 四种精灵动画、打卡庆祝、加班文案、减少动态效果和长期能耗 | 待验 |
| 面板/Escape/外部点击、设置聚焦/保存/取消、重启持久化 | 待验 |
| 按日期弹性上班、默认恢复、修改加班间隔后真实通知 | 待验 |
| 喝水按钮每次一杯、修改杯量不改旧记录、撤销与跨日显示 | 待验 |
| 下班通知允许/拒绝、5/10 分钟通知可见性、打卡后停止当天提醒 | 待验 |
| 锁屏/真实睡眠/唤醒、语音开关、专注模式下行为 | 待验 |
| 固定签名安装路径的登录项注册/批准/撤销与重新登录 | 待验 |
| 沙盒迁移旧偏好、升级安装、macOS 13/Intel 实机 | 待验 |
| 浅深色、长数字、字体增大、键盘/VoiceOver | 待验 |
| iOS 模拟器交互、真机七天预约与打卡取消、后台/时区行为 | 待验 |
| 自有签名归档、商店验证与 TestFlight 安装 | 待验 |

没有修改用户系统时间、睡眠、屏幕授权或登录项来模拟人工结果，也没有提交应用到外部商店。不同路径的旧开发副本可能仍在运行；验证新版前应从旧副本面板退出，仅保留一份。


2026-10-13 丸子头女生：新增 3 张 imagegen 透明图集（24 + 6 + 6 帧），使用共享内置播放器和按脚底锚点校准的裁帧器。macOS / iOS Simulator 构建成功；63 项核心测试全部通过，包含新角色设置持久化和双击轮换顺序。离屏预览验证 216 帧和 4 个按钮均可读取，并更新 GIF。macOS Debug / Release、iOS 包内 3 张图集及布局文件与源文件哈希一致。尚未进行真机长时间播放或桌面鼠标交互验收。

自定义女生测试素材已重新生成，经用户授权对 36 帧做纯平移对齐，未缩放人物。核验透明背景、网格边界留白、每帧脚底 y=228、坐姿中心 x=128±0.5；只保存在 test-assets，不加入应用资源。
