#!/usr/bin/env bash
set -euo pipefail

PRODUCT_KEY="twitch"
DEFAULT_APP_DIR="$HOME/Library/Application Support/TwitchLocalExporter"
SHARED_STATE_DIR="$HOME/Library/Application Support/com.dowen.local_exporter"
DEFAULT_SHARED_ROOT="$SHARED_STATE_DIR/toolchain"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

app_dir="$DEFAULT_APP_DIR"
toolchain_mode="Shared"
toolchain_root=""
whisper_model="small"
whisper_acceleration="Auto"
skip_ffmpeg=false
skip_deno=false
skip_twitch_downloader=false
skip_whisper=false
force_update=false

usage() {
    cat <<'EOF'
Usage: update-tools.sh [options]

Options:
  --app-dir PATH                 Native host installation directory
  --toolchain-mode MODE          Shared, Isolated, or Custom (default: Shared)
  --toolchain-root PATH          Required with --toolchain-mode Custom
  --whisper-model NAME           tiny, base, small, medium, or large (default: small)
  --whisper-acceleration MODE    Auto, Cpu, or Cuda (Cuda is not available on macOS)
  --skip-ffmpeg
  --skip-deno
  --skip-twitch-downloader
  --skip-whisper
  --force-update                 Redownload bundled tools instead of reusing them
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-dir) app_dir="${2:-}"; shift 2 ;;
        --toolchain-mode) toolchain_mode="${2:-}"; shift 2 ;;
        --toolchain-root) toolchain_root="${2:-}"; shift 2 ;;
        --whisper-model) whisper_model="${2:-}"; shift 2 ;;
        --whisper-acceleration) whisper_acceleration="${2:-}"; shift 2 ;;
        --skip-ffmpeg) skip_ffmpeg=true; shift ;;
        --skip-deno) skip_deno=true; shift ;;
        --skip-twitch-downloader) skip_twitch_downloader=true; shift ;;
        --skip-whisper) skip_whisper=true; shift ;;
        --force-update) force_update=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

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
mode_lower="$(printf '%s' "$toolchain_mode" | tr '[:upper:]' '[:lower:]')"
case "$mode_lower" in
    shared) resolved_toolchain_root="${toolchain_root:-$DEFAULT_SHARED_ROOT}" ;;
    custom)
        [[ -n "$toolchain_root" ]] || { echo "--toolchain-root is required with Custom mode." >&2; exit 2; }
        resolved_toolchain_root="$toolchain_root"
        ;;
    isolated) resolved_toolchain_root="$app_dir/tools" ;;
    *) echo "Unsupported toolchain mode: $toolchain_mode" >&2; exit 2 ;;
esac

case "$whisper_model" in
    tiny|base|small|medium|large) ;;
    *) echo "Unsupported Whisper model: $whisper_model" >&2; exit 2 ;;
esac

case "$(printf '%s' "$whisper_acceleration" | tr '[:upper:]' '[:lower:]')" in
    auto|cpu) ;;
    cuda)
        echo "CUDA Whisper is not available on macOS; using the CPU/Metal build instead."
        ;;
    *) echo "Unsupported Whisper acceleration: $whisper_acceleration" >&2; exit 2 ;;
esac

for candidate in /opt/homebrew/bin /usr/local/bin /opt/local/bin; do
    if [[ -d "$candidate" ]]; then
        PATH="$candidate:$PATH"
    fi
done
export PATH

machine="$(uname -m)"
case "$machine" in
    arm64|aarch64)
        deno_target="aarch64-apple-darwin"
        ffmpeg_arch="arm64"
        twitch_asset_pattern='^TwitchDownloaderCLI-.*-MacOSArm64\.zip$'
        ;;
    x86_64|amd64)
        deno_target="x86_64-apple-darwin"
        ffmpeg_arch="amd64"
        twitch_asset_pattern='^TwitchDownloaderCLI-.*-MacOS-x64\.zip$'
        ;;
    *) echo "Unsupported macOS architecture: $machine" >&2; exit 2 ;;
esac

tools_dir="$resolved_toolchain_root"
product_tools_dir="$tools_dir/products/$PRODUCT_KEY"
models_dir="$tools_dir/models"
manifest_dir="$tools_dir/manifests"
mkdir -p "$tools_dir" "$product_tools_dir" "$models_dir" "$manifest_dir"

"$python_bin" - "$SHARED_STATE_DIR/settings.json" "$DEFAULT_SHARED_ROOT" "$PRODUCT_KEY" "$mode_lower" "$resolved_toolchain_root" <<'PY'
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

legacy_tools_dir="$app_dir/tools"
import_legacy() {
    local relative="$1"
    local destination_root="${2:-$tools_dir}"
    local source="$legacy_tools_dir/$relative"
    local destination="$destination_root/$relative"
    if [[ -f "$source" && ! -e "$destination" ]]; then
        mkdir -p "$(dirname -- "$destination")"
        cp "$source" "$destination"
        chmod +x "$destination" 2>/dev/null || true
        echo "Reused legacy tool: $source"
    fi
}

