Download the matching platform bundle: `youtube-local-exporter-vX.Y.Z-windows.zip` on Windows or `youtube-local-exporter-vX.Y.Z-macos-arm64.zip` / `youtube-local-exporter-vX.Y.Z-macos-x64.zip` on macOS. Extract it, then load this folder in your browser extension page:

```text
extension
```

Copy the generated extension ID, then run the native host installer from the extracted release folder:

```powershell
.\scripts\install-native.ps1 -ExtensionId <extension-id> -Browser chrome
.\scripts\update-tools.ps1
```

Use `-Browser edge`, `-Browser chromium`, `-Browser vivaldi`, or omit `-Browser` to register all supported browser registry paths.

On macOS, use the shell scripts:

```bash
./scripts/install-native.sh --extension-id <extension-id> --browser chrome
./scripts/update-tools.sh
```

Use `--browser edge`, `--browser chromium`, `--browser vivaldi`, or `--browser all`. The macOS updater selects Apple Silicon or Intel assets, uses the shared toolchain under `~/Library/Application Support/com.dowen.local_exporter/toolchain`, and uses Homebrew for FFmpeg/Whisper when no working local copy is available.

The release bundle includes the extension files, native host files, installer scripts, release notes, and privacy notes. The Windows updater downloads `yt-dlp`, Deno, FFmpeg/FFprobe, whisper.cpp, and the selected Whisper model into the shared `%LOCALAPPDATA%\com.dowen.local_exporter\toolchain`; the macOS updater uses the corresponding macOS tool names and `~/Library/Application Support/com.dowen.local_exporter/toolchain`. On NVIDIA Windows systems, the default `-WhisperAcceleration Auto` mode also installs the CUDA/cuBLAS Whisper binary and uses CPU fallback if CUDA cannot start.
