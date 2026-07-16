from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


TIME_RE = re.compile(
    r"(?P<sh>\d{2}):(?P<sm>\d{2}):(?P<ss>\d{2})[,.](?P<sms>\d{3})\s+-->\s+"
    r"(?P<eh>\d{2}):(?P<em>\d{2}):(?P<es>\d{2})[,.](?P<ems>\d{3})"
)

NOISE_PHRASES = (
    "MING PAO",
    "subtitle",
    "SUBTITLE",
    "CC subtitle",
    "Subscribe",
)


def find_repo_root(start: Path) -> Path:
    for path in [start, *start.parents]:
        if (path / "native-host" / "twitch_local_exporter").is_dir():
            return path
    raise RuntimeError("Could not find twitch_local_exporter repo root from script path")


REPO_ROOT = find_repo_root(Path(__file__).resolve())
NATIVE_HOST = REPO_ROOT / "native-host"
sys.path.insert(0, str(NATIVE_HOST))

from twitch_local_exporter.commands import (  # noqa: E402
    build_chat_command,
    build_download_audio_command,
    build_ffmpeg_wav_command,
    run_probe,
    summarize_probe,
)
from twitch_local_exporter.subtitle_text import convert_chinese_subtitle_file  # noqa: E402
from twitch_local_exporter.tools import require_tools, status, tools_dir  # noqa: E402


class Context:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.output_dir = Path(args.output_dir).expanduser().resolve()
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.events_path = self.output_dir / "events.jsonl"
        self.manifest_path = self.output_dir / "manifest.json"
        if not args.append_events:
            self.events_path.write_text("", encoding="utf-8")

    def emit(self, payload: dict[str, Any]) -> None:
        payload = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), **payload}
        with self.events_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, ensure_ascii=False) + "\n")
        print(json.dumps(payload, ensure_ascii=False), flush=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export Twitch VOD chat, run local Whisper in chunks, and write timeline artifacts."
    )
    parser.add_argument("urls", nargs="*", help="Twitch VOD URLs")
    parser.add_argument(
        "--output-dir",
        default=str(REPO_ROOT / ".codex" / "vod-summary" / "exports"),
        help="Artifact directory",
    )
    parser.add_argument("--model", default="small", choices=["tiny", "base", "small", "medium", "large"])
    parser.add_argument("--language", default="zh", help="Whisper language code")
    parser.add_argument(
        "--whisper-backend",
        choices=["whisper-cli", "faster-whisper"],
        default="whisper-cli",
        help="Transcription backend; faster-whisper uses CTranslate2 and can run on CUDA.",
    )
    parser.add_argument(
        "--faster-whisper-model",
        default="small",
        help="faster-whisper model name or local model directory.",
    )
    parser.add_argument(
        "--faster-whisper-device",
        default="cuda",
        choices=["cuda", "cpu"],
        help="Device for faster-whisper.",
    )
    parser.add_argument(
        "--faster-whisper-compute-type",
        default="float16",
        help="CTranslate2 compute type, for example float16 or int8_float16.",
    )
    parser.add_argument(
        "--faster-whisper-model-dir",
        default=str(tools_dir() / "models" / "faster-whisper"),
        help="Cache directory for faster-whisper models.",
    )
    parser.add_argument("--workers", type=int, default=4, help="Parallel Whisper processes")
    parser.add_argument("--threads-per-worker", type=int, default=4, help="whisper-cli threads per process")
    parser.add_argument("--chunk-seconds", type=int, default=900, help="Audio chunk size")
    parser.add_argument("--timeline-window-seconds", type=int, default=1800, help="Timeline bucket size")
    parser.add_argument("--check-tools", action="store_true", help="Print tool status and exit")
    parser.add_argument("--no-chat", action="store_true", help="Skip chat export")
    parser.add_argument("--no-whisper", action="store_true", help="Skip audio and Whisper")
    parser.add_argument("--no-reuse", action="store_true", help="Recreate stage outputs where practical")
    parser.add_argument("--append-events", action="store_true", help="Append to events.jsonl instead of truncating")
    parser.add_argument(
        "--cleanup-intermediates",
        action="store_true",
        help="After a successful run, delete recomputable audio/source/chunk/log artifacts.",
    )
    parser.add_argument(
        "--cleanup-only",
        action="store_true",
        help="Clean recomputable artifacts and exit without exporting VODs.",
    )
    parser.add_argument(
        "--cleanup-root",
        default="",
        help="Optional parent cleanup root, such as .codex/vod-summary, for old runner/smoke artifacts.",
    )
    return parser.parse_args()


