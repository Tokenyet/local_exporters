#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
browser="all"
whisper_model="small"
whisper_acceleration="Auto"
skip_update_tools=false
purge_shared_toolchain=false
force_update=false

usage() {
    cat <<'EOF'
Usage: clean-install.sh [options]

Options:
  --browser NAME              chrome, edge, chromium, vivaldi, or all
  --whisper-model NAME        tiny, base, small, medium, or large
  --whisper-acceleration MODE Auto, Cpu, or Cuda (Cuda falls back to CPU on macOS)
  --skip-update-tools
  --force-update
  --purge-shared-toolchain
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --browser) browser="${2:-}"; shift 2 ;;
        --whisper-model) whisper_model="${2:-}"; shift 2 ;;
        --whisper-acceleration) whisper_acceleration="${2:-}"; shift 2 ;;
        --skip-update-tools) skip_update_tools=true; shift ;;
        --force-update) force_update=true; shift ;;
        --purge-shared-toolchain) purge_shared_toolchain=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

for product in twitch youtube; do
    bash "$ROOT/apps/$product/scripts/uninstall-native.sh" --browser "$browser" --remove-files
done

if [[ "$purge_shared_toolchain" == true ]]; then
    shared_root="$HOME/Library/Application Support/com.dowen.local_exporter"
    if [[ -d "$shared_root" && "$shared_root" != "$HOME" && "$shared_root" != "/" ]]; then
        rm -rf "$shared_root"
        echo "Removed shared toolchain: $shared_root"
    fi
fi

for product in twitch youtube; do
    bash "$ROOT/apps/$product/scripts/install-native.sh" --browser "$browser" --toolchain-mode Shared
done

if [[ "$skip_update_tools" == false ]]; then
    update_args=(
        --toolchain-mode Shared
        --whisper-model "$whisper_model"
        --whisper-acceleration "$whisper_acceleration"
    )
    if [[ "$force_update" == true ]]; then
        update_args+=(--force-update)
    fi
    for product in twitch youtube; do
        bash "$ROOT/apps/$product/scripts/update-tools.sh" "${update_args[@]}"
    done
fi

echo "macOS clean install completed. Reload both unpacked extensions before testing."
