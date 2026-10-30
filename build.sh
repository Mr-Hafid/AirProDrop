#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_ROOT/AirProDrop.xcodeproj"
DERIVED_DATA="$PROJECT_ROOT/build"
CONFIGURATION="Release"
MAC_APP_DESTINATION="/Applications/AirProDrop.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

print_step() {
    printf "\n\033[1;36m==> %s\033[0m\n" "$1"
}

fail() {
    printf "\033[1;31m%s\033[0m\n" "$1" >&2
    exit 1
}

print_usage() {
    echo "Usage: ./build.sh [all|mac|phone] [iphone-name]"
    echo "  all    Build and install the Mac app and the iPhone app (default)"
    echo "  mac    Build the Mac app and install it to /Applications"
    echo "  phone  Build the iPhone app and install it on a connected iPhone"
}

generate_project() {
    print_step "Generating Xcode project"
    command -v xcodegen >/dev/null || fail "xcodegen is not installed. Run: brew install xcodegen"
    (cd "$PROJECT_ROOT" && xcodegen generate --quiet)
}

build_mac() {
    print_step "Building Mac app"
    xcodebuild -project "$PROJECT" -scheme AirProDropMac -configuration "$CONFIGURATION" \
        -destination "generic/platform=macOS" -derivedDataPath "$DERIVED_DATA" build -quiet

    local built_app="$DERIVED_DATA/Build/Products/$CONFIGURATION/AirProDrop.app"
    [ -d "$built_app" ] || fail "Mac build output not found at $built_app"

    print_step "Installing Mac app to /Applications"
    osascript -e 'tell application id "com.mrhafid.airpro.mac" to quit' >/dev/null 2>&1 || true
    sleep 1
    pkill -x AirProDrop >/dev/null 2>&1 || true
    rm -rf "$MAC_APP_DESTINATION"
    ditto "$built_app" "$MAC_APP_DESTINATION"
    "$LSREGISTER" -u "$built_app" >/dev/null 2>&1 || true
    "$LSREGISTER" -f "$MAC_APP_DESTINATION"
    open "$MAC_APP_DESTINATION"
    echo "Installed $MAC_APP_DESTINATION"
}

find_connected_iphone() {
    local requested_name="$1"
    local device_list
    device_list="$(mktemp)"
    xcrun devicectl list devices --json-output "$device_list" >/dev/null 2>&1 || fail "Could not list devices with devicectl"
    python3 - "$device_list" "$requested_name" <<'PYTHON'
import json
import sys

device_list_path, requested_name = sys.argv[1], sys.argv[2]
devices = json.load(open(device_list_path))["result"]["devices"]
connected = [
    device for device in devices
    if device["hardwareProperties"].get("platform") == "iOS"
    and device["connectionProperties"].get("pairingState") == "paired"
    and device["connectionProperties"].get("tunnelState") != "unavailable"
    and device["connectionProperties"].get("transportType")
]
if requested_name:
    connected = [device for device in connected if requested_name.lower() in device["deviceProperties"]["name"].lower()]
if not connected:
    sys.exit(1)
device = connected[0]
print(device["identifier"], device["hardwareProperties"]["udid"], device["deviceProperties"]["name"], sep="\t")
PYTHON
    local status=$?
    rm -f "$device_list"
    return $status
}

build_phone() {
    local requested_name="${1:-}"
    print_step "Looking for a connected iPhone"
    local device_line
    device_line="$(find_connected_iphone "$requested_name")" || fail "No connected iPhone found. Plug it in, unlock it and trust this Mac."
    local device_identifier device_udid device_name
    IFS=$'\t' read -r device_identifier device_udid device_name <<< "$device_line"
    echo "Using $device_name"

    print_step "Building iPhone app"
    xcodebuild -project "$PROJECT" -scheme AirProDropPhone -configuration "$CONFIGURATION" \
        -destination "id=$device_udid" -derivedDataPath "$DERIVED_DATA" \
        -allowProvisioningUpdates build -quiet

    local built_app="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/AirProDrop.app"
    [ -d "$built_app" ] || fail "iPhone build output not found at $built_app"

    print_step "Installing on $device_name"
    xcrun devicectl device install app --device "$device_identifier" "$built_app" >/dev/null
    xcrun devicectl device process launch --device "$device_identifier" com.mrhafid.airpro.phone >/dev/null 2>&1 || true
    echo "Installed on $device_name"
}

target="${1:-all}"
case "$target" in
    all)
        generate_project
        build_mac
        build_phone "${2:-}"
        ;;
    mac)
        generate_project
        build_mac
        ;;
    phone)
        generate_project
        build_phone "${2:-}"
        ;;
    -h|--help|help)
        print_usage
        ;;
    *)
        print_usage
        exit 1
        ;;
esac

print_step "Done"