if [[ "$mode_lower" != "isolated" ]]; then
    for relative in yt-dlp deno ffmpeg ffprobe whisper-cli; do
        import_legacy "$relative"
    done
    import_legacy "models/ggml-$whisper_model.bin"
    import_legacy "TwitchDownloaderCLI" "$product_tools_dir"
fi

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/twitch-local-exporter-tools.XXXXXX")"
cleanup() {
    rm -rf "$temp_dir"
}
trap cleanup EXIT

die() {
    echo "$1" >&2
    exit 1
}

download_file() {
    local url="$1"
    local destination="$2"
    local partial="$destination.download"
    mkdir -p "$(dirname -- "$destination")"
    echo "Downloading $url"
    rm -f "$partial"
    curl -fsSL --retry 3 --connect-timeout 30 --output "$partial" "$url"
    [[ -s "$partial" ]] || die "Downloaded file is empty: $url"
    mv -f "$partial" "$destination"
}

find_working_tool() {
    local name="$1"
    local path
    path="$(command -v "$name" 2>/dev/null || true)"
    if [[ -n "$path" ]] && { "$path" --version >/dev/null 2>&1 || "$path" --help >/dev/null 2>&1; }; then
        printf '%s\n' "$path"
    fi
}

github_asset_url() {
    local repository="$1"
    local pattern="$2"
    local response
    response="$(curl -fsSL -H 'Accept: application/vnd.github+json' -H 'User-Agent: local-exporters' "https://api.github.com/repos/$repository/releases/latest")"
    printf '%s' "$response" | "$python_bin" -c '
import json
import re
import sys

pattern = sys.argv[1]
data = json.load(sys.stdin)
for asset in data.get("assets", []):
    if re.search(pattern, asset.get("name", ""), re.IGNORECASE):
        print(asset["browser_download_url"])
        break
else:
    raise SystemExit(1)
' "$pattern"
}

extract_zip_file() {
    local archive="$1"
    local filename="$2"
    local destination="$3"
    local extract_dir="$temp_dir/extract-$(basename "$destination")"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    unzip -q "$archive" -d "$extract_dir"
    local source
    source="$(find "$extract_dir" -type f -name "$filename" -print -quit)"
    [[ -n "$source" ]] || die "Archive did not contain $filename: $archive"
    cp "$source" "$destination"
    chmod +x "$destination"
}

extract_all_zip_files() {
    local archive="$1"
    local destination_dir="$2"
    local extract_dir="$temp_dir/extract-$(basename "$destination_dir")"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir" "$destination_dir"
    unzip -q "$archive" -d "$extract_dir"
    find "$extract_dir" -type f -exec cp {} "$destination_dir/" \;
    find "$destination_dir" -type f -exec chmod +x {} \; 2>/dev/null || true
}

version_of() {
    local path="$1"
    [[ -n "$path" && -x "$path" ]] || return 0
    "$path" --version 2>&1 | sed -n '1p' || true
}

yt_dlp_path="$tools_dir/yt-dlp"
if [[ "$force_update" == true ]]; then
    download_file "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" "$yt_dlp_path"
elif [[ -x "$yt_dlp_path" ]]; then
    echo "Reusing existing yt-dlp: $yt_dlp_path"
else
    external="$(find_working_tool yt-dlp || true)"
    if [[ -n "$external" ]]; then
        echo "Using working PATH tool: yt-dlp ($external)"
        yt_dlp_path="$external"
    else
        download_file "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" "$yt_dlp_path"
    fi
fi

if [[ "$skip_twitch_downloader" == false ]]; then
    twitch_downloader_path="$product_tools_dir/TwitchDownloaderCLI"
    if [[ "$force_update" == false && -x "$twitch_downloader_path" ]]; then
        echo "Reusing existing TwitchDownloaderCLI: $twitch_downloader_path"
    else
        external="$(find_working_tool TwitchDownloaderCLI || true)"
        if [[ "$force_update" == false && -n "$external" ]]; then
            echo "Using working PATH tool: TwitchDownloaderCLI ($external)"
            twitch_downloader_path="$external"
        else
            asset_url="$(github_asset_url "lay295/TwitchDownloader" "$twitch_asset_pattern" || true)"
            [[ -n "$asset_url" ]] || die "Could not find a macOS TwitchDownloaderCLI release for $machine."
            archive="$temp_dir/twitch-downloader.zip"
            download_file "$asset_url" "$archive"
            extract_all_zip_files "$archive" "$product_tools_dir"
            twitch_downloader_path="$product_tools_dir/TwitchDownloaderCLI"
            [[ -x "$twitch_downloader_path" ]] || die "Downloaded TwitchDownloaderCLI archive did not contain an executable."
        fi
    fi
fi

if [[ "$skip_deno" == false ]]; then
    deno_path="$tools_dir/deno"
    if [[ "$force_update" == true ]]; then
        archive="$temp_dir/deno.zip"
        download_file "https://github.com/denoland/deno/releases/latest/download/deno-$deno_target.zip" "$archive"
        extract_zip_file "$archive" "deno" "$deno_path"
    elif [[ -x "$deno_path" ]]; then
        echo "Reusing existing Deno: $deno_path"
    else
        external="$(find_working_tool deno || true)"
        if [[ -n "$external" ]]; then
            echo "Using working PATH tool: deno ($external)"
            deno_path="$external"
        else
            archive="$temp_dir/deno.zip"
            download_file "https://github.com/denoland/deno/releases/latest/download/deno-$deno_target.zip" "$archive"
            extract_zip_file "$archive" "deno" "$deno_path"
        fi
    fi
