#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENTRY="$ROOT/native-host/twitch_local_exporter_host.py"
DIST="$ROOT/native-host/dist"
BUILD="$ROOT/native-host/build"

find_python() {
    local candidate
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done
    echo "Python 3.11 or newer was not found." >&2
    return 1
}

python_bin="$(find_python)"
mkdir -p "$DIST" "$BUILD"
"$python_bin" -m pip install --upgrade pyinstaller opencc-python-reimplemented
"$python_bin" -m PyInstaller \
    --onefile \
    --clean \
    --name twitch-local-exporter-host \
    --hidden-import opencc \
    --distpath "$DIST" \
    --workpath "$BUILD" \
    --specpath "$BUILD" \
    "$ENTRY"

chmod +x "$DIST/twitch-local-exporter-host"
echo "Built native host in $DIST"
