#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/cache/clang
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/cache/clang"

# SwiftPM incrementally copies resources but does not always remove files that
# moved out of Sources. Recreate the processed bundle so retired animation
# versions can never leak into a release package.
rm -rf "$ROOT/.build/release/DouhuaPet_DouhuaPet.bundle"
swift build -c release

# Remove the legacy in-repository app path used before the signed bundle moved
# to ~/Applications (Documents is File Provider-backed on this machine).
rm -rf "$ROOT/.build/DouhuaPet.app"

APP="${DOUHUA_APP_OUTPUT:-$HOME/Applications/DouhuaPet.app}"
APP_PARENT="$(dirname "$APP")"
STAGING="$APP_PARENT/.DouhuaPet.app.staging"
mkdir -p "$APP_PARENT"
rm -rf "$STAGING"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/Contents/MacOS"
cp "$ROOT/.build/release/DouhuaPet" "$STAGING/Contents/MacOS/DouhuaPet"
cp "$ROOT/Resources/Info.plist" "$STAGING/Contents/Info.plist"
if [ -d "$ROOT/.build/release/DouhuaPet_DouhuaPet.bundle" ]; then
    mkdir -p "$STAGING/Contents/Resources"
    cp -R "$ROOT/.build/release/DouhuaPet_DouhuaPet.bundle" "$STAGING/Contents/Resources/"
fi
chmod +x "$STAGING/Contents/MacOS/DouhuaPet"
/usr/bin/xattr -cr "$STAGING"
/usr/bin/codesign --force --sign - "$STAGING"
/usr/bin/codesign --verify --deep --strict "$STAGING"

rm -rf "$APP"
mv "$STAGING" "$APP"
trap - EXIT
/usr/bin/codesign --verify --deep --strict "$APP"

rm -f "$ROOT/.build/DouhuaPet.app.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/.build/DouhuaPet.app.zip"
echo "Built $APP"
echo "Packaged $ROOT/.build/DouhuaPet.app.zip"
