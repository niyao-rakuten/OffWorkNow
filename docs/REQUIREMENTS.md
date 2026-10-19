# 最新需求对照

## Checklist/report extension — 2026-10-19

The current implementation is documented in [the checklist technical specification](checklist-reports-spec.md). Prior counts and platform claims in the historical table below describe earlier revisions.

| Requirement | Current implementation | Evidence / limit |
|---|---|---|
| Report completed and unfinished work | Work-calendar message checklist projection feeds clock-out prose and archived task snapshots | Domain/report tests; no timed-reminder or backlog aggregation |
| Offer yesterday's unfinished tasks at next startup | Structured greeting payload and localized light-blue Yes/No buttons in compact and expanded views | Decision/source-state/deduplication tests; actual native clicks remain manual QA |
| Accept into today's own checklist | Fresh checklist/item IDs with preserved origin IDs; decision and reply saved together | Round-trip and repeated/competing-offer tests; successful save required for restart durability |
| Diary checklist beneath alarm clock | Grouped wrapping editable rows and a separate watercolor icon | Inspected actual SwiftUI preview, seven images loaded |
| Multilingual application copy | English/Chinese catalogs and dynamic structured prompt | Localization tests; task names intentionally preserved |
| Edit and check report tasks | Inline text drafts and completion buttons persist and synchronize linked chat tasks | Four swift-testing regressions plus store/preview smoke; native clicks remain manual QA |
| Remove video downloading | No local download intent, executor, dedicated grant, dependency or product test | Source/configuration search and macOS build |

Verification on this implementation: **165 core XCTest tests plus four editor swift-testing tests, zero failures; macOS Debug build passed**. A synthetic-data preview restored 13 reports, loaded seven icons and preserved corrupt archive bytes. This revision does not claim iOS task-input/carryover parity or a fresh iOS build.

## Earlier requirement baseline

2026-10-13：新增小狐妖、五种角色各自喝水动画、双击切换、PNG 图集导入与播放设置。新增启动日历、喝水/收入/加班日报、本地每日历史和月度折线图，使用 imagegen 手绘表情及指标图标。59 项核心测试和双平台编译通过；PNG 导入、持久化与帧加载 smoke 通过。真实鼠标和设备交互仍待验收。说明见 [自定义精灵](CUSTOM_PETS.md) 与 [日报](DAILY_REPORTS.md)。

| 需求 | 实现 | 验证 |
|---|---|---|
| 名称改为“下班啦” | OffWorkNow.xcodeproj，中文产品/界面/欢迎页/通知名称，版本 1.1.0（2） | 成品 Info.plist 与构建通过 |
| 后续支持 iOS 与 macOS | 原生 macOS 与 iOS 两个 Scheme，共用 WorkdayCore / PetAvatar | macOS 测试及 iOS Simulator 构建通过；iOS 交互待验 |
| macOS 上架与安装流程 | App Sandbox、PrivacyInfo、图标、Release 自动签名、归档/导出配置、首次使用页、APP_STORE.md | 工程及本地权限校验通过；开发者证书/商店归档/TestFlight/审核未执行 |
| 常驻动画桌面精灵 | NSPanel，拖动、位置保存、置顶/隐藏，减少动态效果；倒计时/加班/打卡/喝水入口 | 编译通过；跨屏与实际拖动/长期能耗待验 |
| 猫、狗、打工人、小金鱼 | imagegen 水彩漫画 PNG 图集；每只 24 帧、随机动作、打卡庆祝 | macOS 与 iOS 编译通过；96 帧离屏加载及动画导出通过，真实桌面播放待验 |
| “打卡下班”按钮 | 当天最近一次本地标记，点击后停止当天全部生产提醒；撤销需确认 | 可用时段、冻结加班、持久化、次日/时区测试通过 |
| 超过下班时间显示加班 | 从设置下班时间计时，工资封顶；菜单栏/面板/精灵同步 | 精确边界与不增加工资测试通过 |
| 可配置间隔的加班文案（默认 5 分钟） | 统一 overtime 事件，支持 1–240 分钟；默认 5/10/15…分钟；轮换两句文案，通知及桌面气泡 | 五分钟边界、文案、跨日、不追补、去重与打卡取消测试通过 |
| 喝一杯水记录一次 | 每次新增 UUID、时间、当时杯量；当天杯数和总 ml；撤销上一杯 | 多次点击、持久化、撤销、跨日/时区/回拨测试通过 |
| 每杯水量可设如 500 ml | 默认 500，1–2000 ml 整数；设置变更只影响之后的记录 | 校验、新旧杯量相加、旧配置补默认测试通过 |
| 菜单栏与独立设置 | NSStatusItem / NSPopover / NSWindow；草稿保存/取消 | 构建通过；真实窗口操作待验 |
| 默认 09:00 及每天弹性上班 | 常规默认值 + 日期上班时间覆盖，面板快速调整今天；午休仅扣重叠部分 | 7 个新增测试覆盖弹性时间及自定义加班间隔 |
| 工作日/时间/午休/时区/日期覆盖 | WorkSettings、ScheduleCalculator | 工资与时间基线测试通过 |
| 三种日薪及隐私隐藏 | Decimal EarningsCalculator、显示遮蔽，不计加班工资 | 原 16 个计算测试通过 |
| 整点提醒、暂停、中文语音、下班通知 | 原生系统服务及统一 ReminderCoordinator | 原 10 个提醒测试通过；系统通知/音频待验 |
| 持久化与配置恢复 | schema 默认补齐，损坏拒绝，水杯单独校验 | 编解码及损坏测试通过 |
| 开机启动真实状态 | SMAppService.mainApp | 编译通过；未注册用户登录项，实际登录待验 |
| 浅深色、键盘/VoiceOver、无额外权限 | 系统样式、等宽数字、原生按钮、语义标签、Reduce Motion | 编译通过；辅助功能实际验收待验 |

当前 iOS 为可编译配套基础版，精灵与加班文案仅应用内展示；七天下班通知使用系统预约。macOS 常驻精灵、整点语音、每五分钟通知与开机启动没有宣称全部移植到 iOS 后台，也没有跨设备同步。
