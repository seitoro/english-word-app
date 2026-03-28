#!/bin/zsh

set -euo pipefail

SCHEME="${SCHEME:-English word app}"
BUNDLE_ID="${BUNDLE_ID:-com.ryuseiokada.English-word-app}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

find_simulator_udid() {
  python3 - "$SIMULATOR_NAME" <<'PY'
import json
import subprocess
import sys

name = sys.argv[1]
data = json.loads(subprocess.check_output([
    "xcrun", "simctl", "list", "devices", "available", "-j"
]))

for _, devices in data["devices"].items():
    for device in devices:
        if device["name"] == name and device.get("isAvailable", True):
            print(device["udid"])
            raise SystemExit(0)

raise SystemExit(f"Simulator not found: {name}")
PY
}

find_built_app() {
  python3 - "$SCHEME" <<'PY'
import pathlib
import sys

scheme = sys.argv[1]
root = pathlib.Path.home() / "Library/Developer/Xcode/DerivedData"
candidates = list(root.glob(f"*/Build/Products/Debug-iphonesimulator/{scheme}.app"))
if not candidates:
    raise SystemExit(f"Built app not found for scheme: {scheme}")

latest = max(candidates, key=lambda path: path.stat().st_mtime)
print(latest)
PY
}

SIMULATOR_UDID="$(find_simulator_udid)"

open -a Simulator
xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b

cd "$PROJECT_ROOT"
xcodebuild build \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID"

APP_PATH="$(find_built_app)"

xcrun simctl uninstall "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
sleep 3
xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID"
osascript -e 'tell application "Simulator" to activate' >/dev/null 2>&1 || true
