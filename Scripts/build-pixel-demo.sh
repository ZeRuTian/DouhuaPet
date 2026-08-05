#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/cache/clang
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/cache/clang"

swift build -c release --product DouhuaPixelDemo

APP="${DOUHUA_PIXEL_DEMO_OUTPUT:-$HOME/Applications/DouhuaPixelDemo.app}"
APP_PARENT="$(dirname "$APP")"
STAGING="$APP_PARENT/.DouhuaPixelDemo.app.staging"
mkdir -p "$APP_PARENT"
rm -rf "$STAGING"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/Contents/MacOS"
cp "$ROOT/.build/release/DouhuaPixelDemo" "$STAGING/Contents/MacOS/DouhuaPixelDemo"
cp "$ROOT/Resources/PixelDemo-Info.plist" "$STAGING/Contents/Info.plist"
if [ -d "$ROOT/.build/release/DouhuaPet_DouhuaPixelDemo.bundle" ]; then
    mkdir -p "$STAGING/Contents/Resources"
    cp -R "$ROOT/.build/release/DouhuaPet_DouhuaPixelDemo.bundle" "$STAGING/Contents/Resources/"
fi
chmod +x "$STAGING/Contents/MacOS/DouhuaPixelDemo"
/usr/bin/xattr -cr "$STAGING"
/usr/bin/codesign --force --sign - "$STAGING"
/usr/bin/codesign --verify --deep --strict "$STAGING"

rm -rf "$APP"
mv "$STAGING" "$APP"
trap - EXIT
/usr/bin/codesign --verify --deep --strict "$APP"

rm -f "$ROOT/.build/DouhuaPixelDemo.app.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/.build/DouhuaPixelDemo.app.zip"
echo "Built $APP"
echo "Packaged $ROOT/.build/DouhuaPixelDemo.app.zip"
