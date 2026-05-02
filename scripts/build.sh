#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/UsageBoard.app"
PLIST="$APP_BUNDLE/Contents/Info.plist"
UPDATE_CHECK_URL="${UB_UPDATE_CHECK_URL:-}"

# --- Kill running instance ---
pkill -f "UsageBoard.app" 2>/dev/null && echo "已关闭运行中的 UsageBoard" || true

# --- Build ---
echo "构建 release..."
swift build -c release

# --- Copy binary & plugins ---
echo "打包 app..."
cp .build/release/UsageBoard "$APP_BUNDLE/Contents/MacOS/UsageBoard"
mkdir -p "$APP_BUNDLE/Contents/Resources/Plugins"
cp "$PROJECT_DIR/Resources/BundledPlugins/"*.py "$APP_BUNDLE/Contents/Resources/Plugins/"

# --- Inject update check URL into Info.plist ---
if [ -n "$UPDATE_CHECK_URL" ]; then
    /usr/libexec/PlistBuddy -c "Add :UBUpdateCheckURL string ${UPDATE_CHECK_URL}" "$PLIST" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :UBUpdateCheckURL ${UPDATE_CHECK_URL}" "$PLIST"
fi

codesign --force --deep --sign - "$APP_BUNDLE"

# --- Launch ---
echo "启动 UsageBoard..."
open "$APP_BUNDLE"
