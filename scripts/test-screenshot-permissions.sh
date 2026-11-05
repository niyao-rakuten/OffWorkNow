#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/screenshot-regression
xcrun swiftc -target "$(uname -m)-apple-macos13.0" -parse-as-library -module-cache-path "$PWD/build/screenshot-regression/module-cache" \
  Sources/WorkdayBuddy/ScreenshotController.swift Tests/ScreenshotRegression/PermissionFlow.swift \
  -o build/screenshot-regression/permission-flow
build/screenshot-regression/permission-flow
