#!/bin/zsh
# Builds ClaudeMon.app into ./dist. With --install, copies it to ~/Applications and launches it.
#
# Uses `xcrun swift` deliberately: a swiftly toolchain earlier on PATH may not match the
# installed Xcode SDK and fails with "unknown argument: '-target-arch-variant'".
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

xcrun swift build -c release
bin="$(xcrun swift build -c release --show-bin-path)"

app="dist/ClaudeMon.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/ClaudeMon" "$app/Contents/MacOS/ClaudeMon"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$bin/claudemon-report" dist/claudemon-report

# Ad-hoc signature. macOS ties the Keychain "Always Allow" grant to the signature, so
# expect the Keychain prompt again after each rebuild.
codesign --force --sign - --timestamp=none "$app"
echo "Built $root/$app"

if [[ "${1:-}" == "--install" ]]; then
    dest="$HOME/Applications"
    mkdir -p "$dest"
    pkill -x ClaudeMon 2>/dev/null || true
    rm -rf "$dest/ClaudeMon.app"
    cp -R "$app" "$dest/"
    open "$dest/ClaudeMon.app"
    echo "Installed and launched $dest/ClaudeMon.app"
fi
