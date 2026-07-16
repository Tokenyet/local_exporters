# Local Exporters

Local Exporters is a Windows-first Chromium extension suite for exporting authorized Twitch and YouTube content to local files.

The repository contains two independent extensions:

- [Twitch Local Exporter](apps/twitch/README.md): video, audio, subtitles, and VOD chat.
- [YouTube Local Exporter](apps/youtube/README.md): video, audio, and subtitles.

They share the local toolchain layout and release infrastructure, but keep separate manifests, permissions, native hosts, product behavior, versions, and release artifacts.

## Official site

The project website is published through GitHub Pages:

<https://tokenyet.github.io/local_exporters/>

It includes the product overview, support notes, and privacy policy.

## Quick start

From PowerShell on Windows:

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

Common tools and models are stored once. Product-specific tools live below `products\twitch` or `products\youtube`. Use `-ToolchainMode Isolated` to retain the legacy app-specific layout, or `-ToolchainMode Custom -ToolchainRoot <path>` for another location. Existing files are reused; pass `-ForceUpdate` when a redownload is intentional.

The tool updaters also probe working CLI commands already available on `PATH` (`yt-dlp`, Deno, FFmpeg/FFprobe, Whisper, and TwitchDownloaderCLI). A successful version/help probe lets the native host use that external executable without downloading a duplicate; `-ForceUpdate` overrides this reuse and installs bundled copies.

For NVIDIA CUDA Whisper transcription in both extensions, use the default auto-detected mode (or force it explicitly):

```powershell
.\scripts\clean-install.ps1 -WhisperAcceleration Auto
```

The native host prefers `toolchain\cuda\whisper-cli.exe` when `nvidia-smi` is available and retries with the CPU Whisper binary if CUDA startup fails. The existing Twitch VOD-summary faster-whisper workflow remains available separately.

For a complete clean reinstall after loading the new unpacked extensions, no IDs or browser parameter are needed. The script detects the Windows HTTPS default browser, reinstalls both native hosts, and updates the shared toolchain:

```powershell
.\scripts\clean-install.ps1
```

Use `-Browser all` to register every supported browser, or specify `chrome`, `edge`, `chromium`, or `vivaldi` explicitly.
Use `-SkipUpdateTools` when you only need to repair native-host registration without downloading or checking the toolchain. Use `-WhisperModel tiny|base|small|medium|large` to choose the model downloaded during a complete clean install.

## Development

```powershell
.\scripts\test-all.ps1
.\scripts\package-all.ps1
```

The GitHub Actions workflows validate both apps independently, package extension and Windows release artifacts, publish per-product GitHub Releases, and deploy `docs\` to GitHub Pages.

## Repository layout

```text
apps\twitch\      Twitch extension, native host, tool updater, and VOD summary skill
apps\youtube\     YouTube extension, native host, and tool updater
docs\              Official website, support, privacy, and store submission drafts
scripts\           Monorepo-wide test, package, and clean-install entry points
.github\workflows  Matrix CI, per-product releases, and GitHub Pages deployment
```

## Privacy

The extensions store preferences in `chrome.storage.sync`. Export jobs run through local Windows native hosts, write to the user's selected local output folder, and do not send generated media to a developer service. See the [privacy policy](docs/privacy.html) for the product-specific boundaries.

Use these tools only for content you own or are authorized to export.
