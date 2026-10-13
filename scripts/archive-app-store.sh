#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -z "${XBL_TEAM_ID:-}" ]]; then
  print -u2 '请设置 XBL_TEAM_ID 为自己的 Apple Developer Team ID，并先在 Xcode 登录开发者账号。'
  exit 2
fi
platform="${1:-macOS}"
case "$platform" in
  macOS) scheme=OffWorkNow; destination='generic/platform=macOS'; archs=( 'ARCHS=arm64 x86_64' 'ONLY_ACTIVE_ARCH=NO' ) ;;
  iOS) scheme=OffWorkNow-iOS; destination='generic/platform=iOS'; archs=() ;;
  *) print -u2 '用法：XBL_TEAM_ID=你的TeamID ./scripts/archive-app-store.sh macOS|iOS'; exit 2 ;;
esac
xcodebuild -project OffWorkNow.xcodeproj -scheme "$scheme" -configuration Release \
  -destination "$destination" -derivedDataPath build/StoreDerivedData \
  -archivePath "build/${scheme}.xcarchive" \
  "DEVELOPMENT_TEAM=$XBL_TEAM_ID" CODE_SIGN_STYLE=Automatic \
  "${archs[@]}" -allowProvisioningUpdates archive
print "已生成 build/${scheme}.xcarchive；用 Xcode Organizer 校验并选择 App Store Connect。"
print '此脚本只归档，不上传，不发布。'
