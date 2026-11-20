#!/bin/sh
# Build unit tests and run them in the Connect IQ simulator (start it first: `connectiq`).
# monkeydo exits non-zero even on success, so the result is read from its summary line.
set -e
DEVICE="${1:-fenix847mm}"
if [ -z "$SDK_BIN" ]; then
  for d in "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/"*/bin; do SDK_BIN="$d"; done
fi
mkdir -p bin
"$SDK_BIN/monkeyc" -l 0 --unit-test -f monkey.jungle -d "$DEVICE" -y developer_key.der -o bin/test.prg
OUT=$("$SDK_BIN/monkeydo" bin/test.prg "$DEVICE" -t 2>&1 || true)
echo "$OUT" | tail -12
echo "$OUT" | grep -q '^PASSED'
