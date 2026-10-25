import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


weather = load("corvantium_weather", "shell/services/weather.py")
lyrics = load("corvantium_lyrics", "shell/services/lyrics.py")


class WeatherTests(unittest.TestCase):
    def test_hourly_rows_align_shortest_column(self):
        hourly = {
            "time": ["2026-10-25T10:00", "2026-10-25T11:00"],
            "temperature_2m": [23, 24],
            "precipitation_probability": [5],
            "weather_code": [1, 2],
        }
        self.assertEqual(weather.hourly_rows(hourly), [{
            "time": "2026-10-25T10:00", "temperature": 23,
            "precipitation_probability": 5, "weather_code": 1,
        }])

    def test_weather_can_be_disabled_without_network_lookup(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "settings.json"
            config.write_text(json.dumps({"show_weather": False, "weather_location": "London"}), encoding="utf-8")
            output = io.StringIO()
            with patch.object(sys, "argv", ["weather.py", "--config", str(config)]), \
                    patch.object(weather, "fetch_json") as fetch, \
                    contextlib.redirect_stdout(output):
                self.assertEqual(weather.main(), 0)
            fetch.assert_not_called()
            payload = json.loads(output.getvalue())
            self.assertEqual(payload["status"], "disabled")
            self.assertFalse(payload["show_weather"])


class LyricsTests(unittest.TestCase):
    def test_parse_lrc_sorts_and_expands_multiple_timestamps(self):
        rows = lyrics.parse_lrc("[00:02.50][00:01.250]line\n[ar:artist]\n[00:03]next")
        self.assertEqual(rows, [
            {"time": 1.25, "text": "line"},
            {"time": 2.5, "text": "line"},
            {"time": 3.0, "text": "next"},
        ])

    def test_parse_lrc_ignores_empty_lines(self):
        self.assertEqual(lyrics.parse_lrc("[00:01.00]\nplain text"), [])


if __name__ == "__main__":
    unittest.main()
