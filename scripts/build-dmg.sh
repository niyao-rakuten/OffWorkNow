#!/bin/zsh
# Create a drag-to-Applications disk image. No credentials, upload, or publication.
set -euo pipefail
cd "${0:A:h:h}"

if (( $# > 1 )) || [[ "${1:-}" == --help ]]; then
  print '用法：./scripts/build-dmg.sh [已经签名的.app路径]'
  print '不传参数：构建 arm64 + x86_64 Release 本地测试版；传入路径：原样封装，不修改应用签名。'
  exit 0
fi
mkdir -p build
if (( $# == 0 )); then
  xcodebuild -project OffWorkNow.xcodeproj -scheme OffWorkNow \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath build/DMGDerivedData \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY=- CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
  app="$PWD/build/DMGDerivedData/Build/Products/Release/下班啦.app"
else
  app="${1:A}"
fi
[[ -d "$app" && "$app" == *.app ]] || { print -u2 "应用包不存在：$app"; exit 2; }
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")
architectures=$(lipo -archs "$app/Contents/MacOS/$executable")
if [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]; then
  architecture=universal
elif [[ "$architectures" == arm64 || "$architectures" == x86_64 ]]; then
  architecture="$architectures"
else
  print -u2 "未识别的应用架构：$architectures"; exit 2
fi
[[ "$version" == [0-9]* && "$version" != *[^0-9.]* ]] || { print -u2 '版本号须为数字及点'; exit 2; }
stage=$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
ditto "$app" "$stage/下班啦.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/安装说明.txt" <<'INSTALL'
下班啦 · 安装说明

1. 先退出正在运行的旧版“下班啦”。
2. 将“下班啦.app”拖入旁边的“Applications（应用程序）”文件夹。
3. 复制完成后，从“应用程序”打开“下班啦”，再推出此磁盘映像。

最低 macOS 13。启动后显示收工日记，屏幕顶部有菜单栏入口和桌面宠物。
单击宠物切换动作，双击切换形象，拖动调整位置。
通知与工作安排在设置中配置。开机启动请在安装到固定位置后开启。
退出应用：菜单栏面板 → 退出，或右键桌面宠物 → 退出下班啦。

默认打包脚本生成的是本地测试签名版，未经过 Apple 公证。
面向其他用户公开分发前，请由开发者完成 Developer ID 签名与 Apple 公证。
INSTALL
output="$PWD/build/下班啦-${version}-macOS-${architecture}.dmg"
hdiutil create -volname '下班啦 安装' -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$output"
hdiutil verify "$output"
shasum -a 256 "$output" > "$output.sha256"
print "已生成：$output"
print "应用架构：$architectures"
print '本脚本不会上传、公证或发布；正式分发请完成 Developer ID 签名和公证。'
