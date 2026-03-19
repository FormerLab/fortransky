#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR/bridge/firehose-bridge"
cargo build --release
printf 'Built %s
' "$ROOT_DIR/bridge/firehose-bridge/target/release/firehose_bridge_cli"
