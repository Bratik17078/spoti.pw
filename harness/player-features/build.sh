#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
APP="$HERE/build/PlayerFeatures.app"
mkdir -p "$APP"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -O1 -Wall \
    -Wno-deprecated-declarations -I"$SRC" -isysroot "$SDK" \
    "$HERE/main.m" \
    "$SRC/Shared/PlaybackRules/PlaybackRules.m" "$SRC/Shared/PlaybackRules/PlaybackRulesSettings.m" \
    "$SRC/Shared/LyricCards/LyricCards.m" "$SRC/Shared/LyricCards/LyricCardRenderer.m" \
    "$SRC/Shared/AudioVisualization/Visualization.m" "$SRC/Shared/AudioVisualization/SGSpectrum.m" \
    "$SRC/Redesigned/Player/SGRVisualizer.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/Lyrics/Protobuf.m" \
    "$SRC/Settings/SGPage.m" "$SRC/Settings/SGPageStyle.m" "$SRC/Settings/SGModPage.m" "$SRC/Settings/SGGlowSwitch.m" \
    "$SRC/Core/SGPrefs.m" "$SRC/Core/SGLog.m" "$SRC/Core/SGViewTree.m" "$SRC/Core/SGGlass.m" \
    "$SRC/Core/SGUIMode.m" "$SRC/Core/SGFlagForce.m" \
    -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics \
    -framework CoreImage -framework ImageIO -framework AVFoundation \
    -o "$APP/PlayerFeatures"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PlayerFeatures</string>
<key>CFBundleIdentifier</key><string>com.vojta.playerfeatures</string>
<key>CFBundleName</key><string>Player Features</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
echo "built $APP"