def command_summary(command: list[str]) -> str:
    if not command:
        return ""
    return f"{Path(command[0]).name} {' '.join(command[1:4])}".strip()


def run_command(ctx: Context, command: list[str], *, event: str, log_path: Path) -> None:
    ctx.emit({"event": event, "phase": "start", "command": command_summary(command), "logPath": str(log_path)})
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        process = subprocess.run(
            command,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    if process.returncode != 0:
        tail = "\n".join(log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-20:])
        raise RuntimeError(f"{event} failed with exit code {process.returncode}\n{tail}")
    ctx.emit({"event": event, "phase": "done"})


def vod_id_from_probe(probe: dict[str, Any], info: dict[str, Any]) -> str:
    return str(probe.get("id") or info.get("id") or "").removeprefix("v")


def standard_chat_path(ctx: Context, vod_id: str) -> Path:
    return ctx.output_dir / f"{vod_id}.chat.json"


def existing_chat(ctx: Context, vod_id: str) -> Path | None:
    standard = standard_chat_path(ctx, vod_id)
    if standard.exists() and ctx.args.no_reuse is False:
        return standard
    if ctx.args.no_reuse:
        return None
    matches = sorted(ctx.output_dir.glob(f"*{vod_id}*.chat.json"), key=lambda path: path.stat().st_mtime, reverse=True)
    return matches[0] if matches else None


def ensure_chat(ctx: Context, tools: dict[str, Path], url: str, vod_id: str, title: str) -> Path | None:
    if ctx.args.no_chat:
        ctx.emit({"event": "chat", "vodId": vod_id, "phase": "skipped"})
        return None

    found = existing_chat(ctx, vod_id)
    standard = standard_chat_path(ctx, vod_id)
    if found:
        if found != standard:
            shutil.copy2(found, standard)
        ctx.emit({"event": "chat", "vodId": vod_id, "phase": "reuse", "path": str(standard)})
        return standard

    request = {
        "url": url,
        "vodId": vod_id,
        "videoId": vod_id,
        "title": title,
        "outputDir": str(ctx.output_dir),
        "chat": {"format": "json", "embedImages": False},
    }
    run_command(
        ctx,
        build_chat_command(tools["TwitchDownloaderCLI.exe"], request, standard),
        event=f"chat-{vod_id}",
        log_path=ctx.output_dir / f"{vod_id}.chatdownload.log",
    )
    return standard


def ensure_audio_wav(ctx: Context, tools: dict[str, Path], url: str, vod_id: str) -> Path:
    wav_path = ctx.output_dir / f"{vod_id}.audio.wav"
    if wav_path.exists() and wav_path.stat().st_size > 1024 and not ctx.args.no_reuse:
        ctx.emit({"event": "audio", "vodId": vod_id, "phase": "reuse", "path": str(wav_path)})
        return wav_path

    source_template = ctx.output_dir / f"{vod_id}.source.%(ext)s"
    run_command(
        ctx,
        build_download_audio_command(tools["yt-dlp.exe"], url, source_template),
        event=f"audio-download-{vod_id}",
        log_path=ctx.output_dir / f"{vod_id}.yt-dlp.log",
    )
    sources = sorted(ctx.output_dir.glob(f"{vod_id}.source.*"), key=lambda path: path.stat().st_mtime, reverse=True)
    sources = [path for path in sources if path.suffix.lower() not in {".log", ".part", ".ytdl"}]
    if not sources:
        raise RuntimeError(f"No downloaded audio source for {vod_id}")
    run_command(
        ctx,
        build_ffmpeg_wav_command(tools["ffmpeg.exe"], sources[0], wav_path),
        event=f"audio-wav-{vod_id}",
        log_path=ctx.output_dir / f"{vod_id}.ffmpeg-wav.log",
    )
    return wav_path


def chunk_dir(ctx: Context, vod_id: str) -> Path:
    return ctx.output_dir / f"{vod_id}.chunks-{ctx.args.chunk_seconds}s"


