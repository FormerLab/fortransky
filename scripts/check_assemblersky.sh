#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[fortransky] checking Assemblersky CLI..."
if [[ -x "$ROOT/bridge/assemblersky/bin/assemblersky_cli" ]]; then
  echo "[fortransky] found bundled Assemblersky CLI"
  exit 0
fi

if command -v assemblersky_cli >/dev/null 2>&1; then
  echo "[fortransky] found Assemblersky CLI on PATH"
  exit 0
fi

echo "[fortransky] Assemblersky CLI not found."
echo "[fortransky] Expected one of:"
echo "  $ROOT/bridge/assemblersky/bin/assemblersky_cli"
echo "  assemblersky_cli on PATH"
echo
echo "[fortransky] You can still run relay_raw_tail.py --fixture while preparing the native decoder."
exit 0