#!/bin/zsh
# Builds AI Billing Meter.app into ./dist. With --install, copies it to ~/Applications and launches it.
#
# Uses `xcrun swift` deliberately: a swiftly toolchain earlier on PATH may not match the
# installed Xcode SDK and fails with "unknown argument: '-target-arch-variant'".
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

xcrun swift build -c release
bin="$(xcrun swift build -c release --show-bin-path)"

app="dist/AI Billing Meter.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/AIBillingMeter" "$app/Contents/MacOS/AIBillingMeter"
cp Resources/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleExecutable -string AIBillingMeter "$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.bogovich.AIBillingMeter "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp "$bin/billing-meter" dist/billing-meter

# Ad-hoc signature, for local use only (distribution needs a Developer ID or App Store build).
codesign --force --sign - --timestamp=none "$app"
echo "Built $root/$app"

if [[ "${1:-}" == "--install" ]]; then
    dest="$HOME/Applications"
    mkdir -p "$dest"
    pkill -x AIBillingMeter 2>/dev/null || true
    pkill -x ClaudeMon 2>/dev/null || true # the app's former name
    rm -rf "$dest/AI Billing Meter.app"
    cp -R "$app" "$dest/"
    sleep 1 # launching right after pkill can fail with LaunchServices error -600
    open "$dest/AI Billing Meter.app"
    echo "Installed and launched $dest/AI Billing Meter.app"
fi
