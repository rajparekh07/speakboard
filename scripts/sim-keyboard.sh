#!/bin/bash
# Shows our keyboard in an iOS simulator with no one at the screen, and takes
# screenshots of it (KEY-8). Used by .github/workflows/macos.yml and by hand.
#
#   scripts/sim-keyboard.sh <Speakboard.app> <device type name> <runtime id> <out dir> [<derived data>]
#   e.g. scripts/sim-keyboard.sh .build/xcode/Build/Products/Debug-iphonesimulator/Speakboard.app \
#          "iPhone 18 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-2 .build/screenshots .build/xcode
#
# It makes a fresh simulator (two with <derived data>), deletes it at the end,
# and writes into <out dir>:
#   harness.png        the keyboard's view hosted in the app (-SpeakboardHarness)
#   keyboard.png       the keyboard extension itself, enabled with Full Access,
#                      in the app's text field, in light appearance
#   keyboard-dark.png  the same in dark appearance
#   keyboard.log       the extension's own log line: its height, key count and
#                      Full Access
# With <derived data> (where Speakboard.xcodeproj was built), and unless
# SPEAKBOARD_CAPTURES is set to anything but true, it first takes
# the reference captures of Apple's own keyboard (KEY-9), on a fresh simulator
# of their own where Speakboard is never enabled, so the keyboard on screen can
# only be Apple's and the typing proof's simulator is as it was before KEY-9:
# it runs the UI test AppleKeyboardCapturesUITests alone, once in light and
# once in dark appearance, into apple-<appearance>.log,
# apple-<appearance>.xcresult and apple-<appearance>/, then deletes that
# simulator. If they fail, the typing proof below still runs, and the script
# fails at its end. After both appearances' captures, on the same simulator, in
# light appearance, it runs the measurements of Apple's keyboard (KEY-71), the
# UI test AppleKeyboardMeasurementsUITests alone, into measure-light.log and
# measure-light.xcresult: where taps near the keys' edges land, and what the
# number and symbol keys type, as speakboard-measure lines, which the step
# prints again as a block at its end. If they fail, the rest still runs, and
# the script fails at its end. Each simulator's hardware keyboard is set to disconnected
# first (below, "The hardware keyboard"). On any failure the script ends with a
# short summary of the UI test logs.
# With <derived data>, it then runs the typing proof, the
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

# The hardware keyboard (KEY-9). Connecting the Mac's keyboard to a simulator
# is a setting of the Simulator app (I/O > Keyboard > Connect Hardware
# Keyboard), kept in its defaults, com.apple.iphonesimulator: the key
# ConnectHardwareKeyboard, and the same key per device under DevicePreferences.
# This sets both to false and prints what they read back. They matter only
# when the Simulator app runs (simctl boots the device headless, and it is
# printed whether the app runs); there is no command that reads the setting
# inside the simulated device. What is checked is the effect: iOS shows no
# on-screen keyboard while a hardware keyboard is connected, and the capture
# test fails unless Apple's on-screen keyboard is up, with its keys, before
# each capture.
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
if pgrep -f 'Simulator.app/Contents/MacOS/Simulator' > /dev/null; then
    echo "sim-keyboard: hardware keyboard: the Simulator app is running"
else
    echo "sim-keyboard: hardware keyboard: the Simulator app is not running (the devices are headless)"
fi

# hardware_keyboard_off <udid>: the per-device setting, and what both settings read back.
hardware_keyboard_off() {
    defaults write com.apple.iphonesimulator DevicePreferences -dict-add "$1" \
        '<dict><key>ConnectHardwareKeyboard</key><false/></dict>' 2>&1 \
        || echo "sim-keyboard: could not write the per-device hardware keyboard setting"
    echo "sim-keyboard: hardware keyboard: ConnectHardwareKeyboard reads" \
        "$(defaults read com.apple.iphonesimulator ConnectHardwareKeyboard 2>&1 | tr '\n' ' ')"
    echo "sim-keyboard: hardware keyboard: the preferences of device $1 read" \
        "$(defaults read com.apple.iphonesimulator DevicePreferences 2> /dev/null \
            | awk -v id="$1" 'index($0, id) { on = 1 } on { printf "%s ", $0 } on && /};/ { exit }')"
}

