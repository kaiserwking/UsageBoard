#!/usr/bin/env bash
set -euo pipefail

# --- 发布脚本 ---
# 本地构建签名打包，可选上传到服务器。
# 上传需设置以下环境变量：
#   UB_DEPLOY_HOST        SSH 目标，如 root@your-server
#   UB_DEPLOY_PATH        服务器上存放目录，如 /data/web/usageboard
#   UB_DOWNLOAD_BASE_URL  下载根 URL，如 https://example.com/usageboard
#   UB_UPDATE_CHECK_URL   version.json 的完整 URL，如 https://example.com/usageboard/version.json
# 不设置则仅本地构建，跳过上传。

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/UsageBoard.app"
PLIST="$APP_BUNDLE/Contents/Info.plist"
REMOTE_HOST="${UB_DEPLOY_HOST:-}"
REMOTE_PATH="${UB_DEPLOY_PATH:-}"
DOWNLOAD_BASE_URL="${UB_DOWNLOAD_BASE_URL:-}"
UPDATE_CHECK_URL="${UB_UPDATE_CHECK_URL:-}"

# --- Version handling ---
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")

if [ $# -gt 0 ]; then
    NEW_VERSION="$1"
else
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
    NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
fi

echo "版本: $CURRENT_VERSION → $NEW_VERSION"

# --- Release notes ---
LAST_TAG=$(git tag --sort=-version:refname | head -1)
if [ $# -ge 2 ]; then
    RAW_NOTES="$2"
elif [ -n "$LAST_TAG" ]; then
    RAW_NOTES=$(git log "${LAST_TAG}..HEAD" --format="- %s" 2>/dev/null || echo "")
else
    RAW_NOTES=""
fi
# Escape newlines for JSON
NOTES=$(echo "$RAW_NOTES" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])')

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST"

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
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | tail -1

# --- Zip ---
ZIP_NAME="UsageBoard-${NEW_VERSION}.zip"
cd "$DIST_DIR"
rm -f UsageBoard-*.zip
ditto -c -k --sequesterRsrc --keepParent "UsageBoard.app" "$ZIP_NAME"
cd "$PROJECT_DIR"
echo "已生成: $DIST_DIR/$ZIP_NAME"

# --- version.json ---
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ZIP_SIZE=$(stat -f%z "$DIST_DIR/$ZIP_NAME")

if [ -n "$DOWNLOAD_BASE_URL" ]; then
    DOWNLOAD_URL="${DOWNLOAD_BASE_URL}/${ZIP_NAME}"
    cat > "$DIST_DIR/version.json" << EOF
{
  "updatedAt" : "${UPDATED_AT}",
  "latestVersion" : "${NEW_VERSION}",
  "downloadURL" : "${DOWNLOAD_URL}",
  "notes" : "${NOTES}"
}
EOF
else
    cat > "$DIST_DIR/version.json" << EOF
{
  "updatedAt" : "${UPDATED_AT}",
  "latestVersion" : "${NEW_VERSION}",
  "notes" : "${NOTES}"
}
EOF
fi

echo "已生成: $DIST_DIR/version.json"
echo ""
echo "version.json 内容:"
cat "$DIST_DIR/version.json"
echo ""

# --- Upload ---
if [ -n "$REMOTE_HOST" ] && [ -n "$REMOTE_PATH" ]; then
    echo "上传到 ${REMOTE_HOST}:${REMOTE_PATH}..."
    scp "$DIST_DIR/$ZIP_NAME" "$DIST_DIR/version.json" "${REMOTE_HOST}:${REMOTE_PATH}/"

    echo "清理服务器旧版本..."
    ssh "$REMOTE_HOST" "cd ${REMOTE_PATH} && ls -1t UsageBoard-*.zip 2>/dev/null | tail -n +4 | xargs rm -f 2>/dev/null || true"
else
    echo "跳过上传：未设置 UB_DEPLOY_HOST / UB_DEPLOY_PATH / UB_DOWNLOAD_BASE_URL"
fi

echo ""
echo "发布完成: v${NEW_VERSION}"
