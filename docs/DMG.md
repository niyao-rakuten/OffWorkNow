# 制作 DMG 安装包

在项目根目录执行：

```sh
./scripts/build-dmg.sh
```

默认重新构建 Release 版，包含 Apple Silicon（arm64）和 Intel（x86_64）两种架构，不会替换原来的 Debug 运行包。应用使用本地 ad-hoc 签名，无需 Apple Developer 账号。

输出：`build/下班啦-1.1.0-macOS-universal.dmg`（文件名跟随应用版本号）和同名 `.sha256` 校验文件。脚本会校验应用签名、生成压缩只读磁盘映像并校验映像。

安装：先退出旧版 → 打开 DMG → 将“下班啦.app”拖到“Applications” → 从应用程序启动 → 推出 DMG。DMG 是安装介质，应用应复制到固定目录后再运行及配置开机启动；不需要安装后台服务。

## 正式发给其他用户

本地测试签名不等于 Developer ID 签名，也不包含 Apple 公证票据。通过浏览器下载或 AirDrop 分发时，macOS 可能阻止打开。

正式站外发行流程：

1. 使用 Apple Developer 账号，在 Xcode 的 Release 归档中选择 Developer ID / Direct Distribution，生成开启 Hardened Runtime、使用 Developer ID Application 证书签名的应用，并完成 Apple 公证。
2. 使用脚本原样封装导出的应用（不会重签或修改其内部文件）：

   ```sh
   ./scripts/build-dmg.sh '/完整路径/下班啦.app'
   ```

3. 对最终 DMG 签名，使用 `xcrun notarytool submit` 提交公证；确认 Accepted 后执行 `xcrun stapler staple` 和 `xcrun stapler validate`，再验证 Gatekeeper 和真实下载安装。签名或附加票据会改变 DMG，完成后重新生成 SHA-256。

脚本不会读取登录凭证、自动上传或发布。传入已签名应用时，映像内保留的通用安装说明会解释默认脚本的测试签名行为；正式发布时可据实际签名、公证状态调整这段说明。

Apple 官方流程：[Developer ID](https://developer.apple.com/developer-id/) · [macOS 公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

Mac App Store 使用 Xcode Archive → App Store Connect，不提交 DMG。原商店上架流程仍见 [APP_STORE.md](APP_STORE.md)。
