#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Build Rust firehose bridge first so the staticlib is present for the Fortran link
printf 'Building Rust firehose bridge...\n'
cd "$ROOT/bridge/firehose-bridge"
cargo build --release
printf 'Rust bridge built: %s\n' "$ROOT/bridge/firehose-bridge/target/release/libfortransky_firehose_bridge.a"

# Build Fortran/C executable
mkdir -p "$ROOT/build"
cd "$ROOT/build"
cmake ..
cmake --build . -j