fi

if [[ "$skip_ffmpeg" == false ]]; then
    ffmpeg_path="$tools_dir/ffmpeg"
    ffprobe_path="$tools_dir/ffprobe"
    if [[ "$force_update" == false && -x "$ffmpeg_path" && -x "$ffprobe_path" ]]; then
        echo "Reusing existing FFmpeg: $ffmpeg_path"
    else
        external_ffmpeg="$(find_working_tool ffmpeg || true)"
        external_ffprobe="$(find_working_tool ffprobe || true)"
        if [[ "$force_update" == false && -n "$external_ffmpeg" && -n "$external_ffprobe" ]]; then
            echo "Using working PATH FFmpeg: $external_ffmpeg"
            ffmpeg_path="$external_ffmpeg"
            ffprobe_path="$external_ffprobe"
        else
            brew_path="$(command -v brew 2>/dev/null || true)"
            if [[ -n "$brew_path" && "$force_update" == false ]]; then
                "$brew_path" install ffmpeg
                external_ffmpeg="$(find_working_tool ffmpeg || true)"
                external_ffprobe="$(find_working_tool ffprobe || true)"
            fi
            if [[ -n "$external_ffmpeg" && -n "$external_ffprobe" && "$force_update" == false ]]; then
                ffmpeg_path="$external_ffmpeg"
                ffprobe_path="$external_ffprobe"
            else
                ffmpeg_zip="$temp_dir/ffmpeg.zip"
                ffprobe_zip="$temp_dir/ffprobe.zip"
                download_file "https://ffmpeg.martin-riedl.de/redirect/latest/macos/$ffmpeg_arch/release/ffmpeg.zip" "$ffmpeg_zip"
                download_file "https://ffmpeg.martin-riedl.de/redirect/latest/macos/$ffmpeg_arch/release/ffprobe.zip" "$ffprobe_zip"
                extract_zip_file "$ffmpeg_zip" "ffmpeg" "$ffmpeg_path"
                extract_zip_file "$ffprobe_zip" "ffprobe" "$ffprobe_path"
            fi
        fi
    fi
fi

if [[ "$skip_whisper" == false ]]; then
    whisper_path="$tools_dir/whisper-cli"
    if [[ "$force_update" == false && -x "$whisper_path" ]]; then
        echo "Reusing existing Whisper: $whisper_path"
    else
        external="$(find_working_tool whisper-cli || true)"
        if [[ -z "$external" ]]; then
            external="$(find_working_tool whisper-cpp || true)"
        fi
        brew_path="$(command -v brew 2>/dev/null || true)"
        if [[ -z "$external" && -n "$brew_path" ]]; then
            "$brew_path" install whisper-cpp
            external="$(find_working_tool whisper-cli || true)"
        fi
        if [[ -n "$external" ]]; then
            if [[ "$external" != "$whisper_path" ]]; then
                rm -f "$whisper_path"
                ln -s "$external" "$whisper_path"
            fi
            echo "Using macOS Whisper: $external"
        else
            die "whisper.cpp is required for local subtitle fallback. Install Homebrew, then run: brew install whisper-cpp"
        fi
    fi

    model_path="$models_dir/ggml-$whisper_model.bin"
    if [[ ! -f "$model_path" ]]; then
        download_file "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$whisper_model.bin" "$model_path"
    else
        echo "Reusing Whisper model: $model_path"
    fi
fi

yt_version="$(version_of "$yt_dlp_path")"
deno_version="$(version_of "${deno_path:-}")"
ffmpeg_version="$(version_of "${ffmpeg_path:-}")"
whisper_version="$(version_of "${whisper_path:-}")"
twitch_version="$(version_of "${twitch_downloader_path:-}")"

"$python_bin" - "$manifest_dir/$PRODUCT_KEY.json" "$PRODUCT_KEY" "$mode_lower" "$resolved_toolchain_root" "$machine" "$whisper_model" "$whisper_acceleration" "$yt_version" "$deno_version" "$ffmpeg_version" "$whisper_version" "$twitch_version" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

manifest_path = Path(sys.argv[1])
manifest_path.write_text(json.dumps({
    "updatedAt": datetime.now(timezone.utc).isoformat(),
    "product": sys.argv[2],
    "toolchainMode": sys.argv[3],
    "toolchainRoot": str(Path(sys.argv[4]).expanduser().resolve()),
    "platform": sys.argv[5],
    "ytDlp": sys.argv[8],
    "deno": sys.argv[9],
    "ffmpeg": sys.argv[10],
    "whisper": sys.argv[11],
    "whisperModel": f"ggml-{sys.argv[6]}.bin",
    "whisperAcceleration": sys.argv[7].lower(),
    "twitchDownloader": sys.argv[12]
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

echo "Tools installed in $tools_dir"
