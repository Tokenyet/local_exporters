#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
python3 - "$ROOT/apps/twitch/manifest.json" "$ROOT/apps/youtube/manifest.json" <<'PY'
import base64
import hashlib
import json
import sys
from pathlib import Path

for manifest_path in sys.argv[1:]:
    manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    key = manifest.get("key")
    if not key:
        raise SystemExit(f"Manifest has no stable public signing key: {manifest_path}")
    digest = hashlib.sha256(base64.b64decode(key)).digest()[:16]
    extension_id = "".join(chr(ord("a") + nibble) for byte in digest for nibble in ((byte >> 4) & 0xF, byte & 0xF))
    print(f"{Path(manifest_path).parent.name}: {extension_id}")
PY
