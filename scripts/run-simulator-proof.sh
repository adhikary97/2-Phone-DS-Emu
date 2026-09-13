#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM_PATH="${1:-/Users/paras.adhikary/Downloads/Pokemon - HeartGold Version (USA).nds}"
FRAME_COUNT="${TWO_PHONE_FRAMES:-480}"
CHECKPOINT_INTERVAL="${TWO_PHONE_CHECKPOINT_INTERVAL:-60}"
BUNDLE_ID="com.dsemu.twophone"
APP_PATH="$PROJECT_ROOT/build/DerivedData/Build/Products/Debug-iphonesimulator/DSEmu.app"

if [[ ! -f "$ROM_PATH" ]]; then
    echo "ROM not found: $ROM_PATH" >&2
    exit 2
fi

command -v xcodegen >/dev/null || {
    echo "xcodegen is required (brew install xcodegen)" >&2
    exit 2
}
command -v jq >/dev/null || {
    echo "jq is required" >&2
    exit 2
}

RUNTIME_ID="$(xcrun simctl list runtimes -j | jq -r '[.runtimes[] | select(.platform == "iOS" and .isAvailable == true)] | sort_by(.version) | last | .identifier')"
if [[ -z "$RUNTIME_ID" || "$RUNTIME_ID" == "null" ]]; then
    echo "No available iOS simulator runtime was found" >&2
    exit 2
fi

ensure_device() {
    local name="$1"
    local device_type="$2"
    local udid
    udid="$(xcrun simctl list devices -j | jq -r --arg runtime "$RUNTIME_ID" --arg name "$name" '.devices[$runtime][]? | select(.name == $name and .isAvailable == true) | .udid' | head -n 1)"
    if [[ -z "$udid" ]]; then
        udid="$(xcrun simctl create "$name" "$device_type" "$RUNTIME_ID")"
    fi
    printf '%s' "$udid"
}

CONTROLLER_UDID="$(ensure_device "TwoPhoneDS Controller" "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max")"
DISPLAY_UDID="$(ensure_device "TwoPhoneDS Display" "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation")"

echo "Generating and building the app"
cd "$PROJECT_ROOT"
xcodegen generate
xcodebuild \
    -project DSEmu.xcodeproj \
    -scheme DSEmu \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath build/DerivedData \
    CODE_SIGNING_ALLOWED=NO \
    build >/dev/null

xcrun simctl boot "$CONTROLLER_UDID" 2>/dev/null || true
xcrun simctl boot "$DISPLAY_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$CONTROLLER_UDID" -b >/dev/null
xcrun simctl bootstatus "$DISPLAY_UDID" -b >/dev/null

xcrun simctl install "$CONTROLLER_UDID" "$APP_PATH"
xcrun simctl install "$DISPLAY_UDID" "$APP_PATH"

CONTROLLER_CONTAINER="$(xcrun simctl get_app_container "$CONTROLLER_UDID" "$BUNDLE_ID" data)"
DISPLAY_CONTAINER="$(xcrun simctl get_app_container "$DISPLAY_UDID" "$BUNDLE_ID" data)"
CONTROLLER_REPORT="$CONTROLLER_CONTAINER/Documents/two-phone-result-controller.json"
DISPLAY_REPORT="$DISPLAY_CONTAINER/Documents/two-phone-result-display.json"

cp "$ROM_PATH" "$CONTROLLER_CONTAINER/Documents/TestROM.nds"
cp "$ROM_PATH" "$DISPLAY_CONTAINER/Documents/TestROM.nds"
rm -f "$CONTROLLER_REPORT" "$DISPLAY_REPORT"

COMMON_ARGS=(
    --two-phone-port 47391
    --two-phone-autoload TestROM.nds
    --two-phone-test-frames "$FRAME_COUNT"
    --two-phone-checkpoint-interval "$CHECKPOINT_INTERVAL"
    --two-phone-scripted-inputs
)

echo "Launching display and controller roles"
xcrun simctl launch --terminate-running-process "$DISPLAY_UDID" "$BUNDLE_ID" \
    --two-phone-role display --two-phone-host 127.0.0.1 "${COMMON_ARGS[@]}" >/dev/null
xcrun simctl launch --terminate-running-process "$CONTROLLER_UDID" "$BUNDLE_ID" \
    --two-phone-role controller "${COMMON_ARGS[@]}" >/dev/null

for _ in $(seq 1 180); do
    if [[ -f "$CONTROLLER_REPORT" && -f "$DISPLAY_REPORT" ]]; then
        break
    fi
    sleep 1
done

if [[ ! -f "$CONTROLLER_REPORT" || ! -f "$DISPLAY_REPORT" ]]; then
    echo "Timed out waiting for both proof reports" >&2
    exit 1
fi

mkdir -p "$PROJECT_ROOT/artifacts"
cp "$CONTROLLER_REPORT" "$PROJECT_ROOT/artifacts/controller-report.json"
cp "$DISPLAY_REPORT" "$PROJECT_ROOT/artifacts/display-report.json"
xcrun simctl io "$CONTROLLER_UDID" screenshot "$PROJECT_ROOT/artifacts/controller-final.png" >/dev/null
xcrun simctl io "$DISPLAY_UDID" screenshot "$PROJECT_ROOT/artifacts/display-final.png" >/dev/null

jq -e '.success == true' "$PROJECT_ROOT/artifacts/controller-report.json" >/dev/null
jq -e '.success == true' "$PROJECT_ROOT/artifacts/display-report.json" >/dev/null

CONTROLLER_DIGEST="$(jq -c '.finalDigest' "$PROJECT_ROOT/artifacts/controller-report.json")"
DISPLAY_DIGEST="$(jq -c '.finalDigest' "$PROJECT_ROOT/artifacts/display-report.json")"
if [[ "$CONTROLLER_DIGEST" != "$DISPLAY_DIGEST" ]]; then
    echo "Final digests do not match" >&2
    exit 1
fi

echo "PASS: $FRAME_COUNT HeartGold frames synchronized with matching state and framebuffer digests"
jq '{role, success, framesCompleted, framesPerSecond, checkpointsCompared, snapshotBytes, finalDigest}' \
    "$PROJECT_ROOT/artifacts/controller-report.json" \
    "$PROJECT_ROOT/artifacts/display-report.json"