def ensure_chunks(ctx: Context, tools: dict[str, Path], vod_id: str, wav_path: Path) -> list[Path]:
    directory = chunk_dir(ctx, vod_id)
    directory.mkdir(parents=True, exist_ok=True)
    chunks = sorted(directory.glob("chunk_*.wav"))
    if chunks and not ctx.args.no_reuse:
        ctx.emit({"event": "chunks", "vodId": vod_id, "phase": "reuse", "count": len(chunks)})
        return chunks

    if ctx.args.no_reuse:
        for path in directory.glob("chunk_*.*"):
            path.unlink()

    output_pattern = directory / "chunk_%04d.wav"
    run_command(
        ctx,
        [
            str(tools["ffmpeg.exe"]),
            "-y",
            "-i",
            str(wav_path),
            "-f",
            "segment",
            "-segment_time",
            str(ctx.args.chunk_seconds),
            "-reset_timestamps",
            "1",
            "-c",
            "copy",
            str(output_pattern),
        ],
        event=f"chunk-{vod_id}",
        log_path=ctx.output_dir / f"{vod_id}.ffmpeg-chunks.log",
    )
    chunks = sorted(directory.glob("chunk_*.wav"))
    if not chunks:
        raise RuntimeError(f"No chunks produced for {vod_id}")
    ctx.emit({"event": "chunks", "vodId": vod_id, "phase": "done", "count": len(chunks)})
    return chunks


