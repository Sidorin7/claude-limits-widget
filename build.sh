#!/bin/bash
# Builds ClaudeLimits.app (with the desktop widget inside) and installs it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

# The widget shares data with the app through an app group, which needs a real signing identity.
# By default the first "Apple Development" certificate in the keychain is used; the team ID is
# read from it. Override with IDENTITY=... TEAM_ID=... ./build.sh
IDENTITY="${IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)}"
[ -n "$IDENTITY" ] || { echo "No Apple Development certificate found (sign in to Xcode with an Apple ID)." >&2; exit 1; }
TEAM_ID="${TEAM_ID:-$(security find-certificate -c "$IDENTITY" -p | openssl x509 -noout -subject -nameopt multiline | sed -n 's/^ *organizationalUnitName *= *//p')}"
[ -n "$TEAM_ID" ] || { echo "Could not read the team ID from \"$IDENTITY\"." >&2; exit 1; }

swift build -c release --product ClaudeLimits
swift build -c release --product ClaudeLimitsWidget
BIN="$(swift build -c release --show-bin-path)"

APP="build/ClaudeLimits.app"
WIDGET="$APP/Contents/PlugIns/ClaudeLimitsWidget.appex"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$WIDGET/Contents/MacOS"
cp "$BIN/ClaudeLimits" "$APP/Contents/MacOS/"
cp "$BIN/ClaudeLimitsWidget" "$WIDGET/Contents/MacOS/"
fill() { sed "s/\$(TEAM_ID)/$TEAM_ID/g" "$1" > "$2"; }
fill Resources/Info.plist "$APP/Contents/Info.plist"
fill Resources/Widget-Info.plist "$WIDGET/Contents/Info.plist"
fill Resources/App.entitlements build/App.entitlements
fill Resources/Widget.entitlements build/Widget.entitlements

# Inside out: the extension first, then the app that contains it.
codesign --force --options runtime --sign "$IDENTITY" --entitlements build/Widget.entitlements "$WIDGET"
codesign --force --options runtime --sign "$IDENTITY" --entitlements build/App.entitlements "$APP"

DEST="$HOME/Applications/ClaudeLimits.app"
pkill -x ClaudeLimits 2>/dev/null || true
pkill -x ClaudeLimitsWidget 2>/dev/null || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"
# Let the system pick up the new widget right away.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/ClaudeLimitsWidget.appex" || true
echo "Installed: $DEST"
