import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from youtube_local_exporter.jobs import choose_subtitle_from_probe_summary, interpolate_progress, newest_matching_output
from youtube_local_exporter.cookies import format_cookie_row, normalize_cookies
from youtube_local_exporter.tools import normalize_model_name, require_tools, yt_dlp_js_runtime_args


class ToolsAndJobsTests(unittest.TestCase):
    def test_normalize_model_name(self):
        self.assertEqual(normalize_model_name("base"), "base")
        self.assertEqual(normalize_model_name("unknown"), "small")

    def test_require_tools_reports_missing(self):
        with self.assertRaisesRegex(RuntimeError, "definitely-missing-tool.exe"):
            require_tools(["definitely-missing-tool.exe"])

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