class FasterWhisperTranscriber:
    def __init__(self, args: argparse.Namespace) -> None:
        try:
            from faster_whisper import WhisperModel
        except ImportError as exc:
            raise RuntimeError(
                "faster-whisper is not installed; install it in the active Python environment"
            ) from exc

        self.args = args
        self.model = WhisperModel(
            args.faster_whisper_model,
            device=args.faster_whisper_device,
            compute_type=args.faster_whisper_compute_type,
            download_root=str(Path(args.faster_whisper_model_dir).expanduser().resolve()),
        )

    def transcribe(self, chunk: Path, srt_path: Path, log_path: Path) -> Path:
        language = None if self.args.language == "auto" else self.args.language
        segments, info = self.model.transcribe(
            str(chunk),
            language=language,
            beam_size=5,
            vad_filter=True,
        )
        index = 1
        with srt_path.open("w", encoding="utf-8") as output:
            for segment in segments:
                text = segment.text.strip()
                if not text:
                    continue
                output.write(
                    f"{index}\n"
                    f"{format_time(int(segment.start * 1000))} --> {format_time(int(segment.end * 1000))}\n"
                    f"{text}\n\n"
                )
                index += 1
        log_path.write_text(
            json.dumps(
                {
                    "backend": "faster-whisper",
                    "device": self.args.faster_whisper_device,
                    "computeType": self.args.faster_whisper_compute_type,
                    "model": self.args.faster_whisper_model,
                    "language": getattr(info, "language", self.args.language),
                    "languageProbability": getattr(info, "language_probability", None),
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        if not srt_path.exists():
            raise RuntimeError(f"faster-whisper did not produce {srt_path}")
        return srt_path


def transcribe_chunk(
    ctx: Context,
    tools: dict[str, Path],
    chunk: Path,
    transcriber: FasterWhisperTranscriber | None = None,
) -> Path:
    output_base = chunk.with_suffix("")
    srt_path = output_base.with_suffix(".srt")
    if srt_path.exists() and srt_path.stat().st_size > 0 and not ctx.args.no_reuse:
        return srt_path

    log_path = output_base.with_suffix(".whisper.log")
    if transcriber is not None:
        return transcriber.transcribe(chunk, srt_path, log_path)

    command = [
        str(tools["whisper-cli.exe"]),
        "-np",
        "-t",
        str(ctx.args.threads_per_worker),
        "-m",
        str(tools["model"]),
        "-f",
        str(chunk),
        "-l",
        ctx.args.language,
        "-osrt",
        "-of",
        str(output_base),
    ]
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        process = subprocess.run(
            command,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    if process.returncode != 0:
        tail = "\n".join(log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-20:])
        raise RuntimeError(f"Whisper failed for {chunk.name}: {tail}")
    if not srt_path.exists():
        raise RuntimeError(f"Whisper did not produce {srt_path}")
    return srt_path


def ensure_transcripts(ctx: Context, tools: dict[str, Path], vod_id: str, chunks: list[Path]) -> list[Path]:
    pending = [
        chunk for chunk in chunks
        if ctx.args.no_reuse or not chunk.with_suffix(".srt").exists() or chunk.with_suffix(".srt").stat().st_size == 0
    ]
    done = len(chunks) - len(pending)
    ctx.emit({
        "event": "whisper",
        "vodId": vod_id,
        "phase": "start",
        "chunks": len(chunks),
        "pending": len(pending),
        "backend": ctx.args.whisper_backend,
        "workers": ctx.args.workers,
        "threadsPerWorker": ctx.args.threads_per_worker,
    })
    last_emit = time.time()

    if ctx.args.whisper_backend == "faster-whisper":
        transcriber = FasterWhisperTranscriber(ctx.args)
        for chunk in pending:
            transcribe_chunk(ctx, tools, chunk, transcriber)
            done += 1
            now = time.time()
            if now - last_emit >= 5 or done == len(chunks):
                ctx.emit({
                    "event": "whisper",
                    "vodId": vod_id,
                    "phase": "progress",
                    "done": done,
                    "chunks": len(chunks),
                    "backend": ctx.args.whisper_backend,
                    "lastChunk": chunk.name,
                })
                last_emit = now
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=ctx.args.workers) as executor:
            future_to_chunk = {executor.submit(transcribe_chunk, ctx, tools, chunk): chunk for chunk in pending}
            for future in concurrent.futures.as_completed(future_to_chunk):
                chunk = future_to_chunk[future]
                future.result()
                done += 1
                now = time.time()
                if now - last_emit >= 5 or done == len(chunks):
                    ctx.emit({
                        "event": "whisper",
                        "vodId": vod_id,
                        "phase": "progress",
                        "done": done,
                        "chunks": len(chunks),
                        "backend": ctx.args.whisper_backend,
                        "lastChunk": chunk.name,
                    })
                    last_emit = now

    srts = sorted(chunk.with_suffix(".srt") for chunk in chunks)
    missing = [path for path in srts if not path.exists()]
    if missing:
        raise RuntimeError(f"Missing chunk transcripts: {', '.join(path.name for path in missing[:5])}")
    ctx.emit({"event": "whisper", "vodId": vod_id, "phase": "done", "chunks": len(srts)})
    return srts


def parse_time(value: str) -> int:
    hours, minutes, rest = value.split(":")
    seconds, millis = re.split(r"[,\\.]", rest)
    return ((int(hours) * 3600 + int(minutes) * 60 + int(seconds)) * 1000) + int(millis)


def format_time(total_ms: int) -> str:
    hours, rem = divmod(total_ms, 3_600_000)
    minutes, rem = divmod(rem, 60_000)
    seconds, millis = divmod(rem, 1000)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{millis:03d}"


def adjusted_time_line(line: str, offset_ms: int) -> str:
    match = TIME_RE.search(line)
    if not match:
        return line
    start = parse_time(f"{match.group('sh')}:{match.group('sm')}:{match.group('ss')},{match.group('sms')}")
    end = parse_time(f"{match.group('eh')}:{match.group('em')}:{match.group('es')},{match.group('ems')}")
    return f"{format_time(start + offset_ms)} --> {format_time(end + offset_ms)}"


def combine_srt(ctx: Context, vod_id: str, srts: list[Path]) -> Path:
    output = ctx.output_dir / f"{vod_id}.whisper.zh-tw.srt"
    index = 1
    blocks: list[str] = []
    for chunk_index, srt in enumerate(srts):
        offset_ms = chunk_index * ctx.args.chunk_seconds * 1000
        text = srt.read_text(encoding="utf-8-sig", errors="replace").strip()
        if not text:
            continue
        for block in re.split(r"\n\s*\n", text):
            lines = [line.strip("\ufeff") for line in block.splitlines() if line.strip()]
            if len(lines) < 2:
                continue
            time_line_index = next((i for i, line in enumerate(lines) if "-->" in line), -1)
            if time_line_index < 0:
                continue
            body = lines[time_line_index + 1:]
            if not body:
                continue
            blocks.append("\n".join([
                str(index),
                adjusted_time_line(lines[time_line_index], offset_ms),
                *body,
            ]))
            index += 1
    output.write_text("\n\n".join(blocks) + "\n", encoding="utf-8")
    convert_chinese_subtitle_file(output, "traditional_tw")
    ctx.emit({"event": "combine", "vodId": vod_id, "phase": "done", "path": str(output), "segments": index - 1})
    return output


def srt_segments(srt_path: Path) -> list[tuple[int, str]]:
    segments: list[tuple[int, str]] = []
    current_second = 0
    for line in srt_path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        match = TIME_RE.search(line)
        if match:
            current_second = int(match.group("sh")) * 3600 + int(match.group("sm")) * 60 + int(match.group("ss"))
            continue
        text = line.strip()
        if not text or text.isdigit():
            continue
        if any(phrase.lower() in text.lower() for phrase in NOISE_PHRASES):
            continue
        if len(text) < 2:
            continue
        segments.append((current_second, text))
    return segments


def chat_rows(chat_path: Path | None) -> list[tuple[int, str, str]]:
    if not chat_path or not chat_path.exists() or chat_path.suffix.lower() != ".json":
        return []
    data = json.loads(chat_path.read_text(encoding="utf-8-sig"))
    rows = []
    for comment in data.get("comments", []):
        offset = int(comment.get("content_offset_seconds") or 0)
        user = str((comment.get("commenter") or {}).get("display_name") or "")
        body = str((comment.get("message") or {}).get("body") or "")
        if user.lower() in {"streamelements", "nightbot", "chiwabots"}:
            continue
        rows.append((offset, user, body))
    return rows


def timestamp(seconds: int) -> str:
    return f"{seconds // 3600:02d}:{seconds % 3600 // 60:02d}:{seconds % 60:02d}"


def compact_samples(items: list[str], limit: int = 16) -> list[str]:
    result: list[str] = []
    for item in items:
        text = item.strip()
        if not text or text in result:
            continue
        if len(set(text)) <= 2 and len(text) > 5:
            continue
        result.append(text)
        if len(result) >= limit:
            break
    return result


def is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def cleanup_roots(args: argparse.Namespace) -> list[Path]:
    output_dir = Path(args.output_dir).expanduser().resolve()
    roots = [output_dir]
    if args.cleanup_root:
        roots.append(Path(args.cleanup_root).expanduser().resolve())

    unique: list[Path] = []
    for root in roots:
        if root not in unique:
            unique.append(root)

    reduced: list[Path] = []
    for root in sorted(unique, key=lambda item: len(item.parts)):
        if any(root != existing and is_relative_to(root, existing) for existing in reduced):
            continue
        reduced.append(root)
    return reduced


def cleanup_size(roots: list[Path]) -> int:
    total = 0
    for root in roots:
        if not root.exists():
            continue
        if root.is_file():
            total += root.stat().st_size
            continue
        for path in root.rglob("*"):
            if path.is_file():
                total += path.stat().st_size
    return total


def cleanup_targets(root: Path) -> list[Path]:
    if not root.exists():
        return []
    if root.is_file():
        return []

    directory_patterns = ("*.chunks", "*.chunks-*", "__pycache__", "skill-smoke")
    file_patterns = (
        "*.audio.wav",
        "*.source.*",
        "*.log",
        "*.pid",
        "*events.jsonl",
        "*.pyc",
        "run_vod_exports.py",
        "run_vod_exports_parallel.py",
        "*.chat_timeline.txt",
        "*.partial_timeline.txt",
    )

    targets: list[Path] = []
    for pattern in directory_patterns:
        targets.extend(path for path in root.rglob(pattern) if path.is_dir())
    for pattern in file_patterns:
        targets.extend(path for path in root.rglob(pattern) if path.is_file())
    return targets


def clean_intermediates(args: argparse.Namespace) -> dict[str, Any]:
    roots = cleanup_roots(args)
    repo_root = REPO_ROOT.resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()
    for root in roots:
        if root != output_dir and not is_relative_to(root, repo_root):
            raise RuntimeError(f"Refusing to clean outside the repo unless it is --output-dir: {root}")

    before = cleanup_size(roots)
    targets: list[Path] = []
    for root in roots:
        for target in cleanup_targets(root):
            resolved = target.resolve()
            if not any(resolved == clean_root or is_relative_to(resolved, clean_root) for clean_root in roots):
                raise RuntimeError(f"Refusing to delete outside cleanup roots: {resolved}")
            targets.append(resolved)

    unique_targets = sorted(set(targets), key=lambda item: len(item.parts), reverse=True)
    deleted = 0
    for target in unique_targets:
        if not target.exists():
            continue
        if target.is_dir():
            shutil.rmtree(target)
        else:
            target.unlink()
        deleted += 1

    after = cleanup_size(roots)
    return {
        "cleanupRoots": [str(root) for root in roots],
        "deletedCount": deleted,
        "beforeBytes": before,
        "afterBytes": after,
        "freedBytes": before - after,
        "beforeMB": round(before / (1024 * 1024), 3),
        "afterMB": round(after / (1024 * 1024), 3),
        "freedMB": round((before - after) / (1024 * 1024), 3),
    }


def write_timeline(
    ctx: Context,
    vod_id: str,
    title: str,
    duration: int,
    srt_path: Path | None,
    chat_path: Path | None,
) -> Path:
    speech = srt_segments(srt_path) if srt_path and srt_path.exists() else []
    chat = chat_rows(chat_path)
    window = ctx.args.timeline_window_seconds
    lines = [
        f"# {vod_id} - {title}",
        f"duration: {timestamp(duration)}",
        f"speech_segments: {len(speech)}",
        f"chat_messages: {len(chat)}",
        "",
    ]
    for bucket in range(0, math.ceil(duration / window)):
        start = bucket * window
        end = min(start + window, duration)
        speech_bucket = [text for second, text in speech if start <= second < end]
        chat_bucket = [(second, user, body) for second, user, body in chat if start <= second < end]
        lines.append(f"## {timestamp(start)}-{timestamp(end)}")
        lines.append(f"speech={len(speech_bucket)} chat={len(chat_bucket)}")
        samples = compact_samples([text for text in speech_bucket if len(text) <= 90])
        if samples:
            lines.append("speech: " + " / ".join(samples))
        if chat_bucket:
            chat_samples = [
                f"{timestamp(second)} {user}: {body[:120]}"
                for second, user, body in chat_bucket[:10]
            ]
            lines.append("chat: " + " / ".join(chat_samples))
        lines.append("")

    output = ctx.output_dir / f"{vod_id}.timeline.txt"
    output.write_text("\n".join(lines), encoding="utf-8")
    ctx.emit({"event": "timeline", "vodId": vod_id, "phase": "done", "path": str(output)})
    return output


def process_vod(ctx: Context, tools: dict[str, Path], url: str) -> dict[str, Any]:
    ctx.emit({"event": "probe", "phase": "start", "url": url})
    info = run_probe(tools["yt-dlp.exe"], url, timeout=180)
    probe = summarize_probe(info)
    vod_id = vod_id_from_probe(probe, info)
    title = str(probe.get("title") or info.get("title") or "twitch-vod")
    duration = int(probe.get("duration") or info.get("duration") or 0)
    ctx.emit({"event": "probe", "phase": "done", "url": url, "vodId": vod_id, "title": title, "duration": duration})

    chat_path = ensure_chat(ctx, tools, url, vod_id, title)
    audio_path: Path | None = None
    srt_path: Path | None = None
    chunk_count = 0
    if not ctx.args.no_whisper:
        audio_path = ensure_audio_wav(ctx, tools, url, vod_id)
        chunks = ensure_chunks(ctx, tools, vod_id, audio_path)
        chunk_count = len(chunks)
        srts = ensure_transcripts(ctx, tools, vod_id, chunks)
        srt_path = combine_srt(ctx, vod_id, srts)
    else:
        ctx.emit({"event": "whisper", "vodId": vod_id, "phase": "skipped"})

    timeline_path = write_timeline(ctx, vod_id, title, duration, srt_path, chat_path)
    result = {
        "url": url,
        "vodId": vod_id,
        "title": title,
        "duration": duration,
        "chatPath": str(chat_path) if chat_path else "",
        "audioPath": str(audio_path) if audio_path else "",
        "srtPath": str(srt_path) if srt_path else "",
        "timelinePath": str(timeline_path),
        "chunkCount": chunk_count,
    }
    ctx.emit({"event": "vod", "phase": "done", "vodId": vod_id, "timelinePath": str(timeline_path)})
    return result


def main() -> int:
    args = parse_args()
    if args.check_tools:
        print(json.dumps(status(args.model), ensure_ascii=False, indent=2))
        return 0
    if args.cleanup_only:
        print(json.dumps({"event": "cleanup", **clean_intermediates(args)}, ensure_ascii=False, indent=2))
        return 0
    if not args.urls:
        raise SystemExit("Provide at least one Twitch VOD URL, or use --check-tools/--cleanup-only.")
    if args.workers < 1 or args.threads_per_worker < 1 or args.chunk_seconds < 60:
        raise SystemExit("workers and threads must be positive; chunk-seconds must be at least 60.")

    ctx = Context(args)
    required = ["yt-dlp.exe"]
    if not args.no_chat:
        required.append("TwitchDownloaderCLI.exe")
    if not args.no_whisper:
        required.extend(["ffmpeg.exe", "whisper-cli.exe", "model"])
    tools = require_tools(required, args.model)

    manifest: list[dict[str, Any]] = []
    for url in args.urls:
        manifest.append(process_vod(ctx, tools, url))
        ctx.manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    ctx.emit({"event": "all", "phase": "done", "manifest": str(ctx.manifest_path)})
    if args.cleanup_intermediates:
        print(json.dumps({"event": "cleanup", **clean_intermediates(args)}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
