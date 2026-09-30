#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/web-renderer"
npm ci --ignore-scripts --no-audit --no-fund
npm run typecheck
npm test
npm run build -- --logLevel warn
python3 "$ROOT/scripts/prepare_markdown_resources.py"
