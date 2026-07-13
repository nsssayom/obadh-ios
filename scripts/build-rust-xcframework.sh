#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE_DIR="$ROOT_DIR/rust/ObadhBridge"
FRAMEWORKS_DIR="$ROOT_DIR/Frameworks"
OUTPUT="$FRAMEWORKS_DIR/ObadhBridge.xcframework"

if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is required to create ObadhBridge.xcframework." >&2
  echo "Install Xcode, then run: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

IOS_DEVICE_TARGET="aarch64-apple-ios"
IOS_SIM_ARM_TARGET="aarch64-apple-ios-sim"
IOS_SIM_X86_TARGET="x86_64-apple-ios"
SIM_UNIVERSAL_DIR="$BRIDGE_DIR/target/universal-ios-sim/release"
SIM_UNIVERSAL_LIB="$SIM_UNIVERSAL_DIR/libobadh_ios_bridge.a"

# The C header is the engine's own (the `cabi` feature owns the FFI surface).
# Vendor it from the resolved crate source so it can never drift from the linked
# engine version — the equivalent of the engine's own header-sync test.
ENGINE_MANIFEST="$(cargo metadata --format-version 1 --manifest-path "$BRIDGE_DIR/Cargo.toml" \
  | python3 -c 'import json,sys; m=json.load(sys.stdin); print(next(p["manifest_path"] for p in m["packages"] if p["name"]=="obadh_engine"))')"
ENGINE_HEADER="$(dirname "$ENGINE_MANIFEST")/include/obadh.h"
if [ ! -f "$ENGINE_HEADER" ]; then
  echo "Engine C header not found at $ENGINE_HEADER (is obadh_engine built with the cabi feature?)." >&2
  exit 1
fi
cp "$ENGINE_HEADER" "$BRIDGE_DIR/include/obadh.h"
echo "Vendored engine C header from $ENGINE_HEADER"

rustup target add "$IOS_DEVICE_TARGET" "$IOS_SIM_ARM_TARGET" "$IOS_SIM_X86_TARGET"

cargo build --manifest-path "$BRIDGE_DIR/Cargo.toml" --release --target "$IOS_DEVICE_TARGET"
cargo build --manifest-path "$BRIDGE_DIR/Cargo.toml" --release --target "$IOS_SIM_ARM_TARGET"
cargo build --manifest-path "$BRIDGE_DIR/Cargo.toml" --release --target "$IOS_SIM_X86_TARGET"

rm -rf "$OUTPUT"
rm -rf "$SIM_UNIVERSAL_DIR"
mkdir -p "$FRAMEWORKS_DIR" "$SIM_UNIVERSAL_DIR"

lipo -create \
  "$BRIDGE_DIR/target/$IOS_SIM_ARM_TARGET/release/libobadh_ios_bridge.a" \
  "$BRIDGE_DIR/target/$IOS_SIM_X86_TARGET/release/libobadh_ios_bridge.a" \
  -output "$SIM_UNIVERSAL_LIB"

xcodebuild -create-xcframework \
  -library "$BRIDGE_DIR/target/$IOS_DEVICE_TARGET/release/libobadh_ios_bridge.a" \
  -headers "$BRIDGE_DIR/include" \
  -library "$SIM_UNIVERSAL_LIB" \
  -headers "$BRIDGE_DIR/include" \
  -output "$OUTPUT"
