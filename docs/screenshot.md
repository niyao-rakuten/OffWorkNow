# macOS 截图

点击桌面精灵底部相机按钮，在目标屏幕拖动选区。首次使用需在系统设置授权屏幕录制，系统可能要求重启应用。

选区工具可拖动选区，也可拖动八个控制点改变范围。编辑工具包含铅笔、矩形、椭圆和涂抹马赛克；颜色选择器控制后续画笔和形状颜色。撤销或 Command-Z 删除最后一次标注。调整选区仅改变裁剪范围，已有标注保持屏幕位置。

✅ / Return 将最终图片复制到剪贴板；❌ / Escape 丢弃。截图不写入磁盘、不发送到聊天。

## 验证

macOS Debug 构建通过。需桌面人工验收：首次权限拒绝与授权后重试、多显示器选择、Retina 与非 Retina 粘贴尺寸、八方向缩放、边缘选区工具栏、各标注工具、连续马赛克、撤销、确认复制及取消保留原剪贴板。

## 图标

使用内置 image_gen 生成，透明 PNG：`Resources/Assets.xcassets/ScreenshotCamera.imageset/camera.png`。

最终编辑提示词（内置 image_gen）：

> Use case: precise-object-edit. Edit target: attached existing camera button icon. Remove both eyes, all pink blush/cheek marks, and the smiling mouth completely, reconstruct those areas as uninterrupted cream watercolor camera body. Keep only a simple inanimate camera. Preserve the original camera silhouette, lens, flash, shutter button, muted mint and cream colors, cocoa pencil outlines, hand-drawn watercolor texture, placement and scale. No face, no anthropomorphic features, no text, no additional objects. Preserve genuinely transparent background.
