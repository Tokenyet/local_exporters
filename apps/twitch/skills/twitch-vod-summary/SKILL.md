---
name: twitch-vod-summary
description: Export and summarize Twitch VOD content with the local Twitch Local Exporter toolchain. Use when Codex is in D:\Project\twitch_local_exporter and the user provides one or more Twitch VOD URLs, asks to run Whisper with chat, asks what a livestream was about, wants a two-day or multi-VOD comparison, or needs local Twitch VOD chat plus subtitle artifacts for analysis.
---

# Twitch VOD Summary

Use this project-scoped workflow for Twitch VOD analysis in this repo. Keep the repo-local boundary explicit: use the native-host modules and bundled tools from this project, do not generalize the workflow to other repos without rechecking their toolchain.

## Workflow

1. Confirm the request contains Twitch VOD URLs and that the user wants local analysis, summary, timeline, or comparison.
2. Check current repo state and tools when the run will be expensive:
   - `git status -sb`
   - `python skills/twitch-vod-summary/scripts/export_vod_summary.py --check-tools`
3. Run the exporter script from the repo root. Prefer resumable defaults:
   - `python skills/twitch-vod-summary/scripts/export_vod_summary.py <vod-url> [<vod-url> ...]`
   - Use `--workers 4 --threads-per-worker 4` unless the machine is under load.
   - Use `--output-dir .codex/vod-summary/exports` for local analysis artifacts.
   - For NVIDIA CUDA, run `scripts/install-gpu-whisper.ps1` once, then use `--whisper-backend faster-whisper --faster-whisper-device cuda --faster-whisper-compute-type float16 --workers 1`.
   - Use `--cleanup-intermediates` when the user only needs final deliverables after a successful run.
4. Read the generated manifest, per-VOD timeline files, `.whisper.zh-tw.srt`, and `.chat.json`.
5. Summarize from both Whisper and chat:
   - Treat Whisper as approximate, especially during songs, silence, overlapping game audio, and repeated UI sounds.
   - Use chat to verify topic changes, raid timing, viewer reactions, links, and proper nouns.
   - Do not convert chat text with OpenCC. Chat is already user-authored and should stay untouched.
   - Convert Chinese subtitle output to Traditional Chinese (Taiwan) only for subtitle artifacts.
6. Report artifact paths and the validation limits. For long VODs, mention if the script reused existing audio/chunks/transcripts.
7. For completed long VOD jobs, offer cleanup if `--cleanup-intermediates` was not used. To clean existing artifacts without rerunning exports:
   - `python skills/twitch-vod-summary/scripts/export_vod_summary.py --cleanup-only --cleanup-root .codex/vod-summary`

## Script Contract

`scripts/export_vod_summary.py` produces:

- `<vod-id>.chat.json`
- `<vod-id>.audio.wav`
- `<vod-id>.chunks-<seconds>s/`
- `<vod-id>.whisper.zh-tw.srt`
- `<vod-id>.timeline.txt`
- `manifest.json`
- `events.jsonl`

When cleanup is requested, the script keeps final deliverables and removes recomputable intermediates:

- Keeps: `*.chat.json`, `*.whisper.zh-tw.srt`, `*.timeline.txt`, `manifest.json`, legacy `parallel-manifest.json`.
- Deletes: `*.audio.wav`, `*.source.*`, chunk directories, runner/smoke logs, `events.jsonl`, pid files, Python cache files, and old one-off runner scripts under the cleanup roots.

Useful options:

- `--check-tools`: print tool availability and exit.
- `--output-dir <path>`: choose artifact directory.
- `--model tiny|base|small|medium|large`: select bundled whisper.cpp model.
- `--whisper-backend whisper-cli|faster-whisper`: choose the CPU whisper.cpp path or the CTranslate2 path.
- `--faster-whisper-model <name-or-path>` and `--faster-whisper-model-dir <path>`: select/cache a faster-whisper model.
- `--faster-whisper-device cuda|cpu` and `--faster-whisper-compute-type <type>`: configure the faster-whisper device and precision.
- `--workers <n>` and `--threads-per-worker <n>`: control parallel Whisper chunking.
- `--chunk-seconds <n>`: default `900`.
- `--timeline-window-seconds <n>`: default `1800`.
- `--no-chat`, `--no-whisper`, `--no-reuse`: adjust expensive stages when needed.
- `--cleanup-intermediates`: clean recomputable artifacts after a successful run.
- `--cleanup-only`: clean recomputable artifacts and exit without exporting.
- `--cleanup-root <path>`: optionally clean old runner/smoke artifacts from a parent root such as `.codex/vod-summary`.

## Summary Guidance

For final summaries, prefer:

- A short overall conclusion first.
- Separate sections per VOD/date.
- Timeline chunks only when the user asks for detail.
- Clear uncertainty notes for phrases that look like Whisper hallucination, subtitle boilerplate, song lyrics, or game UI audio.

Avoid:

- Presenting Whisper text as exact quotes.
- Summarizing only from chat when audio is available.
- Deleting final generated artifacts. Cleanup should only remove allowlisted intermediate files.
