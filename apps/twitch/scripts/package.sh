#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
output="dist/twitch-local-exporter.zip"
unpacked_output="dist/unpacked/twitch-local-exporter"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) output="${2:-}"; shift 2 ;;
        --unpacked-output) unpacked_output="${2:-}"; shift 2 ;;
        --help|-h)
            echo "Usage: package.sh [--output PATH] [--unpacked-output PATH]"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

resolve_path() {
    if [[ "$1" == /* ]]; then
        printf '%s\n' "$1"
    else
        printf '%s/%s\n' "$ROOT" "$1"
    fi
}

destination="$(resolve_path "$output")"
unpacked_destination="$(resolve_path "$unpacked_output")"
case "$unpacked_destination" in
    "$ROOT"/*) ;;
    *) echo "Refusing to remove unpacked output outside the workspace: $unpacked_destination" >&2; exit 1 ;;
esac

package_items=(manifest.json src popup options icons _locales)
mkdir -p "$(dirname -- "$destination")"
rm -f "$destination"
rm -rf "$unpacked_destination"
mkdir -p "$unpacked_destination"

for item in "${package_items[@]}"; do
    cp -R "$ROOT/$item" "$unpacked_destination/"
done

(cd "$ROOT" && zip -qr "$destination" "${package_items[@]}")
echo "Created $destination"
echo "Created $unpacked_destination"
