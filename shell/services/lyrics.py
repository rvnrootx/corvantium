#!/usr/bin/env python3
"""Bounded LRCLIB lookup; lyrics stay in the user's session and cache."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

USER_AGENT = "Corvantium/0.1 (https://github.com/rvnrootx/corvantium)"
STAMP = re.compile(r"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]")
MIN_REQUEST_INTERVAL = 0.45


def parse_lrc(text: str) -> list[dict]:
    rows: list[dict] = []
    for line in text.splitlines():
        stamps = list(STAMP.finditer(line))
        lyric = STAMP.sub("", line).strip()
        if not stamps or not lyric or lyric.startswith("["):
            continue
        for stamp in stamps:
            frac = (stamp.group(3) or "").ljust(3, "0")
            seconds = int(stamp.group(1)) * 60 + int(stamp.group(2)) + (int(frac or "0") / 1000)
            rows.append({"time": seconds, "text": lyric})
    return sorted(rows, key=lambda row: row["time"])


def cache_path(fields: str) -> Path:
    root = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "corvantium" / "lyrics"
    return root / (hashlib.sha256(fields.encode("utf-8")).hexdigest()[:20] + ".json")


def lookup(query: dict[str, str]) -> dict:
    url = "https://lrclib.net/api/get?" + urlencode(query)
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urlopen(request, timeout=7) as response:
        if response.status != 200:
            raise RuntimeError(f"LRCLIB returned HTTP {response.status}")
        return json.loads(response.read().decode("utf-8"))


def wait_for_lookup(cache_root: Path) -> None:
    """Serialize requests and keep the documented gap between lookups."""
    cache_root.mkdir(parents=True, exist_ok=True)
    lock_path = cache_root / "request.lock"
    next_path = cache_root / "next-request"
    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        try:
            try:
                allowed_at = float(next_path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                allowed_at = 0.0
            delay = max(0.0, allowed_at - time.time())
            if delay:
                time.sleep(min(delay, 3600))
            next_path.write_text(str(time.time() + MIN_REQUEST_INTERVAL), encoding="utf-8")
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


def defer_after_rate_limit(cache_root: Path, retry_after: str | None) -> None:
    try:
        delay = max(1, min(3600, int(retry_after or "1")))
    except ValueError:
        delay = 1
    cache_root.mkdir(parents=True, exist_ok=True)
    lock_path = cache_root / "request.lock"
    next_path = cache_root / "next-request"
    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        try:
            next_path.write_text(str(time.time() + delay), encoding="utf-8")
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--title", required=True)
    parser.add_argument("--artist", required=True)
    parser.add_argument("--album", default="")
    parser.add_argument("--duration", type=float, default=0)
    args = parser.parse_args()
    title, artist, album = args.title.strip(), args.artist.strip(), args.album.strip()
    search = urlencode({"q": f"{artist} {title}"})
    search_url = f"https://lrclib.net/search?{search}"
    if not title or not artist:
        emit({"status": "metadata-missing", "message": "Track title and artist are needed to search lyrics.", "lines": [], "search_url": search_url})
        return 0

    signature = f"{artist}\0{title}\0{album}\0{int(args.duration)}"
    cached_file = cache_path(signature)
    try:
        cached = json.loads(cached_file.read_text(encoding="utf-8")) if cached_file.is_file() else None
        if cached and time.time() - cached.get("cached_at", 0) < (30 * 86400 if cached.get("status") == "found" else 86400):
            emit(cached["payload"])
            return 0
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError):
        pass

    query = {"track_name": title, "artist_name": artist}
    if album:
        query["album_name"] = album
    if 1 <= args.duration <= 3600:
        query["duration"] = str(round(args.duration))
    wait_for_lookup(cached_file.parent)
    try:
        record = lookup(query)
        synced = record.get("syncedLyrics") or ""
        plain = record.get("plainLyrics") or ""
        status = "found" if synced else ("plain-only" if plain else "no-match")
        payload = {
            "status": status, "lines": parse_lrc(synced), "plain": plain,
            "source": "LRCLIB", "search_url": search_url,
            "message": "Synced lyrics loaded." if synced else ("Only unsynced lyrics were found." if plain else "No lyrics matched this track."),
        }
    except HTTPError as error:
        if error.code == 404:
            payload = {"status": "no-match", "message": "No exact match was found.", "lines": [], "search_url": search_url, "source": "LRCLIB"}
        elif error.code == 429:
            defer_after_rate_limit(cached_file.parent, error.headers.get("Retry-After") if error.headers else None)
            payload = {"status": "rate-limited", "message": "LRCLIB asked Corvantium to pause; try again later.", "lines": [], "search_url": search_url, "source": "LRCLIB"}
        else:
            payload = {"status": "offline", "message": f"LRCLIB returned HTTP {error.code}.", "lines": [], "search_url": search_url, "source": "LRCLIB"}
    except (URLError, TimeoutError, OSError, ValueError, RuntimeError, json.JSONDecodeError):
        payload = {"status": "offline", "message": "LRCLIB could not be reached.", "lines": [], "search_url": search_url, "source": "LRCLIB"}

    if payload["status"] != "offline":
        try:
            cached_file.parent.mkdir(parents=True, exist_ok=True)
            cached_file.write_text(json.dumps({"cached_at": time.time(), "payload": payload}, ensure_ascii=False), encoding="utf-8")
        except OSError:
            pass
    emit(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
