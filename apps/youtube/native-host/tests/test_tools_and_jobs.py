import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from youtube_local_exporter.config import (
    product_tools_dir,
    toolchain_mode,
    toolchain_root,
    tools_dir,
    update_script_command,
    update_script_path,
)
from youtube_local_exporter.jobs import choose_subtitle_from_probe_summary, interpolate_progress, newest_matching_output
from youtube_local_exporter.cookies import format_cookie_row, normalize_cookies
from youtube_local_exporter.tools import normalize_model_name, require_tools, resolve_tool, whisper_backend, yt_dlp_js_runtime_args


class ToolsAndJobsTests(unittest.TestCase):
    def test_normalize_model_name(self):
        self.assertEqual(normalize_model_name("base"), "base")
        self.assertEqual(normalize_model_name("unknown"), "small")

    def test_shared_toolchain_settings_are_resolved(self):
        previous_localappdata = os.environ.get("LOCALAPPDATA")
        previous_override = os.environ.pop("DOWEN_LOCAL_EXPORT_TOOLCHAIN_ROOT", None)
        try:
            with tempfile.TemporaryDirectory() as tmp:
                os.environ["LOCALAPPDATA"] = tmp
                root = Path(tmp) / "com.dowen.local_exporter" / "toolchain"
                settings_path = Path(tmp) / "com.dowen.local_exporter" / "settings.json"
                settings_path.parent.mkdir(parents=True)
                settings_path.write_text(json.dumps({
                    "products": {
                        "youtube": {"mode": "shared", "root": str(root)}
                    }
                }), encoding="utf-8")

                self.assertEqual(toolchain_mode(), "shared")
                self.assertEqual(toolchain_root(), root)
                self.assertEqual(tools_dir(), root)
                self.assertEqual(product_tools_dir(), root / "products" / "youtube")
        finally:
            if previous_localappdata is None:
                os.environ.pop("LOCALAPPDATA", None)
            else:
                os.environ["LOCALAPPDATA"] = previous_localappdata
            if previous_override is not None:
                os.environ["DOWEN_LOCAL_EXPORT_TOOLCHAIN_ROOT"] = previous_override

    def test_require_tools_reports_missing(self):
        with self.assertRaisesRegex(RuntimeError, "definitely-missing-tool.exe"):
            require_tools(["definitely-missing-tool.exe"])

    def test_macos_tool_names_are_resolved_from_unix_bundles(self):
        previous_localappdata = os.environ.get("LOCALAPPDATA")
        try:
            with tempfile.TemporaryDirectory() as tmp:
                os.environ["LOCALAPPDATA"] = tmp
                root = Path(tmp) / "com.dowen.local_exporter" / "toolchain"
                settings_path = root.parent / "settings.json"
                settings_path.parent.mkdir(parents=True)
                settings_path.write_text(json.dumps({
                    "products": {"youtube": {"mode": "shared", "root": str(root)}}
                }), encoding="utf-8")
                root.mkdir(parents=True)
                unix_ffmpeg = root / "ffmpeg"
                unix_ffmpeg.touch()

                with patch("youtube_local_exporter.tools.sys.platform", "darwin"):
                    self.assertEqual(resolve_tool("ffmpeg.exe").path, unix_ffmpeg)
        finally:
            if previous_localappdata is None:
                os.environ.pop("LOCALAPPDATA", None)
            else:
                os.environ["LOCALAPPDATA"] = previous_localappdata

    def test_update_script_uses_shell_on_macos(self):
        with patch("youtube_local_exporter.config.sys.platform", "darwin"):
            self.assertEqual(update_script_path().name, "update-tools.sh")
        self.assertEqual(update_script_command(Path("/tmp/update-tools.sh")), ["/bin/sh", "/tmp/update-tools.sh"])

    def test_whisper_backend_prefers_cuda_binary_when_cuda_is_available(self):
        previous_localappdata = os.environ.get("LOCALAPPDATA")
        try:
            with tempfile.TemporaryDirectory() as tmp:
                os.environ["LOCALAPPDATA"] = tmp
                root = Path(tmp) / "com.dowen.local_exporter" / "toolchain"
                settings_path = root.parent / "settings.json"
                settings_path.parent.mkdir(parents=True)
                settings_path.write_text(json.dumps({
                    "products": {"youtube": {"mode": "shared", "root": str(root)}}
                }), encoding="utf-8")
                (root / "whisper-cli.exe").parent.mkdir(parents=True)
                (root / "whisper-cli.exe").touch()
                (root / "cuda").mkdir(parents=True)
                cuda_path = root / "cuda" / "whisper-cli.exe"
                cuda_path.touch()

                with patch("youtube_local_exporter.tools.cuda_available", return_value=True):
                    self.assertEqual(whisper_backend(), ("cuda", cuda_path))
        finally:
            if previous_localappdata is None:
                os.environ.pop("LOCALAPPDATA", None)
            else:
                os.environ["LOCALAPPDATA"] = previous_localappdata

    def test_js_runtime_args_are_valid_when_present(self):
        args = yt_dlp_js_runtime_args()
        if args:
            self.assertEqual(args[0], "--js-runtimes")
            self.assertRegex(args[1], r"^(deno|node|quickjs|bun):.+")

    def test_interpolate_progress(self):
        self.assertEqual(interpolate_progress("[download] 50.0% of 10MiB", 10, 90), 50)
        self.assertIsNone(interpolate_progress("no percent here", 10, 90))

    def test_newest_matching_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            first = directory / "video.en.srt"
            second = directory / "video.zh.srt"
            bracketed = directory / "2026-07-02 - Me at the zoo [jNQXAC9IVRw].mp4"
            first.write_text("one", encoding="utf-8")
            second.write_text("two", encoding="utf-8")
            bracketed.write_text("three", encoding="utf-8")
            os.utime(first, (1, 1))
            os.utime(second, (2, 2))
            os.utime(bracketed, (3, 3))

            self.assertEqual(newest_matching_output(directory, "video", ["srt"]), second)
            self.assertEqual(newest_matching_output(directory, "2026-07-02 - Me at the zoo [jNQXAC9IVRw]", ["mp4"]), bracketed)
            self.assertIsNone(newest_matching_output(directory, "missing", ["srt"], required=False))

    def test_choose_subtitle_from_probe_summary(self):
        probe = {
            "subtitles": [
                {"lang": "en", "type": "auto"},
                {"lang": "zh-Hant", "type": "manual"}
            ]
        }
        self.assertEqual(choose_subtitle_from_probe_summary(probe, "auto"), ("zh-Hant", True))
        self.assertEqual(choose_subtitle_from_probe_summary(probe, "en"), ("en", True))
        self.assertEqual(choose_subtitle_from_probe_summary({"subtitles": []}, "auto"), ("auto", False))

    def test_cookie_rows_use_netscape_format(self):
        cookies = normalize_cookies([{
            "domain": ".youtube.com",
            "hostOnly": False,
            "path": "/",
            "secure": True,
            "httpOnly": True,
            "expirationDate": 2000000000,
            "name": "SID",
            "value": "secret"
        }])
        self.assertEqual(
            format_cookie_row(cookies[0]),
            "#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t2000000000\tSID\tsecret"
        )


if __name__ == "__main__":
    unittest.main()
