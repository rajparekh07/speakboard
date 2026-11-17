#!/bin/bash
# Shows our keyboard in an iOS simulator with no one at the screen, and takes
# screenshots of it (KEY-8). Used by .github/workflows/macos.yml and by hand.
#
#   scripts/sim-keyboard.sh <Speakboard.app> <device type name> <runtime id> <out dir> [<derived data>]
#   e.g. scripts/sim-keyboard.sh .build/xcode/Build/Products/Debug-iphonesimulator/Speakboard.app \
#          "iPhone 18 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-2 .build/screenshots .build/xcode
#
# It makes a fresh simulator, deletes it at the end, and writes into <out dir>:
#   harness.png        the keyboard's view hosted in the app (-SpeakboardHarness)
#   keyboard.png       the keyboard extension itself, enabled with Full Access,
#                      in the app's text field, in light appearance
#   keyboard-dark.png  the same in dark appearance
#   keyboard.log       the extension's own log line: its height, key count and
#                      Full Access
# With <derived data> (where Speakboard.xcodeproj was built), it then runs the
# UI tests (scheme SpeakboardUITests, KEY-62) on this simulator, once in light
# and once in dark appearance: they type through the extension and read the
# field back. Each run's log, result bundle and exported screenshots go to
# ui-<appearance>.log, ui-<appearance>.xcresult and ui-<appearance>/.
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

if [ "$#" -ne 4 ] && [ "$#" -ne 5 ]; then
    echo "usage: $0 <Speakboard.app> <device type name> <runtime id> <out dir> [<derived data>]" >&2
    exit 2
fi
app=$1
device_type=$2
runtime=$3
out=$4
derived=${5:-}

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

# On a failure after the keyboard should have started: prints into the job log
# what the simulator says about the extension (its own log lines, the system's
# lines naming it, and any crash report), because the uploaded artifact is not
# readable from an agent session (KEY-54).
diagnose() {
    echo "sim-keyboard: diagnostics: the simulator's log lines about the keyboard extension, newest last"
    xcrun simctl spawn "$udid" log show --style compact --start "$start" \
        --predicate "subsystem == \"$ext_id\" OR process == \"SpeakboardKeyboard\" OR eventMessage CONTAINS \"SpeakboardKeyboard\" OR eventMessage CONTAINS \"$ext_id\"" \
        2>&1 | tail -n 80 || true
    echo "sim-keyboard: diagnostics: the simulator's keyboard settings"
    xcrun simctl spawn "$udid" defaults read .GlobalPreferences AppleKeyboards 2>&1 || true
    xcrun simctl spawn "$udid" defaults read com.apple.keyboard.preferences KeyboardsCurrentAndNext 2>&1 || true
    echo "sim-keyboard: diagnostics: crash reports since the step started"
    local report
    for report in $(find "$HOME/Library/Logs/DiagnosticReports" \
        "$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Logs/CrashReporter" \
        -newer "$marker" -type f 2> /dev/null | grep -i speakboard || true); do
        echo "== $report"
        head -n 120 "$report"
    done
}

marker="$out/.started"
: > "$marker"
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
    echo "sim-keyboard: FAIL: the keyboard extension did not start, or did not stay running" >&2
    xcrun simctl io "$udid" screenshot "$out/keyboard.png" > /dev/null 2>&1 || true
    diagnose
    exit 1
fi
sleep 4
xcrun simctl io "$udid" screenshot "$out/keyboard.png" > /dev/null 2>&1
xcrun simctl ui "$udid" appearance dark
sleep 3
xcrun simctl io "$udid" screenshot "$out/keyboard-dark.png" > /dev/null 2>&1
xcrun simctl ui "$udid" appearance light
sleep 2

# 5. Check what the extension itself reported.
xcrun simctl spawn "$udid" log show --style compact --start "$start" \
    --predicate "subsystem == \"$ext_id\"" > "$out/keyboard.log" 2>&1 || true
line=$(grep -o 'speakboard-keyboard .*' "$out/keyboard.log" | tail -1 || true)
if [ -z "$line" ]; then
    echo "sim-keyboard: FAIL: no log line from the keyboard extension (see $out/keyboard.log)" >&2
    diagnose
    exit 1
fi
echo "sim-keyboard: the extension reported: $line"
grep -o 'speakboard-session .*' "$out/keyboard.log" || true
case "$line" in
    *fullAccess=true*) ;;
    *)
        echo "sim-keyboard: FAIL: the extension does not have Full Access" >&2
        exit 1
        ;;
esac
case "$line" in
    *keys=0*)
        echo "sim-keyboard: FAIL: the extension drew no keys" >&2
        exit 1
        ;;
esac
echo "sim-keyboard: OK ($out/harness.png, $out/keyboard.png, $out/keyboard-dark.png)"

# 6. The typing proof through the extension (KEY-62), on this simulator.
if [ -n "$derived" ]; then
    xcrun simctl terminate "$udid" "$app_id" > /dev/null 2>&1 || true
    for appearance in light dark; do
        xcrun simctl ui "$udid" appearance "$appearance"
        echo "sim-keyboard: UI tests in $appearance appearance: xcodebuild starts at $(date '+%H:%M:%S')"
        ui_start=$(date '+%Y-%m-%d %H:%M:%S')
        status=0
        TEST_RUNNER_SPEAKBOARD_APPEARANCE="$appearance" xcodebuild -project Speakboard.xcodeproj \
            -scheme SpeakboardUITests -destination "id=$udid" -derivedDataPath "$derived" \
            -resultBundlePath "$out/ui-$appearance.xcresult" test > "$out/ui-$appearance.log" 2>&1 || status=$?
        echo "sim-keyboard: UI tests in $appearance appearance: xcodebuild ended at $(date '+%H:%M:%S')"
        grep -E 'speakboard-ui:|error:|Test Case .*(started|passed|failed)|TEST (SUCCEEDED|FAILED)' \
            "$out/ui-$appearance.log" || true
        # The extension's own session lines during these tests: whether the proxy gave a document identifier.
        xcrun simctl spawn "$udid" log show --style compact --start "$ui_start" \
            --predicate "subsystem == \"$ext_id\"" 2> /dev/null | grep -o 'speakboard-session .*' || true
        xcrun xcresulttool export attachments --path "$out/ui-$appearance.xcresult" \
            --output-path "$out/ui-$appearance" > /dev/null 2>&1 || echo "sim-keyboard: could not export the screenshots"
        if [ "$status" -ne 0 ]; then
            tail -n 60 "$out/ui-$appearance.log"
            diagnose
            echo "sim-keyboard: FAIL: the UI tests failed in $appearance appearance (see $out/ui-$appearance.log)" >&2
            exit 1
        fi
    done
    echo "sim-keyboard: OK: the UI tests typed through the extension in light and dark appearance"
fi