# On a failure, the last lines of this step: the UI tests' failure lines and their last progress lines, from each
# log, bounded, so a job log's tail says why (the artifact cannot be read from a session, KEY-54).
summary() {
    local log
    echo "sim-keyboard: summary of the UI test logs, at most 25 lines each:"
    for log in "$out"/apple-*.log "$out"/measure-*.log "$out"/ui-*.log; do
        [ -f "$log" ] || continue
        echo "== $log"
        grep -E 'error:|Test Case .*(passed|failed|skipped)|speakboard-ui:|speakboard-apple-capture ' "$log" \
            | grep -v 'apple keyboard tree' | cut -c 1-400 | tail -n 25 || true
    done
}

# Where the step's time goes, a phase at a time, printed as the last line at exit, pass or fail (KEY-9).
times=""
last=$SECONDS
mark() {
    times="$times $1 $((SECONDS - last))s;"
    last=$SECONDS
}

# The measurements of Apple's keyboard (KEY-71), every speakboard-measure line, as a block near the end of the step's
# log, so a short tail of the job's log holds them.
measurements() {
    local log="$out/measure-light.log"
    [ -f "$log" ] || return 0
    echo "sim-keyboard: the measurements of Apple's keyboard (KEY-71), $(grep -c 'speakboard-measure ' "$log" || true) lines:"
    grep -o 'speakboard-measure .*' "$log" | cut -c 1-600 || true
    echo "sim-keyboard: end of the measurements of Apple's keyboard"
}

capture_udid=""
udid=""
cleanup() {
    local code=$? device
    for device in $capture_udid $udid; do
        xcrun simctl shutdown "$device" > /dev/null 2>&1 || true
        xcrun simctl delete "$device" > /dev/null 2>&1 || true
    done
    if [ "$code" -ne 0 ]; then
        summary
    fi
    measurements
    echo "sim-keyboard: where the time went:$times total ${SECONDS}s"
}
trap cleanup EXIT

# 0. Reference captures of Apple's keyboard (KEY-9), on a fresh simulator of their own where Speakboard is never
# enabled, deleted before the typing proof's simulator is made. Taken on the typing proof's own simulator before
# Speakboard was enabled (run 44787518860), Apple's keyboard in use left the simulator's current keyboard setting
# rewritten, and Speakboard did not come up for the typing proof.
# They run only when SPEAKBOARD_CAPTURES is true, or unset (by hand); the workflow sets it from
# scripts/captures-needed.sh, with the reason in SPEAKBOARD_CAPTURES_WHY.
apple_status=0
measure_status=0
captures=no
if [ -n "$derived" ] && [ "${SPEAKBOARD_CAPTURES:-true}" = true ]; then
    captures=yes
    echo "sim-keyboard: this run takes the reference captures of Apple's keyboard: ${SPEAKBOARD_CAPTURES_WHY:-asked for by hand}"
elif [ -n "$derived" ]; then
    echo "sim-keyboard: this run takes no reference captures of Apple's keyboard: ${SPEAKBOARD_CAPTURES_WHY:-SPEAKBOARD_CAPTURES is $SPEAKBOARD_CAPTURES}"
