# Changelog

## 0.1.0 - 2026-07-02

Initial public release.

### Added

- Chromium MV3 extension for exporting authorized YouTube video, audio, and subtitles through a local native messaging host.
- Export modes for MP4 video, audio-only files, and SRT/VTT subtitles.
- YouTube subtitle preference with local Whisper fallback or forced Whisper transcription.
- Windows native messaging host with local output folders, helper tool detection, job progress, cancellation, and output folder opening.
- Installer and uninstaller scripts for Chrome, Edge, Chromium, and Vivaldi native messaging registry entries.
- Tool updater for yt-dlp, Deno, FFmpeg/FFprobe, whisper.cpp, and Whisper models.
- GitHub Actions CI and tag-driven release packaging.

### Release Assets

- `youtube-local-exporter-v0.1.0-windows.zip`: complete Windows sideload bundle.
- `youtube-local-exporter-extension-v0.1.0.zip`: extension-only runtime package.
- `youtube-local-exporter-host-v0.1.0-windows-x64.exe`: standalone native host executable.
- `SHA256SUMS.txt`: checksums for downloadable release assets.
