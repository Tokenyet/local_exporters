# Local Exporters

Local Exporters is a Chromium extension suite for Windows and macOS that exports authorized Twitch and YouTube content to local files.

The repository contains two independent extensions:

- [Twitch Local Exporter](apps/twitch/README.md): video, audio, subtitles, and VOD chat.
- [YouTube Local Exporter](apps/youtube/README.md): video, audio, and subtitles.

They share the local toolchain layout and release infrastructure, but keep separate manifests, permissions, native hosts, product behavior, versions, and release artifacts.

## Why this exists

I built Local Exporters because livestreams are often difficult to catch up on. Some YouTube livestreams have no subtitles, which means there is no transcript to review or give to an AI summarizer. For Twitch, I often follow chat-focused streamers but do not always have time to watch live; subtitles and VOD chat make it possible to understand what was discussed and build an outline before deciding which parts to watch.

The project does not send content to an AI provider. It creates local subtitle, chat, audio, and video files that you can inspect or use with the summarization tool you choose.

## Official site

The project website is published through GitHub Pages:

<https://www.dowen.idv.tw/local_exporters/>

It includes the motivation behind the project, real exporter screenshots, technical architecture, support notes, and privacy policy.

The website is available in English and Traditional Chinese. On a first visit, browsers that prefer Traditional Chinese are directed to the localized pages. A manual language choice is stored locally and takes precedence on later visits.

## Quick start

On Windows, run from PowerShell:

```powershell
.\scripts\package-all.ps1
```

The manifests contain stable public signing keys, so the unpacked extension IDs remain fixed across reloads and clean installs. Print them with:

```powershell
.\scripts\show-extension-ids.ps1
```

Load the generated unpacked directories from `apps\twitch\dist\unpacked\` and `apps\youtube\dist\unpacked\` through the browser's extension developer page, then register the corresponding native hosts. Each app installer derives its stable ID automatically:

```powershell
.\apps\twitch\scripts\install-native.ps1 -Browser all -ToolchainMode Shared
.\apps\youtube\scripts\install-native.ps1 -Browser all -ToolchainMode Shared
.\apps\twitch\scripts\update-tools.ps1 -ToolchainMode Shared
.\apps\youtube\scripts\update-tools.ps1 -ToolchainMode Shared
```

The default shared toolchain is:

```text
%LOCALAPPDATA%\com.dowen.local_exporter\toolchain
```

On macOS, use the shell entry points:

```bash
./scripts/package-all.sh
./apps/twitch/scripts/install-native.sh --browser chrome --toolchain-mode Shared
./apps/youtube/scripts/install-native.sh --browser chrome --toolchain-mode Shared
./apps/twitch/scripts/update-tools.sh --toolchain-mode Shared
./apps/youtube/scripts/update-tools.sh --toolchain-mode Shared
```

The macOS shared toolchain is stored under `~/Library/Application Support/com.dowen.local_exporter/toolchain`. The native host registers manifests under the selected Chromium browser's `~/Library/Application Support/<Browser>/NativeMessagingHosts` directory. Apple Silicon and Intel Macs are supported; the updater selects the matching Deno and TwitchDownloaderCLI assets. FFmpeg and Whisper use working PATH tools or Homebrew (`brew install ffmpeg whisper-cpp`) when needed.

Common tools and models are stored once. Product-specific tools live below `products\twitch` or `products\youtube` on Windows, and `products/twitch` or `products/youtube` on macOS. Use `-ToolchainMode Isolated` on Windows or `--toolchain-mode Isolated` on macOS to retain the legacy app-specific layout. Existing files are reused; pass `-ForceUpdate` on Windows or `--force-update` on macOS when a redownload is intentional.

The tool updaters also probe working CLI commands already available on `PATH` (`yt-dlp`, Deno, FFmpeg/FFprobe, Whisper, and TwitchDownloaderCLI). A successful version/help probe lets the native host use that external executable without downloading a duplicate; the platform's force-update option overrides this reuse and installs bundled copies.

For NVIDIA CUDA Whisper transcription in both extensions, use the default auto-detected mode (or force it explicitly):

```powershell
.\scripts\clean-install.ps1 -WhisperAcceleration Auto
```

On Windows, the native host prefers `toolchain\cuda\whisper-cli.exe` when `nvidia-smi` is available and retries with the CPU Whisper binary if CUDA startup fails. macOS uses the CPU/Metal-capable Whisper build and does not require CUDA. The existing Twitch VOD-summary faster-whisper workflow remains available separately.

For a complete clean reinstall after loading the new unpacked extensions, no IDs or browser parameter are needed. The script detects the Windows HTTPS default browser, reinstalls both native hosts, and updates the shared toolchain:

```powershell
.\scripts\clean-install.ps1
```

Use `-Browser all` to register every supported browser, or specify `chrome`, `edge`, `chromium`, or `vivaldi` explicitly.
Use `-SkipUpdateTools` when you only need to repair native-host registration without downloading or checking the toolchain. Use `-WhisperModel tiny|base|small|medium|large` to choose the model downloaded during a complete clean install.

On macOS, the equivalent flow is:

```bash
./scripts/clean-install.sh --browser all
```

Use `--skip-update-tools`, `--force-update`, and `--purge-shared-toolchain` for the corresponding macOS options.

## Development

```powershell
.\scripts\test-all.ps1
.\scripts\package-all.ps1
```

The GitHub Actions workflows validate both apps on Windows and macOS, package platform-specific release artifacts, publish per-product GitHub Releases, and deploy `docs\` to GitHub Pages.

## Repository layout

```text
apps\twitch\      Twitch extension, native host, tool updater, and VOD summary skill
apps\youtube\     YouTube extension, native host, and tool updater
docs\              Official website, support, privacy, and store submission drafts
scripts\           Monorepo-wide test, package, and clean-install entry points
.github\workflows  Matrix CI, per-product releases, and GitHub Pages deployment
```

## Privacy

The extensions store preferences in `chrome.storage.sync`. Export jobs run through a local native host, write to the user's selected local output folder, and do not send generated media to a developer service. See the [privacy policy](docs/privacy.html) for the product-specific boundaries.

Use these tools only for content you own or are authorized to export.
