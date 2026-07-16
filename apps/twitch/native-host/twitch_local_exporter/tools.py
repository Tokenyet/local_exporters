from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from . import __version__
from .config import models_dir, product_tools_dir, toolchain_mode, toolchain_root, tools_dir


@dataclass(frozen=True)
class Tool:
    name: str
    executable: str
    path: Path | None
    source: str

    @property
    def available(self) -> bool:
        return self.path is not None and self.path.exists()

    def as_dict(self) -> dict[str, object]:
        return {
            "available": self.available,
            "path": str(self.path) if self.path else "",
            "source": self.source
        }


def resolve_tool(executable: str) -> Tool:
    candidates = [product_tools_dir() / executable, tools_dir() / executable]
    if executable == "whisper-cuda-cli.exe":
        candidates.insert(0, tools_dir() / "cuda" / "whisper-cli.exe")
    for bundled in candidates:
        if bundled.exists():
            return Tool(executable.removesuffix(".exe"), executable, bundled, "bundled")

    found = shutil.which(executable)
    if found:
        return Tool(executable.removesuffix(".exe"), executable, Path(found), "path")

    return Tool(executable.removesuffix(".exe"), executable, None, "missing")


def resolve_model(name: str = "small") -> Path | None:
    normalized = normalize_model_name(name)
    candidate = models_dir() / f"ggml-{normalized}.bin"
    if candidate.exists():
        return candidate
    return None


def normalize_model_name(name: str) -> str:
    value = str(name or "small").strip().lower()
    return value if value in {"tiny", "base", "small", "medium", "large"} else "small"


def ffmpeg_location() -> str:
    ffmpeg = resolve_tool("ffmpeg.exe")
    if ffmpeg.path:
        return str(ffmpeg.path.parent)
    return ""


def resolve_js_runtime() -> tuple[str, Tool | None]:
    for runtime, executable in (
        ("deno", "deno.exe"),
        ("node", "node.exe"),
        ("quickjs", "qjs.exe"),
        ("bun", "bun.exe"),
    ):
        tool = resolve_tool(executable)
        if tool.path:
            return runtime, tool
    return "", None


def yt_dlp_js_runtime_args() -> list[str]:
    runtime, tool = resolve_js_runtime()
    if not runtime or not tool or not tool.path:
        return []
    return ["--js-runtimes", f"{runtime}:{tool.path}"]


def cuda_available() -> bool:
    return shutil.which("nvidia-smi.exe") is not None or shutil.which("nvidia-smi") is not None


def whisper_cli_supports_cuda(path: Path | None) -> bool:
    if not path:
        return False
    try:
        result = subprocess.run(
            [str(path), "--help"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    output = f"{result.stdout}\n{result.stderr}".lower()
    return result.returncode == 0 and ("cuda backend" in output or "cuda devices" in output)


def whisper_backend() -> tuple[str, Path | None]:
    cuda_tool = resolve_tool("whisper-cuda-cli.exe")
    if cuda_tool.path and cuda_available():
        return "cuda", cuda_tool.path

    cpu_tool = resolve_tool("whisper-cli.exe")
    if cpu_tool.path and cuda_available() and whisper_cli_supports_cuda(cpu_tool.path):
        return "cuda", cpu_tool.path
    return "cpu", cpu_tool.path


def status(model: str = "small") -> dict[str, object]:
    tools = {
        "yt-dlp": resolve_tool("yt-dlp.exe").as_dict(),
        "twitch-downloader-cli": resolve_tool("TwitchDownloaderCLI.exe").as_dict(),
        "ffmpeg": resolve_tool("ffmpeg.exe").as_dict(),
        "ffprobe": resolve_tool("ffprobe.exe").as_dict(),
        "whisper-cli": resolve_tool("whisper-cli.exe").as_dict(),
        "whisper-cuda-cli": resolve_tool("whisper-cuda-cli.exe").as_dict()
    }
    runtime_name, runtime_tool = resolve_js_runtime()
    tools["javascript-runtime"] = {
        "available": runtime_tool is not None and runtime_tool.available,
        "path": str(runtime_tool.path) if runtime_tool and runtime_tool.path else "",
        "source": runtime_tool.source if runtime_tool else "missing",
        "runtime": runtime_name
    }
    model_path = resolve_model(model)
    tools["whisper-model"] = {
        "available": model_path is not None,
        "path": str(model_path) if model_path else "",
        "source": "bundled" if model_path else "missing"
    }
    backend, backend_path = whisper_backend()
    return {
        "version": __version__,
        "toolsDir": str(tools_dir()),
        "toolchainRoot": str(toolchain_root()),
        "toolchainMode": toolchain_mode(),
        "tools": tools,
        "whisper": {
            "backend": backend,
            "path": str(backend_path) if backend_path else "",
            "cudaAvailable": cuda_available(),
            "fallback": "cpu"
        }
    }


def require_tools(names: Iterable[str], model: str = "small") -> dict[str, Path]:
    resolved: dict[str, Path] = {}
    missing: list[str] = []
    for name in names:
        if name == "model":
            model_path = resolve_model(model)
            if model_path:
                resolved[name] = model_path
            else:
                missing.append(f"ggml-{normalize_model_name(model)}.bin")
            continue

        tool = resolve_tool(name)
        if tool.path:
            resolved[name] = tool.path
        else:
            missing.append(name)

    if missing:
        raise RuntimeError(f"Missing required tool(s): {', '.join(missing)}")
    return resolved


def require_whisper_tools(model: str = "small") -> dict[str, Path]:
    resolved = require_tools(["yt-dlp.exe", "ffmpeg.exe", "whisper-cli.exe", "model"], model)
    cuda_tool = resolve_tool("whisper-cuda-cli.exe")
    if cuda_tool.path:
        resolved["whisper-cuda-cli.exe"] = cuda_tool.path
    return resolved


def read_tool_version(path: Path, args: list[str] | None = None) -> str:
    command = [str(path), *(args or ["--version"])]
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=10, check=False)
    except OSError:
        return ""
    return (result.stdout or result.stderr or "").strip().splitlines()[0] if (result.stdout or result.stderr) else ""
