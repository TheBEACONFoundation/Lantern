#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

test_dir="$(mktemp -d "${TMPDIR:-/tmp}/lantern-rendering.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

xcrun swiftc \
  -swift-version 5 \
  -target arm64-apple-macos13.0 \
  -module-cache-path "$test_dir/module-cache" \
  -framework AppKit -framework IOKit -framework Accelerate \
  -framework Speech -framework AVFoundation \
  Sources/LanternView.swift Sources/LanternArt.swift \
  Sources/LanternRenderer.swift Sources/LanternGlyph.swift \
  Sources/Settings.swift Sources/BatteryMonitor.swift Sources/SMC.swift \
  Sources/OathListener.swift Sources/OathSpeechInput.swift \
  Sources/OathReferenceWindow.swift \
  Tests/Rendering/main.swift \
  -o "$test_dir/rendering-tests"

"$test_dir/rendering-tests"
