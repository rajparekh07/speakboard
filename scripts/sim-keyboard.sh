#!/bin/bash
# Shows our keyboard in an iOS simulator with no one at the screen, and takes
# screenshots of it (KEY-8). Used by .github/workflows/macos.yml and by hand.
#
#   scripts/sim-keyboard.sh <Speakboard.app> <device type name> <runtime id> <out dir>
#   e.g. scripts/sim-keyboard.sh .build/xcode/Build/Products/Debug-iphonesimulator/Speakboard.app \
#          "iPhone 18 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-2 .build/screenshots
#
# It makes a fresh simulator, deletes it at the end, and writes into <out dir>:
#   harness.png   the keyboard's view hosted in the app (-SpeakboardHarness)
#   keyboard.png  the keyboard extension itself, enabled with Full Access, in
#                 the app's text field
#   keyboard.log  the extension's own log line: its height and Full Access
#
# How the keyboard is enabled, found by enabling it in Settings by hand on
# iOS 27.2 and reading what changed:
#   * Settings > General > Keyboard > Keyboards > Add New Keyboard writes the
#     extension's bundle identifier into AppleKeyboards in .GlobalPreferences.
#   * Allow Full Access writes kTCCServiceKeyboardNetwork rows, allowed, for the
#     app and the extension, into the simulator's TCC.db. `simctl privacy` has
#     no service for it, so this writes the rows itself, while the simulator is
#     shut down. This is the simulator's own database, not the Mac's.
#   * The current keyboard is KeyboardsCurrentAndNext in
#     com.apple.keyboard.preferences.
# These are simulator settings, not API. If an iOS release moves them, the
# check at the end fails (the extension's log line is missing or says
# fullAccess=false) rather than passing on a screenshot of the wrong keyboard.
set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <Speakboard.app> <device type name> <runtime id> <out dir>" >&2
    exit 2
fi
app=$1
device_type=$2
runtime=$3
out=$4

app_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
appex="$app/PlugIns/SpeakboardKeyboard.appex"
ext_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$appex/Info.plist")
mkdir -p "$out"

udid=$(xcrun simctl create "speakboard-$$" "$device_type" "$runtime")
cleanup() {
    xcrun simctl shutdown "$udid" > /dev/null 2>&1 || true
    xcrun simctl delete "$udid" > /dev/null 2>&1 || true
}
trap cleanup EXIT
echo "sim-keyboard: simulator $udid ($device_type, $runtime); app $app_id; keyboard $ext_id"

boot() {
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b > /dev/null
}

# Waits up to $2 seconds for a process whose command line matches the regex $1.
wait_for_process() {
    local i=0
    while [ "$i" -lt "$2" ]; do
        if pgrep -f "$1" > /dev/null; then
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    return 1
}

boot
xcrun simctl install "$udid" "$app"

# 1. The harness: the keyboard's view, hosted in the app.
xcrun simctl launch "$udid" "$app_id" -SpeakboardHarness > /dev/null
sleep 5
xcrun simctl io "$udid" screenshot "$out/harness.png" > /dev/null 2>&1
xcrun simctl terminate "$udid" "$app_id"

# 2. Enable the keyboard and make it the current one.
xcrun simctl spawn "$udid" defaults write .GlobalPreferences AppleKeyboards \
    -array "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji" "$ext_id"
xcrun simctl spawn "$udid" defaults write .GlobalPreferences AppleKeyboardsExpanded -int 1
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences KeyboardsCurrentAndNext \
    -array "$ext_id" "en_US@sw=QWERTY;hw=Automatic"
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences KeyboardLastUsed "$ext_id"

# 3. Allow Full Access, with the simulator shut down so tccd reads the rows at boot.
xcrun simctl shutdown "$udid"
tcc="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/TCC/TCC.db"
if [ ! -f "$tcc" ]; then
    echo "sim-keyboard: FAIL: no TCC.db at $tcc" >&2
    exit 1
fi
for client in "$app_id" "$ext_id"; do
    sqlite3 "$tcc" "INSERT OR REPLACE INTO access
        (service, client, client_type, auth_value, auth_reason, auth_version, flags)
        VALUES ('kTCCServiceKeyboardNetwork', '$client', 0, 2, 4, 1, 0);"
done
boot

# 4. Focus the app's text field, so the system shows the current keyboard.
start=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl launch "$udid" "$app_id" -SpeakboardFocusField > /dev/null
# Scoped to this simulator: the extension runs from this device's own folder
# (.../CoreSimulator/Devices/$udid/data/...), so a Speakboard keyboard running in
# another simulator on the host does not count. The extension's log line, read
# from this simulator only, is the gate in any case.
if ! wait_for_process "Devices/$udid/.*SpeakboardKeyboard\.appex" 30; then
    echo "sim-keyboard: FAIL: the keyboard extension did not start" >&2
    xcrun simctl io "$udid" screenshot "$out/keyboard.png" > /dev/null 2>&1 || true
    exit 1
fi
sleep 4
xcrun simctl io "$udid" screenshot "$out/keyboard.png" > /dev/null 2>&1

# 5. Check what the extension itself reported.
xcrun simctl spawn "$udid" log show --style compact --start "$start" \
    --predicate "subsystem == \"$ext_id\"" > "$out/keyboard.log" 2>&1 || true
line=$(grep -o 'speakboard-shell .*' "$out/keyboard.log" | tail -1 || true)
if [ -z "$line" ]; then
    echo "sim-keyboard: FAIL: no log line from the keyboard extension (see $out/keyboard.log)" >&2
    exit 1
fi
echo "sim-keyboard: the extension reported: $line"
case "$line" in
    *fullAccess=true*) ;;
    *)
        echo "sim-keyboard: FAIL: the extension does not have Full Access" >&2
        exit 1
        ;;
esac
echo "sim-keyboard: OK ($out/harness.png, $out/keyboard.png)"
