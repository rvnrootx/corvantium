#!/usr/bin/env python3
"""Opt-in Open-Meteo client used by Corvantium's calendar panel."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

USER_AGENT = "Corvantium/0.1 (https://github.com/rvnrootx/corvantium)"
CURRENT_FIELDS = "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m"
HOURLY_FIELDS = "temperature_2m,precipitation_probability,weather_code"


def fetch_json(url: str) -> dict:
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urlopen(request, timeout=8) as response:
        if response.status != 200:
            raise RuntimeError(f"provider returned HTTP {response.status}")
        return json.loads(response.read().decode("utf-8"))


def cache_file_for(location: str) -> Path:
    root = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "corvantium"
    key = hashlib.sha256(location.casefold().encode("utf-8")).hexdigest()[:16]
    return root / f"weather-{key}.json"


def hourly_rows(hourly: dict, limit: int = 12) -> list[dict]:
    times = hourly.get("time", [])
    temps = hourly.get("temperature_2m", [])
    rain = hourly.get("precipitation_probability", [])
    codes = hourly.get("weather_code", [])
    count = min(limit, len(times), len(temps), len(rain), len(codes))
    return [
        {"time": times[i], "temperature": temps[i], "precipitation_probability": rain[i], "weather_code": codes[i]}
        for i in range(count)
    ]


def get_forecast(location: str, unit: str) -> dict:
    geocode_qs = urlencode({"name": location, "count": 1, "language": "en", "format": "json"})
    geocoded = fetch_json(f"https://geocoding-api.open-meteo.com/v1/search?{geocode_qs}")
    result = (geocoded.get("results") or [None])[0]
    if not result:
        return {"ok": False, "status": "location-not-found", "message": f"No place matched {location}.", "location": location}

    params = {
        "latitude": result["latitude"], "longitude": result["longitude"],
        "current": CURRENT_FIELDS, "hourly": HOURLY_FIELDS, "forecast_days": 2,
        "timezone": "auto", "temperature_unit": unit, "wind_speed_unit": "ms",
    }
    forecast = fetch_json("https://api.open-meteo.com/v1/forecast?" + urlencode(params))
    current = forecast.get("current", {})
    name = ", ".join(x for x in (result.get("name"), result.get("admin1"), result.get("country")) if x)
    return {
        "ok": True, "status": "ok", "location": name,
        "unit": "°F" if unit == "fahrenheit" else "°C",
        "current": {
            "temperature": current.get("temperature_2m"),
            "feels_like": current.get("apparent_temperature"),
            "humidity": current.get("relative_humidity_2m"),
            "precipitation": current.get("precipitation"),
            "weather_code": current.get("weather_code"),
            "wind_speed": current.get("wind_speed_10m"),
        },
        "hourly": hourly_rows(forecast.get("hourly", {})),
        "updated_at": int(time.time()), "stale": False,
    }


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    args = parser.parse_args()
    try:
        settings = json.loads(Path(args.config).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        settings = {}
    location = str(settings.get("weather_location", "")).strip()
    time_format = "12h" if settings.get("time_format") == "12h" else "24h"
    show_weather = settings.get("show_weather", True) is not False
    try:
        refresh_minutes = min(180, max(5, int(settings.get("weather_refresh_minutes", 30))))
    except (TypeError, ValueError):
        refresh_minutes = 30
    if not show_weather:
        emit({"ok": False, "status": "disabled", "message": "Weather is disabled in Corvantium settings.", "time_format": time_format, "refresh_minutes": refresh_minutes, "show_weather": False})
        return 0
    if not location:
        emit({"ok": False, "status": "location-not-configured", "message": "Set a city in Corvantium settings to enable weather.", "time_format": time_format, "refresh_minutes": refresh_minutes, "show_weather": True})
        return 0

    cache_path = cache_file_for(location)
    try:
        cached = json.loads(cache_path.read_text(encoding="utf-8")) if cache_path.is_file() else None
    except (OSError, json.JSONDecodeError):
        cached = None
    refresh = refresh_minutes * 60
    if cached and cached.get("ok") and time.time() - cached.get("updated_at", 0) < refresh:
        cached["time_format"] = time_format
        cached["refresh_minutes"] = refresh_minutes
        cached["show_weather"] = True
        emit(cached)
        return 0

    unit = "fahrenheit" if settings.get("temperature_unit") == "fahrenheit" else "celsius"
    try:
        payload = get_forecast(location, unit)
        if payload.get("ok"):
            payload["time_format"] = time_format
            payload["refresh_minutes"] = refresh_minutes
            payload["show_weather"] = True
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            temporary = cache_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            temporary.replace(cache_path)
        emit(payload)
    except (HTTPError, URLError, TimeoutError, OSError, ValueError, KeyError, RuntimeError, json.JSONDecodeError) as error:
        if cached and cached.get("ok"):
            cached.update({"stale": True, "status": "offline-cache", "message": "Showing the last saved forecast; the network request failed."})
            cached["time_format"] = time_format
            cached["refresh_minutes"] = refresh_minutes
            cached["show_weather"] = True
            emit(cached)
        else:
            emit({"ok": False, "status": "offline", "message": f"Weather is unavailable: {error}", "time_format": time_format, "refresh_minutes": refresh_minutes, "show_weather": True})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
