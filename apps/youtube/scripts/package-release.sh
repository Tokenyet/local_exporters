#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
version=""
output_dir="dist/release"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) version="${2:-}"; shift 2 ;;
        --output-dir) output_dir="${2:-}"; shift 2 ;;
        --help|-h)
            echo "Usage: package-release.sh [--version VERSION] [--output-dir PATH]"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

find_python() {
    local candidate
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done
    echo "Python was not found." >&2
    return 1
}

python_bin="$(find_python)"
if [[ -z "$version" ]]; then
    version="$("$python_bin" - "$ROOT/manifest.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["version"])
PY
)"
fi
version="${version#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] || { echo "Invalid version: $version" >&2; exit 2; }

manifest_version="$("$python_bin" - "$ROOT/manifest.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["version"])
PY
)"
[[ "$manifest_version" == "$version" ]] || { echo "manifest.json version $manifest_version does not match $version." >&2; exit 1; }

tag="v$version"
machine="$(uname -m)"
case "$machine" in
    arm64|aarch64) platform_arch="arm64" ;;
    x86_64|amd64) platform_arch="x64" ;;
    *) echo "Unsupported macOS architecture: $machine" >&2; exit 2 ;;
esac

resolve_path() {
    if [[ "$1" == /* ]]; then printf '%s\n' "$1"; else printf '%s/%s\n' "$ROOT" "$1"; fi
}

release_dir="$(resolve_path "$output_dir")"
bundle_name="youtube-local-exporter-$tag-macos-$platform_arch"
bundle_root="$release_dir/$bundle_name"
unpacked_output="${output_dir%/}/unpacked/youtube-local-exporter"
extension_zip="$release_dir/youtube-local-exporter-extension-$tag-macos-$platform_arch.zip"
bundle_zip="$release_dir/$bundle_name.zip"
host_source="$ROOT/native-host/dist/youtube-local-exporter-host"
host_asset="$release_dir/youtube-local-exporter-host-$tag-macos-$platform_arch"

mkdir -p "$release_dir"
rm -rf "$bundle_root" "$(resolve_path "${output_dir%/}/unpacked")"
bash "$ROOT/scripts/package.sh" \
    --output "$extension_zip" \
    --unpacked-output "$unpacked_output"

mkdir -p "$bundle_root/extension" "$bundle_root/native-host" "$bundle_root/scripts" "$bundle_root/docs"
cp -R "$(resolve_path "$unpacked_output")/." "$bundle_root/extension/"
for file in "$ROOT"/native-host/*.py; do
    cp "$file" "$bundle_root/native-host/"
done
mkdir -p "$bundle_root/native-host/youtube_local_exporter"
for file in "$ROOT"/native-host/youtube_local_exporter/*.py; do
    cp "$file" "$bundle_root/native-host/youtube_local_exporter/"
done
if [[ -f "$host_source" ]]; then
    cp "$host_source" "$bundle_root/native-host/youtube-local-exporter-host"
    chmod +x "$bundle_root/native-host/youtube-local-exporter-host"
    cp "$host_source" "$host_asset"
    chmod +x "$host_asset"
fi
for script in install-native.sh uninstall-native.sh update-tools.sh build-native.sh package.sh; do
    cp "$ROOT/scripts/$script" "$bundle_root/scripts/"
    chmod +x "$bundle_root/scripts/$script"
done
for doc in PRIVACY.md NATIVE_HOST.md RELEASE_INSTALL.md; do
    cp "$ROOT/docs/$doc" "$bundle_root/docs/"
done
for file in README.md CHANGELOG.md LICENSE manifest.json pyproject.toml; do
    cp "$ROOT/$file" "$bundle_root/"
done

rm -f "$bundle_zip"
(cd "$release_dir" && zip -qr "$bundle_zip" "$bundle_name")

"$python_bin" - "$ROOT/CHANGELOG.md" "$ROOT/docs/RELEASE_INSTALL.md" "$version" "$release_dir/RELEASE_NOTES-macos-$platform_arch.md" <<'PY'
import re
import sys
from pathlib import Path

changelog = Path(sys.argv[1]).read_text(encoding="utf-8")
install = Path(sys.argv[2]).read_text(encoding="utf-8")
version = re.escape(sys.argv[3])
match = re.search(rf"(?ms)^##\s+{version}[^\r\n]*\r?\n.*?(?=^##\s+|\Z)", changelog)
notes = match.group(0).strip() if match else f"## {sys.argv[3]}\n\nSee CHANGELOG.md for release details."
Path(sys.argv[4]).write_text(f"# YouTube Local Exporter v{sys.argv[3]} (macOS)\n\n{notes}\n\n## Install From This Release\n\n{install}", encoding="utf-8")
PY

artifacts=("$extension_zip" "$bundle_zip")
if [[ -f "$host_asset" ]]; then artifacts+=("$host_asset"); fi
checksum_path="$release_dir/SHA256SUMS-macos-$platform_arch.txt"
: > "$checksum_path"
for artifact in "${artifacts[@]}"; do
    shasum -a 256 "$artifact" | awk -v name="$(basename "$artifact")" '{print $1 "  " name}' >> "$checksum_path"
done

"$python_bin" - "$release_dir/release-manifest-macos-$platform_arch.json" "$version" "$tag" "${artifacts[@]}" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "version": sys.argv[2],
    "tag": sys.argv[3],
    "platform": "macos",
    "architecture": "arm64" if "arm64" in sys.argv[1] else "x64",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "assets": [Path(value).name for value in sys.argv[4:]]
}, indent=2) + "\n", encoding="utf-8")
PY

echo "Created macOS release assets in $release_dir"
