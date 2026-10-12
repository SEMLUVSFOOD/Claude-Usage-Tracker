#!/bin/bash
# Builds "Claude Usage.app" with only the Xcode Command Line Tools (no Xcode).
#
# SwiftPM compiles the app sources, then the bundle is assembled by hand:
# Info.plist, localizations, app icon, logo images and Sparkle.framework.
# Output: build/local/Claude Usage.app and build/local/Claude-Usage.dmg
#
# Usage: scripts/build-local.sh [--install]
#   --install   quit the running app, replace /Applications/Claude Usage.app
#               (old copy moved to the Trash) and relaunch it.
#
# Signing: uses the "Claude Usage Local" certificate when present (stable
# identity, so keychain "Always Allow" survives rebuilds), else ad-hoc.
# Override with SIGN_IDENTITY="name or -".
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/Claude Usage"
WORK="$REPO/build/local"
PKG="$WORK/pkg"
APP="$WORK/Claude Usage.app"
NOTCHKIT="$WORK/DynamicNotchKit"
PBX="$REPO/Claude Usage.xcodeproj/project.pbxproj"

MARKETING_VERSION=$(grep -m1 'MARKETING_VERSION = ' "$PBX" | sed 's/.*= \(.*\);/\1/')
BUILD_NUMBER=$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$PBX" | sed 's/.*= \(.*\);/\1/')
BUNDLE_ID="HamedElfayome.Claude-Usage"

if [ -z "${SIGN_IDENTITY:-}" ]; then
    if security find-certificate -c "Claude Usage Local" >/dev/null 2>&1; then
        SIGN_IDENTITY="Claude Usage Local"
    else
        SIGN_IDENTITY="-"
    fi
fi

echo "==> Claude Usage $MARKETING_VERSION ($BUILD_NUMBER), signing: $SIGN_IDENTITY"
mkdir -p "$WORK"

# --- Swift 6.2 toolchain: the project relies on default MainActor isolation
#     (SWIFT_DEFAULT_ACTOR_ISOLATION), which older Command Line Tools lack.
#     Unpacked into build/local, nothing is installed system-wide.
SWIFT_VERSION_TAG="6.2.1"
TOOLCHAIN="$WORK/toolchain"
if [ ! -x "$TOOLCHAIN/usr/bin/swift" ]; then
    echo "==> Downloading Swift $SWIFT_VERSION_TAG toolchain"
    curl -fL --progress-bar -o "$WORK/swift.pkg" \
        "https://download.swift.org/swift-$SWIFT_VERSION_TAG-release/xcode/swift-$SWIFT_VERSION_TAG-RELEASE/swift-$SWIFT_VERSION_TAG-RELEASE-osx.pkg"
    pkgutil --check-signature "$WORK/swift.pkg" | grep -q "trusted by the Apple notary service"
    rm -rf "$WORK/toolchain-x"
    pkgutil --expand-full "$WORK/swift.pkg" "$WORK/toolchain-x"
    mv "$WORK/toolchain-x/swift-$SWIFT_VERSION_TAG-RELEASE-osx-package.pkg/Payload" "$TOOLCHAIN"
    rm -rf "$WORK/toolchain-x" "$WORK/swift.pkg"
fi
SWIFT="$TOOLCHAIN/usr/bin/swift"

# --- DynamicNotchKit: vendored copy without SwiftUI macros (@Entry, #Preview),
#     whose compiler plugins ship only with full Xcode.
if [ ! -d "$NOTCHKIT" ]; then
    git clone --quiet --depth 1 --branch 1.1.0 https://github.com/MrKai77/DynamicNotchKit "$NOTCHKIT"
    cat > "$NOTCHKIT/Package.swift" <<'EOF'
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DynamicNotchKit",
    platforms: [.macOS(.v13)],
    products: [.library(name: "DynamicNotchKit", targets: ["DynamicNotchKit"])],
    targets: [.target(name: "DynamicNotchKit", path: "Sources")]
)
EOF
    cat > "$NOTCHKIT/Sources/DynamicNotchKit/Utility/EnvironmentValues+Extensions.swift" <<'EOF'
import SwiftUI

private struct NotchStyleKey: EnvironmentKey {
    static let defaultValue: DynamicNotchStyle = .auto
}

private struct NotchSectionKey: EnvironmentKey {
    static let defaultValue: DynamicNotchSection = .expanded
}

extension EnvironmentValues {
    var notchStyle: DynamicNotchStyle {
        get { self[NotchStyleKey.self] }
        set { self[NotchStyleKey.self] = newValue }
    }

