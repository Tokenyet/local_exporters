#!/usr/bin/env bash
set -euo pipefail

HOST_NAME="com.dowen.twitch_local_exporter"
DEFAULT_APP_DIR="$HOME/Library/Application Support/TwitchLocalExporter"
browser="all"
app_dir="$DEFAULT_APP_DIR"
remove_files=false

usage() {
    cat <<'EOF'
Usage: uninstall-native.sh [options]

Options:
  --browser NAME     chrome, edge, chromium, vivaldi, or all (default: all)
  --app-dir PATH     Override the native host installation directory
  --remove-files     Remove the app's installed native host files too
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --browser) browser="${2:-}"; shift 2 ;;
        --app-dir) app_dir="${2:-}"; shift 2 ;;
        --remove-files) remove_files=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$(printf '%s' "$browser" | tr '[:upper:]' '[:lower:]')" in
    chrome|edge|chromium|vivaldi|all) ;;
    *) echo "Unsupported browser: $browser" >&2; exit 2 ;;
esac

if [[ -z "$app_dir" || "$app_dir" == "/" || "$app_dir" == "$HOME" ]]; then
    echo "Refusing to remove an unsafe app directory: $app_dir" >&2
    exit 2
fi

unregister_browser() {
    local name="$1"
    local browser_dir
    case "$name" in
        chrome) browser_dir="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts" ;;
        edge) browser_dir="$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts" ;;
        chromium) browser_dir="$HOME/Library/Application Support/Chromium/NativeMessagingHosts" ;;
        vivaldi) browser_dir="$HOME/Library/Application Support/Vivaldi/NativeMessagingHosts" ;;
        *) echo "Unsupported browser: $name" >&2; return 1 ;;
    esac
    rm -f "$browser_dir/$HOST_NAME.json"
    echo "Removed $name native host registration."
}

if [[ "$browser" == "all" ]]; then
    for name in chrome edge chromium vivaldi; do
        unregister_browser "$name"
    done
else
    unregister_browser "$browser"
fi

if [[ "$remove_files" == true && -d "$app_dir" ]]; then
    rm -rf "$app_dir"
    echo "Removed $app_dir"
fi
