#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
for product in twitch youtube; do
    echo "== Packaging $product =="
    bash "$ROOT/apps/$product/scripts/package.sh"
done

echo "All extension packages created under apps/<product>/dist."
