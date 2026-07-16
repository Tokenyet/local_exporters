from __future__ import annotations

import os
from pathlib import Path


APP_NAME = "YouTubeLocalExporter"
HOST_NAME = "com.dowen.youtube_local_exporter"


def app_dir() -> Path:
    root = os.environ.get("LOCALAPPDATA")
    if root:
        return Path(root) / APP_NAME
    return Path.home() / ".youtube-local-exporter"


def tools_dir() -> Path:
    return app_dir() / "tools"


def models_dir() -> Path:
    return tools_dir() / "models"


def default_output_dir() -> Path:
    return Path.home() / "Downloads" / "YouTube Local Exporter"


def update_script_path() -> Path:
    return app_dir() / "scripts" / "update-tools.ps1"
