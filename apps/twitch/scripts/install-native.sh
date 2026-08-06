#!/usr/bin/env bash
set -euo pipefail

PRODUCT_KEY="twitch"
HOST_NAME="com.dowen.twitch_local_exporter"
DEFAULT_APP_DIR="$HOME/Library/Application Support/TwitchLocalExporter"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

extension_id=""
browser="all"
toolchain_mode="Shared"
toolchain_root=""
app_dir="$DEFAULT_APP_DIR"

usage() {
    cat <<'EOF'
Usage: install-native.sh [options]

Options:
  --extension-id ID       Extension ID; derived from manifest.json when omitted
  --browser NAME          chrome, edge, chromium, vivaldi, or all (default: all)
  --toolchain-mode MODE   Shared, Isolated, or Custom (default: Shared)
  --toolchain-root PATH   Required with --toolchain-mode Custom
  --app-dir PATH          Override the native host installation directory
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --extension-id) extension_id="${2:-}"; shift 2 ;;
        --browser) browser="${2:-}"; shift 2 ;;
        --toolchain-mode) toolchain_mode="${2:-}"; shift 2 ;;
        --toolchain-root) toolchain_root="${2:-}"; shift 2 ;;
        --app-dir) app_dir="${2:-}"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$app_dir" || "$app_dir" == "/" ]]; then
    echo "Invalid --app-dir." >&2
    exit 2
fi

case "$(printf '%s' "$browser" | tr '[:upper:]' '[:lower:]')" in
    chrome|edge|chromium|vivaldi|all) ;;
    *) echo "Unsupported browser: $browser" >&2; exit 2 ;;
esac

case "$(printf '%s' "$toolchain_mode" | tr '[:upper:]' '[:lower:]')" in
    shared|isolated) ;;
    custom)
        if [[ -z "$toolchain_root" ]]; then
            echo "--toolchain-root is required with --toolchain-mode Custom." >&2
            exit 2
        fi
        ;;
    *) echo "Unsupported toolchain mode: $toolchain_mode" >&2; exit 2 ;;
esac

find_python() {
    local candidate
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done
    echo "Python 3.11 or newer was not found. Install Python, then run this script again." >&2
    return 1
}

python_bin="$(find_python)"
manifest_source="$ROOT/manifest.json"

if [[ -z "$extension_id" ]]; then
    extension_id="$("$python_bin" - "$manifest_source" <<'PY'
import base64
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)
key = manifest.get("key")
if not key:
    raise SystemExit("manifest.json has no stable public signing key; pass --extension-id explicitly")
digest = hashlib.sha256(base64.b64decode(key)).digest()[:16]
print("".join(chr(ord("a") + nibble) for byte in digest for nibble in ((byte >> 4) & 0xF, byte & 0xF)))
PY
)"
fi

if [[ ! "$extension_id" =~ ^[a-p]{32}$ ]]; then
    echo "Extension ID must be 32 lowercase characters in the a-p range: $extension_id" >&2
    exit 2
fi

shared_state_dir="$HOME/Library/Application Support/com.dowen.local_exporter"
default_shared_root="$shared_state_dir/toolchain"
legacy_tools_root="$app_dir/tools"
mode_lower="$(printf '%s' "$toolchain_mode" | tr '[:upper:]' '[:lower:]')"
case "$mode_lower" in
    shared) resolved_toolchain_root="${toolchain_root:-$default_shared_root}" ;;
    custom) resolved_toolchain_root="$toolchain_root" ;;
    isolated) resolved_toolchain_root="$legacy_tools_root" ;;
esac

native_dest="$app_dir/native-host"
scripts_dest="$app_dir/scripts"
python_libs_dest="$app_dir/python-libs"
manifest_path="$app_dir/$HOST_NAME.json"
launcher_path="$app_dir/twitch-local-exporter-host"
built_host="$ROOT/native-host/dist/twitch-local-exporter-host"
installed_host="$app_dir/twitch-local-exporter-host"

mkdir -p "$shared_state_dir" "$resolved_toolchain_root" "$native_dest" "$scripts_dest" "$python_libs_dest"

"$python_bin" - "$shared_state_dir/settings.json" "$default_shared_root" "$PRODUCT_KEY" "$mode_lower" "$resolved_toolchain_root" <<'PY'
import json
import os
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
default_root = sys.argv[2]
product = sys.argv[3]
mode = sys.argv[4]
root = str(Path(sys.argv[5]).expanduser().resolve())
try:
    settings = json.loads(settings_path.read_text(encoding="utf-8-sig")) if settings_path.exists() else {}
except (OSError, ValueError, TypeError):
    settings = {}
settings["schemaVersion"] = 1
settings["root"] = settings.get("root") or default_root
products = settings.get("products")
if not isinstance(products, dict):
    products = {}
settings["products"] = products
products[product] = {"mode": mode, "root": root}
settings_path.parent.mkdir(parents=True, exist_ok=True)
temporary = settings_path.with_suffix(".tmp")
temporary.write_text(json.dumps(settings, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
os.replace(temporary, settings_path)
PY

cp -R "$ROOT/native-host/." "$native_dest/"
cp "$ROOT/scripts/update-tools.sh" "$scripts_dest/update-tools.sh"
chmod +x "$scripts_dest/update-tools.sh"

if [[ -f "$built_host" ]]; then
    cp "$built_host" "$installed_host"
    chmod +x "$installed_host"
    host_path="$installed_host"
else
    echo "Installing native host Python dependencies..."
    "$python_bin" -m pip install --upgrade --target "$python_libs_dest" "opencc-python-reimplemented>=0.1.7"
    cat > "$launcher_path" <<EOF
#!/bin/sh
set -eu
SCRIPT_DIR=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
export PYTHONUTF8=1
export PATH="/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:\$PATH"
export PYTHONPATH="\$SCRIPT_DIR/python-libs:\$SCRIPT_DIR/native-host\${PYTHONPATH:+:\$PYTHONPATH}"
exec "$python_bin" "\$SCRIPT_DIR/native-host/twitch_local_exporter_host.py" "\$@"
EOF
    chmod +x "$launcher_path"
    host_path="$launcher_path"
fi

"$python_bin" - "$manifest_path" "$host_path" "$extension_id" "$HOST_NAME" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
host_path = str(Path(sys.argv[2]).resolve())
extension_id = sys.argv[3]
host_name = sys.argv[4]
manifest_path.write_text(json.dumps({
    "name": host_name,
    "description": "Twitch Local Exporter native messaging host",
    "path": host_path,
    "type": "stdio",
    "allowed_origins": [f"chrome-extension://{extension_id}/"]
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

register_browser() {
    local name="$1"
    local browser_dir
    case "$name" in
        chrome) browser_dir="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts" ;;
        edge) browser_dir="$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts" ;;
        chromium) browser_dir="$HOME/Library/Application Support/Chromium/NativeMessagingHosts" ;;
        vivaldi) browser_dir="$HOME/Library/Application Support/Vivaldi/NativeMessagingHosts" ;;
        *) echo "Unsupported browser: $name" >&2; return 1 ;;
    esac
    mkdir -p "$browser_dir"
    cp "$manifest_path" "$browser_dir/$HOST_NAME.json"
    echo "Registered $name native host: $browser_dir/$HOST_NAME.json"
}

if [[ "$browser" == "all" ]]; then
    for name in chrome edge chromium vivaldi; do
        register_browser "$name"
    done
else
    register_browser "$browser"
fi

echo "Installed Twitch native host in $app_dir"
echo "Host path: $host_path"
echo "Toolchain root: $resolved_toolchain_root"
