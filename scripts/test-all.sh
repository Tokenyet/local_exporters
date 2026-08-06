#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
for product in twitch youtube; do
    app_root="$ROOT/apps/$product"
    echo "== Testing $product =="
    (cd "$app_root" && \
        node --check src/background.js && \
        node --check src/content.js && \
        node --check popup/popup.js && \
        node --check options/options.js && \
        node scripts/smoke-test.mjs && \
        python3 -m unittest discover -s native-host/tests -p 'test*.py')
done

echo "All extension tests passed."