    var notchSection: DynamicNotchSection {
        get { self[NotchSectionKey.self] }
        set { self[NotchSectionKey.self] = newValue }
    }
}

enum DynamicNotchSection {
    case expanded
    case compactLeading
    case compactTrailing
}
EOF
    find "$NOTCHKIT/Sources" -name '*.swift' -print0 | xargs -0 python3 "$REPO/scripts/strip_previews.py"
fi

# --- App sources: fresh copy with #Preview blocks removed
rm -rf "$PKG/Sources"
mkdir -p "$PKG/Sources/ClaudeUsage"
rsync -a --include='*/' --include='*.swift' --exclude='*' "$SRC/" "$PKG/Sources/ClaudeUsage/"
find "$PKG/Sources" -name '*.swift' -print0 | xargs -0 python3 "$REPO/scripts/strip_previews.py"

cat > "$PKG/Package.swift" <<'EOF'
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1"),
        .package(path: "../DynamicNotchKit"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeUsage",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit"),
            ],
            path: "Sources/ClaudeUsage",
            // Mirror the Xcode target: Swift 5 mode, default MainActor
            // isolation, approachable concurrency.
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("InferSendableFromCaptures"),
                .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
                .enableUpcomingFeature("DisableOutwardActorInference"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
EOF

echo "==> Compiling (release)"
(cd "$PKG" && "$SWIFT" build -c release)
BIN_DIR="$(cd "$PKG" && "$SWIFT" build -c release --show-bin-path)"

# --- Assemble the bundle
echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/ClaudeUsage" "$APP/Contents/MacOS/Claude Usage"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Claude Usage"
install_name_tool -delete_rpath "$TOOLCHAIN/usr/lib/swift-6.2/macosx" "$APP/Contents/MacOS/Claude Usage" 2>/dev/null || true
cp -R "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"

sed -e 's/$(DEVELOPMENT_LANGUAGE)/en/' \
    -e 's/$(EXECUTABLE_NAME)/Claude Usage/' \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/" \
    -e 's/$(PRODUCT_NAME)/Claude Usage/' \
    -e 's/$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/' \
    -e "s/\$(MARKETING_VERSION)/$MARKETING_VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/" \
    -e 's/$(MACOSX_DEPLOYMENT_TARGET)/14.0/' \
    "$SRC/Resources/Info.plist" > "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Claude Usage" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

for lproj in "$SRC"/Resources/*.lproj; do
    cp -R "$lproj" "$APP/Contents/Resources/"
done

# Asset catalog stand-ins (actool needs Xcode): .icns icon + loose logo PNGs
ICONSET="$WORK/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
cp "$SRC"/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
for logo in header about wizard; do
    name="$(tr '[:lower:]' '[:upper:]' <<< "${logo:0:1}")${logo:1}Logo"
    set_dir="$SRC/Assets.xcassets/$name.imageset"
    cp "$set_dir/${logo}_logo_1x.png" "$APP/Contents/Resources/$name.png"
    cp "$set_dir/${logo}_logo.png" "$APP/Contents/Resources/$name@2x.png"
done

# --- Sign (inside-out)
echo "==> Signing"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$SPARKLE"/XPCServices/*.xpc "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app"; do
    [ -e "$item" ] && codesign --force --sign "$SIGN_IDENTITY" "$item"
done
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements "$SRC/Claude UsageRelease.entitlements" "$APP"
codesign --verify --deep --strict "$APP"

# --- DMG (drag to Applications to update)
echo "==> Creating DMG"
STAGE="$WORK/dmg"
rm -rf "$STAGE" "$WORK/Claude-Usage.dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Claude Usage" -srcfolder "$STAGE" -ov -format UDZO "$WORK/Claude-Usage.dmg"
rm -rf "$STAGE"

echo "==> Built: $APP"
echo "==> DMG:   $WORK/Claude-Usage.dmg"

if [ "${1:-}" = "--install" ]; then
    echo "==> Installing to /Applications"
    osascript -e 'tell application id "'"$BUNDLE_ID"'" to quit' 2>/dev/null || true
    sleep 2
    pkill -x "Claude Usage" 2>/dev/null || true
    if [ -d "/Applications/Claude Usage.app" ]; then
        osascript -e 'tell application "Finder" to delete POSIX file "/Applications/Claude Usage.app"' >/dev/null
    fi
    cp -R "$APP" "/Applications/"
    open "/Applications/Claude Usage.app"
    echo "==> Installed and launched"
fi
