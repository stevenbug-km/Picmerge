#!/bin/bash
#
# Picmerge 一键构建脚本
# ------------------------------------------------------------
# 作用：把多文件 Swift 源码编译成真正可双击运行的 macOS 应用，
#       带上完整图标，结束旧进程，安装到 ~/Applications 并启动。
#
# 为什么要这个脚本：
#   命令行环境里 Swift Package Manager 的沙盒会阻止解析依赖，
#   所以这里直接用 Xcode 自带的 swiftc 编译，再手工组装 .app。
#   每一步都写清楚，方便对照学习「一个 macOS app 包里到底有什么」。
#
# 用法：bash Scripts/build-app.sh

set -euo pipefail

# ---------- 基本路径与版本 ----------
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Picmerge.app"
INSTALL_APP="$HOME/Applications/Picmerge.app"
VERSION="1.6.0"
BUILD_NUMBER="7"

XCODE="/Applications/Xcode.app/Contents/Developer"
if [ ! -d "$XCODE" ]; then
    echo "错误：找不到 Xcode，请确认已安装 /Applications/Xcode.app" >&2
    exit 1
fi
export DEVELOPER_DIR="$XCODE"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

echo "==> 1/7 收集 Swift 源文件"
SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find "$ROOT/Sources/Picmerge" -name '*.swift' | sort)
echo "    共 ${#SOURCES[@]} 个文件"

echo "==> 2/7 编译 arm64 macOS 可执行文件"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc "${SOURCES[@]}" \
    -o "$APP/Contents/MacOS/Picmerge" \
    -sdk "$SDK" \
    -target arm64-apple-macosx13.0 \
    -framework SwiftUI \
    -framework AppKit \
    -framework WebKit \
    -framework UniformTypeIdentifiers \
    -parse-as-library

echo "==> 3/7 生成 macOS 应用图标 (.icns)"
ICON_SRC="$ROOT/Sources/Picmerge/Resources/Assets.xcassets/AppIcon.appiconset/picmerge-icon.png"
ICONSET="$BUILD/Picmerge.iconset"
ICNS="$BUILD/AppIcon.icns"
mkdir -p "$ICONSET"

# macOS 图标需要一组固定文件名和尺寸，iconutil 会把它们打包成 .icns。
make_icon() {
    sips -z "$1" "$1" "$ICON_SRC" --out "$ICONSET/$2" >/dev/null
}
make_icon 16    "icon_16x16.png"
make_icon 32    "icon_16x16@2x.png"
make_icon 32    "icon_32x32.png"
make_icon 64    "icon_32x32@2x.png"
make_icon 128   "icon_128x128.png"
make_icon 256   "icon_128x128@2x.png"
make_icon 256   "icon_256x256.png"
make_icon 512   "icon_256x256@2x.png"
make_icon 512   "icon_512x512.png"
make_icon 1024  "icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$ICNS"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

echo "==> 4/7 写入应用元数据 Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleDisplayName</key><string>Picmerge</string>
    <key>CFBundleName</key><string>Picmerge</string>
    <key>CFBundleIdentifier</key><string>com.picmerge.app</string>
    <key>CFBundleExecutable</key><string>Picmerge</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon.icns</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST

echo "==> 5/7 重新做 ad-hoc 签名（让图标与网络权限生效）"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "==> 6/7 结束旧版本并安装"
osascript -e 'tell application id "com.picmerge.app" to quit' >/dev/null 2>&1 || true
pkill -TERM -f "$INSTALL_APP/Contents/MacOS/Picmerge" >/dev/null 2>&1 || true
mkdir -p "$HOME/Applications"
rm -rf "$INSTALL_APP"
cp -R "$APP" "$INSTALL_APP"

# 通知 LaunchServices 刷新图标缓存，避免 Dock / Finder 显示旧图标或空白图标。
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$INSTALL_APP" >/dev/null 2>&1 || true
fi
touch "$INSTALL_APP"

echo "==> 7/7 启动并验证"
open "$INSTALL_APP"

echo "    版本: $VERSION ($BUILD_NUMBER)"
echo "    图标: $(ls -lh "$INSTALL_APP/Contents/Resources/AppIcon.icns" | awk '{print $5}')"
echo "    程序: $(file -b "$INSTALL_APP/Contents/MacOS/Picmerge")"
if pgrep -f "$INSTALL_APP/Contents/MacOS/Picmerge" >/dev/null; then
    echo "    状态: 已启动 ✓"
else
    echo "    状态: 已安装，正在启动…"
fi
echo "完成：$INSTALL_APP"
