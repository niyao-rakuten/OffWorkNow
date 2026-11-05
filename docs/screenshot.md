# macOS 截图

点击桌面精灵底部相机按钮，在目标屏幕拖动选区。首次使用需在系统设置授权屏幕录制，系统可能要求重启应用。

选区工具可拖动选区，也可拖动八个控制点改变范围。编辑工具包含铅笔、矩形、椭圆和涂抹马赛克；颜色选择器控制后续画笔和形状颜色。撤销或 Command-Z 删除最后一次标注。调整选区仅改变裁剪范围，已有标注保持屏幕位置。

✅ / Return 将最终图片复制到剪贴板；❌ / Escape 丢弃。截图不写入磁盘、不发送到聊天。

## 验证

macOS Debug 构建通过。需桌面人工验收：首次权限拒绝与授权后重试、多显示器选择、Retina 与非 Retina 粘贴尺寸、八方向缩放、边缘选区工具栏、各标注工具、连续马赛克、撤销、确认复制及取消保留原剪贴板。

## 图标

使用内置 image_gen 生成，透明 PNG：`Resources/Assets.xcassets/ScreenshotCamera.imageset/camera.png`。

相机位于水杯左侧；相机和九个工具栏按钮使用重新生成的透明手绘素材，按内容裁去透明留白并保持宽高比。按钮包含选区、画笔、矩形、椭圆、马赛克、调色盘、撤销、取消和确认，显示选中高亮并保留悬停说明及辅助功能标签。调色盘右下角显示当前颜色。

所有图标通过内置 image_gen 生成，最终资源路径和完整提示词见 [screenshot-icon-prompts.json](screenshot-icon-prompts.json)。

## 屏幕录制权限循环修复（1.5.1 / build 7）

旧实现将 `CGPreflightScreenCaptureAccess()` 用作硬性前置条件；返回 false 后调用 `CGRequestScreenCaptureAccess()`，忽略请求结果并直接弹窗退出，未尝试 ScreenCaptureKit。授权状态未及时反映到当前进程时，重复点击始终走同一分支。

修复后直接调用 ScreenCaptureKit，交由系统完成授权流程；只把 `SCStreamErrorDomain` / `userDeclined` 归为未授权。无显示器、连接失败等错误保留实际错误原因。权限失败提供“打开系统设置”和当前应用路径，不自动重试、不重复调用另一套授权 API。截图期间重复点击仍会合并；失败后可再次主动点击尝试。

本机排查确认运行路径为 `/Applications/下班啦.app`，安装版本为 1.5.1，签名为 ad-hoc（无 TeamIdentifier）。临时签名更新可能造成旧授权与新构建不匹配，移除前置判断不能修复系统中已失效的授权条目。替换修复包前退出旧应用，从应用程序目录重新打开；若仍收到 ScreenCaptureKit 未授权错误，在“屏幕与系统音频录制”移除旧条目，添加 `/Applications/下班啦.app` 并重新授权，按系统要求退出并重新打开。正式分发应使用稳定的 Developer ID 签名。

回归命令：`./scripts/test-screenshot-permissions.sh`。用注入的截图提供器验证实际调用、重复点击合并、拒绝后不自动重试、后续主动重试、错误分类；不读取屏幕、不弹系统权限窗、不修改隐私设置。实际 macOS TCC 授权与多屏截图仍需安装后人工验证。

参考：[Apple ScreenCaptureKit 权限错误定义](https://developer.apple.com/documentation/screencapturekit/error-constants)。

### 2026-11-05 系统日志确认

本次不是权限开关未开启。`tccd` 在 15:55:02、15:55:07、15:55:16 和 15:56:40 对 `/Applications/下班啦.app` 明确记录：

```text
Failed to match existing code requirement for subject com.workdaybuddy.app and service kTCCServiceScreenCapture
Service kTCCServiceScreenCapture does not allow prompting; returning denied.
```

旧授权的双架构 cdhash 为 `36c19c352ec2a5cf5a10538c4b2d72870fa0a4a0` / `779b6d8a7823d95295c550cac487bd7cd8ebb652`；安装包实际签名为 `af39e39d66f7b91acb7aa43fbb5b92350f75295e` / `cd60d82579527f3e8abf7f0c283a841a16f54b1e`。由系统日志与 `codesign -d -r-` 交叉确认旧授权签名不匹配，不能仅靠开启开关或更换截图 API 修复。

针对当前安装版本，使用系统工具 `tccutil reset ScreenCapture com.workdaybuddy.app` 清除该应用的旧截屏授权，再退出重开应用、点击相机并在系统设置重新授权。不清除其他应用或系统音频权限。不要在重新授权之后再替换测试包，否则 ad-hoc 签名变化可能再次触发同样问题。长期解决需要使用稳定证书签名的构建。
