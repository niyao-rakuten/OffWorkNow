# 收工日记

启动应用显示日历，macOS 菜单栏“每日报表”可重新打开；iOS 默认进入“日记”页签。点击日期查看喝水量、估算收入、加班时长，在下方切换三种月度折线图。

- 喝水小于 1500 ml 显示少喝提醒；达到 1500 ml 显示鼓励文案。
- 工作日收工表情：加班不足 15 分钟为笑脸；15 至不足 30 分钟为无奈；至少 30 分钟为哭脸。尚未到下班时间且未打卡时显示“进行中”；休息日显示“休”。
- 收入按已配置工作安排估算，不增加加班工资；日报收入在打卡时冻结，撤销后重新计算。主面板原有计划收入时钟仍按计划推进。
- 加班从当天计划下班时刻开始，打卡后冻结。未打卡时保存到应用最后观察的时刻；关闭期间没有后台考勤检测，再次打开当天会按当前时间更新。跨午夜不延续上一天计时。
- 喝水、撤销、打卡、设置保存立即记录，运行期间每分钟保存快照；macOS 正常退出、iOS 离开前台时再保存。
- 记录按工作时区和日期索引，日历展示当前配置的工作时区。之后修改工资或工作安排不重算过去日期；同一天修改设置会更新当天报表。时钟回拨不会用旧时间快照覆盖较新的日报。
- 历史缺失日期不补零，不推断为没有加班。升级前只存有当天喝水与最近打卡，因此无法恢复之前未记录的历史。
- “隐藏收入”同步遮蔽日报金额、收入文案与图表。

日报存储在本机 UserDefaults 的 `dailyReportArchive`，按版本校验。数据无法解析时保留原始数据并提示，不静默覆盖。恢复默认设置不清除日报。设备之间不自动同步；应用卸载后的容器清理会删除本地历史。

图标由 imagegen 生成，提示词见 [report-art-prompts.json](report-art-prompts.json)。[界面预览](assets/daily-report.png)使用临时空间中的合成演示数据，不写入真实用户记录。

## Checklist reporting update — 2026-10-19

Implementation contract: [Checklist reports and next-day carryover](checklist-reports-spec.md). This section describes the current working tree; earlier validation counts above are historical.

The macOS host supplies deduplicated current-day message checklist items through `AIBotContext.checklistItems` and `DailyReportStore.capture`. `DailyReport.checklistItems` preserves the task names and completion states in the report snapshot. The clock-out message adds a bilingual completed/unfinished summary. Later same-day diary captures can update task state without rewriting that earlier chat message; only earnings and overtime follow the existing checkout freeze.

The report card order is **water → earnings → overtime/alarm clock → checklist**. `ReportTaskSection` shows completed and unfinished counts and individually wrapping editable rows beside a 48 pt hand-drawn checklist icon. It replaces the earlier dense paragraph layout. Task state changes bypass the minute-only capture throttle.

Missing `checklistItems` in a legacy report means unknown historical task data and hides the task section; an empty array is a known empty snapshot and shows the localized empty state. Archive schema remains 1. Timed reminders in `assistant.localBot` are not included in this message-checklist projection. Reports are indexed by the configured work time zone and date; no historical backfill or device synchronization is performed.

The next day's first macOS startup greeting offers the immediately previous calendar day's unfinished checklist items. Yes creates an independent new checklist message; No records the decision without deleting tasks. Successful persistence preserves the choice across restarts. See the technical spec for source rechecking, origin identity, expiry and write-failure limits. The iOS host currently passes no message checklist items and does not expose carryover actions.

[Updated synthetic-data preview](assets/daily-report-checklist.png). The standalone icon is `Resources/PetArt/report-checklist.png`, loaded as `PetArtwork.reportIcon(6)`; [generation prompt](assets/report-checklist-prompt.md). The original six-cell report atlas is unchanged. Seven icons and 13 persisted synthetic reports were checked by `scripts/render-report-preview.swift`. No new download capability is part of reporting or chat.


### Editing report tasks

Click a task name to edit it inline; use Save/Return to commit or Cancel to discard. Click a circle to complete or reopen a task. Completed tasks remain editable. Counts and groups update immediately, and edits persist across restarts. `DailyReportStore.editChecklistItem` validates a candidate snapshot and coordinates with the macOS host callback to update the source chat checklist before saving the archive. Recalled copies sharing the checklist ID stay synchronized; independently carried tasks are not changed.

Historical report tasks can be edited without changing water, checkout, earnings, overtime or the historical snapshot timestamp. If the source conversation is absent, the archived task remains editable on its own. Failed source writes reject the archive edit and show an issue. This is not an atomic transaction across history JSON and UserDefaults. Earlier clock-out summary messages are not rewritten by later edits.