fi
if [ "$captures" = yes ]; then
    capture_udid=$(xcrun simctl create "speakboard-apple-$$" "$device_type" "$runtime")
    echo "sim-keyboard: simulator $capture_udid for the captures of Apple's keyboard ($device_type, $runtime)"
    hardware_keyboard_off "$capture_udid"
    xcrun simctl boot "$capture_udid"
    xcrun simctl bootstatus "$capture_udid" -b > /dev/null
    mark "capture simulator made and booted"
    # iOS shows a slide-to-type card over the keyboard the first time one comes up; on run 44793753513 it covered
    # the light capture. This preference is meant to say it was shown (its name is not documented, and is not known
    # to be right on iOS 27): the test also dismisses the card if it is up, and proves the keyboard takes taps.
    xcrun simctl spawn "$capture_udid" defaults write com.apple.keyboard.preferences \
        DidShowContinuousPathIntroduction -bool true || echo "sim-keyboard: could not write the introduction setting"
    echo "sim-keyboard: DidShowContinuousPathIntroduction reads" \
        "$(xcrun simctl spawn "$capture_udid" defaults read com.apple.keyboard.preferences \
            DidShowContinuousPathIntroduction 2>&1 | tr '\n' ' ')"
    echo "sim-keyboard: its keyboards:" \
        "$(xcrun simctl spawn "$capture_udid" defaults read .GlobalPreferences AppleKeyboards 2>&1 | tr -s ' \n' ' ')"
    for appearance in light dark; do
        xcrun simctl ui "$capture_udid" appearance "$appearance"
        echo "sim-keyboard: Apple's keyboard in $appearance appearance: xcodebuild starts at $(date '+%H:%M:%S')"
        status=0
        TEST_RUNNER_SPEAKBOARD_APPEARANCE="$appearance" TEST_RUNNER_SPEAKBOARD_APPLE_CAPTURES=1 \
            TEST_RUNNER_SPEAKBOARD_DEVICE_TYPE="$device_type" xcodebuild \
            -project Speakboard.xcodeproj -scheme SpeakboardUITests -destination "id=$capture_udid" \
            -derivedDataPath "$derived" -only-testing:SpeakboardUITests/AppleKeyboardCapturesUITests \
            -resultBundlePath "$out/apple-$appearance.xcresult" test > "$out/apple-$appearance.log" 2>&1 || status=$?
        echo "sim-keyboard: Apple's keyboard in $appearance appearance: xcodebuild ended at $(date '+%H:%M:%S')"
        mark "captures $appearance"
        grep -E 'speakboard-ui:|speakboard-apple-capture |error:|Test Case .*(started|passed|failed|skipped)|TEST (SUCCEEDED|FAILED)' \
            "$out/apple-$appearance.log" | cut -c 1-3000 || true
        xcrun xcresulttool export attachments --path "$out/apple-$appearance.xcresult" \
            --output-path "$out/apple-$appearance" > /dev/null 2>&1 || echo "sim-keyboard: could not export the captures"
        if [ "$status" -ne 0 ] || grep -q 'Test Case .*skipped' "$out/apple-$appearance.log"; then
            echo "sim-keyboard: FAIL: the captures of Apple's keyboard failed in $appearance appearance" \
                "(see $out/apple-$appearance.log); the typing proof still runs" >&2
            apple_status=1
        fi
    done
    # The measurements (KEY-71), after all ten captures, so a failed measurement cannot cost a capture.
    xcrun simctl ui "$capture_udid" appearance light
    echo "sim-keyboard: measurements of Apple's keyboard in light appearance: xcodebuild starts at $(date '+%H:%M:%S')"
    status=0
    TEST_RUNNER_SPEAKBOARD_APPEARANCE=light TEST_RUNNER_SPEAKBOARD_APPLE_MEASUREMENTS=1 xcodebuild \
        -project Speakboard.xcodeproj -scheme SpeakboardUITests -destination "id=$capture_udid" \
        -derivedDataPath "$derived" -only-testing:SpeakboardUITests/AppleKeyboardMeasurementsUITests \
        -resultBundlePath "$out/measure-light.xcresult" test > "$out/measure-light.log" 2>&1 || status=$?
    echo "sim-keyboard: measurements of Apple's keyboard in light appearance: xcodebuild ended at $(date '+%H:%M:%S')"
    mark "measurements light"
    # Their speakboard-measure lines are printed once, as a block at the step's end.
    grep -E 'speakboard-ui:|error:|Test Case .*(started|passed|failed|skipped)|TEST (SUCCEEDED|FAILED)' \
        "$out/measure-light.log" | cut -c 1-3000 || true
    if [ "$status" -ne 0 ] || grep -q 'Test Case .*skipped' "$out/measure-light.log"; then
        echo "sim-keyboard: FAIL: the measurements of Apple's keyboard failed (see $out/measure-light.log);" \
            "the typing proof still runs" >&2
        measure_status=1
    fi
    xcrun simctl shutdown "$capture_udid" > /dev/null 2>&1 || true
    xcrun simctl delete "$capture_udid" > /dev/null 2>&1 || true
    capture_udid=""
    mark "capture simulator deleted"
fi

udid=$(xcrun simctl create "speakboard-$$" "$device_type" "$runtime")
hardware_keyboard_off "$udid"
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

mark "typing proof simulator, harness, keyboard enabled, screenshots"

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
            -only-testing:SpeakboardUITests/KeyboardExtensionUITests \
            -resultBundlePath "$out/ui-$appearance.xcresult" test > "$out/ui-$appearance.log" 2>&1 || status=$?
        echo "sim-keyboard: UI tests in $appearance appearance: xcodebuild ended at $(date '+%H:%M:%S')"
        mark "typing proof $appearance"
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
    if [ "$apple_status" -ne 0 ]; then
        echo "sim-keyboard: FAIL: the captures of Apple's keyboard failed (see the FAIL lines above)" >&2
        exit 1
    fi
    if [ "$measure_status" -ne 0 ]; then
        echo "sim-keyboard: FAIL: the measurements of Apple's keyboard failed (see the FAIL line above)" >&2
        exit 1
    fi
    if [ "$captures" = yes ]; then
        echo "sim-keyboard: OK: the captures of Apple's keyboard, in light and dark appearance, and the measurements"
    fi
fi
