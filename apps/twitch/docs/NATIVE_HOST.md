# Native Host Notes

## Message Protocol

Messages use the Chrome native messaging framing: a 4-byte little-endian payload length followed by a UTF-8 JSON object.

Extension requests include an `id` and one of these actions:

- `ping`
- `probe`
- `export`
- `jobStatus`
- `cancelJob`
- `openOutputFolder`
- `chooseOutputFolder`
- `updateTools`

Responses echo `id` for direct requests. Job updates are pushed as standalone messages containing `jobId`, `event`, `percent`, `detail`, and optionally `outputPath` or `error`.

## Tool Locations

Bundled tools are preferred from:

```text
Windows shared mode: `%LOCALAPPDATA%\com.dowen.local_exporter\toolchain`

macOS shared mode: `~/Library/Application Support/com.dowen.local_exporter/toolchain`

Windows isolated mode: `%LOCALAPPDATA%\TwitchLocalExporter\tools`

macOS isolated mode: `~/Library/Application Support/TwitchLocalExporter/tools`
```

The host falls back to PATH for development when a bundled executable is missing.

Required tools by export type:

- Video/audio: `yt-dlp`/`yt-dlp.exe`, `ffmpeg`/`ffmpeg.exe`, and `ffprobe`/`ffprobe.exe`
- Chat: `TwitchDownloaderCLI`/`TwitchDownloaderCLI.exe`
- Subtitle fallback: yt-dlp, FFmpeg, Whisper, and `models/ggml-small.bin` by default
- Optional Windows GPU subtitle path: `cuda\whisper-cli.exe`; selected automatically when `nvidia-smi` is available, with CPU retry on CUDA startup failure
- Twitch-only: `products/twitch/TwitchDownloaderCLI` in macOS shared mode
- Optional `yt-dlp` JavaScript runtime: Deno or another supported runtime on PATH (`node`, `quickjs`, or `bun`)

## Output Naming

Files use:

```text
YYYY-MM-DD - title [vodId].ext
YYYY-MM-DD - title [vodId].chat.json
```

Invalid filename characters and `%` are replaced with `_`.
