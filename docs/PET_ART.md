# 日系手绘桌面伙伴

最新：五张 `*-music.png` 新增耳机听歌动作，内置共 **180 帧**。各角色完整动作与单击/双击操作见 [PET_ANIMATIONS.md](PET_ANIMATIONS.md)，生成词见 [music-art-prompts.json](music-art-prompts.json)。

2026-10-13 新增：`fox.png` 为 6×4 小狐妖基础动作图集，五张 `*-drink.png` 为 3×2 喝水图集。内置动画共 150 帧。喝水动作每帧 0.26 秒，成功打卡后播放一次；连续点击重新播放。双击动画区域轮换角色。自定义序列帧见 [CUSTOM_PETS.md](CUSTOM_PETS.md)。

新增 `report-ui.png` 为 3×2 日报图标：笑脸、无奈、哭脸、水杯、钱袋、时钟。原始生成词见 [fox-and-drink-prompts.json](fox-and-drink-prompts.json) 和 [report-art-prompts.json](report-art-prompts.json)。[狐妖原画](assets/fox-portrait.png) · [狐妖动画](assets/fox-actions.gif) · [喝水动画](assets/pets-drinking.gif)。

2026-10-12 重做。通过内置 **image_gen** 生成，不使用 CLI/API fallback。原始透明 PNG 已复制进 `Resources/PetArt/`，随 macOS 和 iOS 一起打包，不依赖生成缓存目录或网络。完整生成提示词见 [pet-art-prompts.json](pet-art-prompts.json)。

## 素材与帧定义

| 文件 | 尺寸 / 网格 | 从上到下四组动作，每组从左到右 6 帧 |
|---|---|---|
| `cat.png` | 1536×1024 / 6×4 | 坐姿眨眼、蜷睡打呼噜、弓背伸展、挥爪庆祝 |
| `dog.png` | 1536×1024 / 6×4 | 摇尾眨眼、犬吠、站立作揖、开心跳跃 |
| `worker.png` | 1536×1024 / 6×4 | 拼命敲键盘、累到灵魂出窍、思考、合电脑伸懒腰 |
| `goldfish.png` | 1536×1024 / 6×4 | 摆尾游动、吐泡泡、转向、开心翻游 |
| `controls.png` | 1254×1254 / 2×2 | 左上水杯、右上时间纸签、左下打卡底图、右下已打卡底图 |

美术为细棕色线条、水彩纹理、暖色漫画 Q 版角色。应用读取 PNG 原始 alpha；生成图集名义每格 256×256；通过 `atlas-layout.json` 按实际透明间隙校准行/列边界，完整取出耳朵、尾巴等。运行时统一为 288×288 透明画布，以固定比例与公共基线放置，不逐帧缩放，避免因为姿势变化导致角色大小跳动。UI 图标加载时裁掉透明边距；数字、杯数和按钮中文用原生文字叠加，保证清晰和实时更新。

## 播放

- 每帧 0.18 秒；猫打呼噜每帧 0.28 秒。完整播放一轮后才切动作。
- 待机随机持续 3–6 轮，再随机挑选一个代表动作播放 1–3 轮，然后回到待机。
- 加班中的打工人更常出现灵魂出窍；打卡后在庆祝与待机之间切换。
- 小金鱼还有轻微左右、上下移动。犬吠与呼噜是画面动作，不播放声音。
- 使用单调时钟计算帧，不受系统时间调节影响。视图消失时任务取消；`animate=false` 或“减少动态效果”使用静帧。
- 图像按宠物首次使用时加载并缓存；不在每帧读盘或重复解码。

## 桌面 UI

窗口从 290×450 缩为 240×290，透明底。从上到下排列为“水杯 × 杯数 | 时间”、宠物动画、打卡按钮。底部按钮只在工作日下班倒计时归零及加班期间且尚未打卡时展示；下班前、休息日和打卡后隐藏，同时保留底部高度避免宠物跳动。数字时间也是设置按钮；水杯点击记一杯、右键撤销上一杯；宠物可拖动、右键设置/退出。移除“距离下班”“拖动宠物”等常驻文字和加班长文案，定时系统通知保留。

下班前显示倒计时，加班显示 `+HH:MM:SS`；打卡后显示 `✓ HH:MM`（实际打卡时刻），休息日显示时间占位符。所有按钮保留键盘操作、VoiceOver 标签与帮助提示。杯数仍用历史每杯水量累计；不会改变既有喝水数据。

## 预览与验证

[浅色](assets/pets-light.png) · [深色](assets/pets-dark.png) · [动作 GIF](assets/pets-actions.gif)

预览由实际 `PetControls` / `PetSprite` SwiftUI 组件离屏渲染，GIF 按顺序展示四组动作，用于观察美术帧，不是实际桌面录屏或随机调度的交互验证。真实桌面拖动、按钮点击、随机切换和长期能耗仍需人工验收。

在 macOS 构建后重新生成预览：

```sh
xcrun swiftc -parse-as-library -module-cache-path build/PreviewModuleCache \
  -I build/XiaBanLaDerivedData/Build/Products/Debug \
  -o build/render-pet-previews \
  Sources/SharedUI/PetAvatar.swift Sources/SharedUI/PetArtwork.swift \
  Sources/SharedUI/PetControls.swift Sources/SharedUI/CustomPetLibrary.swift scripts/render-pet-previews.swift \
  build/XiaBanLaDerivedData/Build/Products/Debug/WorkdayCore.o
build/render-pet-previews
```
