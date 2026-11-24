#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build/tests
run_test() {
    xcrun --sdk macosx swiftc -module-cache-path build/ModuleCache "Sources/$2.swift" \
        "Tests/$1/main.swift" -o "build/tests/$1"
    "build/tests/$1"
}
run_test Frames Frames
run_test Dial DialGeometry
run_test Sound SoundSettings
run_test Placement MenuPlacement
