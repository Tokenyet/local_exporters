from __future__ import annotations

import os
import json
from pathlib import Path


APP_NAME = "TwitchLocalExporter"
HOST_NAME = "com.dowen.twitch_local_exporter"
PRODUCT_KEY = "twitch"
SHARED_STATE_NAME = "com.dowen.local_exporter"


def app_dir() -> Path:
    root = os.environ.get("LOCALAPPDATA")
    if root:
        return Path(root) / APP_NAME
    return Path.home() / ".twitch-local-exporter"


def tools_dir() -> Path:
    return toolchain_root()


def models_dir() -> Path:
    return tools_dir() / "models"


def product_tools_dir() -> Path:
    return tools_dir() / "products" / PRODUCT_KEY


def shared_state_dir() -> Path:
    root = os.environ.get("LOCALAPPDATA")
    if root:
        return Path(root) / SHARED_STATE_NAME
    return Path.home() / ".com.dowen.local_exporter"


def default_shared_toolchain_root() -> Path:
    return shared_state_dir() / "toolchain"


def toolchain_settings_path() -> Path:
    return shared_state_dir() / "settings.json"


def toolchain_mode() -> str:
    if os.environ.get("DOWEN_LOCAL_EXPORT_TOOLCHAIN_ROOT"):
        return "custom"

    settings_path = toolchain_settings_path()
    if not settings_path.exists():
        return "isolated"

    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8-sig"))
        product = (settings.get("products") or {}).get(PRODUCT_KEY) or {}
        return str(product.get("mode") or "isolated")
    except (OSError, ValueError, TypeError):
        return "isolated"


def toolchain_root() -> Path:
    override = os.environ.get("DOWEN_LOCAL_EXPORT_TOOLCHAIN_ROOT")
    if override:
        return Path(override).expanduser()

    settings_path = toolchain_settings_path()
    if settings_path.exists():
        try:
            settings = json.loads(settings_path.read_text(encoding="utf-8-sig"))
            product = (settings.get("products") or {}).get(PRODUCT_KEY) or {}
            mode = str(product.get("mode") or "isolated")
            if mode in {"shared", "custom"} and product.get("root"):
                return Path(str(product["root"])).expanduser()
        except (OSError, ValueError, TypeError):
            pass

    return app_dir() / "tools"


def default_output_dir() -> Path:
    return Path.home() / "Downloads" / "Twitch Local Exporter"


def update_script_path() -> Path:
    return app_dir() / "scripts" / "update-tools.ps1"
