#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NODE_BIN="$SCRIPT_DIR/../.tools/node/bin"

export PATH="$NODE_BIN:$PATH"

cd "$SCRIPT_DIR"
npm run dev
