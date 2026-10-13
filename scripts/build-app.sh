#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
xcodebuild -project OffWorkNow.xcodeproj -scheme OffWorkNow \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/OffWorkNowDerivedData build CODE_SIGN_IDENTITY=- CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
ditto 'build/OffWorkNowDerivedData/Build/Products/Debug/下班啦.app' 'build/下班啦.app'
codesign --verify --deep --strict 'build/下班啦.app'
printf '已生成 %s/build/下班啦.app（本地 Debug、ad-hoc 签名）\n' "$PWD"
