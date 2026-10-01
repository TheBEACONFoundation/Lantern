#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

test_dir="$(mktemp -d "${TMPDIR:-/tmp}/lantern-probe.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

xcrun swiftc \
  -swift-version 5 \
  -module-cache-path "$test_dir/module-cache" \
  Probe/ProbeSupport.swift Tests/Probe/main.swift \
  -o "$test_dir/probe-tests"
"$test_dir/probe-tests"

# Compile the real entry point, then exercise only argument handling. These
# commands return before privilege checks, SMC initialization or hardware access.
xcrun swiftc \
  -swift-version 5 \
  -module-cache-path "$test_dir/module-cache" \
  -framework IOKit \
  Sources/SMC.swift Probe/ProbeSupport.swift Probe/main.swift \
  -o "$test_dir/lantern-probe"
"$test_dir/lantern-probe" --help > "$test_dir/help.txt"
if ! grep -q '^Usage: lantern-probe' "$test_dir/help.txt"; then
  echo 'FAIL: probe help must describe the command' >&2
  exit 1
fi
if "$test_dir/lantern-probe" --key CHIE --value 02zz > "$test_dir/invalid.txt" 2>&1; then
  echo 'FAIL: malformed hexadecimal input was accepted' >&2
  exit 1
fi
if ! grep -q '^Invalid arguments: --value contains a non-hexadecimal byte' "$test_dir/invalid.txt"; then
  echo 'FAIL: malformed input did not fail before privilege and SMC checks' >&2
  cat "$test_dir/invalid.txt" >&2
  exit 1
fi
if "$test_dir/lantern-probe" --key CHIE --value 2 > "$test_dir/odd.txt" 2>&1; then
  echo 'FAIL: an incomplete hexadecimal byte was accepted' >&2
  exit 1
fi
if ! grep -q '^Invalid arguments: --value must contain complete hexadecimal byte pairs' "$test_dir/odd.txt"; then
  echo 'FAIL: an incomplete byte did not fail before privilege and SMC checks' >&2
  cat "$test_dir/odd.txt" >&2
  exit 1
fi

echo 'Probe entry-point checks passed (no hardware access).'
